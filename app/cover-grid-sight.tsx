"use client";

/**
 * Drafting-style sight at cover grid intersections.
 * Faint crosshair when the pointer nears a vline×hline crossing;
 * nearest mono labels step up one brightness notch.
 * Disabled for reduced motion and coarse (touch) pointers.
 */

import { useEffect, useRef } from "react";

const SNAP_RADIUS = 40;
const LABEL_RADIUS = 96;
const ARM = 14;

type Intersection = {
  x: number;
  y: number;
  vline: HTMLElement;
  hline: HTMLElement;
};

function visibleGridLines(cover: HTMLElement, selector: string) {
  return [...cover.querySelectorAll<HTMLElement>(selector)].filter(
    (el) => getComputedStyle(el).display !== "none",
  );
}

function collectIntersections(cover: HTMLElement): Intersection[] {
  const coverRect = cover.getBoundingClientRect();
  const vlines = visibleGridLines(cover, ".cover-vline").map((el) => {
    const rect = el.getBoundingClientRect();
    return { el, x: rect.left + rect.width / 2 - coverRect.left };
  });
  const hlines = visibleGridLines(cover, ".cover-hline").map((el) => {
    const rect = el.getBoundingClientRect();
    return { el, y: rect.top + rect.height / 2 - coverRect.top };
  });

  const points: Intersection[] = [];
  for (const vline of vlines) {
    for (const hline of hlines) {
      points.push({
        x: vline.x,
        y: hline.y,
        vline: vline.el,
        hline: hline.el,
      });
    }
  }
  return points;
}

export function CoverGridSight() {
  const sightRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const sight = sightRef.current;
    if (!sight) return;

    const cover = sight.closest(".cover");
    if (!(cover instanceof HTMLElement)) return;

    const reduceMedia = window.matchMedia("(prefers-reduced-motion: reduce)");
    const coarseMedia = window.matchMedia("(pointer: coarse)");
    let reduced = reduceMedia.matches;
    let coarse = coarseMedia.matches;
    let intersections = collectIntersections(cover);
    let lastPointer: { x: number; y: number } | null = null;
    let activeV: HTMLElement | null = null;
    let activeH: HTMLElement | null = null;
    const litLabels = new Set<Element>();

    const clearLines = () => {
      activeV?.classList.remove("is-sight-line");
      activeH?.classList.remove("is-sight-line");
      activeV = null;
      activeH = null;
    };

    const clearLabels = () => {
      litLabels.forEach((el) => el.classList.remove("is-sight-lit"));
      litLabels.clear();
    };

    const hide = () => {
      sight.dataset.active = "false";
      sight.style.opacity = "0";
      clearLines();
      clearLabels();
    };

    const release = () => {
      lastPointer = null;
      hide();
    };

    const inactive = () => reduced || coarse;

    const updateLabels = (ix: number, iy: number, coverRect: DOMRect) => {
      clearLabels();
      const labels = cover.querySelectorAll(".cover-year, .cover-tags, .cs-meta");
      labels.forEach((el) => {
        const rect = el.getBoundingClientRect();
        if (rect.width === 0 && rect.height === 0) return;
        const cx = rect.left + rect.width / 2 - coverRect.left;
        const cy = rect.top + rect.height / 2 - coverRect.top;
        if (Math.hypot(cx - ix, cy - iy) <= LABEL_RADIUS) {
          el.classList.add("is-sight-lit");
          litLabels.add(el);
        }
      });
    };

    const applySight = (clientX: number, clientY: number) => {
      if (inactive() || intersections.length === 0) {
        hide();
        return;
      }

      const coverRect = cover.getBoundingClientRect();
      const localX = clientX - coverRect.left;
      const localY = clientY - coverRect.top;

      let nearest: Intersection | null = null;
      let nearestDist = Infinity;
      for (const point of intersections) {
        const dist = Math.hypot(point.x - localX, point.y - localY);
        if (dist < nearestDist) {
          nearestDist = dist;
          nearest = point;
        }
      }

      if (!nearest || nearestDist > SNAP_RADIUS) {
        hide();
        return;
      }

      const strength = 1 - nearestDist / SNAP_RADIUS;
      sight.dataset.active = "true";
      sight.style.opacity = String(0.22 + strength * 0.5);
      sight.style.transform = `translate(${nearest.x}px, ${nearest.y}px)`;

      if (activeV !== nearest.vline || activeH !== nearest.hline) {
        clearLines();
        nearest.vline.classList.add("is-sight-line");
        nearest.hline.classList.add("is-sight-line");
        activeV = nearest.vline;
        activeH = nearest.hline;
      }

      updateLabels(nearest.x, nearest.y, coverRect);
    };

    const onPointerMove = (event: PointerEvent) => {
      if (inactive()) return;
      lastPointer = { x: event.clientX, y: event.clientY };
      applySight(event.clientX, event.clientY);
    };

    const onPointerLeave = () => {
      release();
    };

    const onScroll = () => {
      if (inactive() || !lastPointer) return;
      intersections = collectIntersections(cover);
      const rect = cover.getBoundingClientRect();
      const inside =
        lastPointer.x >= rect.left &&
        lastPointer.x <= rect.right &&
        lastPointer.y >= rect.top &&
        lastPointer.y <= rect.bottom;
      if (!inside) {
        release();
        return;
      }
      applySight(lastPointer.x, lastPointer.y);
    };

    const refreshGeometry = () => {
      intersections = collectIntersections(cover);
      if (lastPointer) applySight(lastPointer.x, lastPointer.y);
      else hide();
    };

    const syncPrefs = () => {
      reduced = reduceMedia.matches;
      coarse = coarseMedia.matches;
      if (inactive()) release();
    };

    hide();
    syncPrefs();
    reduceMedia.addEventListener("change", syncPrefs);
    coarseMedia.addEventListener("change", syncPrefs);
    cover.addEventListener("pointermove", onPointerMove);
    cover.addEventListener("pointerleave", onPointerLeave);
    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", refreshGeometry);
    window.visualViewport?.addEventListener("resize", refreshGeometry);
    window.visualViewport?.addEventListener("scroll", onScroll);

    return () => {
      reduceMedia.removeEventListener("change", syncPrefs);
      coarseMedia.removeEventListener("change", syncPrefs);
      cover.removeEventListener("pointermove", onPointerMove);
      cover.removeEventListener("pointerleave", onPointerLeave);
      window.removeEventListener("scroll", onScroll);
      window.removeEventListener("resize", refreshGeometry);
      window.visualViewport?.removeEventListener("resize", refreshGeometry);
      window.visualViewport?.removeEventListener("scroll", onScroll);
      clearLines();
      clearLabels();
    };
  }, []);

  return (
    <div
      ref={sightRef}
      className="cover-sight"
      aria-hidden="true"
      data-active="false"
    >
      <i
        className="cover-sight-arm cover-sight-arm-h"
        style={{ width: ARM * 2, marginLeft: -ARM }}
      />
      <i
        className="cover-sight-arm cover-sight-arm-v"
        style={{ height: ARM * 2, marginTop: -ARM }}
      />
      <i className="cover-sight-core" />
    </div>
  );
}
