import { ClosingCTA } from "@/components/ClosingCTA";
import { FAQ } from "@/components/FAQ";
import { Footer } from "@/components/Footer";
import { GlassNav } from "@/components/GlassNav";
import { Hero } from "@/components/Hero";
import { LogoMarquee } from "@/components/LogoMarquee";
import { FeatureBento } from "@/components/Features";
import { Product } from "@/components/Product";
import { Steps } from "@/components/Steps";
import { Commands } from "@/components/Commands";

export default function Home() {
  return (
    <>
      <GlassNav />
      <main id="main">
        <Hero />
        <LogoMarquee />
        <Steps />
        <Product />
        <Commands />
        <FeatureBento />
        <FAQ />
        <ClosingCTA />
      </main>
      <Footer />
    </>
  );
}
