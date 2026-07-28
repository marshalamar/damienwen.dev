import Link from "next/link";
import { essays } from "../lib/essays";
import { CoverSketch } from "./cover-sketch";

export default function Home() {
  return (
    <main className="site-shell">
      <section className="cover" aria-labelledby="site-title">
        <div className="cover-grid" aria-hidden="true">
          <span className="cover-vline" />
          <span className="cover-vline" />
          <span className="cover-vline" />
          <span className="cover-hline" />
          <span className="cover-hline" />
          <span className="cover-hline" />
          <span className="cover-hline" />
          <span className="cover-hline" />
        </div>

        <header className="cover-header">
          <a
            href="https://github.com/marshalamar"
            target="_blank"
            rel="noreferrer"
          >
            GitHub ↗
          </a>
        </header>

        <p className="cover-kicker" aria-label="Damien Wen">
          <span>Damien Wen</span>
          <span>
            Essays
            <i className="cover-sq" aria-hidden="true" />
          </span>
        </p>

        <p className="cover-year">2026</p>
        <p className="cover-tags">
          Music, Memory,
          <br />
          And Making.
        </p>

        <div className="cover-figure" aria-hidden="true">
          <CoverSketch />
        </div>

        <h1 className="cover-title" id="site-title">
          <span>Objects</span>
          <span className="cover-title-italic">
            &amp; Echoes
            <i className="cover-accent" aria-hidden="true" />
          </span>
        </h1>

        <a className="cover-scroll" href="#essays">
          Index ↓
        </a>
      </section>

      <section
        className="essay-list"
        id="essays"
        aria-labelledby="essay-list-title"
      >
        <div className="section-heading">
          <h2 id="essay-list-title">文章</h2>
          <span className="section-heading-meta">
            {String(essays.length).padStart(2, "0")} entries
          </span>
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
