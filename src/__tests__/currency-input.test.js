import { describe, expect, it } from "vitest";
import {
  currencyInputDigits,
  formatCurrencyInput,
  parseCurrencyInput,
  toCurrencyInput,
} from "../lib/currency-input.js";

describe("currency input helpers", () => {
  it("formats and parses Brazilian real values without losing cents", () => {
    const digits = currencyInputDigits("R$ 1.234,56");

    expect(digits).toBe("123456");
    expect(formatCurrencyInput(digits)).toBe("1.234,56");
    expect(parseCurrencyInput(digits)).toBe(1234.56);
    expect(toCurrencyInput(1234.56)).toBe("123456");
  });

  it("represents zero and empty values predictably", () => {
    expect(formatCurrencyInput("")).toBe("");
    expect(formatCurrencyInput("0")).toBe("0,00");
    expect(parseCurrencyInput("")).toBe(0);
    expect(parseCurrencyInput("0")).toBe(0);
  });
});
