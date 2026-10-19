# Checklist de implantação

## Antes de implantar
- [ ] Faça backup completo do Supabase e valide uma restauração em projeto separado.
- [ ] Revogue/rotacione a chave privada que estava exposta no antigo `.env.example`; confira os logs de uso.
- [ ] Configure `.env` local apenas com a URL Supabase e chave publicável/anon. Nunca exponha `service_role` em `VITE_*`.
- [ ] Revise e aplique em ordem `supabase/migrations/202610190001_phase1_integrity.sql`, `202610190002_organizations_rls_audit.sql`, `202610190003_notifications.sql`.
- [ ] Execute `supabase/tests/phase1_integrity.sql` e `phase2_rls.sql` no ambiente Supabase de homologação e confira o isolamento entre organizações.
- [ ] Configure Supabase Auth SMTP, domínio de e-mail e `APP_BASE_URL` para convites.
- [ ] Publique Edge Functions `invite-member` e `service-reminders`.
- [ ] Configure `RESEND_API_KEY` e `RESEND_FROM_EMAIL` como secrets da Edge Function; teste primeiro com domínio verificado e destinatário de teste.
- [ ] Configure agendamento diário da função de lembretes em horário adequado para America/Sao_Paulo.
- [ ] Revise os membros e papéis da organização inicial Pax Shalom.

## Validar após implantação
- [ ] Teste contas separadas com papéis admin, financeiro, operador e leitura.
- [ ] Confirme que vales e pagamentos de salário não afetam KPIs, relatórios, nem saldo geral.
- [ ] Feche um dia de teste com cobradores; tente editar após fechamento e valide bloqueio no banco.
- [ ] Confirme idempotência repetindo chamadas de fechamento/pagamento com a mesma chave.
- [ ] Registre e pague serviço terceirizado; confira saída, vencimento seguinte e ausência de lembrete após baixa.
- [ ] Teste reabertura somente com admin e justificativa, conferindo trilha de auditoria.
- [ ] Configure alertas de falha das Edge Functions e monitore entregas do Resend.
