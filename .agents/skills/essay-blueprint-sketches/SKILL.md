---
name: essay-blueprint-sketches
description: >-
  Create and style damienwen.dev essay blueprint sketches: white-plate SVG
  line diagrams with mono FIG labels, geometric nodes, and short Chinese
  captions. Use when adding, editing, or redesigning article illustrations,
  essay diagrams, or line sketches inside MDX essays.
---

# Essay Blueprint Sketches

White-plate architectural line diagrams for essay bodies — not photos, not
dark full-bleed art, not decorative illustration. One idea per figure.

This skill owns article diagrams only. Site chrome, cover, and fonts live in
`objects-echoes-design`. Essay authoring and publish live in
`publish-damienwen-site`.

## Source of truth

Read before inventing new forms:

- Styles: `.essay-sketch*` and `.es-*` in `app/globals.css`
- Shell pattern: `app/rama-sketches.tsx`, `app/skill-harness-sketches.tsx`
- MDX registration: `app/essay-components.tsx`

Extend existing classes and the `SketchShell` pattern. Do not fork a second
diagram palette.

## Visual grammar

| Piece | Rule |
| --- | --- |
| Plate | White `#fff` background, hairline border, sits on reading `#fafafa` |
| Strokes | Black/gray only; thin; square caps; miter joins |
| Nodes | Circles, diamonds, small plates — geometric, sparse |
| Structure labels | English, JetBrains Mono, uppercase / tracked |
| Caption | Short Chinese under the plate (`Taipei Sans` via `.essay-sketch-caption`) |
| Fig chrome | Indigo mono `FIG / 01` + short English label |
| Accent | At most one indigo fill (`es-anchor-core`); no extra colors |

Tokens that matter (do not invent alternatives):

```css
--ink: #191a1b;
--accent: #34429e;   /* figcaption + rare anchor fill only */
--hairline / --hairline-bold;
--mono / --sans;
```

## Sketch rules

1. One idea per figure; prefer **2–3 figures max** per essay.
2. Keep `viewBox` ~`640×280`; width follows the measure column via CSS.
3. Reuse stroke classes: `es-draw`, `es-rail`, `es-line-strong`, `es-node-*`,
   `es-plate`, `es-meta`, `es-label`.
4. Mono English inside the SVG for structure; Chinese only in the caption.
5. Provide `role="img"` and a Chinese `aria-label` on the `<svg>`.

### Avoid

- Black / night full-bleed plates inside light prose
- Photos or heavy illustration (use `<ArticleImage />` only when the essay
  already needs photos)
- New accent colors, gradients, glow, filled cartoon shapes
- Dense labels, legends, or multi-panel dashboards in one figure
- Cover-style black grid art inside the article body

## Implementation workflow

1. Confirm the figure explains a structural idea in the essay (not decoration).
2. Add SVG React components in a dedicated file, e.g.
   `app/<essay-slug>-sketches.tsx` — copy the `SketchShell` from
   `rama-sketches.tsx` first.
3. Export named components (`FooBarSketch`).
4. Register them in `app/essay-components.tsx` (import + `components` map).
5. Place in MDX next to the paragraph they clarify, e.g. `<FooBarSketch />`.
6. Preview the essay route locally; check light plate contrast and label
   overflow at narrow widths.
7. Run `npm run typecheck` (and `npm run verify` before publish).

### SketchShell template

```tsx
function SketchShell({
  caption,
  frame,
  label,
  children,
}: {
  caption: string;
  frame: string;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <figure className="essay-sketch">
      <figcaption>
        <span>{frame}</span>
        <span>{label}</span>
      </figcaption>
      <div className="essay-sketch-stage">{children}</div>
      <p className="essay-sketch-caption">{caption}</p>
    </figure>
  );
}
```

`frame` like `FIG / 01`, `label` like `DUAL MEMORY`, `caption` one short
Chinese sentence.

## Related skills

- Site-wide visual language (cover, chrome, fonts): `objects-echoes-design`
- Essay content, images, preview, VPS publish: `publish-damienwen-site`
