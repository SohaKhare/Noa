/*
  Noa is a cat: quiet, always listening (ears up), never in the way.
  CatMark  = app/logo tile (cream cat face on forest green).
  CatFace  = bare face for avatars.
  CatSit   = full mascot, sitting with a curled tail.
  CatPeek  = head and paws peeking over the top edge of a card.
  Motion is small and foreground only: blink, ear twitch, tail sway (see .cat-* in globals.css).
*/

const GREEN = "#1E3A2F";
const CREAM = "#F4F1E6";
const CORAL = "#D9734E";

function Face({ ink = GREEN, fur = CREAM, animate = false }: { ink?: string; fur?: string; animate?: boolean }) {
  return (
    <g>
      <g className={animate ? "cat-ear-l" : undefined} style={{ transformOrigin: "21px 27px" }}>
        <path d="M14 33 L17 11 L30 22 Z" fill={fur} />
        <path d="M18 27 L19.5 16 L26 22 Z" fill={CORAL} opacity="0.55" />
      </g>
      <g className={animate ? "cat-ear-r" : undefined} style={{ transformOrigin: "43px 27px" }}>
        <path d="M50 33 L47 11 L34 22 Z" fill={fur} />
        <path d="M46 27 L44.5 16 L38 22 Z" fill={CORAL} opacity="0.55" />
      </g>
      <ellipse cx="32" cy="37" rx="19" ry="16" fill={fur} />
      <g className={animate ? "cat-blink" : undefined} style={{ transformOrigin: "32px 36px" }}>
        <path d="M22.5 36.5 q3.2 -3.4 6.4 0" stroke={ink} strokeWidth="2.4" strokeLinecap="round" fill="none" />
        <path d="M35.1 36.5 q3.2 -3.4 6.4 0" stroke={ink} strokeWidth="2.4" strokeLinecap="round" fill="none" />
      </g>
      <path d="M30.4 41 h3.2 l-1.6 2 Z" fill={CORAL} />
      <path d="M32 43 q-1.6 2 -3.6 1.2 M32 43 q1.6 2 3.6 1.2" stroke={ink} strokeWidth="1.4" strokeLinecap="round" fill="none" />
      <path d="M15 40 h6 M15.5 43.5 l5.5 -1.2 M49 40 h-6 M48.5 43.5 l-5.5 -1.2" stroke={ink} strokeWidth="1.2" strokeLinecap="round" opacity="0.55" />
    </g>
  );
}

export function CatMark({ size = 28, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 64 64" width={size} height={size} className={`shrink-0 ${className}`}>
      <rect width="64" height="64" rx="18" fill={GREEN} />
      <g transform="translate(0 3)">
        <Face />
      </g>
    </svg>
  );
}

export function CatFace({ size = 28, className = "", animate = false }: { size?: number; className?: string; animate?: boolean }) {
  return (
    <svg aria-hidden viewBox="8 6 48 50" width={size} height={size} className={`shrink-0 ${className}`}>
      <Face animate={animate} />
    </svg>
  );
}

export function CatSit({ size = 120, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden viewBox="0 0 120 120" width={size} height={size} className={`shrink-0 overflow-visible ${className}`}>
      <path
        d="M80 104 C104 104 110 80 96 70"
        stroke={GREEN}
        strokeWidth="9"
        strokeLinecap="round"
        fill="none"
        className="cat-tail"
        style={{ transformOrigin: "80px 104px" }}
      />
      <path d="M38 106 C32 82 40 60 60 60 C80 60 88 82 82 106 Z" fill={GREEN} />
      <ellipse cx="50" cy="105" rx="7" ry="3.6" fill="#2B4D3F" />
      <ellipse cx="70" cy="105" rx="7" ry="3.6" fill="#2B4D3F" />
      <g transform="translate(28 8)">
        <Face ink={CREAM} fur={GREEN} animate />
      </g>
    </svg>
  );
}

export function CatPeek({ size = 84, className = "" }: { size?: number; className?: string }) {
  return (
    <svg aria-hidden viewBox="4 6 56 44" width={size} height={size * (44 / 56)} className={`shrink-0 overflow-visible ${className}`}>
      <g clipPath="url(#peek-clip)">
        <Face ink={CREAM} fur={GREEN} animate />
      </g>
      <defs>
        <clipPath id="peek-clip">
          <rect x="0" y="0" width="64" height="44" />
        </clipPath>
      </defs>
      <ellipse cx="22" cy="45" rx="6" ry="3.4" fill={GREEN} />
      <ellipse cx="42" cy="45" rx="6" ry="3.4" fill={GREEN} />
    </svg>
  );
}
