"use client";

/**
 * Cover line sketch — simple blueprint geometry for Objects & Echoes.
 * Concentric arcs (echo) + framed vessel (object) + light hatch. No color.
 * Pointer over the cover gently deflects the echo rings toward the cursor.
 */

import { useEffect, useRef } from "react";

const ANCHOR_X = 260;
const ANCHOR_Y = 160;
const MAX_OFFSET = 11;
const REACH = 300;
const EASE = 0.14;
const RING_DEPTHS = [0.35, 0.7, 1] as const;

export function CoverSketch() {
  const svgRef = useRef<SVGSVGElement>(null);
  const ringsRef = useRef<(SVGGElement | null)[]>([]);
  const targetRef = useRef({ x: 0, y: 0 });
  const currentRef = useRef({ x: 0, y: 0 });
  const rafRef = useRef(0);
  const reducedRef = useRef(false);

  useEffect(() => {
    const svg = svgRef.current;
    if (!svg) return;

    const cover = svg.closest(".cover");
    if (!(cover instanceof HTMLElement)) return;

    const media = window.matchMedia("(prefers-reduced-motion: reduce)");
    let lastPointer: { x: number; y: number } | null = null;

    const apply = (x: number, y: number) => {
      ringsRef.current.forEach((ring, index) => {
        if (!ring) return;
        const depth = RING_DEPTHS[index] ?? 1;
        ring.setAttribute(
          "transform",
          `translate(${(x * depth).toFixed(3)} ${(y * depth).toFixed(3)})`,
        );
      });
      svg.style.setProperty("--echo-glow", Math.min(1, Math.hypot(x, y) / MAX_OFFSET).toFixed(3));
    };

    const settle = () => {
      targetRef.current = { x: 0, y: 0 };
      currentRef.current = { x: 0, y: 0 };
      apply(0, 0);
    };

    const pointerInsideCover = (clientX: number, clientY: number) => {
      const rect = cover.getBoundingClientRect();
      return (
        clientX >= rect.left &&
        clientX <= rect.right &&
        clientY >= rect.top &&
        clientY <= rect.bottom
      );
    };

    const tick = () => {
      const target = targetRef.current;
      const current = currentRef.current;
      current.x += (target.x - current.x) * EASE;
      current.y += (target.y - current.y) * EASE;

      if (
        Math.abs(target.x - current.x) < 0.02 &&
        Math.abs(target.y - current.y) < 0.02
      ) {
        current.x = target.x;
        current.y = target.y;
        apply(current.x, current.y);
        rafRef.current = 0;
        return;
      }

      apply(current.x, current.y);
      rafRef.current = requestAnimationFrame(tick);
    };

    const kick = () => {
      if (reducedRef.current) return;
      if (!rafRef.current) rafRef.current = requestAnimationFrame(tick);
    };

    const release = () => {
      lastPointer = null;
      targetRef.current = { x: 0, y: 0 };
      kick();
    };

    const syncReduced = () => {
      reducedRef.current = media.matches;
      if (media.matches) {
        if (rafRef.current) {
          cancelAnimationFrame(rafRef.current);
          rafRef.current = 0;
        }
        lastPointer = null;
        settle();
      }
    };
    syncReduced();
    media.addEventListener("change", syncReduced);

    const toSvgPoint = (clientX: number, clientY: number) => {
      const ctm = svg.getScreenCTM();
      if (!ctm) return null;
      const point = svg.createSVGPoint();
      point.x = clientX;
      point.y = clientY;
      return point.matrixTransform(ctm.inverse());
    };

    const onPointerMove = (event: PointerEvent) => {
      if (reducedRef.current) return;

      lastPointer = { x: event.clientX, y: event.clientY };

      const point = toSvgPoint(event.clientX, event.clientY);
      if (!point) return;

      const dx = point.x - ANCHOR_X;
      const dy = point.y - ANCHOR_Y;
      const dist = Math.hypot(dx, dy) || 1;
      const strength = Math.max(0, 1 - dist / REACH);

      targetRef.current = {
        x: (dx / dist) * MAX_OFFSET * strength,
        y: (dy / dist) * MAX_OFFSET * strength,
      };
      kick();
    };

    const onPointerLeave = () => {
      release();
    };

    // pointerleave does not fire when the cover scrolls out from under a
    // stationary cursor — re-check bounds on scroll and settle if needed.
    const onScroll = () => {
      if (reducedRef.current || !lastPointer) return;
      if (!pointerInsideCover(lastPointer.x, lastPointer.y)) {
        release();
      }
    };

    cover.addEventListener("pointermove", onPointerMove);
    cover.addEventListener("pointerleave", onPointerLeave);
    window.addEventListener("scroll", onScroll, { passive: true });

    return () => {
      media.removeEventListener("change", syncReduced);
      cover.removeEventListener("pointermove", onPointerMove);
      cover.removeEventListener("pointerleave", onPointerLeave);
      window.removeEventListener("scroll", onScroll);
      if (rafRef.current) cancelAnimationFrame(rafRef.current);
    };
  }, []);

  return (
    <svg
      ref={svgRef}
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
        <g
          className="cs-echo-ring"
          ref={(node) => {
            ringsRef.current[0] = node;
          }}
        >
          <path d="M260 160 A70 70 0 0 1 330 230" pathLength={1} />
          <path d="M260 160 A70 70 0 0 0 190 230" pathLength={1} />
        </g>
        <g
          className="cs-echo-ring"
          ref={(node) => {
            ringsRef.current[1] = node;
          }}
        >
          <path d="M260 160 A110 110 0 0 1 370 270" pathLength={1} />
          <path d="M260 160 A110 110 0 0 0 150 270" pathLength={1} />
        </g>
        <g
          className="cs-echo-ring"
          ref={(node) => {
            ringsRef.current[2] = node;
          }}
        >
          <path d="M260 160 A150 150 0 0 1 410 292" pathLength={1} />
        </g>
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
