export function currencyInputDigits(value) {
  return String(value ?? "").replace(/\D/g, "");
}

export function formatCurrencyInput(digits) {
  const numericDigits = currencyInputDigits(digits);
  if (!numericDigits) return "";

  return (Number(numericDigits) / 100).toLocaleString("pt-BR", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

export function parseCurrencyInput(digits) {
  const numericDigits = currencyInputDigits(digits);
  return numericDigits ? Number(numericDigits) / 100 : 0;
}

export function toCurrencyInput(value) {
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return "";

  return String(Math.round(numericValue * 100));
}
