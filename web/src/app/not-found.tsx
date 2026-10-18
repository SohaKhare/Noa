import Link from "next/link";
import { BrandMark } from "@/components/BrandMark";

export default function NotFound() {
  return (
    <div className="grid min-h-screen place-items-center mist-wash px-4 text-center">
      <div>
        <BrandMark />
        <p className="mt-6 text-[20px] font-semibold">Nothing here</p>
        <p className="mt-1.5 text-[13.5px] text-muted">The page moved, or the link is wrong.</p>
        <Link href="/" className="mt-5 inline-block rounded-full bg-accent px-4 py-2 text-[13.5px] font-medium text-white">
          Open My day
        </Link>
      </div>
    </div>
  );
}
