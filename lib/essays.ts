import type { MDXContent } from "mdx/types";

export type EssayMeta = {
  title: string;
  subtitle?: string;
  excerpt?: string;
  publishedAt: string;
  sourceUrl?: string;
};

export type Essay = EssayMeta & {
  slug: string;
  number: string;
  date: string;
  dateISO: string;
  Content: MDXContent;
};

type EssayModule = {
  default: MDXContent;
  meta: unknown;
};

const essayModules = import.meta.glob<EssayModule>(
  "../content/essays/*.mdx",
  { eager: true },
);

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function requiredString(
  meta: Record<string, unknown>,
  field: "title" | "publishedAt",
  filePath: string,
) {
  const value = meta[field];

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`${filePath}: meta.${field} must be a non-empty string`);
  }

  return value.trim();
}

function optionalString(
  meta: Record<string, unknown>,
  field: "subtitle" | "excerpt",
  filePath: string,
) {
  const value = meta[field];

  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(
      `${filePath}: meta.${field} must be a non-empty string when provided`,
    );
  }

  return value.trim();
}

function readMeta(value: unknown, filePath: string): EssayMeta {
  if (!isRecord(value)) {
    throw new Error(`${filePath}: export a meta object`);
  }

  const title = requiredString(value, "title", filePath);
  const subtitle = optionalString(value, "subtitle", filePath);
  const excerpt = optionalString(value, "excerpt", filePath);
  const publishedAt = requiredString(value, "publishedAt", filePath);

  if (!/^\d{4}-\d{2}-\d{2}$/.test(publishedAt)) {
    throw new Error(
      `${filePath}: meta.publishedAt must use the YYYY-MM-DD format`,
    );
  }

  const parsedDate = new Date(`${publishedAt}T00:00:00.000Z`);

  if (
    Number.isNaN(parsedDate.valueOf()) ||
    parsedDate.toISOString().slice(0, 10) !== publishedAt
  ) {
    throw new Error(`${filePath}: meta.publishedAt is not a valid date`);
  }

  const sourceUrlValue = value.sourceUrl;
  let sourceUrl: string | undefined;

  if (sourceUrlValue !== undefined) {
    if (typeof sourceUrlValue !== "string" || sourceUrlValue.trim() === "") {
      throw new Error(
        `${filePath}: meta.sourceUrl must be a non-empty URL when provided`,
      );
    }

    sourceUrl = sourceUrlValue.trim();

    try {
      const url = new URL(sourceUrl);

      if (url.protocol !== "https:" && url.protocol !== "http:") {
        throw new Error("unsupported protocol");
      }
    } catch {
      throw new Error(
        `${filePath}: meta.sourceUrl must be an absolute HTTP(S) URL`,
      );
    }
  }

  return {
    title,
    publishedAt,
    ...(subtitle ? { subtitle } : {}),
    ...(excerpt ? { excerpt } : {}),
    ...(sourceUrl ? { sourceUrl } : {}),
  };
}

const seenNumbers = new Set<number>();
const seenSlugs = new Set<string>();

export const essays: readonly Essay[] = Object.entries(essayModules)
  .map(([filePath, essayModule]) => {
    const fileName = filePath.split("/").at(-1) ?? filePath;
    const match = /^(\d{2,})-([a-z0-9]+(?:-[a-z0-9]+)*)\.mdx$/.exec(
      fileName,
    );

    if (!match) {
      throw new Error(
        `${filePath}: filename must look like 03-my-essay.mdx`,
      );
    }

    const numberValue = Number.parseInt(match[1], 10);
    const slug = match[2];

    if (numberValue < 1 || seenNumbers.has(numberValue)) {
      throw new Error(`${filePath}: essay number must be unique and positive`);
    }

    if (seenSlugs.has(slug)) {
      throw new Error(`${filePath}: essay slug must be unique`);
    }

    seenNumbers.add(numberValue);
    seenSlugs.add(slug);

    const meta = readMeta(essayModule.meta, filePath);

    return {
      ...meta,
      slug,
      number: String(numberValue).padStart(2, "0"),
      date: meta.publishedAt.replaceAll("-", "."),
      dateISO: meta.publishedAt,
      Content: essayModule.default,
    };
  })
  .sort((left, right) => Number(left.number) - Number(right.number));

export function getEssay(slug: string) {
  return essays.find((essay) => essay.slug === slug);
}
