import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.57.0'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const allowedRoles = new Set(['admin', 'financeiro', 'operador', 'leitura'])

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (request.method !== 'POST') return Response.json({ error: 'Método não permitido.' }, { status: 405, headers: cors })
  const url = Deno.env.get('SUPABASE_URL')
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!url || !anonKey || !serviceKey) return Response.json({ error: 'Secrets Supabase ausentes.' }, { status: 500, headers: cors })

  const authorization = request.headers.get('Authorization')
  if (!authorization) return Response.json({ error: 'Sessão autenticada obrigatória.' }, { status: 401, headers: cors })
  const caller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } })
  const { data: authData, error: authError } = await caller.auth.getUser()
  if (authError || !authData.user) return Response.json({ error: 'Sessão inválida ou expirada.' }, { status: 401, headers: cors })

  let body: { email?: string; role?: string }
  try { body = await request.json() } catch { return Response.json({ error: 'Corpo da solicitação inválido.' }, { status: 400, headers: cors }) }
  const email = body.email?.trim().toLowerCase()
  const role = body.role || 'operador'
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !allowedRoles.has(role)) {
    return Response.json({ error: 'Informe um e-mail válido e uma permissão permitida.' }, { status: 400, headers: cors })
  }

  const { data: organizations, error: orgError } = await caller.rpc('get_my_organizations')
  if (orgError) return Response.json({ error: orgError.message }, { status: 400, headers: cors })
  const current = (organizations || []).find((org: { is_default: boolean }) => org.is_default)
  if (!current || current.role !== 'admin') return Response.json({ error: 'Somente um administrador pode convidar membros.' }, { status: 403, headers: cors })

  const existing = await caller.rpc('add_existing_organization_member', { p_email: email, p_role: role })
  if (!existing.error) return Response.json({ message: 'Conta existente adicionada à organização.', invited: false }, { headers: cors })
  if (!existing.error.message.includes('ainda não possui uma conta')) {
    return Response.json({ error: existing.error.message }, { status: 400, headers: cors })
  }

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const invitationId = crypto.randomUUID()
  const { error: insertError } = await admin.from('organization_invitations').insert({
    id: invitationId,
    organization_id: current.id,
    email,
    role,
    invited_by: authData.user.id,
  })
  if (insertError) return Response.json({ error: insertError.message }, { status: 500, headers: cors })

  const redirectTo = Deno.env.get('APP_BASE_URL')
  const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    data: { organization_invitation_id: invitationId },
    ...(redirectTo ? { redirectTo } : {}),
  })
  if (inviteError) {
    const { data: invitation } = await admin.from('organization_invitations').select('status').eq('id', invitationId).maybeSingle()
    console.error(JSON.stringify({ event: 'organization_invite_email_failed', invitation_id: invitationId, status: invitation?.status || 'pending' }))
    return Response.json({ error: `Convite preparado, mas o Supabase Auth não confirmou o envio do e-mail: ${inviteError.message}` }, { status: 502, headers: cors })
  }
  return Response.json({ message: 'Convite enviado. O acesso será ativado quando a pessoa aceitar.', invited: true }, { headers: cors })
})
