import { useCallback, useEffect, useRef, useState } from "react";

export const INACTIVITY_LOCK_MS = 5 * 60 * 1000;

export function useInactivityLock(enabled) {
  const [locked, setLocked] = useState(false);
  const [obscured, setObscured] = useState(false);
  const lockedRef = useRef(false);
  const lastActivity = useRef(0);

  useEffect(() => {
    if (!enabled) {
      lockedRef.current = false;
      setLocked(false);
      setObscured(false);
      return undefined;
    }

    lastActivity.current = Date.now();
    const lock = () => {
      if (lockedRef.current) return;
      lockedRef.current = true;
      setLocked(true);
      setObscured(true);
    };
    const checkInactivity = () => {
      if (Date.now() - lastActivity.current >= INACTIVITY_LOCK_MS) lock();
    };
    const recordActivity = () => {
      if (lockedRef.current || document.visibilityState === "hidden") return;
      lastActivity.current = Date.now();
      setObscured(false);
    };
    const handleVisibilityChange = () => {
      if (document.visibilityState === "hidden") {
        setObscured(true);
        return;
      }
      checkInactivity();
      if (!lockedRef.current) setObscured(false);
    };
    const handleBlur = () => setObscured(true);
    const handleFocus = () => {
      checkInactivity();
      if (!lockedRef.current) setObscured(false);
    };
    const timer = window.setInterval(checkInactivity, 1000);

    window.addEventListener("pointerdown", recordActivity);
    window.addEventListener("keydown", recordActivity);
    window.addEventListener("scroll", recordActivity, { passive: true });
    window.addEventListener("blur", handleBlur);
    window.addEventListener("focus", handleFocus);
    document.addEventListener("visibilitychange", handleVisibilityChange);

    return () => {
      window.clearInterval(timer);
      window.removeEventListener("pointerdown", recordActivity);
      window.removeEventListener("keydown", recordActivity);
      window.removeEventListener("scroll", recordActivity);
      window.removeEventListener("blur", handleBlur);
      window.removeEventListener("focus", handleFocus);
      document.removeEventListener("visibilitychange", handleVisibilityChange);
    };
  }, [enabled]);

  const unlock = useCallback(() => {
    lastActivity.current = Date.now();
    lockedRef.current = false;
    setLocked(false);
    setObscured(document.visibilityState === "hidden");
  }, []);

  return { locked, obscured, unlock };
}
