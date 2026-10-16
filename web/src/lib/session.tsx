"use client";

import { useQuery, useQueryClient } from "@tanstack/react-query";
import { ApiError, getMe, type Membership, type User } from "./api";

/* The signed-in user. `user` is null when signed out (the API answered 401). */
export function useMe() {
  const query = useQuery<User | null>({
    queryKey: ["me"],
    queryFn: async () => {
      try {
        return await getMe();
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) return null;
        throw e;
      }
    },
    retry: false,
    staleTime: 60_000,
  });
  return { user: query.data, loading: query.isLoading, error: query.error as ApiError | null };
}

/* The workspace the user is working in. One org per person for now: the first membership. */
export function currentMembership(user: User | null | undefined): Membership | null {
  return user?.memberships[0] ?? null;
}

export function isOrgAdmin(user: User | null | undefined) {
  return !!user?.is_superadmin || currentMembership(user)?.role === "org_admin";
}

export function initials(user: Pick<User, "name" | "email">) {
  const base = user.name?.trim() || user.email;
  const parts = base.split(/[\s@._-]+/).filter(Boolean);
  return ((parts[0]?.[0] ?? "") + (parts[1]?.[0] ?? "")).toUpperCase() || "?";
}

export function useSetMe() {
  const client = useQueryClient();
  return (user: User | null) => client.setQueryData(["me"], user);
}
