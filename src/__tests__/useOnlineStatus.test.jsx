import { act, renderHook, waitFor } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { useOnlineStatus } from "../hooks/useOnlineStatus.js";

const originalOnlineDescriptor = Object.getOwnPropertyDescriptor(
  navigator,
  "onLine",
);

describe("useOnlineStatus", () => {
  beforeEach(() => {
    Object.defineProperty(navigator, "onLine", {
      configurable: true,
      value: true,
    });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    if (originalOnlineDescriptor) {
      Object.defineProperty(navigator, "onLine", originalOnlineDescriptor);
    }
  });

  it("reports online only after the health endpoint responds successfully", async () => {
    const { result, unmount } = renderHook(() =>
      useOnlineStatus("https://project.supabase.co/auth/v1/health"),
    );

    await waitFor(() => expect(result.current).toBe(true));
    expect(fetch).toHaveBeenCalledWith(
      "https://project.supabase.co/auth/v1/health",
      expect.objectContaining({ cache: "no-store" }),
    );
    unmount();
  });

  it("reports offline for failed probes and responds to offline events", async () => {
    fetch.mockRejectedValueOnce(new TypeError("Network unavailable"));
    const { result, unmount } = renderHook(() =>
      useOnlineStatus("https://project.supabase.co/auth/v1/health"),
    );

    await waitFor(() => expect(fetch).toHaveBeenCalledOnce());
    expect(result.current).toBe(false);

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue({ ok: true }));
    await act(async () => {
      window.dispatchEvent(new Event("online"));
    });
    await waitFor(() => expect(result.current).toBe(true));

    act(() => {
      window.dispatchEvent(new Event("offline"));
    });
    expect(result.current).toBe(false);
    unmount();
  });
});
