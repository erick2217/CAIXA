import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { ConfirmDialog } from "../components/index.jsx";

describe("ConfirmDialog", () => {
  it("shows the financial details and confirms the requested action", () => {
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        open
        title="Confirmar pagamento"
        description="Contadora · R$ 500,00 · vencimento 20/10/2026"
        confirmLabel="Confirmar pagamento"
        onConfirm={onConfirm}
        onCancel={() => {}}
      />,
    );
    expect(screen.getByRole("alertdialog").textContent).toContain("R$ 500,00");
    fireEvent.click(
      screen.getByRole("button", { name: /confirmar pagamento/i }),
    );
    expect(onConfirm).toHaveBeenCalledOnce();
  });
});
