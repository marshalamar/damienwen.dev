import type { Metadata } from "next";
import "./fonts.css";
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
      <head>
        <link rel="icon" href="/icon.svg" type="image/svg+xml" />
        {/* Same-origin only — vendored under public/fonts/zhuque */}
        <link rel="stylesheet" href="/fonts/zhuque/result.css" />
      </head>
      <body>{children}</body>
    </html>
  );
}
