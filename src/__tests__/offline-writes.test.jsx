import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { CollectorsModule, PayrollModule } from "../Modules.jsx";
import ServicesModule from "../ServicesModule.jsx";

function createSupabaseMock(rowsByTable) {
  const insert = vi.fn();
  const update = vi.fn(() => ({ eq: vi.fn() }));
  const rpc = vi.fn();
  const from = vi.fn((table) => {
    const query = {
      select: () => query,
      eq: () => query,
      order: () => query,
      limit: () => query,
      gte: () => query,
      lt: () => query,
      in: () => query,
      maybeSingle: async () => ({ data: null, error: null }),
      insert,
      update,
      then: (resolve, reject) =>
        Promise.resolve({
          data: rowsByTable[table] || [],
          error: null,
        }).then(resolve, reject),
    };
    return query;
  });

  return { from, insert, update, rpc };
}

describe("offline financial write controls", () => {
  it("disables collector receipts and cash closure while offline", async () => {
    const supabase = createSupabaseMock({
      cobradores: [{ id: "collector-1", name: "Ana" }],
      collector_receipts: [],
    });

    render(
      <CollectorsModule
        supabase={supabase}
        userId="user-1"
        role="admin"
        online={false}
      />,
    );

    expect(
      (await screen.findByRole("button", { name: /Adicionar cobrador/i }))
        .disabled,
    ).toBe(true);
    expect(
      screen.getByRole("button", { name: /Fechar caixa dos cobradores/i })
        .disabled,
    ).toBe(true);
    expect(
      screen.getByRole("textbox", { name: /Valor entregue por Ana/i }).disabled,
    ).toBe(true);
    expect(supabase.insert).not.toHaveBeenCalled();
    expect(supabase.rpc).not.toHaveBeenCalled();
  });

  it("disables payroll and service payment actions while offline", async () => {
    const payrollSupabase = createSupabaseMock({
      funcionarios: [{ id: "employee-1", name: "Rosa", salary: 1200 }],
      payroll_movements: [],
    });
    const serviceSupabase = createSupabaseMock({
      third_party_services: [
        {
          id: "service-1",
          name: "Contadora",
          fixed_amount: 350,
          next_due_date: "2026-10-20",
          due_day: 20,
          reminder_days: 7,
        },
      ],
      third_party_service_payments: [],
    });

    const payroll = render(
      <PayrollModule
        supabase={payrollSupabase}
        userId="user-1"
        role="financeiro"
        online={false}
      />,
    );

    expect(
      (await screen.findByRole("button", { name: /Registrar vale/i })).disabled,
    ).toBe(true);
    expect(
      screen.getByRole("button", { name: /Pagar líquido/i }).disabled,
    ).toBe(true);
    expect(payrollSupabase.rpc).not.toHaveBeenCalled();
    payroll.unmount();

    render(
      <ServicesModule
        supabase={serviceSupabase}
        userId="user-1"
        role="financeiro"
        online={false}
      />,
    );

    expect(
      (await screen.findByRole("button", { name: /Já paguei/i })).disabled,
    ).toBe(true);
    expect(serviceSupabase.rpc).not.toHaveBeenCalled();
  });
});
