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

/** Skill volume grows; human review capacity does not. */
export function SkillVolumeSketch() {
  const layers = [
    { y: 188, w: 120, opacity: "es-node-ghost" },
    { y: 164, w: 160, opacity: "es-node-soft" },
    { y: 140, w: 200, opacity: "es-node-soft" },
    { y: 116, w: 240, opacity: "es-node-solid" },
    { y: 92, w: 280, opacity: "es-node-solid" },
  ] as const;

  return (
    <SketchShell
      frame="FIG / 01"
      label="VOLUME GAP"
      caption="Skill 体量持续累积；审查能力仍停在个人通读的尺度上。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="体量膨胀示意图：Skill 堆叠增高，审查能力保持水平"
      >
        <g className="es-meta">
          <text x="28" y="36">
            SCALE / OPEN
          </text>
          <text x="612" y="36" textAnchor="end">
            READ CAPACITY FIXED
          </text>
        </g>

        {/* Growing skill stack */}
        <g className="es-draw" fill="none">
          <text className="es-label" x="96" y="72">
            SKILL CORPUS
          </text>
          {layers.map((layer, i) => {
            const x = 96 + (280 - layer.w) / 2;
            if (layer.opacity === "es-node-solid") {
              return (
                <rect
                  key={`layer-${i}`}
                  className="es-plate"
                  x={x}
                  y={layer.y}
                  width={layer.w}
                  height="20"
                />
              );
            }
            if (layer.opacity === "es-node-soft") {
              return (
                <rect
                  key={`layer-${i}`}
                  className="es-plate"
                  x={x}
                  y={layer.y}
                  width={layer.w}
                  height="20"
                  opacity={0.7}
                />
              );
            }
            return (
              <rect
                key={`layer-${i}`}
                className="es-node-ghost"
                x={x}
                y={layer.y}
                width={layer.w}
                height="20"
              />
            );
          })}
          <path className="es-line-strong" d="M236 88 V72" pathLength={1} />
          <path d="M228 80 L236 72 L244 80" pathLength={1} />
        </g>

        {/* Fixed review capacity line */}
        <g className="es-draw" fill="none">
          <path className="es-line-strong" d="M420 200 H580" pathLength={1} />
          <rect className="es-plate" x="448" y="120" width="104" height="36" />
          <text className="es-label es-label-center" x="500" y="142">
            REVIEWER
          </text>
          <path d="M500 156 V196" pathLength={1} />
          <path d="M492 188 L500 196 L508 188" pathLength={1} />
          <text className="es-label" x="420" y="224">
            HUMAN READ LIMIT
          </text>
        </g>

        {/* Gap callout */}
        <g className="es-draw" fill="none">
          <path d="M340 140 H400" pathLength={1} />
          <rect
            className="es-anchor-plate"
            x="388"
            y="128"
            width="24"
            height="24"
            transform="rotate(45 400 140)"
          />
          <rect className="es-anchor-core" x="394" y="134" width="12" height="12" />
        </g>

        <g className="es-meta">
          <text x="28" y="260">
            WRITERS ↑
          </text>
          <text x="612" y="260" textAnchor="end">
            READERS ≠ WRITERS
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Putting reminders into the unread pile cannot constrain it. */
export function SkillReminderSketch() {
  return (
    <SketchShell
      frame="FIG / 02"
      label="SAME MATERIAL"
      caption="用更多文字去约束读不完的文字，只会让读不完更严重。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="提醒无效示意图：新增约束文字仍落入未读堆叠"
      >
        <g className="es-meta">
          <text x="28" y="36">
            CONTENT LOOP
          </text>
          <text x="612" y="36" textAnchor="end">
            NO HARD STOP
          </text>
        </g>

        {/* Unread pile */}
        <g className="es-draw" fill="none">
          <rect className="es-plate es-plate-lg" x="72" y="72" width="200" height="148" />
          <path d="M96 104 H248" pathLength={1} />
          <path d="M96 128 H232" pathLength={1} />
          <path d="M96 152 H240" pathLength={1} />
          <path d="M96 176 H210" pathLength={1} />
          <text className="es-label es-label-center" x="172" y="206">
            UNREAD STACK
          </text>
        </g>

        {/* Reminder plate feeding back in */}
        <g className="es-draw" fill="none">
          <rect className="es-plate" x="360" y="96" width="196" height="52" />
          <text className="es-label es-label-center" x="458" y="118">
            ADD REMINDER
          </text>
          <text className="es-label es-label-center" x="458" y="136">
            “STOP AND ASK”
          </text>

          <path className="es-line-strong" d="M360 122 H292" pathLength={1} />
          <path d="M304 114 L292 122 L304 130" pathLength={1} />

          <path d="M458 148 V188" pathLength={1} />
          <path d="M292 188 H458" pathLength={1} />
          <path d="M304 180 L292 188 L304 196" pathLength={1} />

          <text className="es-label" x="304" y="212">
            BACK INTO THE PILE
          </text>
        </g>

        <g className="es-meta">
          <text x="320" y="260" textAnchor="middle">
            TEXT ≠ CONSTRAINT
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}

/** Harness enforces structure outside content volume. */
export function SkillHarnessSketch() {
  return (
    <SketchShell
      frame="FIG / 03"
      label="HARNESS BOUNDARY"
      caption="内容层负责说明；权限与沙箱在结构上强制生效，不依赖是否读完。"
    >
      <svg
        className="essay-sketch-svg"
        viewBox="0 0 640 280"
        role="img"
        aria-label="Harness 边界示意图：内容层之上是强制生效的权限与沙箱"
      >
        <g className="es-meta">
          <text x="28" y="36">
            STRUCTURE / FORCE
          </text>
          <text x="612" y="36" textAnchor="end">
            VOLUME-INDEPENDENT
          </text>
        </g>

        {/* Content layer */}
        <g className="es-draw" fill="none">
          <rect className="es-plate" x="48" y="168" width="544" height="48" />
          <text className="es-label es-label-center" x="320" y="196">
            CONTENT · SKILLS · PROSE ADVICE
          </text>
        </g>

        {/* Structural barrier */}
        <g className="es-draw" fill="none">
          <path className="es-line-strong" d="M48 140 H592" pathLength={1} />
          <text className="es-label" x="48" y="128">
            HARNESS BOUNDARY
          </text>
        </g>

        {/* Enforcement nodes */}
        <g className="es-draw" fill="none">
          <rect className="es-plate" x="96" y="64" width="120" height="40" />
          <text className="es-label es-label-center" x="156" y="88">
            PERMISSION
          </text>
          <rect className="es-plate" x="260" y="64" width="120" height="40" />
          <text className="es-label es-label-center" x="320" y="88">
            SANDBOX
          </text>
          <rect className="es-plate" x="424" y="64" width="120" height="40" />
          <text className="es-label es-label-center" x="484" y="88">
            HUMAN GATE
          </text>

          <path d="M156 104 V136" pathLength={1} />
          <path d="M320 104 V136" pathLength={1} />
          <path d="M484 104 V136" pathLength={1} />
        </g>

        {/* Accent diamond on the boundary */}
        <g className="es-draw" fill="none">
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
          <text x="28" y="260">
            EXTERNAL · IRREVERSIBLE → BLOCK
          </text>
          <text x="612" y="260" textAnchor="end">
            INTENT → VERIFY
          </text>
        </g>
      </svg>
    </SketchShell>
  );
}
