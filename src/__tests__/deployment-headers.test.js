import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const config = JSON.parse(
  readFileSync(resolve(process.cwd(), "vercel.json"), "utf8"),
);
const headers = new Map(
  config.headers[0].headers.map(({ key, value }) => [key, value]),
);

describe("PWA deployment security headers", () => {
  it("sets a restrictive CSP that permits Supabase, Google Fonts, and the service worker", () => {
    const policy = headers.get("Content-Security-Policy");

    expect(policy).toContain("default-src 'self'");
    expect(policy).toContain("script-src 'self'");
    expect(policy).not.toContain("'unsafe-eval'");
    expect(policy).toContain("https://*.supabase.co");
    expect(policy).toContain("wss://*.supabase.co");
    expect(policy).toContain("worker-src 'self' blob:");
  });

  it("sets HTTPS and content-sniffing protections", () => {
    expect(headers.get("Strict-Transport-Security")).toContain("max-age=");
    expect(headers.get("X-Content-Type-Options")).toBe("nosniff");
    expect(headers.get("X-Frame-Options")).toBe("DENY");
  });
});
