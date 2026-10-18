import path from "node:path";
import { fileURLToPath } from "node:url";

// Keep container configuration native ESM: Node can load it without TS config transpilation.
/** @type {import("next").NextConfig} */
const nextConfig = {
  transpilePackages: ["@noa/theme"],
  output: "standalone",
  outputFileTracingRoot: path.join(path.dirname(fileURLToPath(import.meta.url)), ".."),
};

export default nextConfig;
