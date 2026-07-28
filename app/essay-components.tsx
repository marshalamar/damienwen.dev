import type { ImgHTMLAttributes, ReactNode } from "react";
import type { MDXComponents } from "mdx/types";
import {
  RamaDualTrackSketch,
  RamaLocalFileSketch,
  RamaLoopSketch,
} from "./rama-sketches";

type SectionProps = {
  title: string;
  children: ReactNode;
};

type ArticleImageProps = Omit<
  ImgHTMLAttributes<HTMLImageElement>,
  "alt" | "height" | "width"
> & {
  alt: string;
  height: number;
  width: number;
};

export function Section({ title, children }: SectionProps) {
  return (
    <section>
      <div className="section-number" aria-hidden="true" />
      <div className="article-section-copy">
        <h2>{title}</h2>
        {children}
      </div>
    </section>
  );
}

export function ArticleImage({
  alt,
  decoding = "async",
  height,
  loading = "lazy",
  width,
  ...imageProps
}: ArticleImageProps) {
  return (
    <figure className="article-image">
      {/* MDX authors may supply image dimensions at content-authoring time. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        {...imageProps}
        alt={alt}
        decoding={decoding}
        height={height}
        loading={loading}
        width={width}
      />
    </figure>
  );
}

export const essayComponents = {
  Section,
  ArticleImage,
  RamaDualTrackSketch,
  RamaLoopSketch,
  RamaLocalFileSketch,
} satisfies MDXComponents;
