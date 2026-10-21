import { Check, ChevronRight, X } from "lucide-react";

export function Brand() {
  return (
    <a className="brand" href="#">
      <span className="brand-mark pax-mini-mark">PS</span>
      <span>
        Pax Shalom<span className="brand-dot">.</span>
      </span>
    </a>
  );
}
export function PageHeader({ eyebrow, title, description, action }) {
  return (
    <section className="page-heading">
      <div>
        <span className="eyebrow">{eyebrow}</span>
        <h1>
          {title}
          <span>.</span>
        </h1>
        <p>{description}</p>
      </div>
      {action}
    </section>
  );
}
export function MetricCard({ label, value, detail, icon: Icon, variant = "" }) {
  return (
    <article className={`summary-card ${variant}`}>
      <div className="summary-label">
        {label}
        {Icon && (
          <span className="summary-icon">
            <Icon size={17} />
          </span>
        )}
      </div>
      <strong>{value}</strong>
      {detail && <small>{detail}</small>}
    </article>
  );
}
export function Modal({ open, onClose, title, children }) {
  if (!open) return null;
  return (
    <div
      className="modal-backdrop"
      onMouseDown={(e) => e.target === e.currentTarget && onClose?.()}
    >
      <section
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="shared-modal-title"
      >
        <div className="modal-heading">
          <h2 id="shared-modal-title">{title}</h2>
          <button
            type="button"
            className="icon-close"
            onClick={onClose}
            aria-label="Fechar"
          >
            <X size={18} />
          </button>
        </div>
        {children}
      </section>
    </div>
  );
}
export function StatusBadge({ children, status = "open" }) {
  return (
    <span className={`mod-pill ${status}`}>
      <i />
      {children}
    </span>
  );
}
export function ThemeToggle({ theme, onToggle }) {
  return (
    <button
      type="button"
      className="theme-toggle"
      onClick={onToggle}
      aria-label={
        theme === "light" ? "Ativar tema escuro" : "Ativar tema claro"
      }
    >
      {theme === "light" ? "◐" : "☼"}
      <span>{theme === "light" ? "Escuro" : "Claro"}</span>
    </button>
  );
}
export function DataTable({
  columns,
  rows,
  renderRow,
  empty = "Nenhum registro encontrado.",
}) {
  if (!rows.length) return <EmptyState>{empty}</EmptyState>;
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((x) => (
              <th key={x}>{x}</th>
            ))}
          </tr>
        </thead>
        <tbody>{rows.map(renderRow)}</tbody>
      </table>
    </div>
  );
}
export function EmptyState({ title, children, icon: Icon }) {
  return (
    <div className="mod-empty">
      {Icon && <Icon size={22} />}
      {title && <b>{title}</b>}
      {children && <span>{children}</span>}
    </div>
  );
}
export function ConfirmDialog({
  open,
  title,
  description,
  confirmLabel = "Confirmar",
  busy = false,
  confirmDisabled = false,
  onCancel,
  onConfirm,
}) {
  if (!open) return null;
  return (
    <div className="modal-backdrop" role="presentation">
      <section
        className="modal"
        role="alertdialog"
        aria-modal="true"
        aria-labelledby="confirm-title"
      >
        <div className="modal-heading">
          <h2 id="confirm-title">{title}</h2>
        </div>
        <p className="modal-hint">{description}</p>
        <div className="modal-actions">
          <button
            className="secondary-button"
            disabled={busy}
            onClick={onCancel}
          >
            Cancelar
          </button>
          <button
            className="close-button"
            disabled={busy || confirmDisabled}
            onClick={onConfirm}
          >
            <Check size={15} />
            {busy ? "Processando…" : confirmLabel}
            <ChevronRight size={15} />
          </button>
        </div>
      </section>
    </div>
  );
}
export function Skeleton({ width = "100%", height: heightPx = 18 }) {
  return (
    <span
      aria-hidden="true"
      className="skeleton"
      style={{ display: "block", width, height: heightPx, borderRadius: 6 }}
    />
  );
}
