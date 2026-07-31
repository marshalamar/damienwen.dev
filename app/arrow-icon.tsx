type ArrowDirection = "ne" | "down" | "left";

type ArrowIconProps = {
  direction?: ArrowDirection;
  className?: string;
};

const PATHS: Record<ArrowDirection, string> = {
  ne: "M5 11L11 5M11 5H6.25M11 5V9.75",
  down: "M8 3.5V12M8 12L4.75 8.75M8 12L11.25 8.75",
  left: "M12.5 8H4M4 8L7.25 4.75M4 8L7.25 11.25",
};

export function ArrowIcon({ direction = "ne", className }: ArrowIconProps) {
  return (
    <svg
      className={["arrow-icon", className].filter(Boolean).join(" ")}
      viewBox="0 0 16 16"
      width="1em"
      height="1em"
      fill="none"
      aria-hidden="true"
    >
      <path
        d={PATHS[direction]}
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="square"
        strokeLinejoin="miter"
      />
    </svg>
  );
}
