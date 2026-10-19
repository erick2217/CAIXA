# Atualização PAXSHALOM — registro por fase

## Fase 4 — Design system e acessibilidade

- Tokens oficiais da marca e do modo escuro em `src/styles/tokens.css`; Tailwind agora exporta `pax.*`, `font-display` Playfair Display, `font-sans` DM Sans e sombra oficial.
- Componentes passam a usar superfícies/cores semânticas; foco visível, disabled e apresentação móvel das tabelas foram melhorados.
- Verificação automatizada será registrada abaixo após lint, typecheck, testes e build.

## Fase 5 — Organização e qualidade

- Criadas áreas `src/features`, `src/components`, `src/lib`, `src/__tests__`; configuração TypeScript incremental mantém JSX existente em JavaScript e ativa TypeScript estrito para os novos módulos TS.
- Vitest e testes de formatação/data, ESLint com regras React Hooks/TypeScript, Prettier e workflow CI GitHub Actions configurados.
- Sem Git instalado, não foi possível criar branch ou commits; árvore de trabalho compartilhada preservada.

## Fase 6 — Relatórios, exportação e backup

- Relatório mensal compara entradas/saídas gerais, detalha fechamentos, mostra RH em área independente, exporta CSV e abre impressão para salvar PDF.
- Consulta geral exclui categoria RH; consulta de folha lê `payroll_movements` separadamente.
- Procedimento de backup/restore em `docs/BACKUP.md`.

## Fase 7 — Verificação e entrega

- Resultados efetivamente executados e bloqueios registrados após validação. SQL remoto, SMTP/Resend, Auth, cron e RLS multi-conta precisam de implantação/credenciais externas, indisponíveis nesta sessão.
## Diagnóstico da Fase 0

- Aplicação existente em React/Vite JSX; estilos concentrados em `src/styles.css`; schema monolítico tinha definições SQL sobrepostas.
- Schema inicial preservado em `supabase/backups/schema_20261019_initial.sql`; snapshots pré-fases posteriores também preservados.
- Não havia suíte de lint/typecheck/test nem pipeline CI; validações SQL dependem de ambiente Supabase.
- Git, Supabase CLI, PostgreSQL, Docker e Deno não estavam disponíveis; branch/commits não foram possíveis.
- O `.env.example` original continha credencial privada em variável Vite. Foi substituído por placeholders e `.env` foi ignorado. A chave deve ser rotacionada no Supabase. O arquivo `.env` não foi lido nem usado para conexão.

## Fases 4 a 6

- Design system e catálogo de componentes compartilhados descritos acima; `Brand` e `ConfirmDialog` são usados pelo app.
- Dependências adicionadas e justificadas em `DECISIONS.md`; suites npm configuradas.
- Relatório mensal, comparativo Recharts, exportação CSV/PDF e instruções de backup implementados.

## Fase 7 — validação final

- `npm run lint`: passou sem erros; 11 avisos React Hooks/Fast Refresh permanecem em componentes legados.
- `npm run typecheck`: passou.
- `npm test -- --run`: passou com 3 arquivos e 7 testes (formatadores, confirmação e contratos estáticos do schema).
- `npm run format_check`: passou nos arquivos novos/configurados.
- `npm run build`: passou com URL/chave pública fictícias do Supabase para incluir telas autenticadas; relatório está em chunk lazy. Nenhuma conexão foi feita ao Supabase.
- `npm audit --omit=dev`: 0 vulnerabilidades runtime. `npm audit` aponta 7 vulnerabilidades dev herdadas do Tailwind 3; ver `DECISIONS.md`.
- Varredura de padrões de chave em `.env.example`: passou.
- Testes SQL reais, RLS entre contas, convites, e-mail, cron e ponta a ponta de banco não foram realizados pela ausência de Supabase CLI/PostgreSQL/Docker/Deno e projeto de homologação acessível. Os testes estáticos do schema não os substituem.

### Revisão das cinco regras de negócio (estática)

1. RH fica separado: a RPC não grava em `transactions`, o fechamento filtra RH e os relatórios exibem folha à parte.
2. Dia fechado bloqueia transações por trigger e desativa edição no frontend; falta confirmar no banco remoto.
3. Fechamento integrado consolida cobradores antes do caixa geral, com totais individuais no relatório.
4. Pagamento do serviço usa RPC atômica, registra saída e avança o vencimento; falta teste de integração real.
5. Cálculos críticos permanecem no PostgreSQL com locks e idempotência; aplicar e testar migrations ainda é pendente.
