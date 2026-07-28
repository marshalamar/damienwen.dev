import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { essays, getEssay } from "../../../lib/essays";
import { essayComponents } from "../../essay-components";
import { SiteHeader } from "../../site-header";

type EssayPageProps = {
  params: Promise<{
    slug: string;
  }>;
};

export function generateStaticParams() {
  return essays.map((essay) => ({ slug: essay.slug }));
}

export async function generateMetadata({
  params,
}: EssayPageProps): Promise<Metadata> {
  const { slug } = await params;
  const essay = getEssay(slug);

  if (!essay) {
    return {};
  }

  const description = essay.excerpt ?? essay.title;

  return {
    title: essay.title,
    description,
    openGraph: {
      title: essay.title,
      description,
      type: "article",
      publishedTime: essay.dateISO,
    },
  };
}

export default async function EssayPage({ params }: EssayPageProps) {
  const { slug } = await params;
  const essay = getEssay(slug);

  if (!essay) {
    notFound();
  }

  const { Content } = essay;

  return (
    <main className="site-shell site-shell--article">
      <SiteHeader />

      <article className="article">
        <header className="article-header">
          <div className="article-number" aria-hidden="true">
            <span>Essay</span>
            <strong>{essay.number}</strong>
          </div>

          <div className="article-heading">
            <h1>{essay.title}</h1>
            {essay.subtitle ? (
              <p className="article-subtitle">{essay.subtitle}</p>
            ) : null}
          </div>

          <div className="article-meta">
            <time dateTime={essay.dateISO}>{essay.date}</time>
            {essay.sourceUrl ? (
              <a href={essay.sourceUrl} target="_blank" rel="noreferrer">
                Source repository ↗
              </a>
            ) : null}
          </div>
        </header>

        <div className="article-rule" aria-hidden="true">
          <span />
        </div>

        <div className="article-body">
          <Content components={essayComponents} />
        </div>

        <footer className="article-footer">
          <Link href="/#essays">← 返回文章列表</Link>
        </footer>
      </article>
    </main>
  );
}
