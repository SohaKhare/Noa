import {
  CalendarDotsIcon,
  DiscordLogoIcon,
  GithubLogoIcon,
  GoogleLogoIcon,
  SlackLogoIcon,
  TerminalWindowIcon,
  VideoCameraIcon,
  WhatsappLogoIcon,
} from "@phosphor-icons/react/ssr";
import type { Icon } from "@phosphor-icons/react";

const items: { label: string; Icon: Icon }[] = [
  { label: "Discord", Icon: DiscordLogoIcon },
  { label: "Slack", Icon: SlackLogoIcon },
  { label: "Google Meet", Icon: VideoCameraIcon },
  { label: "Google Calendar", Icon: CalendarDotsIcon },
  { label: "WhatsApp", Icon: WhatsappLogoIcon },
  { label: "GitHub", Icon: GithubLogoIcon },
  { label: "Google Drive", Icon: GoogleLogoIcon },
  { label: "Claude Code and Cursor (MCP)", Icon: TerminalWindowIcon },
];

export function LogoMarquee() {
  return (
    <section aria-labelledby="works-with" className="px-5 pt-16">
      <p id="works-with" className="text-center text-[15px] text-muted">
        Listens where your team already talks
      </p>
      <div className="group relative mx-auto mt-7 max-w-6xl overflow-hidden [mask-image:linear-gradient(90deg,transparent,black_12%,black_88%,transparent)]">
        <ul className="sr-only">
          {items.map(({ label }) => (
            <li key={label}>{label}</li>
          ))}
        </ul>
        <div aria-hidden className="flex w-max animate-marquee group-hover:[animation-play-state:paused] motion-reduce:animate-none">
          {[0, 1].map((copy) => (
            <div key={copy} className="flex shrink-0 items-center gap-14 pr-14">
              {items.map(({ label, Icon }) => (
                <span key={label} className="flex items-center gap-2.5 text-[17px] font-medium tracking-tight text-ink/45">
                  <Icon size={22} />
                  {label}
                </span>
              ))}
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
