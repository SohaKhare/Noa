"use client";

import { CheckIcon, DiscordLogoIcon, SlackLogoIcon, VideoCameraIcon, WhatsappLogoIcon } from "@phosphor-icons/react";
import Link from "next/link";
import { useState } from "react";
import { BrandMark } from "@/components/BrandMark";
import { Button } from "@/components/ui";
import { cn } from "@/lib/cn";
import { projects } from "@/lib/mock";

const STEPS = ["Organization", "Connect sources", "Map channels", "People and roles", "Done"];
const sources = [
  { name: "Discord", Icon: DiscordLogoIcon, status: "Connected · 14 channels" },
  { name: "Slack", Icon: SlackLogoIcon, status: "" },
  { name: "Google Workspace", Icon: VideoCameraIcon, status: "Connected · Meet, Calendar" },
  { name: "WhatsApp (Kapso)", Icon: WhatsappLogoIcon, status: "Connected · 1 number" },
];
const channels = [
  { name: "#veriq", map: "a" },
  { name: "#emmarie", map: "b" },
  { name: "#video-break", map: "c" },
  { name: "#general", map: "split" },
  { name: "#random", map: "off" },
];

export default function Onboarding() {
  const [step, setStep] = useState(2);
  const [map, setMap] = useState(() => Object.fromEntries(channels.map((c) => [c.name, c.map])));

  return (
    <div className="min-h-screen mist-wash px-4 py-10">
      <div className="mx-auto max-w-4xl">
        <div className="flex items-center gap-2 text-[16px] font-semibold">
          <BrandMark /> Noa
        </div>
        <h1 className="mt-8 text-[28px] font-semibold tracking-[-0.03em]">Set up your organization</h1>
        <ol className="mt-5 flex flex-wrap gap-2">
          {STEPS.map((s, i) => (
            <li
              key={s}
              className={cn(
                "flex items-center gap-2 rounded-full py-1 pr-3.5 pl-1 text-[12.5px]",
                i === step ? "bg-accent text-white" : i < step ? "bg-surface text-ink" : "bg-surface/60 text-muted",
              )}
            >
              <span className={cn("grid size-6 place-items-center rounded-full font-mono text-[11px]", i === step ? "bg-white/15" : "bg-bg")}>
                {i < step ? <CheckIcon size={11} weight="bold" /> : i + 1}
              </span>
              {s}
            </li>
          ))}
        </ol>

        <div className="mt-6 grid gap-4 rounded-[28px] bg-surface p-6 card-shadow md:grid-cols-[1fr_1.6fr]">
          <div className="space-y-2">
            {sources.map(({ name, Icon, status }) => (
              <div key={name} className="flex items-center gap-3 rounded-2xl bg-bg p-3">
                <Icon size={20} className="text-accent-fg" />
                <div className="flex-1">
                  <p className="text-[13px] font-medium">{name}</p>
                  {status ? <p className="text-[11.5px] text-good">{status}</p> : <p className="text-[11.5px] font-medium text-accent-fg">Connect</p>}
                </div>
              </div>
            ))}
          </div>
          <div className="rounded-2xl ring-1 ring-line">
            <div className="grid grid-cols-[1fr_1.2fr] border-b border-line px-4 py-2.5 text-[11.5px] text-muted">
              <span>Channel</span>
              <span>Project</span>
            </div>
            {channels.map((c) => (
              <div key={c.name} className="grid grid-cols-[1fr_1.2fr] items-center border-b border-line/60 px-4 py-2.5 text-[13px] last:border-0">
                <span>{c.name}</span>
                <select
                  value={map[c.name]}
                  onChange={(e) => setMap((m) => ({ ...m, [c.name]: e.target.value }))}
                  className="rounded-lg bg-bg px-2 py-1.5 text-[12.5px] text-accent-fg focus:outline-none"
                >
                  {projects.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                  <option value="split">Split by message</option>
                  <option value="off">Not ingested</option>
                </select>
              </div>
            ))}
            <p className="px-4 py-3 text-[11.5px] text-muted">Direct messages are never ingested. Noa suggests a project from each channel&apos;s name and recent messages.</p>
          </div>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <Button variant="ghost" onClick={() => setStep((s) => Math.max(0, s - 1))}>
            Back
          </Button>
          {step < STEPS.length - 1 ? (
            <Button onClick={() => setStep((s) => s + 1)}>Continue</Button>
          ) : (
            <Link href="/" className="rounded-full bg-accent px-4 py-2 text-[13.5px] font-medium text-white">
              Open My day
            </Link>
          )}
        </div>
      </div>
    </div>
  );
}
