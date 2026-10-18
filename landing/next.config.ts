import path from "node:path";
import type { NextConfig } from "next";

const cdnUrl = process.env.NEXT_PUBLIC_CDN_URL || "https://cdn.saish.xyz";

function cdnHostname(url: string) {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
}

const hostname = cdnHostname(cdnUrl);

const nextConfig: NextConfig = {
  transpilePackages: ["@noa/theme"],
  // Self-contained server for the Docker image; traced from the workspace root for @noa/theme.
  output: "standalone",
  outputFileTracingRoot: path.join(__dirname, ".."),
  ...(hostname && {
    images: {
      unoptimized: true,
      remotePatterns: [
        {
          protocol: "https" as const,
          hostname,
          pathname: "/noa/**",
        },
      ],
    },
  }),
};

export default nextConfig;
