import { PlayIcon } from "@phosphor-icons/react/ssr";
import { cdnAsset } from "@/lib/cdn";
import Image from "next/image";

const chips = ["Cites every source", "Asks before it changes things", "Lives in your chat apps"];

/* Elf's hero card at full height, night starlight in place of the sky film. */
export function Hero() {
  return (
    <section id="top" aria-labelledby="hero-title" className="p-2 sm:p-3">
      <div className="relative isolate flex min-h-[calc(100dvh-1rem)] flex-col items-center justify-start overflow-hidden rounded-card bg-[#0e1c33] px-5 pt-[clamp(7rem,21vh,12rem)] pb-12 text-center sm:min-h-[calc(100dvh-1.5rem)]">
        <Image src={cdnAsset("/images/night.jpg")} alt="" fill priority sizes="100vw" className="object-cover -z-20" />
        <div
          aria-hidden
          className="absolute inset-0 -z-10 bg-[radial-gradient(68%_38%_at_50%_28%,rgba(8,16,32,0.35),rgba(8,16,32,0.05)_70%),linear-gradient(180deg,rgba(8,16,32,0.28),rgba(8,16,32,0)_28%)]"
        />
        <h1
          id="hero-title"
          className="text-[clamp(2.6rem,6.6vw,5.75rem)] leading-[0.94] font-semibold tracking-[-0.05em] text-white [text-shadow:0_2px_24px_rgba(8,16,32,0.45)]"
        >
          <span className="block sm:whitespace-nowrap">Work gets lost in chat.</span>
          <span className="block sm:whitespace-nowrap">Noa keeps it live.</span>
        </h1>
        <p className="mt-6 max-w-2xl text-lg leading-relaxed text-white/90 [text-shadow:0_1px_14px_rgba(8,16,32,0.45)] sm:text-xl">
          Chats and meetings become tasks, decisions and briefs, each tied to the message it came from.
        </p>
        <a
          href="#product"
          className="group mt-8 inline-flex items-center gap-2.5 rounded-full bg-white py-2 pr-2 pl-6 text-[15px] font-medium text-accent shadow-[0_12px_40px_-12px_rgba(8,16,32,0.45)] transition-colors duration-300 ease-soft hover:bg-mist active:scale-[0.98]"
        >
          See it work
          <span className="grid size-9 place-items-center rounded-full bg-accent/10 transition-transform duration-300 ease-soft group-hover:translate-x-0.5">
            <PlayIcon size={13} weight="fill" />
          </span>
        </a>
        <ul className="mt-6 flex flex-wrap justify-center gap-2">
          {chips.map((chip) => (
            <li key={chip} className="rounded-full bg-white/15 px-3.5 py-1.5 text-[13px] text-white ring-1 ring-white/25">
              {chip}
            </li>
          ))}
        </ul>
      </div>
    </section>
  );
}
