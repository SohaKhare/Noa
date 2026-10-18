import path from "node:path";
import type { NextConfig } from "next";

// The app is a client of the Phoenix API (api/). No Next.js API routes or server actions:
// auth, data and live updates all come from Phoenix.
const nextConfig: NextConfig = {
  transpilePackages: ["@noa/theme"],
  // Vercel supplies its own runtime output. Docker opts into a self-contained server.
  output: process.env.NEXT_OUTPUT === "standalone" ? "standalone" : undefined,
  // Trace workspace dependencies (including @noa/theme) from the repository root.
  outputFileTracingRoot: path.join(__dirname, ".."),
};

export default nextConfig;
