"use client";

import Link from "next/link";
import { useEffect } from "react";
import { Button } from "@/components/ui";

/* Anything that throws while rendering a page lands here instead of a blank screen (4.4). */
export default function PageError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  useEffect(() => console.error(error), [error]);
  return (
    <div className="mx-auto grid max-w-md place-items-center py-24 text-center">
      <p className="text-[18px] font-semibold">This page hit a problem</p>
      <p className="mt-1.5 text-[13.5px] text-muted">Nothing you saved was lost. Try again, or go back to My day.</p>
      <div className="mt-5 flex gap-2">
        <Button onClick={reset}>Try again</Button>
        <Link href="/" className="rounded-full px-4 py-2 text-[13.5px] font-medium ring-1 ring-line">
          My day
        </Link>
      </div>
    </div>
  );
}
