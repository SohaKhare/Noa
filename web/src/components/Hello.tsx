"use client";

import { useMe } from "@/lib/session";

/* "Good morning, Vedant" with the signed-in person's first name. */
export function Hello() {
  const { user } = useMe();
  const hour = new Date().getHours();
  const part = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening";
  const first = user?.name?.split(" ")[0] ?? user?.email.split("@")[0] ?? "";
  return (
    <>
      Good {part}
      {first && `, ${first}`}
    </>
  );
}
