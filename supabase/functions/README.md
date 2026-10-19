# Edge Functions Pax Shalom

## `invite-member`

Recebe sessão autenticada, exige papel `admin`, adiciona contas existentes ou envia convite pelo Supabase Auth. A função de trigger aceita a organização somente quando o convite pendente tem o mesmo e-mail e não expirou.

## `service-reminders`

Execute uma vez por dia. Envia um e-mail por serviço/vencimento/destinatário/dia a partir da antecedência configurada, repetindo uma vez ao dia até a baixa. Uma chave única e a função atômica `claim_service_notification` impedem duas execuções concorrentes de enviar a mesma notificação.

Sem `RESEND_API_KEY`, a função registra `dry_run` no banco e nos logs, sem enviar e-mail. Falhas podem ser repetidas na próxima execução; a chamada Resend recebe a chave de idempotência do registro.

### Secrets do ambiente Edge

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY` (somente servidor; nunca usar prefixo `VITE_`)
- `RESEND_API_KEY` (opcional: sem valor, opera em dry-run)
- `RESEND_FROM_EMAIL` (obrigatório quando Resend estiver ativado e domínio verificado)
- `APP_BASE_URL` (URL permitida pelo Supabase Auth para retorno do convite)

Configure os secrets no ambiente das Edge Functions. Agende `service-reminders` diariamente com autenticação de serviço. O envio real também depende de SMTP/convites habilitados no Supabase Auth e de um domínio verificado no Resend.
