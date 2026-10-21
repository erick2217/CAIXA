import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  INACTIVITY_LOCK_MS,
  useInactivityLock,
} from "../hooks/useInactivityLock.js";

describe("useInactivityLock", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-10-20T12:00:00"));
    Object.defineProperty(document, "visibilityState", {
      configurable: true,
      value: "visible",
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("locks after five minutes without activity and unlock resets the timer", () => {
    const { result } = renderHook(() => useInactivityLock(true));

    act(() => vi.advanceTimersByTime(INACTIVITY_LOCK_MS));
    expect(result.current.locked).toBe(true);
    expect(result.current.obscured).toBe(true);

    act(() => result.current.unlock());
    expect(result.current.locked).toBe(false);
    expect(result.current.obscured).toBe(false);
  });

  it("obscures the app on blur and locks after five minutes in the background", () => {
    const { result } = renderHook(() => useInactivityLock(true));

    act(() => window.dispatchEvent(new Event("blur")));
    expect(result.current.obscured).toBe(true);

    vi.setSystemTime(Date.now() + INACTIVITY_LOCK_MS);
    act(() => window.dispatchEvent(new Event("focus")));
    expect(result.current.locked).toBe(true);
  });

  it("does not keep the lock after the authenticated session ends", () => {
    const { result, rerender } = renderHook(
      ({ enabled }) => useInactivityLock(enabled),
      { initialProps: { enabled: true } },
    );

    act(() => vi.advanceTimersByTime(INACTIVITY_LOCK_MS));
    expect(result.current.locked).toBe(true);

    rerender({ enabled: false });
    expect(result.current.locked).toBe(false);
  });
});
