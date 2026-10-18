import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Special_Gothic_Condensed_One } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/Providers";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });
const wordmark = Special_Gothic_Condensed_One({ weight: "400", subsets: ["latin"], variable: "--font-gothic" });

const description = "Your company brain.";
const logo = { url: "/logo.svg", alt: "Noa", type: "image/svg+xml" };

export const metadata: Metadata = {
  metadataBase: new URL("https://app.heynoa.xyz"),
  title: { default: "Noa", template: "%s · Noa" },
  description,
  applicationName: "Noa",
  robots: { index: false, follow: false },
  icons: {
    icon: [{ url: "/favicon.svg", type: "image/svg+xml" }],
    shortcut: ["/favicon.svg"],
    apple: [{ url: "/logo.svg", type: "image/svg+xml" }],
  },
  openGraph: {
    type: "website",
    siteName: "Noa",
    title: "Noa",
    description,
    images: [logo],
  },
  twitter: {
    card: "summary",
    title: "Noa",
    description,
    images: [logo],
  },
};

export const viewport: Viewport = { themeColor: "#EEF2F6" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${geistSans.variable} ${geistMono.variable} ${wordmark.variable} h-full antialiased`}>
      <body className="min-h-full bg-bg font-sans text-ink">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
