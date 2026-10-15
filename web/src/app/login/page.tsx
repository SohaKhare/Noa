import { GoogleLogoIcon } from "@phosphor-icons/react/ssr";
import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";

export const metadata = { title: "Sign in" };

// Auth is AshAuthentication on the Phoenix API (item 1.4). This page posts to it once wired.
export default function Login() {
  return (
    <div className="grid min-h-screen place-items-center p-4 mist-wash">
      <div className="w-full max-w-sm rounded-[28px] bg-surface p-8 card-shadow">
        <div className="flex items-center gap-2 text-[17px] font-semibold">
          <BrandMark size={28} /> Noa
        </div>
        <h1 className="mt-6 text-[24px] font-semibold tracking-[-0.03em]">Sign in</h1>
        <p className="mt-1 text-[13.5px] text-muted">Use your work account.</p>
        <button className="mt-6 flex w-full items-center justify-center gap-2 rounded-full bg-surface py-2.5 text-[14px] font-medium ring-1 ring-line hover:bg-bg">
          <GoogleLogoIcon size={16} /> Continue with Google
        </button>
        <div className="my-5 flex items-center gap-3 text-[11px] text-muted">
          <span className="h-px flex-1 bg-line" /> or <span className="h-px flex-1 bg-line" />
        </div>
        <form className="space-y-3">
          <label className="block">
            <span className="text-[12px] text-muted">Work email</span>
            <input type="email" autoComplete="email" placeholder="you@company.com" className="mt-1 w-full rounded-xl bg-bg px-3.5 py-2.5 text-[14px] focus:ring-2 focus:ring-accent/30 focus:outline-none" />
          </label>
          <Link href="/" className="block w-full rounded-full bg-accent py-2.5 text-center text-[14px] font-medium text-white hover:bg-accent-soft">
            Email me a magic link
          </Link>
        </form>
        <p className="mt-6 text-center text-[12px] text-muted">
          Have an invite? <Link href="/invite" className="text-accent-fg">Join your team</Link>
          <span className="mx-1.5 text-line">/</span>
          New team? <Link href="/onboarding" className="text-accent-fg">Set up your organization</Link>
        </p>
      </div>
    </div>
  );
}
