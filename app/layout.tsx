import type { Metadata } from "next";
import "./globals.css";

const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://damienwen.dev";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  title: {
    default: "器物与回声",
    template: "%s｜器物与回声",
  },
  description: "Damien Wen 的个人文章。",
  authors: [{ name: "Damien Wen" }],
  openGraph: {
    title: "器物与回声",
    description: "Damien Wen 的文章。",
    type: "website",
  },
  twitter: {
    card: "summary",
    title: "器物与回声",
    description: "Damien Wen 的文章。",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
