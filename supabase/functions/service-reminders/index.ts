import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.0'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function localDate() {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(new Date())
  const part = (type: string) => parts.find((item) => item.type === type)?.value || '00'
  return `${part('year')}-${part('month')}-${part('day')}`
}

function dayNumber(date: string) {
  const [year, month, day] = date.split('-').map(Number)
  return Date.UTC(year, month - 1, day) / 86_400_000
}

function escapeHtml(value: string) {
  return value.replace(/[&<>"']/g, (char) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[char] || char)
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return Response.json({ error: 'Método não permitido.' }, { status: 405, headers: cors })

  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!supabaseUrl || !serviceKey) {
    return Response.json({ error: 'Secrets Supabase ausentes na Edge Function.' }, { status: 500, headers: cors })
  }

  const db = createClient(supabaseUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const resendKey = Deno.env.get('RESEND_API_KEY')
  const from = Deno.env.get('RESEND_FROM_EMAIL')
  if (resendKey && !from) return Response.json({ error: 'RESEND_FROM_EMAIL precisa estar configurado junto com RESEND_API_KEY.' }, { status: 500, headers: cors })
  const today = localDate()
  const { data: services, error: servicesError } = await db.from('third_party_services')
    .select('id,organization_id,name,fixed_amount,next_due_date,reminder_days')
    .eq('active', true).order('next_due_date')
  if (servicesError) return Response.json({ error: servicesError.message }, { status: 500, headers: cors })

  const results = { sent: 0, dryRun: 0, skipped: 0, failed: 0 }
  const userEmailCache = new Map<string, string | null>()
  for (const service of services || []) {
    const start = new Date(`${service.next_due_date}T12:00:00Z`)
    start.setUTCDate(start.getUTCDate() - Number(service.reminder_days))
    const firstReminder = start.toISOString().slice(0, 10)
    if (dayNumber(today) < dayNumber(firstReminder)) continue

    const { data: members, error: membersError } = await db.from('organization_members')
      .select('user_id').eq('organization_id', service.organization_id).in('role', ['admin', 'financeiro'])
    if (membersError) { results.failed++; console.error('recipient_lookup_failed', service.id); continue }

    for (const member of members || []) {
      let email = userEmailCache.get(member.user_id)
      if (email === undefined) {
        const { data } = await db.auth.admin.getUserById(member.user_id)
        email = data?.user?.email || null
        userEmailCache.set(member.user_id, email)
      }
      if (!email) { results.skipped++; continue }

      const notificationRow = {
        organization_id: service.organization_id,
        service_id: service.id,
        due_date: service.next_due_date,
        notification_date: today,
        channel: 'email',
        recipient_email: email.toLowerCase(),
        status: 'pending',
      }
      let { data: notification, error: insertError } = await db.from('service_notifications')
        .insert(notificationRow).select('id,status').maybeSingle()
      if (insertError?.code === '23505') {
        const existing = await db.from('service_notifications').select('id,status')
          .eq('service_id', service.id).eq('due_date', service.next_due_date)
          .eq('notification_date', today).eq('channel', 'email')
          .eq('recipient_email', email.toLowerCase()).maybeSingle()
        notification = existing.data
        insertError = existing.error
      }
      if (insertError || !notification || ['sent', 'dry_run', 'sending'].includes(notification.status)) {
        results.skipped++
        continue
      }

      const claimed = await db.rpc('claim_service_notification', { p_notification_id: notification.id })
      if (claimed.error || !claimed.data) { results.skipped++; continue }

      if (!resendKey) {
        await db.from('service_notifications').update({ status: 'dry_run', last_error: 'RESEND_API_KEY não configurada.', updated_at: new Date().toISOString() })
          .eq('id', notification.id)
        results.dryRun++
        console.log(JSON.stringify({ event: 'reminder_dry_run', service_id: service.id, due_date: service.next_due_date, date: today }))
        continue
      }

      const name = escapeHtml(service.name)
      const amount = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(service.fixed_amount))
      const days = dayNumber(service.next_due_date) - dayNumber(today)
      const dueText = days < 0 ? `Vencido há ${Math.abs(days)} dia(s)` : days === 0 ? 'Vence hoje' : `Vence em ${days} dia(s)`
      const subject = `${dueText}: pagamento de ${service.name}`
      const textBody = `Pax Shalom: ${service.name}, ${amount}. ${dueText}. Vencimento: ${service.next_due_date}. Acesse o sistema para confirmar o pagamento.`
      const htmlBody = `<div style="font-family:Arial,sans-serif;color:#1F2C3F"><h2>Pax Shalom · lembrete de pagamento</h2><p><strong>${name}</strong>: ${amount}</p><p>${dueText}. Vencimento: ${service.next_due_date}.</p><p>Acesse o sistema e confirme a baixa quando o pagamento for realizado.</p></div>`
      try {
        const response = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { Authorization: `Bearer ${resendKey}`, 'Content-Type': 'application/json', 'Idempotency-Key': notification.id },
          body: JSON.stringify({ from, to: [email], subject, text: textBody, html: htmlBody }),
        })
        if (!response.ok) throw new Error(`Resend respondeu ${response.status}: ${(await response.text()).slice(0, 300)}`)
        await db.from('service_notifications').update({ status: 'sent', sent_at: new Date().toISOString(), last_error: null, updated_at: new Date().toISOString() })
          .eq('id', notification.id)
        results.sent++
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Falha desconhecida ao enviar e-mail.'
        await db.from('service_notifications').update({ status: 'failed', last_error: message.slice(0, 500), updated_at: new Date().toISOString() })
          .eq('id', notification.id)
        results.failed++
        console.error(JSON.stringify({ event: 'reminder_failed', service_id: service.id, date: today, message }))
      }
    }
  }
  return Response.json({ date: today, ...results }, { headers: cors })
})
