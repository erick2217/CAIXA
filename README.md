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

Preencha apenas `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` ou `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` para o frontend. Esses prefixos são públicos; **nunca** coloque `service_role`, Resend ou outros segredos em variáveis `VITE_*` ou `NEXT_PUBLIC_*`.

```sh
npm run dev
```

## Banco e deploy

Leia `CHECKLIST_DEPLOY.md`. Em ambiente de homologação, aplique as migrations na ordem numérica em `supabase/migrations/`; não use o `schema.sql` como substituto sem comparar seu histórico com migrations já aplicadas. Os arquivos em `supabase/tests/` são scripts de integração SQL, não rodam pelo Vitest.

Edge Functions e lembretes: `supabase/functions/README.md`. Segredos de envio devem ficar no Supabase, nunca no browser.

## Aplicativo PWA

- **Android:** publique em HTTPS, abra a URL no Chrome e toque em **Instalar app** no menu da aplicação ou em **Instalar app** no cabeçalho. Confirme a instalação.
- **iPhone/iPad:** abra a URL no Safari, toque em **Compartilhar** e selecione **Adicionar à Tela de Início**. Abra o ícone criado para usar em modo standalone.
- **Teste local:** gere o build com `npm run build` e sirva `dist/` por HTTPS. `npm run preview -- --host 0.0.0.0` inicia o preview HTTP; para testar instalação, service worker e offline em dispositivo, coloque-o atrás de um proxy TLS local confiável (por exemplo, Caddy com certificado local instalado no dispositivo) ou use o domínio de homologação HTTPS. `localhost` também é considerado contexto seguro em navegadores de desenvolvimento, mas só testa o próprio dispositivo.
- **Publicação no Vercel:** configure as variáveis públicas de Supabase no projeto, confirme o domínio/ambiente de destino e publique pela integração GitHub/Vercel após enviar o commit para a branch conectada, ou use `npx vercel --prod` em uma sessão autenticada. Não envie arquivos `.env` nem chaves privadas.
- **Atualização:** o app avisa quando há uma nova versão; toque em **Atualizar** depois de salvar ou fechar qualquer formulário. Nunca limpe dados do site durante um lançamento pendente. Em caso de versão presa, feche e reabra o app; no Chrome, a equipe também pode atualizar o service worker pelo painel Application/Service Workers.
- **Modo offline:** telas visitadas podem exibir dados de consulta em cache por até 24 horas. Lançamentos, pagamentos, baixas e fechamentos exigem conexão; nenhuma gravação é guardada em fila. O logout apaga os caches de leitura do Supabase.

Cabeçalhos HTTPS e segurança estão configurados para Vercel em `vercel.json`; revise domínio e cabeçalhos em `CHECKLIST_DEPLOY.md` antes de publicar.

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
