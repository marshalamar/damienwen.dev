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

/** Nested containment ends at absolute nothingness. */
export function BashoContainmentSketch() {
  return (
    <SketchShell
      frame="FIG / 01"
      label="PLACE CHAIN"
      caption="有被场所包含；链条停在自身不是有的绝对无。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="场所包含链条示意图：水、杯、屋被更大的场所容纳，终点是绝对无"
      >
        <g className="es-meta">
          <text x="28" y="36">
            CONTAINMENT
          </text>
          <text x="612" y="36" textAnchor="end">
            ENDS AT MU
          </text>
        </g>

        {/* Nested places: water → cup → room */}
        <g className="es-draw" fill="none">
          <rect className="es-plate" x="48" y="64" width="280" height="168" />
          <text className="es-label" x="64" y="88">
            ROOM
          </text>

          <rect className="es-plate" x="96" y="108" width="184" height="96" />
          <text className="es-label" x="112" y="132">
            CUP
          </text>

          <circle className="es-node-solid" cx="188" cy="168" r="18" />
          <text className="es-label es-label-center" x="188" y="172">
            WATER
          </text>
        </g>

        {/* Arrow into absolute nothingness */}
        <g className="es-draw" fill="none">
          <path className="es-line-strong" d="M348 148 H420" pathLength={1} />
          <path d="M408 140 L420 148 L408 156" pathLength={1} />

          <rect className="es-node-ghost" x="436" y="88" width="156" height="120" />
          <text className="es-label es-label-center" x="514" y="136">
            ABSOLUTE
          </text>
          <text className="es-label es-label-center" x="514" y="156">
            NOTHINGNESS
          </text>
          <rect
            className="es-anchor-plate"
            x="502"
            y="176"
            width="24"
            height="24"
            transform="rotate(45 514 188)"
          />
          <rect className="es-anchor-core" x="508" y="182" width="12" height="12" />
        </g>

        <g className="es-meta">
          <text x="28" y="260">
            BEING ⊂ PLACE
          </text>
          <text x="612" y="260" textAnchor="end">
            PLACE ≠ BEING
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Model is being; harness is relational nothing. */
export function BashoBeingNothingSketch() {
  return (
    <SketchShell
      frame="FIG / 02"
      label="BEING / NOTHING"
      caption="模型可被单独指向；harness 只有关系，没有自性。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="有与无对照示意图：左侧独立存在的模型，右侧仅由关系构成的 harness"
      >
        <g className="es-meta">
          <text x="28" y="36">
            MODEL = BEING
          </text>
          <text x="612" y="36" textAnchor="end">
            HARNESS = MU
          </text>
        </g>

        {/* Model: solid, nameable */}
        <g className="es-draw" fill="none">
          <rect className="es-plate es-plate-lg" x="56" y="72" width="200" height="140" />
          <text className="es-label es-label-center" x="156" y="108">
            MODEL
          </text>
          <path d="M88 128 H224" pathLength={1} />
          <text className="es-label" x="88" y="152">
            NAME · VERSION
          </text>
          <text className="es-label" x="88" y="176">
            DOWNLOADABLE
          </text>
          <text className="es-label" x="88" y="200">
            CALLABLE ALONE
          </text>
        </g>

        {/* Harness: empty frame, relational */}
        <g className="es-draw" fill="none">
          <rect className="es-node-ghost" x="384" y="72" width="200" height="140" />
          <text className="es-label es-label-center" x="484" y="108">
            HARNESS
          </text>
          <path d="M416 128 H552" pathLength={1} />
          <text className="es-label" x="416" y="152">
            CONFIG · TOOLS
          </text>
          <text className="es-label" x="416" y="176">
            EMPTY CONTEXT
          </text>
          <text className="es-label" x="416" y="200">
            NO SELF-NATURE
          </text>
        </g>

        <g className="es-meta">
          <text x="156" y="260" textAnchor="middle">
            POINTABLE
          </text>
          <text x="484" y="260" textAnchor="middle">
            RELATIONAL ONLY
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Neither alone is a system; they co-constitute. */
export function BashoMutualSketch() {
  return (
    <SketchShell
      frame="FIG / 03"
      label="CO-CONSTITUTION"
      caption="各自不成系统；有和无凑在一起，显现才成立。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="互相成就示意图：模型与 harness 单独无效，合在一起构成系统"
      >
        <g className="es-meta">
          <text x="28" y="36">
            ALONE INCOMPLETE
          </text>
          <text x="612" y="36" textAnchor="end">
            TOGETHER = SYSTEM
          </text>
        </g>

        {/* Alone: model drifts */}
        <g className="es-draw" fill="none">
          <circle className="es-node-soft" cx="108" cy="120" r="28" />
          <text className="es-label es-label-center" x="108" y="124">
            MODEL
          </text>
          <path d="M148 120 H196" pathLength={1} />
          <text className="es-label" x="156" y="108">
            DRIFT
          </text>
          <text className="es-label es-label-center" x="108" y="176">
            NO PLACE
          </text>
        </g>

        {/* Alone: harness idle */}
        <g className="es-draw" fill="none">
          <rect className="es-node-ghost" x="248" y="92" width="96" height="56" />
          <text className="es-label es-label-center" x="296" y="124">
            HARNESS
          </text>
          <text className="es-label es-label-center" x="296" y="176">
            NOTHING HAPPENS
          </text>
        </g>

        {/* Together */}
        <g className="es-draw" fill="none">
          <path className="es-line-strong" d="M360 120 H412" pathLength={1} />
          <path d="M400 112 L412 120 L400 128" pathLength={1} />

          <rect className="es-plate" x="428" y="72" width="168" height="112" />
          <circle className="es-node-solid" cx="512" cy="116" r="22" />
          <text className="es-label es-label-center" x="512" y="120">
            MODEL
          </text>
          <text className="es-label es-label-center" x="512" y="164">
            IN PLACE
          </text>

          <rect
            className="es-anchor-plate"
            x="500"
            y="188"
            width="24"
            height="24"
            transform="rotate(45 512 200)"
          />
          <rect className="es-anchor-core" x="506" y="194" width="12" height="12" />
        </g>

        <g className="es-meta">
          <text x="320" y="260" textAnchor="middle">
            NOT OPPOSITES · MUTUAL ENABLEMENT
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}
