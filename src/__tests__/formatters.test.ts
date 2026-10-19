import { describe, expect, it } from "vitest";
import { money, monthBounds } from "../lib/formatters";

describe("formatters", () => {
  it("formats Brazilian currency", () =>
    expect(money(1250.5)).toContain("1.250,50"));
  it("returns exact month boundaries", () =>
    expect(monthBounds("2024-02")).toEqual({
      from: "2024-02-01",
      to: "2024-02-29",
    }));
});
