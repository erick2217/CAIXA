# Pax Shalom — Caixa e Gestão Financeira

Aplicação responsiva para fluxo de caixa diário, cobradores, pagamentos de RH, serviços terceirizados, membros/papéis e relatórios mensais. Stack: React, Vite, Tailwind CSS e Supabase PostgreSQL/Auth/Edge Functions.

## Requisitos

- Node.js 20 ou superior e npm.
- Projeto Supabase com Auth por e-mail habilitado.

## Instalação local

```sh
npm ci
Copy-Item .env.example .env
```

Preencha apenas `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` (ou chave publicável suportada) para o frontend. **Nunca** coloque `service_role`, Resend ou outros segredos em variáveis `VITE_*`.

```sh
npm run dev
```

## Banco e deploy

Leia `CHECKLIST_DEPLOY.md`. Em ambiente de homologação, aplique as migrations na ordem numérica em `supabase/migrations/`; não use o `schema.sql` como substituto sem comparar seu histórico com migrations já aplicadas. Os arquivos em `supabase/tests/` são scripts de integração SQL, não rodam pelo Vitest.

Edge Functions e lembretes: `supabase/functions/README.md`. Segredos de envio devem ficar no Supabase, nunca no browser.

## Módulos e regra contábil

- Caixa diário: entradas/saídas, saldo contado, fechamento e bloqueio após encerrar.
- Cobradores: lançamentos por pessoa, fechamento atômico e consolidação no caixa geral.
- RH: salários e adiantamentos registrados em folha, **fora** das saídas e saldos do caixa geral.
- Serviços fixos: vencimentos recorrentes, lembretes até baixa e pagamento lançado como saída.
- Equipe: organizações, papéis e trilha de auditoria, aplicados no backend por RLS.
- Relatórios: CSV e impressão/PDF, com RH sempre em bloco separado.

## Qualidade

```sh
npm run lint
npm run typecheck
npm test -- --run
npm run build
```

`supabase/tests/phase1_integrity.sql` e `phase2_rls.sql` devem ser executados em ambiente Supabase de homologação com usuários de teste. Veja `UPGRADE_LOG.md`, `DECISIONS.md` e `docs/BACKUP.md`.
