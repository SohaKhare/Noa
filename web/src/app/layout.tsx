import type { Metadata, Viewport } from "next";
import { Geist, Geist_Mono, Special_Gothic_Condensed_One } from "next/font/google";
import "./globals.css";
import { Providers } from "@/components/Providers";

const geistSans = Geist({ variable: "--font-geist-sans", subsets: ["latin"] });
const geistMono = Geist_Mono({ variable: "--font-geist-mono", subsets: ["latin"] });
const wordmark = Special_Gothic_Condensed_One({ weight: "400", subsets: ["latin"], variable: "--font-gothic" });

export const metadata: Metadata = {
  title: { default: "Noa", template: "%s · Noa" },
  description: "Your company brain.",
  robots: { index: false, follow: false },
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
