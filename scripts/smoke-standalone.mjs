import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { access, stat } from "node:fs/promises";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "..");
const standaloneDirectory = resolve(repositoryRoot, "dist/standalone");
const serverEntry = resolve(standaloneDirectory, "server.js");
const startupTimeoutMs = 15_000;
const requestTimeoutMs = 5_000;

function decodeHtmlAttribute(value) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&#x2F;", "/")
    .replaceAll("&#47;", "/");
}

function attributesFrom(html, baseUrl) {
  const attributes = [];
  const tagPattern = /<([a-z][\w:-]*)\b[^>]*>/giu;

  for (const tagMatch of html.matchAll(tagPattern)) {
    const tag = tagMatch[1].toLowerCase();
    const attributePattern = /\b(src|href)\s*=\s*(["'])(.*?)\2/giu;

    for (const attributeMatch of tagMatch[0].matchAll(attributePattern)) {
      const attribute = attributeMatch[1].toLowerCase();
      const rawValue = decodeHtmlAttribute(attributeMatch[3].trim());

      if (
        !rawValue ||
        rawValue.startsWith("#") ||
        /^(?:data|blob|javascript|mailto|tel):/iu.test(rawValue)
      ) {
        continue;
      }

      let url;

      try {
        url = new URL(rawValue, baseUrl);
      } catch {
        continue;
      }

      if (url.origin !== baseUrl.origin || url.protocol !== "http:") {
        continue;
      }

      url.hash = "";
      attributes.push({ attribute, tag, url });
    }
  }

  return attributes;
}

function isStaticAttribute({ attribute, tag, url }) {
  if (attribute === "src") {
    return true;
  }

  if (tag === "link") {
    return true;
  }

  return /\/[^/]+\.[a-z0-9]{1,10}$/iu.test(url.pathname);
}

function isEssayImage({ attribute, tag, url }) {
  return (
    attribute === "src" &&
    tag === "img" &&
    url.pathname.startsWith("/essays/")
  );
}

function essayPathsFrom(attributes) {
  return [
    ...new Set(
      attributes
        .filter(({ attribute, tag }) => attribute === "href" && tag === "a")
        .map(({ url }) => url.pathname.replace(/\/+$/u, ""))
        .filter((pathname) => /^\/essays\/[a-z0-9-]+$/u.test(pathname)),
    ),
  ].sort();
}

async function responseBody(url, description) {
  const response = await fetch(url, {
    headers: { accept: "*/*" },
    redirect: "manual",
    signal: AbortSignal.timeout(requestTimeoutMs),
  });

  assert.equal(
    response.status,
    200,
    `${description} returned HTTP ${response.status}: ${url.pathname}`,
  );

  const body = Buffer.from(await response.arrayBuffer());
  assert.ok(body.byteLength > 0, `${description} was empty: ${url.pathname}`);

  return { body, response };
}

async function renderBuiltHtml(worker, pathname) {
  const url = new URL(pathname, "http://standalone-smoke.invalid");
  const request = new Request(url, {
    headers: { accept: "text/html" },
  });
  const executionContext = {
    passThroughOnException() {},
    waitUntil() {},
  };
  const assets = {
    fetch: async () => new Response("Not found", { status: 404 }),
  };
  const response =
    typeof worker === "function"
      ? await worker(request)
      : await worker.fetch(request, { ASSETS: assets }, executionContext);

  assert.equal(
    response.status,
    200,
    `built worker returned HTTP ${response.status}: ${pathname}`,
  );
  assert.match(
    response.headers.get("content-type") ?? "",
    /^text\/html\b/iu,
    `built worker should return HTML: ${pathname}`,
  );

  return response.text();
}

async function nonemptyFile(pathname) {
  try {
    const details = await stat(pathname);
    return details.isFile() && details.size > 0;
  } catch {
    return false;
  }
}

function pathInside(root, pathname) {
  const relativePath = relative(root, pathname);
  return (
    relativePath !== "" &&
    relativePath !== ".." &&
    !relativePath.startsWith(`..${sep}`) &&
    !isAbsolute(relativePath)
  );
}

async function validatePackagedEssayImages() {
  const workerEntry = resolve(
    standaloneDirectory,
    "dist/server/index.js",
  );
  await access(workerEntry);

  const workerUrl = pathToFileURL(workerEntry);
  workerUrl.searchParams.set("standalone-smoke", `${process.pid}-${Date.now()}`);
  const workerModule = await import(workerUrl.href);
  const worker = workerModule.default;

  assert.ok(
    typeof worker === "function" ||
      (worker && typeof worker.fetch === "function"),
    "built worker should export a handler function or a fetch() handler",
  );

  const baseUrl = new URL("http://standalone-smoke.invalid/");
  const homepageHtml = await renderBuiltHtml(worker, "/");
  const homepageAttributes = attributesFrom(homepageHtml, baseUrl);
  const essayPaths = essayPathsFrom(homepageAttributes);

  assert.ok(
    essayPaths.length > 0,
    "built homepage should link to at least one /essays/<slug> page",
  );

  const pageAttributes = [...homepageAttributes];

  for (const essayPath of essayPaths) {
    const essayHtml = await renderBuiltHtml(worker, essayPath);
    pageAttributes.push(
      ...attributesFrom(essayHtml, new URL(essayPath, baseUrl)),
    );
  }

  const essayImagePaths = [
    ...new Set(
      pageAttributes
        .filter(isEssayImage)
        .map(({ url }) => decodeURIComponent(url.pathname)),
    ),
  ].sort();

  for (const essayImagePath of essayImagePaths) {
    const pathFromPublic = essayImagePath.replace(/^\/+/u, "");
    const sourcePath = resolve(repositoryRoot, "public", pathFromPublic);
    const packagedPaths = [
      resolve(standaloneDirectory, "public", pathFromPublic),
      resolve(standaloneDirectory, "dist/client", pathFromPublic),
    ];

    assert.ok(
      pathInside(resolve(repositoryRoot, "public"), sourcePath),
      `essay image resolved outside public/: ${essayImagePath}`,
    );
    assert.ok(
      await nonemptyFile(sourcePath),
      `essay image source is missing or empty: ${essayImagePath}`,
    );
    assert.ok(
      packagedPaths.every((pathname) =>
        pathInside(standaloneDirectory, pathname),
      ),
      `essay image resolved outside standalone output: ${essayImagePath}`,
    );
    assert.ok(
      (await Promise.all(packagedPaths.map(nonemptyFile))).some(Boolean),
      `essay image is missing or empty in standalone output: ${essayImagePath}`,
    );
  }

  return {
    essayCount: essayPaths.length,
    essayImageCount: essayImagePaths.length,
  };
}

async function waitForHealthyHomepage(baseUrl, child, transcript) {
  const deadline = Date.now() + startupTimeoutMs;
  let latestError;

  while (Date.now() < deadline) {
    if (child.exitCode !== null || child.signalCode !== null) {
      throw new Error(
        `standalone server exited before becoming healthy\n${transcript.text}`,
      );
    }

    try {
      const result = await responseBody(baseUrl, "homepage");
      assert.match(
        result.response.headers.get("content-type") ?? "",
        /^text\/html\b/iu,
        "homepage should return HTML",
      );
      return result.body.toString("utf8");
    } catch (error) {
      latestError = error;
      await new Promise((resolveDelay) => setTimeout(resolveDelay, 150));
    }
  }

  throw new Error(
    `standalone server did not become healthy within ${startupTimeoutMs}ms: ${
      latestError?.message ?? "no response"
    }\n${transcript.text}`,
  );
}

function waitForListeningPort(child, transcript) {
  return new Promise((resolvePort, rejectPort) => {
    let settled = false;

    const settle = (callback, value) => {
      if (settled) {
        return;
      }

      settled = true;
      clearTimeout(timeout);
      callback(value);
    };

    const inspectOutput = () => {
      const match = transcript.text.match(
        /\[vinext\] Production server running at http:\/\/127\.0\.0\.1:(\d+)/u,
      );

      if (match) {
        settle(resolvePort, Number.parseInt(match[1], 10));
      }
    };

    const timeout = setTimeout(() => {
      settle(
        rejectPort,
        new Error(
          `standalone server did not report a listening port within ${startupTimeoutMs}ms\n${transcript.text}`,
        ),
      );
    }, startupTimeoutMs);

    child.stdout.on("data", inspectOutput);
    child.stderr.on("data", inspectOutput);
    child.once("error", (error) => settle(rejectPort, error));
    child.once("exit", (code, signal) => {
      settle(
        rejectPort,
        new Error(
          `standalone server exited before listening (code=${code}, signal=${signal})\n${transcript.text}`,
        ),
      );
    });

    inspectOutput();
  });
}

function createTranscript(child) {
  const transcript = { text: "" };
  const append = (chunk) => {
    transcript.text = `${transcript.text}${chunk.toString("utf8")}`.slice(
      -128_000,
    );
  };

  child.stdout.on("data", append);
  child.stderr.on("data", append);

  return transcript;
}

function waitForExit(child, timeoutMs) {
  if (child.exitCode !== null || child.signalCode !== null) {
    return Promise.resolve(true);
  }

  return new Promise((resolveExit) => {
    const timeout = setTimeout(() => {
      child.removeListener("exit", onExit);
      resolveExit(false);
    }, timeoutMs);
    const onExit = () => {
      clearTimeout(timeout);
      resolveExit(true);
    };

    child.once("exit", onExit);
  });
}

let terminationPromise;

function terminateChild(child) {
  if (terminationPromise) {
    return terminationPromise;
  }

  terminationPromise = (async () => {
    if (child.exitCode !== null || child.signalCode !== null) {
      return;
    }

    child.kill("SIGTERM");

    if (await waitForExit(child, 2_000)) {
      return;
    }

    child.kill("SIGKILL");
    await waitForExit(child, 2_000);
  })();

  return terminationPromise;
}

function canSkipLocalMacSandboxBind(error, transcript) {
  if (
    process.platform !== "darwin" ||
    process.env.CODEX_SANDBOX !== "seatbelt" ||
    /^(?:1|true)$/iu.test(process.env.CI ?? "") ||
    process.env.GITHUB_ACTIONS === "true" ||
    process.env.STANDALONE_SMOKE_STRICT === "1"
  ) {
    return false;
  }

  return /(?:listen\s+EPERM|code:\s*['"]EPERM['"])/u.test(
    `${error?.message ?? ""}\n${transcript.text}`,
  );
}

async function run() {
  await access(serverEntry);
  const packagedValidation = await validatePackagedEssayImages();

  const child = spawn(process.execPath, [serverEntry], {
    cwd: standaloneDirectory,
    env: {
      ...process.env,
      HOST: "127.0.0.1",
      PORT: "0",
      NODE_ENV: "production",
    },
    stdio: ["ignore", "pipe", "pipe"],
  });
  const transcript = createTranscript(child);

  const signalHandlers = new Map();

  for (const signal of ["SIGINT", "SIGTERM"]) {
    const handler = () => {
      void terminateChild(child).finally(() => {
        process.removeListener(signal, handler);
        process.kill(process.pid, signal);
      });
    };

    signalHandlers.set(signal, handler);
    process.once(signal, handler);
  }

  try {
    let port;

    try {
      port = await waitForListeningPort(child, transcript);
    } catch (error) {
      if (canSkipLocalMacSandboxBind(error, transcript)) {
        console.warn(
          `standalone HTTP smoke skipped: the Codex macOS seatbelt denied loopback binding; packaged validation passed for ${packagedValidation.essayCount} essay(s) and ${packagedValidation.essayImageCount} essay image(s) (set STANDALONE_SMOKE_STRICT=1 to fail instead)`,
        );
        return;
      }

      throw error;
    }

    const baseUrl = new URL(`http://127.0.0.1:${port}/`);
    const homepageHtml = await waitForHealthyHomepage(
      baseUrl,
      child,
      transcript,
    );
    const homepageAttributes = attributesFrom(homepageHtml, baseUrl);
    const essayPaths = essayPathsFrom(homepageAttributes);

    assert.ok(
      essayPaths.length > 0,
      "homepage should link to at least one /essays/<slug> page",
    );

    const pageAttributes = [...homepageAttributes];

    for (const essayPath of essayPaths) {
      const essayUrl = new URL(essayPath, baseUrl);
      const { body, response } = await responseBody(essayUrl, "essay page");

      assert.match(
        response.headers.get("content-type") ?? "",
        /^text\/html\b/iu,
        `${essayPath} should return HTML`,
      );

      pageAttributes.push(...attributesFrom(body.toString("utf8"), essayUrl));
    }

    const staticAttributes = pageAttributes.filter(isStaticAttribute);
    const staticUrls = [
      ...new Map(
        staticAttributes.map(({ url }) => [url.href, url]),
      ).values(),
    ].sort((left, right) => left.href.localeCompare(right.href));
    const essayImageUrls = new Set(
      pageAttributes.filter(isEssayImage).map(({ url }) => url.href),
    );

    for (const staticUrl of staticUrls) {
      const { response } = await responseBody(staticUrl, "static asset");

      if (essayImageUrls.has(staticUrl.href)) {
        assert.match(
          response.headers.get("content-type") ?? "",
          /^image\//iu,
          `essay image should return an image content type: ${staticUrl.pathname}`,
        );
      }
    }

    for (const essayImageUrl of essayImageUrls) {
      assert.ok(
        staticUrls.some(({ href }) => href === essayImageUrl),
        `essay image was not checked as a static asset: ${essayImageUrl}`,
      );
    }

    console.log(
      `standalone smoke test passed: ${essayPaths.length} essay(s), ${staticUrls.length} local static asset(s), ${essayImageUrls.size} essay image(s)`,
    );
  } finally {
    for (const [signal, handler] of signalHandlers) {
      process.removeListener(signal, handler);
    }
    await terminateChild(child);
  }
}

await run();
