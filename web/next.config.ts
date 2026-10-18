import path from "node:path";
import type { NextConfig } from "next";

// The app is a client of the Phoenix API (api/). No Next.js API routes or server actions:
// auth, data and live updates all come from Phoenix.
const nextConfig: NextConfig = {
  transpilePackages: ["@noa/theme"],
  // Self-contained server for the Docker image; traced from the workspace root for @noa/theme.
  output: "standalone",
  outputFileTracingRoot: path.join(__dirname, ".."),
};

export default nextConfig;
