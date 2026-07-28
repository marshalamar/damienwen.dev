import Link from "next/link";
import { essays } from "../lib/essays";
import { SiteHeader } from "./site-header";

export default function Home() {
  return (
    <main className="site-shell">
      <SiteHeader />

      <section className="hero" aria-labelledby="site-title">
        <div className="hero-heading">
          <h1 id="site-title">
            器物
            <br />
            与回声
          </h1>
        </div>

        <aside className="hero-index" aria-label="站点信息">
          <span>BEIJING · MMXXVI</span>
        </aside>

        <div className="staff-lines" aria-hidden="true">
          <span>✦</span>
        </div>
      </section>

      <section
        className="essay-list"
        id="essays"
        aria-labelledby="essay-list-title"
      >
        <div className="section-heading">
          <h2 id="essay-list-title">文章</h2>
        </div>

        <div className="essay-rows">
          {essays.map((essay) => (
            <Link
              className="essay-row"
              href={`/essays/${essay.slug}`}
              key={essay.slug}
            >
              <span className="essay-number">{essay.number}</span>
              <span className="essay-row-copy">
                <span className="essay-row-title">{essay.title}</span>
                {essay.subtitle ? (
                  <span className="essay-row-subtitle">{essay.subtitle}</span>
                ) : null}
              </span>
              <time className="essay-date" dateTime={essay.dateISO}>
                {essay.date}
              </time>
              <span className="essay-arrow" aria-hidden="true">
                ↗
              </span>
            </Link>
          ))}
        </div>
      </section>
    </main>
  );
}
