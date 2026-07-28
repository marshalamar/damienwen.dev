#!/usr/bin/env node
/**
 * Vendor Zhuque Fangsong unicode-range webfonts into public/fonts/zhuque.
 * Run when refreshing the title face: `node scripts/vendor-zhuque-font.mjs`
 */
import { createWriteStream } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT_DIR = join(ROOT, "public", "fonts", "zhuque");
const CSS_URL = "https://fontsapi.zeoseven.com/7/main/result.css";
const BASE_URL = "https://fontsapi.zeoseven.com/7/main/";

async function download(url, dest) {
  const response = await fetch(url, {
    headers: { "user-agent": "damienwen-dev-font-vendor/1.0" },
  });

  if (!response.ok || !response.body) {
    throw new Error(`Failed to download ${url}: ${response.status}`);
  }

  await pipeline(response.body, createWriteStream(dest));
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true });

  const cssResponse = await fetch(CSS_URL, {
    headers: { "user-agent": "damienwen-dev-font-vendor/1.0" },
  });

  if (!cssResponse.ok) {
    throw new Error(`Failed to download Zhuque CSS: ${cssResponse.status}`);
  }

  const css = await cssResponse.text();
  const files = [
    ...new Set(
      [...css.matchAll(/url\("\.\/([^"]+)"\)/g)].map((match) => match[1]),
    ),
  ];

  if (files.length === 0) {
    throw new Error("No woff2 references found in Zhuque CSS");
  }

  await writeFile(join(OUT_DIR, "result.css"), css, "utf8");

  let completed = 0;
  const concurrency = 12;
  const queue = [...files];

  async function worker() {
    while (queue.length > 0) {
      const name = queue.shift();
      if (!name) {
        return;
      }

      await download(`${BASE_URL}${name}`, join(OUT_DIR, name));
      completed += 1;
      if (completed % 20 === 0 || completed === files.length) {
        process.stdout.write(`vendored ${completed}/${files.length}\n`);
      }
    }
  }

  await Promise.all(Array.from({ length: concurrency }, () => worker()));
  process.stdout.write(
    `Wrote ${files.length} subsets to public/fonts/zhuque/\n`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
