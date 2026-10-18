export const APP_URL = process.env.NEXT_PUBLIC_APP_URL || "http://localhost:3000";

/* Same order as the page, so each link is further down than the one before it. */
export const navLinks = [
  { href: "#how", label: "How it works" },
  { href: "#product", label: "Product" },
  { href: "#agents", label: "For agents" },
  { href: "#features", label: "Features" },
  { href: "#privacy", label: "Privacy" },
  { href: "#faq", label: "FAQ" },
];

/* Where privacy and data requests go (privacy and terms pages). */
export const LEGAL_CONTACT = "privacy@notyouridea.com";
