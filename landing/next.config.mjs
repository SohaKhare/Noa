import path from "node:path";
import { fileURLToPath } from "node:url";

const cdnUrl = process.env.NEXT_PUBLIC_CDN_URL || "https://cdn.saish.xyz";

function cdnHostname(url) {
  try {
    return new URL(url).hostname;
  } catch {
    return null;
  }
}

const hostname = cdnHostname(cdnUrl);

/** @type {import("next").NextConfig} */
const nextConfig = {
  transpilePackages: ["@noa/theme"],
  output: "standalone",
  outputFileTracingRoot: path.join(path.dirname(fileURLToPath(import.meta.url)), ".."),
  ...(hostname && {
    images: {
      unoptimized: true,
      remotePatterns: [
        {
          protocol: "https",
          hostname,
          pathname: "/noa/**",
        },
      ],
    },
  }),
};

export default nextConfig;
