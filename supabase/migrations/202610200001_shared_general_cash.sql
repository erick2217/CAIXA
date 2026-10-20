-- Consolida as organizações atuais em um único caixa Pax Shalom.
-- Cada pessoa mantém o próprio usuário e os eventos de auditoria preservam o ator.
-- O usuário central recebe admin; os demais mantêm papéis operacionais explícitos
-- e contas que eram admin apenas da própria organização passam a operador.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.shared_cash_settings (
  singleton boolean primary key default true check (singleton),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  admin_user_id uuid not null references auth.users(id) on delete restrict,
  updated_at timestamptz not null default now()
);
revoke all on private.shared_cash_settings from public, anon, authenticated;

create table if not exists private.shared_cash_migration_backup_20261020 (
  table_name text not null,
  row_key text not null,
  original_organization_id uuid,
  row_data jsonb not null,
  archived_at timestamptz not null default now(),
  primary key (table_name, row_key)
);
revoke all on private.shared_cash_migration_backup_20261020 from public, anon, authenticated;

do $$
declare
  v_admin_id uuid;
  v_org_id uuid;
  v_table text;
  v_role text;
begin
  select id into v_admin_id
  from auth.users
  where lower(email) = lower('erick@paxshalom.com')
  order by created_at
  limit 1;

  if v_admin_id is null then
    raise exception 'Conta administradora erick@paxshalom.com não existe em Supabase Auth.';
  end if;

  select organization_id into v_org_id
  from public.organization_members
  where user_id = v_admin_id
  order by is_default desc, created_at, organization_id
  limit 1;

  if v_org_id is null then
    select id into v_org_id
    from public.organizations
    where legacy_owner_id = v_admin_id
    order by created_at, id
    limit 1;
  end if;

  if v_org_id is null then
    insert into public.organizations(name, legacy_owner_id, created_by)
    values ('Caixa Geral Pax Shalom', v_admin_id, v_admin_id)
    returning id into v_org_id;
  end if;

  -- Evita lançamentos simultâneos durante a troca de organização e o merge dos fechamentos.
  lock table public.organizations, public.organization_members,
    public.transactions, public.cash_closures, public.cobradores,
    public.collector_receipts, public.collector_cash_closures,
    public.funcionarios, public.payroll_movements,
    public.third_party_services, public.third_party_service_payments,
    public.audit_log, public.organization_invitations,
    public.service_notifications in access exclusive mode;

  -- Snapshot privado, idempotente e anterior a qualquer alteração.
  foreach v_table in array array[
    'organizations', 'organization_members', 'transactions', 'cash_closures',
    'cobradores', 'collector_receipts', 'collector_cash_closures',
    'funcionarios', 'payroll_movements', 'third_party_services',
    'third_party_service_payments', 'audit_log', 'organization_invitations',
    'service_notifications'
  ] loop
    execute format(
      'insert into private.shared_cash_migration_backup_20261020(table_name,row_key,original_organization_id,row_data) '
      'select %L, coalesce(to_jsonb(r)->>''id'', md5(to_jsonb(r)::text)), '
      'nullif(to_jsonb(r)->>''organization_id'','''')::uuid, to_jsonb(r) '
      'from public.%I r on conflict (table_name,row_key) do nothing',
      v_table, v_table
    );
  end loop;

  create temporary table _shared_cash_user_roles on commit drop as
  select u.id as user_id,
    case
      when u.id = v_admin_id then 'admin'
      when bool_or(m.role = 'financeiro') then 'financeiro'
      when bool_or(m.role = 'operador') then 'operador'
      when bool_or(m.role = 'leitura') then 'leitura'
      else 'operador'
    end as role
  from auth.users u
  left join public.organization_members m on m.user_id = u.id
  group by u.id;

  -- Desliga apenas triggers de aplicação/auditoria enquanto os dados são movidos.
  foreach v_table in array array[
    'transactions', 'cash_closures', 'cobradores', 'collector_receipts',
    'collector_cash_closures', 'funcionarios', 'payroll_movements',
    'third_party_services', 'third_party_service_payments'
  ] loop
    execute format('alter table public.%I disable trigger user', v_table);
  end loop;

  -- Uma linha diária por organização: consolida os saldos paralelos e arquiva
  -- integralmente as linhas originais no schema privado acima.
  create temporary table _shared_cash_closures on commit drop as
  select close_date,
    (array_agg(id order by (organization_id = v_org_id) desc, closed_at, id))[1] as keeper_id,
    sum(opening_balance)::numeric(12,2) as opening_balance,
    sum(income_total)::numeric(12,2) as income_total,
    sum(expense_total)::numeric(12,2) as expense_total,
    sum(expected_balance)::numeric(12,2) as expected_balance,
    sum(counted_balance)::numeric(12,2) as counted_balance,
    sum(difference)::numeric(12,2) as difference,
    max(closed_at) as closed_at,
    bool_and(is_closed) as is_closed,
    max(reopened_at) as reopened_at,
    (array_agg(reopened_by order by reopened_at desc nulls last)
      filter (where reopened_by is not null))[1] as reopened_by,
    string_agg(distinct reopen_reason, E'\n') filter (where reopen_reason is not null) as reopen_reason
  from public.cash_closures
  group by close_date;

  -- Remove duplicate user/date rows before assigning the keeper to the admin,
  -- because the legacy user/date unique constraint is still present.
  delete from public.cash_closures c
  using _shared_cash_closures r
  where c.close_date = r.close_date and c.id <> r.keeper_id;

  update public.cash_closures c set
    user_id = v_admin_id,
    opening_balance = r.opening_balance,
    income_total = r.income_total,
    expense_total = r.expense_total,
    expected_balance = r.expected_balance,
    counted_balance = r.counted_balance,
    difference = r.difference,
    closed_at = r.closed_at,
    is_closed = r.is_closed,
    reopened_at = r.reopened_at,
    reopened_by = r.reopened_by,
    reopen_reason = r.reopen_reason
  from _shared_cash_closures r
  where c.id = r.keeper_id;

  create temporary table _shared_collector_closures on commit drop as
  select close_date,
    (array_agg(id order by (organization_id = v_org_id) desc, closed_at, id))[1] as keeper_id,
    sum(total_amount)::numeric(12,2) as total_amount,
    max(closed_at) as closed_at,
    bool_and(is_closed) as is_closed,
    max(reopened_at) as reopened_at,
    (array_agg(reopened_by order by reopened_at desc nulls last)
      filter (where reopened_by is not null))[1] as reopened_by,
    string_agg(distinct reopen_reason, E'\n') filter (where reopen_reason is not null) as reopen_reason
  from public.collector_cash_closures
  group by close_date;

  create temporary table _shared_collector_closure_map on commit drop as
  select c.id as source_id, r.keeper_id, c.close_date
  from public.collector_cash_closures c
  join _shared_collector_closures r using (close_date);

  delete from public.collector_cash_closures c
  using _shared_collector_closures r
  where c.close_date = r.close_date and c.id <> r.keeper_id;

  update public.collector_cash_closures c set
    user_id = v_admin_id,
    total_amount = r.total_amount,
    closed_at = r.closed_at,
    is_closed = r.is_closed,
    reopened_at = r.reopened_at,
    reopened_by = r.reopened_by,
    reopen_reason = r.reopen_reason
  from _shared_collector_closures r
  where c.id = r.keeper_id;

  -- Cada fechamento agregado de cobradores conserva um único lançamento ativo;
  -- cópias redundantes ficam anuladas e os originais permanecem no backup privado.
  create temporary table _shared_collector_transactions on commit drop as
  select m.close_date,
    m.keeper_id as keeper_closure_id,
    (array_agg(t.id order by (t.is_voided_at is null) desc,
      (t.collector_cash_closure_id = m.keeper_id) desc, t.created_at, t.id))[1] as keeper_transaction_id,
    coalesce(sum(t.amount) filter (where t.is_voided_at is null), 0)::numeric(12,2) as active_amount,
    bool_or(t.is_voided_at is null) as has_active_transaction
  from _shared_collector_closure_map m
  join public.transactions t on t.collector_cash_closure_id = m.source_id
  group by m.close_date, m.keeper_id;

  update public.transactions t set
    collector_cash_closure_id = null,
    is_voided_at = coalesce(t.is_voided_at, now()),
    void_reason = coalesce(t.void_reason, 'Lançamento duplicado consolidado no caixa geral; original arquivado.')
  from _shared_collector_closure_map m
  join _shared_collector_transactions r using (close_date)
  where t.collector_cash_closure_id = m.source_id
    and t.id <> r.keeper_transaction_id;

  update public.transactions t set
    collector_cash_closure_id = r.keeper_closure_id,
    amount = case when r.has_active_transaction then r.active_amount else t.amount end,
    user_id = v_admin_id,
    is_voided_at = case when r.has_active_transaction then null else t.is_voided_at end,
    void_reason = case when r.has_active_transaction then null else t.void_reason end
  from _shared_collector_transactions r
  where t.id = r.keeper_transaction_id;

  -- O caixa geral passa a conter todos os lançamentos, funcionários, serviços,
  -- convites, lembretes e trilhas de auditoria de todos os usuários cadastrados.
  update public.transactions set organization_id = v_org_id;
  update public.cash_closures set organization_id = v_org_id;
  update public.cobradores set organization_id = v_org_id;
  update public.collector_receipts set organization_id = v_org_id;
  update public.collector_cash_closures set organization_id = v_org_id;
  update public.funcionarios set organization_id = v_org_id;
  update public.payroll_movements set organization_id = v_org_id;
  update public.third_party_services set organization_id = v_org_id;
  update public.third_party_service_payments set organization_id = v_org_id;
  update public.audit_log set organization_id = v_org_id;
  update public.organization_invitations set organization_id = v_org_id;
  update public.service_notifications set organization_id = v_org_id;

  update public.organizations set legacy_owner_id = null where id <> v_org_id;
  update public.organizations
  set name = 'Caixa Geral Pax Shalom', legacy_owner_id = v_admin_id
  where id = v_org_id;

  delete from public.organization_members;
  insert into public.organization_members(organization_id, user_id, role, is_default)
  select v_org_id, user_id, role, true from _shared_cash_user_roles;

  insert into private.shared_cash_settings(singleton, organization_id, admin_user_id)
  values (true, v_org_id, v_admin_id)
  on conflict (singleton) do update set
    organization_id = excluded.organization_id,
    admin_user_id = excluded.admin_user_id,
    updated_at = now();

  foreach v_table in array array[
    'transactions', 'cash_closures', 'cobradores', 'collector_receipts',
    'collector_cash_closures', 'funcionarios', 'payroll_movements',
    'third_party_services', 'third_party_service_payments'
  ] loop
    execute format('alter table public.%I enable trigger user', v_table);
  end loop;
end $$;

-- New accounts can enter the shared cash only through a valid administrator invitation.
create or replace function public.create_initial_organization_for_user()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,private,auth as $$
declare
  v_invite public.organization_invitations;
  v_org uuid;
  v_invite_id uuid;
begin
  select organization_id into v_org
  from private.shared_cash_settings where singleton;
  if v_org is null then raise exception 'Caixa geral ainda não foi configurado.'; end if;

  begin
    v_invite_id := (new.raw_user_meta_data->>'organization_invitation_id')::uuid;
  exception when others then
    v_invite_id := null;
  end;

  if v_invite_id is not null then
    select * into v_invite
    from public.organization_invitations
    where id = v_invite_id
      and organization_id = v_org
      and lower(email) = lower(new.email)
      and status = 'pending'
      and expires_at > now()
    for update;
  end if;

  if v_invite.id is null then
    raise exception 'A criação de conta exige um convite válido para o caixa geral.';
  end if;

  insert into public.organization_members(organization_id, user_id, role, is_default)
  values (v_org, new.id, v_invite.role, true);
  update public.organization_invitations
  set status = 'accepted', accepted_at = now()
  where id = v_invite.id;
  return new;
end; $$;
revoke all on function public.create_initial_organization_for_user() from public, anon, authenticated;
