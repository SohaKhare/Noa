import {
  ArrowsLeftRightIcon,
  ChatsCircleIcon,
  CheckCircleIcon,
  DiscordLogoIcon,
  GavelIcon,
  VideoCameraIcon,
} from "@phosphor-icons/react/ssr";
import type { Icon } from "@phosphor-icons/react";

/* Three updates, held still. */
type Item = { Icon: Icon; source: Icon; title: string; meta: string; tone?: "accent" | "signal" };

const ITEMS: Item[] = [
  { Icon: GavelIcon, source: VideoCameraIcon, title: "Decision: Board report before Practitioner", meta: "Weekly sync · Meet transcript" },
  { Icon: ArrowsLeftRightIcon, source: ChatsCircleIcon, title: "Soha moved to Emmarie", meta: "3 tasks handed over · agent pack sent", tone: "signal" },
  { Icon: CheckCircleIcon, source: DiscordLogoIcon, title: "Task added: Board report PDF", meta: "Saish · due Fri · from #veriq" },
];

export function LiveFeed({
  size = "md",
  className = "",
}: {
  size?: "sm" | "md";
  visible?: number;
  className?: string;
  peek?: boolean;
}) {
  const sm = size === "sm";

  return (
    <ul className={`w-full space-y-2 ${className}`}>
      {ITEMS.map((item) => {
        const { Icon, source: Source } = item;
        return (
          <li
            key={item.title}
            className={`flex items-center gap-3 rounded-2xl bg-surface text-left card-shadow ${sm ? "p-2.5" : "p-3"}`}
          >
            <span
              className={`grid shrink-0 place-items-center rounded-full ${sm ? "size-8" : "size-9"} ${
                item.tone === "signal" ? "bg-signal/12 text-signal" : "bg-mist text-accent"
              }`}
            >
              <Icon size={sm ? 16 : 18} weight="fill" />
            </span>
            <span className="min-w-0 flex-1">
              <span className={`block truncate font-medium ${sm ? "text-[12.5px]" : "text-[13.5px]"}`}>{item.title}</span>
              <span className={`block truncate text-muted ${sm ? "text-[11px]" : "text-[12px]"}`}>{item.meta}</span>
            </span>
            <Source size={sm ? 14 : 16} className="shrink-0 text-ink/35" />
          </li>
        );
      })}
    </ul>
  );
}
