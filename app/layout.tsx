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
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link
          rel="preconnect"
          href="https://fonts.gstatic.com"
          crossOrigin="anonymous"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Hanken+Grotesk:ital,wght@0,400;0,500;0,600;1,400&family=Instrument+Serif:ital@0;1&family=JetBrains+Mono:wght@400;500&family=Noto+Serif+SC:wght@400;500;600&display=swap"
          rel="stylesheet"
        />
        <link
          rel="stylesheet"
          href="https://fontsapi.zeoseven.com/7/main/result.css"
        />
        <link
          rel="stylesheet"
          href="https://cdn.jsdelivr.net/npm/@vp-tw/taipei-sans-tc/dist/Regular/TaipeiSansTCBeta-Regular.css"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
