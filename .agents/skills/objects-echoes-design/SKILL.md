---
name: objects-echoes-design
description: >-
  Apply the Objects & Echoes (器物与回声 / damienwen.dev) visual language:
  black grid cover, light editorial reading chrome, Zhuque Fangsong titles,
  Taipei Sans body, indigo accent, and white-plate blueprint essay sketches.
  Use when redesigning pages, styling the cover or article chrome, choosing
  fonts, or adding essay illustrations / line diagrams for this site.
---

# Objects & Echoes Design Language

Keep the site looking like a precise editorial playbook, not a warm paper
broadsheet and not a purple SaaS landing page. Prefer structure, hairlines,
and typography over decoration.

## Source of truth

- Tokens and layout: `app/globals.css`
- Font imports: `app/fonts.css` (self-hosted; no runtime Google / Zeoseven / jsDelivr CSS)
- Cover sketch: `app/cover-sketch.tsx`
- Essay sketches: `app/rama-sketches.tsx` (pattern for future essays)
- Root layout: `app/layout.tsx`

Read those files before inventing new visual forms. Extend existing classes
and components when possible.

## Visual intent

| Surface | Intent |
| --- | --- |
| Cover | Full-bleed black, architectural grid, large Latin serif brand, sparse mono meta, one indigo mark |
| Reading | Cool light `#fafafa`, hairline rules, quiet sticky header, measured column |
| Diagrams in articles | White plates, black/gray lines, mono labels — never dark full-bleed blocks inside light prose |

One accent only: indigo `#34429e`. Do not introduce purple gradients, glow
stacks, pill clusters, or card grids in the hero.

## Tokens (do not drift)

```css
--bg: #fafafa;
--ink: #191a1b;
--hairline: rgba(20, 22, 24, 0.12);
--accent: #34429e;
--cover: #000;
--serif: Instrument Serif + Songti fallbacks;          /* Latin display */
--title-cn: Zhuque Fangsong + FangSong fallbacks;      /* Chinese titles */
--sans: Taipei Sans TC + PingFang / Noto Sans;         /* body + UI */
--mono: JetBrains Mono;                                /* meta / fig labels */
--measure: 680px;
```

Fonts ship with the site:

- Latin faces via `@fontsource/*` (latin subsets only — never add Noto Serif SC)
- Body via `@vp-tw/taipei-sans-tc` Regular CSS
- Titles via vendored unicode-range files in `public/fonts/zhuque/`,
  linked from `app/layout.tsx` as `/fonts/zhuque/result.css`
  Refresh with `npm run fonts:zhuque` when upgrading Zhuque.

Do not reintroduce runtime `<link>` tags to Google Fonts, Zeoseven, or
jsDelivr for these faces.

## Typography rules

1. **Cover brand title**: English, Instrument Serif. One italic line is OK
   (`Objects` / `& Echoes`). Keep Chinese site name in metadata if needed.
2. **Chinese headings** (list titles, article H1, section H2): Zhuque Fangsong
   via `--title-cn`. Slight positive tracking is fine; avoid heavy weight.
3. **Body / captions / subtitles**: Taipei Sans via `--sans`.
4. **Meta** (dates, FIG labels, nav, kicker tags): JetBrains Mono, small,
   uppercase or tracked.

Do not set Chinese display type in Instrument Serif. Do not use Noto Serif SC
as the primary Chinese title face anymore.

## Cover pattern

Required pieces:

- Visible grid (few vlines / hlines at low opacity)
- Kicker: author + short label + small square mark
- Year + short uppercase tag line on a grid intersection
- Optional line sketch (`CoverSketch`) in open quadrant — hatch, axes,
  echo arcs, mono callouts; no color fills
- Large brand title bottom-left + indigo accent bar
- Quiet scroll cue to `#essays`

Motion: short blur/fade/draw-in only; respect `prefers-reduced-motion`.

## Article chrome

- Sticky light header with indigo square wordmark + mono nav
- Essay header: mono `Essay` + number, Zhuque title, Taipei subtitle, meta rail
- Section numbers via CSS counters; indigo markers
- Hairline dividers; no ornamental ✦ staff lines

## Essay illustrations (blueprint sketches)

When an essay needs diagrams:

1. Add SVG React components (see `app/rama-sketches.tsx`).
2. Register them in `app/essay-components.tsx`.
3. Place them in MDX near the idea they explain.
4. Style with `.essay-sketch` — **white background, dark strokes**, indigo
   figcaption labels (`FIG / 01`), short Chinese caption under the plate.

Sketch grammar:

- Thin strokes, square caps, geometric nodes (circles / diamonds / plates)
- Mono English labels for structure; Chinese only in the caption
- One idea per figure; prefer 2–3 figures max per essay
- Keep viewBox ~640×280; width follows the measure column

Avoid:

- Black/night full-bleed plates inside article body (too abrupt on `#fafafa`)
- Photos or heavy illustration unless the essay already uses `<ArticleImage />`
- New accent colors inside diagrams

## Workflow

1. Confirm the change is visual/layout for this site (not deploy/content ops).
2. Reuse tokens/classes above; extend rather than fork a second palette.
3. For new essay diagrams, copy the RAMA sketch shell pattern first.
4. Preview the affected route locally.
5. Update `tests/rendered-html.test.mjs` if the homepage or essay chrome
   strings change in a testable way.
6. Run `npm run typecheck` (and `npm run verify` before publish).

## Related skills

For essay authoring, images, preview, and VPS publish, use
`publish-damienwen-site`. This skill only governs visual language.
