/*
  Client for the Phoenix API. Until api/ exists, `apiEnabled` is false and pages use lib/mock.ts.
  Item 0.8 replaces this with the ash_typescript generated RPC client.
*/

export const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "";
export const apiEnabled = API_URL.length > 0;

export async function api<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`${API_URL}${path}`, {
    credentials: "include",
    headers: { "content-type": "application/json", ...(init?.headers ?? {}) },
    ...init,
  });
  if (!res.ok) throw new Error(`${init?.method ?? "GET"} ${path} failed: ${res.status}`);
  return res.json() as Promise<T>;
}
