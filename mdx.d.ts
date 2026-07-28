/// <reference types="vite/client" />

declare module "*.mdx" {
  export const meta: {
    title: string;
    subtitle?: string;
    excerpt?: string;
    publishedAt: string;
    sourceUrl?: string;
  };
}
