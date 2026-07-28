/**
 * Cover line sketch — simple blueprint geometry for Objects & Echoes.
 * Concentric arcs (echo) + framed vessel (object) + light hatch. No color.
 */
export function CoverSketch() {
  return (
    <svg
      className="cover-sketch"
      viewBox="0 0 520 320"
      role="img"
      aria-hidden="true"
      preserveAspectRatio="xMidYMid meet"
    >
      <defs>
        <clipPath id="cs-vessel-clip">
          <path d="M168 86 H352 L372 234 H148 Z" />
        </clipPath>
      </defs>

      <g
        className="cs-meta"
        fontFamily="'JetBrains Mono', ui-monospace, monospace"
      >
        <text x="24" y="28">
          FRAME / 01
        </text>
        <text x="496" y="28" textAnchor="end">
          LINEAR FILL
        </text>
      </g>

      <g className="cs-axis" fill="none">
        <path d="M24 292 H496" pathLength={1} />
        <path d="M260 36 V292" pathLength={1} />
      </g>

      <g className="cs-echo" fill="none">
        <path d="M260 160 A70 70 0 0 1 330 230" pathLength={1} />
        <path d="M260 160 A110 110 0 0 1 370 270" pathLength={1} />
        <path d="M260 160 A150 150 0 0 1 410 292" pathLength={1} />
        <path d="M260 160 A70 70 0 0 0 190 230" pathLength={1} />
        <path d="M260 160 A110 110 0 0 0 150 270" pathLength={1} />
      </g>

      <g className="cs-hatch" clipPath="url(#cs-vessel-clip)">
        {Array.from({ length: 14 }, (_, i) => {
          const x = 140 + i * 22;
          return (
            <line
              key={i}
              className="cs-hatch-line"
              x1={x}
              y1="250"
              x2={x - 70}
              y2="70"
              pathLength={1}
              style={{ ["--d" as string]: `${0.42 + i * 0.03}s` }}
            />
          );
        })}
      </g>

      <g className="cs-vessel" fill="none">
        <path
          className="cs-line-primary"
          d="M168 86 H352 L372 234 H148 Z"
          pathLength={1}
        />
        <path
          className="cs-line-secondary"
          d="M188 112 H332 L344 198 H176 Z"
          pathLength={1}
        />
        <path className="cs-line-tertiary" d="M260 86 V234" pathLength={1} />
        <path className="cs-line-tertiary" d="M168 160 H352" pathLength={1} />
      </g>

      <g className="cs-ticks" fill="none">
        <path d="M24 52 H88 M432 52 H496 M24 52 V96 M496 52 V96" />
        <path d="M24 248 H88 M432 248 H496 M24 204 V248 M496 204 V248" />
      </g>

      <g className="cs-anchor">
        <rect
          className="cs-anchor-plate"
          x="248"
          y="148"
          width="24"
          height="24"
          transform="rotate(45 260 160)"
        />
        <rect className="cs-anchor-core" x="254" y="154" width="12" height="12" />
      </g>

      <g
        className="cs-meta cs-callout"
        fontFamily="'JetBrains Mono', ui-monospace, monospace"
      >
        <text x="260" y="312" textAnchor="middle">
          OBJECT · ECHO FIELD
        </text>
      </g>
    </svg>
  );
}
