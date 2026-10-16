import Link from "next/link";
import { AuthCard } from "@/components/AuthCard";

export const metadata = { title: "Join your team" };

export default function InviteHelp() {
  return (
    <AuthCard title="Join your team" sub="Open the link in your invite email to set up your account. Invites are sent by your workspace admin.">
      <Link href="/login" className="block w-full rounded-full bg-surface py-2.5 text-center text-[14px] font-medium ring-1 ring-line hover:bg-bg">
        I already have an account
      </Link>
    </AuthCard>
  );
}
