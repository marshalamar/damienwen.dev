import { randomUUID } from "node:crypto";
import {
  link,
  lstat,
  mkdir,
  open,
  readdir,
  rmdir,
  stat,
  unlink,
} from "node:fs/promises";
import path from "node:path";
import { setTimeout as wait } from "node:timers/promises";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(scriptDirectory, "..");
const essaysDirectory = path.join(projectDirectory, "content", "essays");
const publicEssaysDirectory = path.join(projectDirectory, "public", "essays");
const creationLockPath = path.join(essaysDirectory, ".new-essay.lock");
const lockTimeoutMilliseconds = 10_000;
const lockRetryMilliseconds = 50;

function usage(message) {
  if (message) {
    console.error(message);
  }

  console.error('Usage: npm run essay:new -- <slug> "文章标题"');
  process.exitCode = 1;
}

function beijingDate() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  })
    .formatToParts(new Date())
    .filter((part) => part.type !== "literal")
    .reduce((result, part) => {
      result[part.type] = part.value;
      return result;
    }, {});

  return `${parts.year}-${parts.month}-${parts.day}`;
}

async function releaseCreationLock(lock) {
  await lock.handle.close();

  try {
    const currentLock = await lstat(creationLockPath);
    if (
      currentLock.dev === lock.identity.dev &&
      currentLock.ino === lock.identity.ino
    ) {
      await unlink(creationLockPath);
    }
  } catch (error) {
    if (error.code !== "ENOENT") {
      throw error;
    }
  }
}

async function acquireCreationLock() {
  const startedAt = Date.now();

  while (true) {
    let handle;

    try {
      handle = await open(creationLockPath, "wx", 0o600);
      const identity = await handle.stat();
      await handle.writeFile(
        `${JSON.stringify({
          pid: process.pid,
          createdAt: new Date().toISOString(),
        })}\n`,
      );

      return { handle, identity };
    } catch (error) {
      if (handle) {
        const identity = await handle.stat();
        await releaseCreationLock({ handle, identity });
      }

      if (error.code !== "EEXIST") {
        throw error;
      }

      if (Date.now() - startedAt >= lockTimeoutMilliseconds) {
        throw new Error(
          `等待新文章创建锁超时。请确认没有其他 essay:new 进程后，再检查 ${path.relative(
            projectDirectory,
            creationLockPath,
          )}。`,
        );
      }

      await wait(lockRetryMilliseconds);
    }
  }
}

async function ensureImageDirectory(imageDirectory) {
  try {
    await mkdir(imageDirectory);
    return true;
  } catch (error) {
    if (error.code !== "EEXIST") {
      throw error;
    }

    const existingPath = await stat(imageDirectory);
    if (!existingPath.isDirectory()) {
      throw new Error(
        `${path.relative(projectDirectory, imageDirectory)} 已存在，但不是目录。`,
      );
    }

    return false;
  }
}

async function cleanUpCreatedArtifacts({
  essayPath,
  finalEssayCreated,
  imageDirectory,
  imageDirectoryCreated,
  temporaryEssayCreated,
  temporaryEssayPath,
}) {
  const warnings = [];

  for (const [created, filePath] of [
    [finalEssayCreated, essayPath],
    [temporaryEssayCreated, temporaryEssayPath],
  ]) {
    if (!created) {
      continue;
    }

    try {
      await unlink(filePath);
    } catch (error) {
      if (error.code !== "ENOENT") {
        warnings.push(
          `无法清理 ${path.relative(projectDirectory, filePath)}：${error.message}`,
        );
      }
    }
  }

  if (imageDirectoryCreated) {
    try {
      await rmdir(imageDirectory);
    } catch (error) {
      if (error.code !== "ENOENT" && error.code !== "ENOTEMPTY") {
        warnings.push(
          `无法清理 ${path.relative(projectDirectory, imageDirectory)}：${error.message}`,
        );
      }
    }
  }

  return warnings;
}

async function createEssay(slug, title) {
  await mkdir(essaysDirectory, { recursive: true });

  const lock = await acquireCreationLock();

  try {
    const existingFiles = await readdir(essaysDirectory);
    const existingEssays = existingFiles.flatMap((fileName) => {
      const match = /^(\d+)-([a-z0-9]+(?:-[a-z0-9]+)*)\.mdx$/.exec(fileName);
      return match
        ? [
            {
              fileName,
              number: Number.parseInt(match[1], 10),
              numberWidth: match[1].length,
              slug: match[2],
            },
          ]
        : [];
    });

    if (existingEssays.some((essay) => essay.slug === slug)) {
      throw new Error(`文章 ${slug} 已存在。`);
    }

    const nextNumber =
      Math.max(0, ...existingEssays.map((essay) => essay.number)) + 1;
    const numberWidth = Math.max(
      2,
      ...existingEssays.map((essay) => essay.numberWidth),
      String(nextNumber).length,
    );
    const prefix = String(nextNumber).padStart(numberWidth, "0");
    const fileName = `${prefix}-${slug}.mdx`;
    const essayPath = path.join(essaysDirectory, fileName);
    const imageDirectory = path.join(publicEssaysDirectory, slug);
    const temporaryEssayPath = path.join(
      essaysDirectory,
      `.${fileName}.${process.pid}.${randomUUID()}.tmp`,
    );
    const template = `export const meta = {
  title: ${JSON.stringify(title)},
  publishedAt: "${beijingDate()}",
};

<Section title="第一节">

在这里写正文。

</Section>
`;
    let finalEssayCreated = false;
    let imageDirectoryCreated = false;
    let temporaryEssayCreated = false;

    try {
      await mkdir(publicEssaysDirectory, { recursive: true });
      imageDirectoryCreated = await ensureImageDirectory(imageDirectory);

      const temporaryEssay = await open(temporaryEssayPath, "wx", 0o644);
      temporaryEssayCreated = true;

      try {
        await temporaryEssay.writeFile(template, { encoding: "utf8" });
        await temporaryEssay.sync();
      } finally {
        await temporaryEssay.close();
      }

      // A hard link makes the complete MDX visible in one filesystem operation
      // and, unlike rename(), refuses to replace an unexpected existing file.
      await link(temporaryEssayPath, essayPath);
      finalEssayCreated = true;

      await unlink(temporaryEssayPath);
      temporaryEssayCreated = false;
    } catch (error) {
      const warnings = await cleanUpCreatedArtifacts({
        essayPath,
        finalEssayCreated,
        imageDirectory,
        imageDirectoryCreated,
        temporaryEssayCreated,
        temporaryEssayPath,
      });

      if (warnings.length > 0) {
        error.message = `${error.message}\n${warnings.join("\n")}`;
      }

      throw error;
    }

    console.log(`已创建 content/essays/${fileName}`);
    console.log(`图片可放在 public/essays/${slug}/`);
  } finally {
    await releaseCreationLock(lock);
  }
}

const [slug, ...titleParts] = process.argv.slice(2);
const title = titleParts.join(" ").trim();

if (!slug || !title) {
  usage();
} else if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
  usage("Slug 只能包含小写字母、数字和单个连字符。");
} else {
  try {
    await createEssay(slug, title);
  } catch (error) {
    console.error(`无法创建文章：${error.message}`);
    process.exitCode = 1;
  }
}
