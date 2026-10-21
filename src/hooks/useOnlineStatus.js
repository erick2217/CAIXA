import { useEffect, useState } from "react";

const PROBE_TIMEOUT_MS = 3000;
const PROBE_INTERVAL_MS = 30000;

export function useOnlineStatus(probeUrl) {
  const [online, setOnline] = useState(false);

  useEffect(() => {
    if (!probeUrl) {
      setOnline(false);
      return undefined;
    }

    let active = true;
    let requestId = 0;
    let controller;

    const verifyConnection = async () => {
      const currentRequestId = ++requestId;
      if (!navigator.onLine) {
        controller?.abort();
        setOnline(false);
        return;
      }

      controller?.abort();
      const requestController = new AbortController();
      controller = requestController;
      const timeoutId = window.setTimeout(
        () => requestController.abort(),
        PROBE_TIMEOUT_MS,
      );

      try {
        const response = await fetch(probeUrl, {
          cache: "no-store",
          signal: requestController.signal,
        });
        if (active && currentRequestId === requestId) {
          setOnline(response.ok);
        }
      } catch {
        if (active && currentRequestId === requestId) {
          setOnline(false);
        }
      } finally {
        window.clearTimeout(timeoutId);
      }
    };

    const handleOffline = () => {
      requestId += 1;
      controller?.abort();
      setOnline(false);
    };

    window.addEventListener("online", verifyConnection);
    window.addEventListener("offline", handleOffline);
    void verifyConnection();
    const intervalId = window.setInterval(
      verifyConnection,
      PROBE_INTERVAL_MS,
    );

    return () => {
      active = false;
      requestId += 1;
      controller?.abort();
      window.clearInterval(intervalId);
      window.removeEventListener("online", verifyConnection);
      window.removeEventListener("offline", handleOffline);
    };
  }, [probeUrl]);

  return online;
}
