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

## PWA — segurança e testes em dispositivo

- [ ] Confirme que o domínio de produção oferece HTTPS e redireciona HTTP para HTTPS; HSTS está definido no `vercel.json`.
- [ ] Verifique nos headers da página: `Content-Security-Policy`, `Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options`, `Referrer-Policy` e `Permissions-Policy`.
- [ ] Confirme que o build publicado contém `manifest.webmanifest`, `sw.js`, `offline.html`, favicon, Apple touch icon e todos os PNGs de instalação.
- [ ] Android/Chrome: instalar pelo botão do app ou menu do navegador e abrir em modo standalone.
- [ ] iPhone/Safari: **Compartilhar → Adicionar à Tela de Início**; verificar safe areas no cabeçalho, navegação e fechamento fixo.
- [ ] Visitar telas com rede, ficar offline e conferir leitura somente das telas previamente visitadas; confirmar que lançamento, pagamento, fechamento e baixa estão desativados.
- [ ] Restaurar a rede e confirmar reativação. Verificar nos logs de rede que nenhuma escrita ficou enfileirada durante o período offline.
- [ ] Fazer logout; ficar offline e confirmar que leituras Supabase cacheadas não aparecem.
- [ ] Publicar uma versão nova e confirmar o aviso manual de atualização; manter um formulário aberto e verificar que a atualização não o descarta.
- [ ] Aguardar cinco minutos parado e em segundo plano; confirmar que os valores ficam ocultos. Senha incorreta ou falta de rede não deve desbloquear.
- [ ] Alternar para o seletor de apps e confirmar que o conteúdo está desfocado/oculto; voltar e conferir a tela.
- [ ] Executar Lighthouse nas categorias PWA e desempenho no build de produção HTTPS; registrar notas no `UPGRADE_LOG.md`.

## Atualização e rollback do PWA

- [ ] Usuários confirmam **Atualizar** no próprio app; não há recarga automática. Feche/salve formulários antes de atualizar.
- [ ] Se a publicação apresentar regressão, reimplantar o último build estável no Vercel e validar a atualização pelo service worker.
- [ ] Validar em aparelhos físicos Android e iPhone antes de anunciar a instalação para toda a equipe.
