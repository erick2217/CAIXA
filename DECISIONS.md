# Decisões técnicas

## Fase 0

- RH permanece fora do caixa geral, conforme regra de negócio vigente.
- No fechamento integrado, a política conservadora será bloquear se algum cobrador ativo não tiver lançamento explícito para a data; valor zero deve ser registrado explicitamente. O operador poderá corrigir e tentar novamente.
- Backups/migrations serão aditivos; `user_id` será preservado ao introduzir organização.
- Chaves privadas nunca recebem prefixo `VITE_`; ficam somente em secret stores de backend.
- Git ausente: sem branch/commits; arquivos de decisão e log documentam o progresso.

## Reversão

- Fase 0: `.env.example` pode ser reconstruído somente com placeholders; `.gitignore` pode ser ajustado sem afetar dados. O schema-fonte original está em `supabase/backups/schema_20261019_initial.sql`.
- A credencial privada anteriormente presente em `.env.example` deve ser rotacionada no Supabase; não se deve restaurá-la do backup.
## Fase 1

- Fechamento diário integrado consolida os cobradores automaticamente, mas bloqueia se faltar valor explícito de qualquer cobrador ativo (R$ 0,00 é válido). Isso evita fechar com arrecadação desconhecida.
- Uma repetição de fechamento só retorna o fechamento anterior se saldo inicial e valor contado forem iguais; entradas divergentes exigem conferência, sem sobrescrever o registro.
- A baixa de um vencimento já registrado retorna a baixa existente. A data de vencimento é a chave; o vencimento seguinte só avança uma vez.
- O valor zero de uma entrega de cobrador é válido; transações e pagamentos continuam exigindo valor positivo.
- Reabertura autorizada por papel depende de membership/roles da Fase 2; o ponto será integrado nessa migração, sem liberar reabertura antes de existir autorização verificável.
- Rollback mantém novas colunas/funções no banco; a remoção delas apagaria chaves de idempotência e não é necessária para voltar o frontend.
## Fase 2

- Uma organização inicial é criada por usuário existente, com o usuário como admin; `user_id` continua armazenado como identificador legado do proprietário da organização. O ator real fica em `audit_log.actor_id`.
- Usuários adicionais só veem a organização selecionada como padrão. Inserções novas herdam essa organização no banco; não confiam no `organization_id` enviado pelo navegador.
- Permissões: admin configura membros e reabre dias; financeiro administra lançamentos, folha e serviços; operador registra caixa e entregas; leitura consulta módulos e não grava.
- O snapshot privado é feito uma vez pela migration e não é atualizado em reexecuções, para preservar o estado pré-migração.
- Reabertura de fechamentos legados sem vínculo único entre fechamento e transação consolidada é bloqueada. Associar transações antigas por descrição aproximada poderia reverter entradas erradas.
- Convite por e-mail de novos usuários fica para a Fase 3; até lá o módulo só adiciona usuários que já criaram uma conta.
- A aplicação não pode validar esta migração no Supabase remoto sem CLI/cliente PostgreSQL, então a execução e os testes remotos seguem como passos manuais.
## Fase 3

- Um aviso é criado uma vez por dia, por destinatário e vencimento, desde a antecedência configurada até a baixa. Isso mantém o lembrete ativo sem duplicar execuções do mesmo dia.
- Falta de chave Resend gera registro `dry_run`; nenhum e-mail é enviado sem configuração explícita.
- Novos convites recebem ID aleatório persistido; o trigger do Auth valida ID, e-mail e expiração antes de associar a conta à organização. Convites são aceitos apenas quando o usuário usa o e-mail destinatário.
- Para remover a automação, pausar o cron/schedule e apagar secrets de envio; logs ficam preservados.
## Fases 4–6

- Dependências adicionadas com justificativa: TypeScript e @types para migração incremental; Vitest/jsdom/Testing Library para testes; ESLint/TypeScript ESLint e Prettier para consistência; GitHub Actions para CI. Recharts e lucide já existiam e foram reutilizados.
- Repositório feature-first iniciado com caixas, cobradores, folha, serviços e relatórios; módulos históricos continuam em caminhos antigos para reduzir risco durante a migração incremental.
- Relatório mensal geral exclui RH, mostra folha separada, fechamentos diários, movimentações e comparativo Recharts; exporta CSV e usa impressão do navegador para PDF.

## Dependências e risco residual de segurança

- `npm audit --omit=dev`: 0 vulnerabilidades em dependências de runtime.
- `npm audit`: 7 vulnerabilidades de desenvolvimento herdadas do Tailwind CSS 3.x (5 high, 2 moderate); a correção automática indicada exige Tailwind 4, migração major incompatível com a instrução de manter a stack e que requer ajuste de configuração. Não fiz upgrade forçado sem validação visual; registrar e planejar atualização dedicada.

## Fase 7 e risco residual

- Alterações do Tailwind 3 para Tailwind 4 não foram feitas: `npm audit` só oferece correção automática por major upgrade, e isso exige revisão do setup e regressão visual. Até atualização, a exposição verificada está em dependências de desenvolvimento; runtime audit está limpo.
- 11 warnings de lint existentes em componentes antigos (hooks/Fast Refresh) não bloqueiam a execução, mas merecem correção em refatoração própria.
- Não foi possível executar branch/commits porque Git não está instalado na sessão.
- `@types/node` foi adicionado somente para tipar o teste de contrato que lê o schema local sem depender do banco.

## PWA — Etapa 1

- Ícones PNG são gerados a partir do SVG do monograma usando `sharp` como dependência exclusivamente de desenvolvimento, permitida para essa geração e mantida reproduzível pelo script `npm run generate:pwa-icons`. Não foi usada uma fonte externa para compor os ícones; o desenho usa Playfair Display com Georgia como fallback.
- O ícone maskable reduz o conteúdo para manter margem ampla dentro da zona segura. Para reverter esta etapa, remova o plugin e suas dependências, a configuração/metadata do PWA, os ícones e o script; isso não altera dados nem regras de negócio.

## PWA — Etapa 2

- A política de cache exclui todas as RPCs, inclusive as somente de leitura, para evitar classificar incorretamente qualquer RPC de escrita. Só respostas GET de tabelas PostgREST podem ser guardadas; auth, Functions, Realtime e métodos de escrita não correspondem à rota.
- As leituras cacheadas são apagadas antes e depois do `signOut` para reduzir a chance de uma resposta em voo recriar dados após o logout. Ao reverter, remova a estratégia runtime de tabelas e o helper de limpeza; isso apenas desativa consulta offline e não altera operações financeiras.
