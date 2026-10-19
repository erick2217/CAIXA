import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";

const schema = readFileSync(
  resolve(process.cwd(), "supabase/schema.sql"),
  "utf8",
);

describe("Supabase business-rule contracts", () => {
  it("keeps payroll outside general cash expenses", () => {
    expect(schema).toContain("category<>'RH'");
    expect(schema).toContain("public.register_payroll_movement");
  });

  it("closes collectors and daily cash in the integrated function", () => {
    const closeDay = schema.slice(
      schema.lastIndexOf("create or replace function public.close_day"),
    );
    expect(closeDay).toContain("public.close_collectors_cash");
    expect(closeDay).toContain("public.close_daily_cash");
  });

  it("guards closed transactions and scopes access to organizations", () => {
    expect(schema).toContain("transactions_guard_closed_day");
    expect(schema).toContain("current_organization_id()");
  });

  it("records third-party service payment as a cash expense", () => {
    expect(schema).toContain("terceirizado - '||v_service.name");
    expect(schema).toContain("set next_due_date=v_next_due");
  });

  it("recreates policies safely when the schema is rerun", () => {
    expect(schema).toContain("drop policy if exists audit_read on public.audit_log");
    expect(schema).toContain(
      "drop policy if exists service_notifications_read on public.service_notifications",
    );
  });
});
