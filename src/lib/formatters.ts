export const money = (value: number | string | null | undefined): string =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(
    Number(value || 0),
  );

export const monthBounds = (month: string) => {
  const [year, mm] = month.split("-").map(Number);
  return {
    from: `${month}-01`,
    to: new Date(year, mm, 0).toISOString().slice(0, 10),
  };
};
