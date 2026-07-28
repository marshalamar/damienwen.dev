import type { ReactNode } from "react";

type SketchShellProps = {
  caption: string;
  frame: string;
  label: string;
  children: ReactNode;
};

function SketchShell({ caption, frame, label, children }: SketchShellProps) {
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

/** Dual rails: play history as clue vs spoken preference as committed memory. */
export function RamaDualTrackSketch() {
  return (
    <SketchShell
      frame="FIG / 01"
      label="DUAL MEMORY"
      caption="听过的歌只作线索；亲口说过的话才进入长期记忆。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="双轨记忆示意图：播放记录与口头偏好分开保存"
      >
        <g className="es-meta">
          <text x="28" y="36">
            PLAY HISTORY
          </text>
          <text x="612" y="36" textAnchor="end">
            CLUE ONLY
          </text>
        </g>

        {/* Top rail — play history */}
        <g className="es-rail" fill="none">
          <path d="M48 88 H592" pathLength={1} />
          {[120, 200, 280, 360, 440, 520].map((x, i) => (
            <circle
              key={`play-${x}`}
              className={i % 2 === 0 ? "es-node-soft" : "es-node-ghost"}
              cx={x}
              cy="88"
              r="5"
            />
          ))}
          <text className="es-label" x="48" y="72">
            RECENT PLAYS · NETEASE HISTORY
          </text>
        </g>

        {/* Bottom rail — spoken memory */}
        <g className="es-rail" fill="none">
          <path className="es-line-strong" d="M48 188 H592" pathLength={1} />
          {[160, 280, 400, 520].map((x) => (
            <rect
              key={`spoken-${x}`}
              className="es-node-solid"
              x={x - 6}
              y="182"
              width="12"
              height="12"
              transform={`rotate(45 ${x} 188)`}
            />
          ))}
          <text className="es-label" x="48" y="172">
            SPOKEN PREFERENCE · COMMITTED
          </text>
        </g>

        {/* Gate: only spoken path enters long-term store */}
        <g className="es-gate" fill="none">
          <path d="M560 108 V168" pathLength={1} />
          <path d="M548 156 L560 168 L572 156" pathLength={1} />
          <rect className="es-plate" x="500" y="208" width="104" height="36" />
          <text className="es-label es-label-center" x="552" y="230">
            LONG-TERM
          </text>
        </g>

        <g className="es-meta">
          <text x="28" y="260">
            LISTENED ≠ LIKED
          </text>
          <text x="612" y="260" textAnchor="end">
            SAID → KEPT
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Recommend loop: memory → RYM → album → feedback. */
export function RamaLoopSketch() {
  const nodes = [
    { x: 140, y: 140, label: "MEMORY" },
    { x: 320, y: 70, label: "RYM" },
    { x: 500, y: 140, label: "ALBUM" },
    { x: 320, y: 210, label: "FEEDBACK" },
  ] as const;

  return (
    <SketchShell
      frame="FIG / 02"
      label="RECOMMEND LOOP"
      caption="从记忆出发找下一张专辑，听完后再把感受写回本地。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="推荐回路示意图：记忆、RYM、专辑与反馈形成闭环"
      >
        <g className="es-meta">
          <text x="28" y="36">
            LOOP / OPEN
          </text>
          <text x="612" y="36" textAnchor="end">
            NO EXTRA RANKER
          </text>
        </g>

        {/* Loop path */}
        <g className="es-loop" fill="none">
          <path
            className="es-line-strong"
            d="M170 130 C220 90, 260 70, 300 70"
            pathLength={1}
          />
          <path
            className="es-line-strong"
            d="M340 70 C380 70, 420 90, 470 130"
            pathLength={1}
          />
          <path
            className="es-line-strong"
            d="M470 150 C420 190, 380 210, 340 210"
            pathLength={1}
          />
          <path
            className="es-line-strong"
            d="M300 210 C260 210, 220 190, 170 150"
            pathLength={1}
          />
        </g>

        {nodes.map((node) => (
          <g key={node.label} className="es-loop-node">
            <rect
              className="es-plate"
              x={node.x - 46}
              y={node.y - 18}
              width="92"
              height="36"
            />
            <text
              className="es-label es-label-center"
              x={node.x}
              y={node.y + 4}
            >
              {node.label}
            </text>
          </g>
        ))}

        {/* Center anchor */}
        <g className="es-anchor">
          <rect
            className="es-anchor-plate"
            x="308"
            y="128"
            width="24"
            height="24"
            transform="rotate(45 320 140)"
          />
          <rect className="es-anchor-core" x="314" y="134" width="12" height="12" />
        </g>

        <g className="es-meta">
          <text x="320" y="260" textAnchor="middle">
            LISTEN → JUDGE → WRITE BACK
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Local markdown file stays under user control while the agent reads it. */
export function RamaLocalFileSketch() {
  return (
    <SketchShell
      frame="FIG / 03"
      label="LOCAL STORE"
      caption="music-memory.md 留在本地：可看、可改、可删、可带走。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="本地记忆文件示意图：Agent 可读取，文件仍由用户保管"
      >
        <g className="es-meta">
          <text x="28" y="36">
            FILE / OWNED
          </text>
          <text x="612" y="36" textAnchor="end">
            VISIBLE · EDITABLE
          </text>
        </g>

        {/* Precision ticks */}
        <g className="es-ticks" fill="none">
          <path d="M120 56 H168 M472 56 H520 M120 56 V96 M520 56 V96" />
          <path d="M120 224 H168 M472 224 H520 M120 184 V224 M520 184 V224" />
        </g>

        {/* Document plate */}
        <g className="es-doc" fill="none">
          <rect className="es-plate es-plate-lg" x="190" y="68" width="260" height="144" />
          <path d="M214 100 H426" pathLength={1} />
          <path d="M214 124 H390" pathLength={1} />
          <path d="M214 148 H410" pathLength={1} />
          <path d="M214 172 H360" pathLength={1} />
          <text className="es-label es-label-center" x="320" y="198">
            music-memory.md
          </text>
        </g>

        {/* Agent read arrow from outside */}
        <g className="es-agent" fill="none">
          <rect className="es-plate" x="48" y="118" width="88" height="44" />
          <text className="es-label es-label-center" x="92" y="144">
            AGENT
          </text>
          <path className="es-line-strong" d="M140 140 H186" pathLength={1} />
          <path d="M176 132 L186 140 L176 148" pathLength={1} />
        </g>

        {/* Portable mark */}
        <g className="es-portable" fill="none">
          <rect className="es-plate" x="504" y="118" width="88" height="44" />
          <text className="es-label es-label-center" x="548" y="144">
            EXPORT
          </text>
          <path className="es-line-strong" d="M454 140 H500" pathLength={1} />
          <path d="M490 132 L500 140 L490 148" pathLength={1} />
        </g>

        <g className="es-meta">
          <text x="320" y="260" textAnchor="middle">
            CONTEXT IN · OWNERSHIP OUT
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}
