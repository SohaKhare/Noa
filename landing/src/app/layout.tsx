import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Special_Gothic_Condensed_One } from "next/font/google";
import "lenis/dist/lenis.css";
import "./globals.css";
import { SmoothScroll } from "@/components/SmoothScroll";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

const wordmark = Special_Gothic_Condensed_One({
  weight: "400",
  subsets: ["latin"],
  variable: "--font-gothic",
});

// Shared metadata keeps the landing page previews consistent.
const description =
  "Noa turns your team's Discord, Slack, Meet and WhatsApp conversations into tasks, owners, deadlines and decisions, kept current and always cited.";

const logo = { url: "/logo.svg", alt: "Noa", type: "image/svg+xml" };

export const metadata: Metadata = {
  metadataBase: new URL("https://heynoa.xyz"),
  title: "Noa: your company brain",
  description,
  applicationName: "Noa",
  icons: {
    icon: [{ url: "/favicon.svg", type: "image/svg+xml" }],
    shortcut: ["/favicon.svg"],
    apple: [{ url: "/logo.svg", type: "image/svg+xml" }],
  },
  openGraph: {
    type: "website",
    siteName: "Noa",
    title: "Noa: your company brain",
    description,
    locale: "en_US",
    images: [logo],
  },
  twitter: {
    card: "summary_large_image",
    title: "Noa: your company brain",
    description,
    images: [logo],
  },
};

export const viewport: Viewport = {
  themeColor: "#F2F1EE",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} ${wordmark.variable} h-full antialiased`}>
      <body className="min-h-full bg-bg font-sans text-ink">
        <a
          href="#main"
          className="sr-only z-[60] rounded-full bg-accent px-4 py-2 text-sm text-white focus:not-sr-only focus:fixed focus:top-4 focus:left-4"
        >
          Skip to content
        </a>
        <SmoothScroll>{children}</SmoothScroll>
      </body>
    </html>
  );
}
