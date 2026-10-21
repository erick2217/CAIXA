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

## PWA — Etapa 1: manifesto e ícones

- Configurado `vite-plugin-pwa` com `registerType: "prompt"` e manifesto Pax Shalom para Android/iOS.
- Criados o SVG-fonte do monograma PS, ícones PNG 192x192, 512x512, maskable 512x512 com margem conservadora, Apple touch icon 180x180 e favicon SVG.
- Incluídos metadados iOS, `viewport-fit=cover` e o script repetível de geração dos PNGs.
- `npm run lint`: passou sem erros; 11 avisos legados.
- `npm run typecheck`: passou.
- `npm test -- --run`: passou (3 arquivos, 8 testes).
- `npm run format_check`: passou.
- `npm run build`: passou; manifesto e service worker gerados.
- Dimensões dos quatro PNGs verificadas com Sharp.

## PWA — Etapa 2: service worker e cache de leitura

- O precache inclui o app shell, arquivos estáticos, fontes locais/ícones e `/offline.html`; a navegação usa o fallback do shell.
- Fontes do Google usam `StaleWhileRevalidate`. Apenas `GET /rest/v1/<tabela>` usa `NetworkFirst`, timeout de 3 s, 24 h e até 100 entradas. Auth, RPC, Functions e todos os métodos de escrita ficam fora da regra de cache.
- O logout remove somente caches de leituras Supabase antes e depois de encerrar a sessão; falhas de limpeza são exibidas.
- `npm run lint`: passou sem erros; 11 avisos legados.
- `npm run typecheck`: passou.
- `npm test -- --run`: passou (4 arquivos, 11 testes), incluindo métodos/rotas excluídos e erros de limpeza.
- `npm run format_check`: passou.
- `npm run build`: passou; inspeção do service worker gerado confirmou as rotas, o timeout e o cache restrito.

## PWA — Etapa 3: conectividade, atualização e instalação

- Criado `useOnlineStatus` com eventos do navegador e verificação real em `/auth/v1/health`, sem cache e com timeout de 3 s; banner informa consulta offline e bloqueio de lançamentos.
- Ações de caixa, cobradores, RH, serviços e permissões são desativadas offline e seus handlers também recusam gravações; chamadas de autenticação exigem conexão.
- A instalação Android usa `beforeinstallprompt`; no iPhone a dica é dispensável e persistida em `localStorage`. O tema sincroniza a meta `theme-color`.
- A atualização usa registro manual com prompt. A página só chama o update quando solicitado pelo usuário e recusa atualizar se houver formulário aberto.
- Testes (6 arquivos, 15 casos), typecheck e build passaram; lint passou sem erros com 11 avisos legados. Os testes de cache e conectividade incluem falha de rede, rota e botões offline.
