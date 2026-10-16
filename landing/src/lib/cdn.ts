const CDN_BASE = (process.env.NEXT_PUBLIC_CDN_URL || "https://cdn.saish.xyz").replace(/\/$/, "");
const PREFIX = "/noa";

export function cdnAsset(path: string) {
  if (!path) return path;
  if (/^https?:\/\//.test(path) || path.startsWith("data:")) return path;

  const normalized = path.startsWith("/") ? path : `/${path}`;
  const prefixed = normalized.startsWith(`${PREFIX}/`) ? normalized : `${PREFIX}${normalized}`;
  return `${CDN_BASE}${prefixed}`;
}
