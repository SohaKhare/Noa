import { useId } from "react";

const strokes = [
  "M27.4877 47.6194V31.8699C27.4877 29.0755 29.753 26.8102 32.5474 26.8102H48.8223",
  "M42.084 41.0476L28.6095 27.9048",
  "M48.8223 20.8095H32.5474C29.753 20.8095 27.4877 18.5442 27.4877 15.7498V0",
  "M42.084 6.57153L28.6095 19.7144",
  "M21.3345 0V15.7498C21.3345 18.5442 19.0692 20.8095 16.2748 20.8095H0",
  "M6.73828 6.57153L20.2127 19.7144",
  "M0 26.8096H16.2748C19.0692 26.8096 21.3345 29.0749 21.3345 31.8693V47.6191",
  "M6.73828 41.0476L20.2127 27.9048",
];

/* Full eight-stroke spark, drawn solid. The landing site is the one that animates it. */
export function BrandMark({ size = 26, className = "" }: { size?: number; className?: string; tone?: "accent" | "light" }) {
  const id = `mark-${useId().replace(/:/g, "")}`;
  return (
    <svg aria-hidden viewBox="0 0 48 46" width={size} height={size} className={`brand-mark shrink-0 ${className}`}>
      <defs>
        <clipPath id={id}>
          <ellipse cx="23.5803" cy="23" rx="23.5803" ry="23" />
        </clipPath>
      </defs>
      <g clipPath={`url(#${id})`}>
        {strokes.map((d) => (
          <path key={d} d={d} pathLength={1} fill="none" stroke="currentColor" strokeWidth="3.2" strokeLinecap="round" strokeLinejoin="round" />
        ))}
      </g>
    </svg>
  );
}
