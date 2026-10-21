import { useEffect, useMemo, useState } from "react";
import { Download, Printer } from "lucide-react";
import {
  Bar,
  BarChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";

const money = (n) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(
    Number(n || 0),
  );
const monthName = (value) =>
  new Intl.DateTimeFormat("pt-BR", { month: "long", year: "numeric" }).format(
    new Date(`${value}-01T12:00:00`),
  );
const initialMonth = () => {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
};
function csvCell(v) {
  return `"${String(v ?? "").replaceAll('"', '""')}"`;
}
export default function ReportsModule({ supabase }) {
  const [month, setMonth] = useState(initialMonth),
    [rows, setRows] = useState([]),
    [previousRows, setPreviousRows] = useState([]),
    [payroll, setPayroll] = useState([]),
    [closures, setClosures] = useState([]),
    [collectorReceipts, setCollectorReceipts] = useState([]),
    [busy, setBusy] = useState(true),
    [error, setError] = useState("");
  useEffect(() => {
    let alive = true;
    async function load() {
      setBusy(true);
      setError("");
      const [y, m] = month.split("-").map(Number),
        from = `${month}-01`,
        to = new Date(y, m, 0).toISOString().slice(0, 10),
        prev = new Date(y, m - 1, 1),
        prevMonth = prev.toISOString().slice(0, 7),
        prevFrom = `${prevMonth}-01`,
        prevTo = new Date(prev.getFullYear(), prev.getMonth() + 1, 0)
          .toISOString()
          .slice(0, 10);
      const results = await Promise.all([
        supabase
          .from("transactions")
          .select("id,description,amount,type,category,transaction_date")
          .gte("transaction_date", from)
          .lte("transaction_date", to)
          .neq("category", "RH")
          .order("transaction_date"),
        supabase
          .from("payroll_movements")
          .select(
            "id,movement_type,amount,payment_date,period_month,employee_id,funcionarios(name)",
          )
          .gte("period_month", from)
          .lte("period_month", to)
          .order("payment_date"),
        supabase
          .from("cash_closures")
          .select(
            "close_date,income_total,expense_total,expected_balance,counted_balance,difference",
          )
          .gte("close_date", from)
          .lte("close_date", to)
          .order("close_date"),
        supabase
          .from("transactions")
          .select("amount,type")
          .gte("transaction_date", prevFrom)
          .lte("transaction_date", prevTo)
          .neq("category", "RH"),
        supabase
          .from("collector_receipts")
          .select("id,amount,receipt_date,cobradores(name)")
          .gte("receipt_date", from)
          .lte("receipt_date", to)
          .order("receipt_date"),
      ]);
      if (!alive) return;
      const err = results.find((x) => x.error)?.error;
      if (err) setError(err.message);
      setRows(results[0].data || []);
      setPayroll(results[1].data || []);
      setClosures(results[2].data || []);
      setPreviousRows(results[3].data || []);
      setCollectorReceipts(results[4].data || []);
      setBusy(false);
    }
    load();
    return () => {
      alive = false;
    };
  }, [supabase, month]);
  const totals = useMemo(
    () => ({
      income: rows
        .filter((x) => x.type === "income")
        .reduce((a, x) => a + Number(x.amount), 0),
      expense: rows
        .filter((x) => x.type === "expense")
        .reduce((a, x) => a + Number(x.amount), 0),
      payroll: payroll.reduce((a, x) => a + Number(x.amount), 0),
      collectors: collectorReceipts.reduce((a, x) => a + Number(x.amount), 0),
      services: rows
        .filter(
          (x) =>
            x.category === "Servicos terceirizados" ||
            x.category === "Serviços terceirizados",
        )
        .reduce((a, x) => a + Number(x.amount), 0),
    }),
    [rows, payroll, collectorReceipts],
  );
  const receiptsByCollector = collectorReceipts.reduce((result, receipt) => {
    const name = receipt.cobradores?.name || "Cobrador";
    result[name] = (result[name] || 0) + Number(receipt.amount);
    return result;
  }, {});
  const exportCsv = () => {
    const lines = [
      ["Data", "Tipo", "Descrição", "Categoria", "Valor"],
      ...rows.map((x) => [
        x.transaction_date,
        x.type === "income" ? "Entrada" : "Saída",
        x.description,
        x.category,
        x.amount,
      ]),
      [],
      ["Arrecadação por cobrador"],
      ["Data", "Cobrador", "Valor"],
      ...collectorReceipts.map((x) => [
        x.receipt_date,
        x.cobradores?.name || "Cobrador",
        x.amount,
      ]),
      [],
      ["RH (separado do caixa geral)"],
      ["Data", "Tipo", "Funcionário", "Valor"],
      ...payroll.map((x) => [
        x.payment_date,
        x.movement_type === "advance" ? "Adiantamento" : "Pagamento de salário",
        x.funcionarios?.name,
        x.amount,
      ]),
    ];
    const blob = new Blob(
      ["\ufeff" + lines.map((row) => row.map(csvCell).join(";")).join("\r\n")],
      { type: "text/csv;charset=utf-8" },
    );
    const url = URL.createObjectURL(blob),
      a = document.createElement("a");
    a.href = url;
    a.download = `paxshalom-relatorio-${month}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };
  const previous = new Date(`${month}-01T12:00:00`);
  previous.setMonth(previous.getMonth() - 1);
  const prevKey = previous.toISOString().slice(0, 7),
    previousIncome = previousRows
      .filter((x) => x.type === "income")
      .reduce((a, x) => a + Number(x.amount), 0),
    previousExpense = previousRows
      .filter((x) => x.type === "expense")
      .reduce((a, x) => a + Number(x.amount), 0),
    compareData = [
      {
        name: monthName(prevKey),
        Entradas: previousIncome,
        Saídas: previousExpense,
      },
      {
        name: monthName(month),
        Entradas: totals.income,
        Saídas: totals.expense,
      },
    ];
  return (
    <>
      <section className="page-heading">
        <div>
          <span className="eyebrow">RELATÓRIOS</span>
          <h1>
            Resumo mensal<span>.</span>
          </h1>
          <p>
            Entradas e saídas do caixa geral, com folha de RH em seção
            independente.
          </p>
        </div>
        <div className="report-actions">
          <button className="secondary-button" onClick={exportCsv}>
            <Download size={15} /> Exportar CSV
          </button>
          <button className="secondary-button" onClick={() => window.print()}>
            <Printer size={15} /> Salvar PDF
          </button>
        </div>
      </section>
      <section className="mod-toolbar">
        <label className="mod-date">
          <span>MÊS DO RELATÓRIO</span>
          <input
            type="month"
            value={month}
            onChange={(e) => setMonth(e.target.value)}
          />
        </label>
        <span className="count-pill">{monthName(month)}</span>
      </section>
      {error && (
        <div className="mod-notice" role="alert">
          {error}
        </div>
      )}
      {busy ? (
        <div className="mod-card">Carregando relatório…</div>
      ) : (
        <>
          <div className="summary-grid report-grid">
            <article className="summary-card">
              <small>Entradas do caixa</small>
              <strong className="income-text">{money(totals.income)}</strong>
              <small>Cobradores: {money(totals.collectors)}</small>
            </article>
            <article className="summary-card">
              <small>Saídas do caixa</small>
              <strong className="expense-text">{money(totals.expense)}</strong>
              <small>Serviços terceirizados: {money(totals.services)}</small>
            </article>
            <article className="summary-card final-card">
              <small>Saldo líquido geral</small>
              <strong>{money(totals.income - totals.expense)}</strong>
            </article>
            <article className="summary-card">
              <small>Folha e vales · separado</small>
              <strong>{money(totals.payroll)}</strong>
              <small>Não compõe as saídas gerais</small>
            </article>
          </div>
          <section className="mod-card">
            <div className="mod-card-head">
              <div>
                <h2>Comparativo mensal</h2>
                <p>
                  Entradas e saídas do caixa geral no mês selecionado e no
                  anterior.
                </p>
              </div>
            </div>
            <div className="report-chart">
              <ResponsiveContainer width="100%" height="100%">
                <BarChart data={compareData}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis dataKey="name" />
                  <YAxis />
                  <Tooltip formatter={(value) => money(value)} />
                  <Bar
                    dataKey="Entradas"
                    fill="#1F2C3F"
                    radius={[5, 5, 0, 0]}
                  />
                  <Bar dataKey="Saídas" fill="#B39263" radius={[5, 5, 0, 0]} />
                </BarChart>
              </ResponsiveContainer>
            </div>
          </section>
          <section className="mod-card">
            <div className="mod-card-head">
              <div>
                <h2>Arrecadação por cobrador</h2>
                <p>
                  Entregas registradas no mês, antes ou depois do fechamento.
                </p>
              </div>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>COBRADOR</th>
                    <th>TOTAL ARRECADADO</th>
                  </tr>
                </thead>
                <tbody>
                  {Object.entries(receiptsByCollector).map(([name, amount]) => (
                    <tr key={name}>
                      <td data-label="Cobrador">{name}</td>
                      <td data-label="Total arrecadado">{money(amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {collectorReceipts.length === 0 && (
              <p className="mod-empty">
                Nenhuma entrega de cobrador neste mês.
              </p>
            )}
          </section>
          <section className="mod-card">
            <div className="mod-card-head">
              <div>
                <h2>Fechamentos diários</h2>
                <p>Conferência do saldo esperado e contado.</p>
              </div>
              <span className="count-pill">{closures.length} fechamentos</span>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>DATA</th>
                    <th>ENTRADAS</th>
                    <th>SAÍDAS</th>
                    <th>ESPERADO</th>
                    <th>CONTADO</th>
                    <th>DIFERENÇA</th>
                  </tr>
                </thead>
                <tbody>
                  {closures.map((c) => (
                    <tr key={c.close_date}>
                      <td data-label="Data">
                        {new Date(
                          `${c.close_date}T12:00:00`,
                        ).toLocaleDateString("pt-BR")}
                      </td>
                      <td data-label="Entradas">{money(c.income_total)}</td>
                      <td data-label="Saídas">{money(c.expense_total)}</td>
                      <td data-label="Esperado">{money(c.expected_balance)}</td>
                      <td data-label="Contado">{money(c.counted_balance)}</td>
                      <td data-label="Diferença">{money(c.difference)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {closures.length === 0 && (
              <p className="mod-empty">Nenhum fechamento neste mês.</p>
            )}
          </section>
          <section className="mod-card">
            <div className="mod-card-head">
              <div>
                <h2>Movimentações do caixa geral</h2>
                <p>
                  RH é excluído por consulta e apresentado separadamente acima.
                </p>
              </div>
              <span className="count-pill">{rows.length} registros</span>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>DATA</th>
                    <th>TIPO</th>
                    <th>DESCRIÇÃO</th>
                    <th>CATEGORIA</th>
                    <th>VALOR</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.id}>
                      <td data-label="Data">
                        {new Date(
                          `${r.transaction_date}T12:00:00`,
                        ).toLocaleDateString("pt-BR")}
                      </td>
                      <td data-label="Tipo">
                        {r.type === "income" ? "Entrada" : "Saída"}
                      </td>
                      <td data-label="Descrição">{r.description}</td>
                      <td data-label="Categoria">{r.category}</td>
                      <td data-label="Valor">{money(r.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {rows.length === 0 && (
              <p className="mod-empty">Sem movimentos no período.</p>
            )}
          </section>
          <section className="mod-card">
            <div className="mod-card-head">
              <div>
                <h2>RH · folha e adiantamentos</h2>
                <p>Relatório informativo, independente do caixa geral.</p>
              </div>
            </div>
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>DATA</th>
                    <th>FUNCIONÁRIO</th>
                    <th>TIPO</th>
                    <th>VALOR</th>
                  </tr>
                </thead>
                <tbody>
                  {payroll.map((p) => (
                    <tr key={p.id}>
                      <td data-label="Data">
                        {new Date(
                          `${p.payment_date}T12:00:00`,
                        ).toLocaleDateString("pt-BR")}
                      </td>
                      <td data-label="Funcionário">
                        {p.funcionarios?.name || "Funcionário"}
                      </td>
                      <td data-label="Tipo">
                        {p.movement_type === "advance"
                          ? "Adiantamento"
                          : "Pagamento de salário"}
                      </td>
                      <td data-label="Valor">{money(p.amount)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {payroll.length === 0 && (
              <p className="mod-empty">Sem movimentos de RH no período.</p>
            )}
          </section>
        </>
      )}
    </>
  );
}
