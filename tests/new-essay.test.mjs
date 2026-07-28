import assert from "node:assert/strict";
import {
  cp,
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  rm,
  stat,
  writeFile,
} from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { spawn } from "node:child_process";
import { setTimeout as wait } from "node:timers/promises";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

const testDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.resolve(testDirectory, "..");
const sourceScript = path.join(projectDirectory, "scripts", "new-essay.mjs");
const fixtures = [];

afterEach(async () => {
  for (const fixture of fixtures.splice(0)) {
    await rm(fixture, { recursive: true, force: true });
  }
});

async function createFixture() {
  const fixture = await mkdtemp(path.join(os.tmpdir(), "damienwen-new-essay-"));
  fixtures.push(fixture);

  await mkdir(path.join(fixture, "scripts"), { recursive: true });
  await mkdir(path.join(fixture, "content", "essays"), { recursive: true });
  await mkdir(path.join(fixture, "public", "essays"), { recursive: true });
  await cp(sourceScript, path.join(fixture, "scripts", "new-essay.mjs"));

  return fixture;
}

function runNewEssay(fixture, slug, title) {
  return new Promise((resolve) => {
    const child = spawn(
      process.execPath,
      [path.join(fixture, "scripts", "new-essay.mjs"), slug, title],
      { cwd: fixture },
    );
    let stderr = "";
    let stdout = "";

    child.stderr.setEncoding("utf8");
    child.stdout.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.on("close", (code) => resolve({ code, stderr, stdout }));
  });
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

function runGitCheckIgnore(filePath) {
  return new Promise((resolve) => {
    const child = spawn(
      "git",
      ["check-ignore", "--no-index", "--quiet", filePath],
      { cwd: projectDirectory },
    );

    child.on("close", (code) => resolve(code));
  });
}

async function waitForTemporaryEssay(essaysDirectory) {
  const deadline = Date.now() + 5_000;

  while (Date.now() < deadline) {
    const temporaryEssay = (await readdir(essaysDirectory)).find((fileName) =>
      fileName.endsWith(".tmp"),
    );
    if (temporaryEssay) {
      return temporaryEssay;
    }

    await wait(1);
  }

  throw new Error("Timed out waiting for the temporary essay");
}

async function forceCommitCollision(fixture, slug) {
  const essaysDirectory = path.join(fixture, "content", "essays");
  const resultPromise = runNewEssay(
    fixture,
    slug,
    `无法写入${"。".repeat(32_000)}`,
  );

  await waitForTemporaryEssay(essaysDirectory);
  await writeFile(
    path.join(essaysDirectory, `01-${slug}.mdx`),
    "do not replace",
    { flag: "wx" },
  );

  return resultPromise;
}

test("a successful creation writes escaped metadata and the complete template", async () => {
  const fixture = await createFixture();
  const title = '他说："先听\\\\再说"\n第二行';
  const dateBeforeCreation = beijingDate();
  const result = await runNewEssay(fixture, "escaped-title", title);
  const dateAfterCreation = beijingDate();

  assert.equal(result.code, 0, result.stderr);

  const essay = await readFile(
    path.join(fixture, "content", "essays", "01-escaped-title.mdx"),
    "utf8",
  );
  const dateMatch = essay.match(/publishedAt: "(\d{4}-\d{2}-\d{2})"/);

  assert.ok(dateMatch, "generated essay should contain a publication date");
  assert.ok(
    [dateBeforeCreation, dateAfterCreation].includes(dateMatch[1]),
    `expected a Beijing date, received ${dateMatch[1]}`,
  );
  assert.equal(
    essay,
    `export const meta = {
  title: ${JSON.stringify(title)},
  publishedAt: "${dateMatch[1]}",
};

<Section title="第一节">

在这里写正文。

</Section>
`,
  );
});

test("Git ignores essay creation lock and temporary files", async () => {
  for (const filePath of [
    "content/essays/.new-essay.lock",
    "content/essays/.03-test.mdx.123.uuid.tmp",
  ]) {
    assert.equal(
      await runGitCheckIgnore(filePath),
      0,
      `${filePath} should be ignored`,
    );
  }
});

test("concurrent creations receive distinct numbers and leave no transaction files", async () => {
  const fixture = await createFixture();

  const results = await Promise.all([
    runNewEssay(fixture, "first-listen", "第一次听"),
    runNewEssay(fixture, "second-listen", "第二次听"),
  ]);

  assert.deepEqual(
    results.map((result) => result.code),
    [0, 0],
    results.map((result) => result.stderr).join("\n"),
  );

  const essayFiles = (await readdir(path.join(fixture, "content", "essays")))
    .filter((fileName) => fileName.endsWith(".mdx"))
    .sort();
  assert.equal(essayFiles.length, 2);
  assert.match(essayFiles[0], /^01-(?:first|second)-listen\.mdx$/);
  assert.match(essayFiles[1], /^02-(?:first|second)-listen\.mdx$/);

  const transactionFiles = (
    await readdir(path.join(fixture, "content", "essays"))
  ).filter(
    (fileName) => fileName === ".new-essay.lock" || fileName.endsWith(".tmp"),
  );
  assert.deepEqual(transactionFiles, []);
});

test("an existing image directory and its files are preserved", async () => {
  const fixture = await createFixture();
  const imageDirectory = path.join(
    fixture,
    "public",
    "essays",
    "prepared-images",
  );
  const markerPath = path.join(imageDirectory, "cover.png");

  await mkdir(imageDirectory);
  await writeFile(markerPath, "already here");

  const result = await runNewEssay(
    fixture,
    "prepared-images",
    "已经准备好的配图",
  );

  assert.equal(result.code, 0, result.stderr);
  assert.equal(await readFile(markerPath, "utf8"), "already here");
});

test("a failed commit removes only artifacts created by that invocation", async () => {
  const fixture = await createFixture();
  const essaysDirectory = path.join(fixture, "content", "essays");
  const unrelatedDirectory = path.join(
    fixture,
    "public",
    "essays",
    "unrelated",
  );
  const unrelatedFile = path.join(unrelatedDirectory, "keep.txt");

  await mkdir(unrelatedDirectory);
  await writeFile(unrelatedFile, "keep me");

  const result = await forceCommitCollision(fixture, "write-fails");
  assert.notEqual(result.code, 0);
  await assert.rejects(
    stat(path.join(fixture, "public", "essays", "write-fails")),
    { code: "ENOENT" },
  );
  assert.equal(
    await readFile(path.join(essaysDirectory, "01-write-fails.mdx"), "utf8"),
    "do not replace",
  );
  assert.deepEqual(
    (await readdir(essaysDirectory)).filter(
      (fileName) =>
        fileName === ".new-essay.lock" || fileName.endsWith(".tmp"),
    ),
    [],
  );
  assert.equal(await readFile(unrelatedFile, "utf8"), "keep me");
});

test("a failed commit preserves a pre-existing target image directory", async () => {
  const fixture = await createFixture();
  const imageDirectory = path.join(
    fixture,
    "public",
    "essays",
    "prepared-failure",
  );
  const markerPath = path.join(imageDirectory, "cover.png");

  await mkdir(imageDirectory);
  await writeFile(markerPath, "keep this image");

  const result = await forceCommitCollision(fixture, "prepared-failure");

  assert.notEqual(result.code, 0);
  assert.equal(await readFile(markerPath, "utf8"), "keep this image");
});
