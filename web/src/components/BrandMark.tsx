/* Placeholder logo for now: a green tile with "N". */
export function BrandMark({ size = 26, className = "" }: { size?: number; className?: string; tone?: "accent" | "light" }) {
  return (
    <svg aria-hidden viewBox="0 0 64 64" width={size} height={size} className={`shrink-0 ${className}`}>
      <rect width="64" height="64" rx="18" fill="#1E3A2F" />
      <text x="32" y="43" textAnchor="middle" fontFamily="ui-sans-serif, system-ui, sans-serif" fontSize="30" fontWeight="700" fill="#F4F1E6">
        N
      </text>
    </svg>
  );
}
