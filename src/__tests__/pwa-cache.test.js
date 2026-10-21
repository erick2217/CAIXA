import { describe, expect, it, vi } from "vitest";
import {
  clearSupabaseReadCaches,
  isSupabaseTableRead,
} from "../lib/pwa-cache.js";

describe("clearSupabaseReadCaches", () => {
  it("deletes Supabase read caches without clearing unrelated caches", async () => {
    const cacheStorage = {
      keys: vi
        .fn()
        .mockResolvedValue([
          "pax-supabase-read-v1",
          "google-font-files",
          "pax-supabase-read-v2",
        ]),
      delete: vi.fn().mockResolvedValue(true),
    };

    await clearSupabaseReadCaches(cacheStorage);

    expect(cacheStorage.delete).toHaveBeenCalledTimes(2);
    expect(cacheStorage.delete).toHaveBeenCalledWith("pax-supabase-read-v1");
    expect(cacheStorage.delete).toHaveBeenCalledWith("pax-supabase-read-v2");
  });

  describe("isSupabaseTableRead", () => {
    it("matches only GET requests for Supabase table REST resources", () => {
      const matches = (method, path) =>
        isSupabaseTableRead({
          url: new URL(`https://project.supabase.co${path}`),
          request: { method },
        });

      expect(matches("GET", "/rest/v1/transactions?select=*")).toBe(true);
      expect(matches("POST", "/rest/v1/transactions")).toBe(false);
      expect(matches("GET", "/rest/v1/rpc/register_payroll_movement")).toBe(
        false,
      );
      expect(matches("GET", "/auth/v1/token")).toBe(false);
      expect(matches("GET", "/functions/v1/notify")).toBe(false);
    });
  });

  it("surfaces cache deletion failures", async () => {
    const failure = new Error("Cache storage unavailable");
    const cacheStorage = {
      keys: vi.fn().mockResolvedValue(["pax-supabase-read-v1"]),
      delete: vi.fn().mockRejectedValue(failure),
    };

    await expect(clearSupabaseReadCaches(cacheStorage)).rejects.toBe(failure);
  });
});
