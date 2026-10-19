-- PAXSHALOM: movimentacoes e fechamento diario. Execute no SQL Editor do Supabase.
create table if not exists public.transactions (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, description text not null, amount numeric(12,2) not null check(amount>0), type text not null check(type in('income','expense')), category text not null default 'Outros', transaction_date date not null default current_date, created_at timestamptz not null default now());
alter table public.transactions enable row level security;
drop policy if exists "Users can view their transactions" on public.transactions;
drop policy if exists "Users can create their transactions" on public.transactions;
drop policy if exists "Users can update their transactions" on public.transactions;
drop policy if exists "Users can delete their transactions" on public.transactions;
create policy "Users can view their transactions" on public.transactions for select using(auth.uid()=user_id);
create policy "Users can create their transactions" on public.transactions for insert with check(auth.uid()=user_id);
create policy "Users can update their transactions" on public.transactions for update using(auth.uid()=user_id) with check(auth.uid()=user_id);
create policy "Users can delete their transactions" on public.transactions for delete using(auth.uid()=user_id);
create index if not exists transactions_user_date_idx on public.transactions(user_id,transaction_date desc);
create table if not exists public.cash_closures (id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade, close_date date not null, opening_balance numeric(12,2) not null check(opening_balance>=0), income_total numeric(12,2) not null, expense_total numeric(12,2) not null, expected_balance numeric(12,2) not null, counted_balance numeric(12,2) not null check(counted_balance>=0), difference numeric(12,2) not null, closed_at timestamptz not null default now(), unique(user_id,close_date));
alter table public.cash_closures enable row level security;
drop policy if exists "Users can view their cash closures" on public.cash_closures;
create policy "Users can view their cash closures" on public.cash_closures for select using(auth.uid()=user_id);
create or replace function public.guard_closed_cash_day() returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_date date;
begin
 if tg_op='DELETE' then v_user:=old.user_id; v_date:=old.transaction_date; else v_user:=new.user_id; v_date:=new.transaction_date; end if;
 if tg_op='UPDATE' and (new.user_id<>old.user_id or new.transaction_date<>old.transaction_date) then raise exception 'Nao e permitido mover uma movimentacao entre dias.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':'||v_date::text,0));
 if exists(select 1 from public.cash_closures c where c.user_id=v_user and c.close_date=v_date) then raise exception 'O caixa deste dia ja foi fechado.'; end if;
 if tg_op='DELETE' then return old; end if; return new;
end; $$;
drop trigger if exists transactions_guard_closed_day on public.transactions;
create trigger transactions_guard_closed_day before insert or update or delete on public.transactions for each row execute function public.guard_closed_cash_day();
-- Cobradores: valores diarios e fechamento por usuario/data.
create table if not exists public.cobradores (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 120), active boolean not null default true,
 created_at timestamptz not null default now(), unique(id,user_id)
);
create table if not exists public.collector_receipts (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 collector_id uuid not null, receipt_date date not null, amount numeric(12,2) not null check(amount>=0),
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(user_id,collector_id,receipt_date),
 foreign key(collector_id,user_id) references public.cobradores(id,user_id) on delete restrict
);
create table if not exists public.collector_cash_closures (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 close_date date not null, total_amount numeric(12,2) not null, closed_at timestamptz not null default now(),
 unique(user_id,close_date)
);
alter table public.cobradores enable row level security;
alter table public.collector_receipts enable row level security;
alter table public.collector_cash_closures enable row level security;
drop policy if exists "Users manage their collectors" on public.cobradores;
create policy "Users manage their collectors" on public.cobradores for all using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "Users manage their collector receipts" on public.collector_receipts;
create policy "Users manage their collector receipts" on public.collector_receipts for all using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "Users view their collector closures" on public.collector_cash_closures;
create policy "Users view their collector closures" on public.collector_cash_closures for select using(auth.uid()=user_id);

create or replace function public.guard_collector_cash_day() returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_date date;
begin
 if tg_op='DELETE' then v_user:=old.user_id; v_date:=old.receipt_date; else v_user:=new.user_id; v_date:=new.receipt_date; end if;
 if tg_op='UPDATE' and (new.user_id<>old.user_id or new.receipt_date<>old.receipt_date or new.collector_id<>old.collector_id) then raise exception 'Nao e permitido mover uma entrega registrada para outro cobrador ou dia.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':collector:'||v_date::text,0));
 if exists(select 1 from public.collector_cash_closures c where c.user_id=v_user and c.close_date=v_date) then raise exception 'O caixa dos cobradores deste dia ja foi fechado.'; end if;
 if tg_op='DELETE' then return old; end if;
 new.updated_at:=now(); return new;
end; $$;
drop trigger if exists collector_receipts_guard_closed_day on public.collector_receipts;
create trigger collector_receipts_guard_closed_day before insert or update or delete on public.collector_receipts for each row execute function public.guard_collector_cash_day();

-- RH: adiantamentos e pagamentos registrados tambem no caixa principal.
create table if not exists public.funcionarios (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 120), salary numeric(12,2) not null check(salary>=0),
 active boolean not null default true, created_at timestamptz not null default now(), unique(id,user_id)
);
create table if not exists public.payroll_movements (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 employee_id uuid not null, movement_type text not null check(movement_type in('advance','salary_payment')),
 period_month date not null check(extract(day from period_month)=1), amount numeric(12,2) not null check(amount>0),
 payment_date date not null default current_date, notes text, created_at timestamptz not null default now(),
 foreign key(employee_id,user_id) references public.funcionarios(id,user_id) on delete restrict
);
create unique index if not exists payroll_one_salary_per_month on public.payroll_movements(user_id,employee_id,period_month) where movement_type='salary_payment';
alter table public.funcionarios enable row level security;
alter table public.payroll_movements enable row level security;
drop policy if exists "Users manage their employees" on public.funcionarios;
create policy "Users manage their employees" on public.funcionarios for all using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "Users view their payroll movements" on public.payroll_movements;
create policy "Users view their payroll movements" on public.payroll_movements for select using(auth.uid()=user_id);

-- RH fica fora do caixa geral; mantenha apenas o registro na folha.
-- Servicos terceirizados com vencimento mensal e lembrete ate a baixa.
create table if not exists public.third_party_services (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check(length(trim(name)) between 1 and 140), fixed_amount numeric(12,2) not null check(fixed_amount>0),
 due_day smallint not null check(due_day between 1 and 31), next_due_date date not null,
 reminder_days smallint not null default 7 check(reminder_days between 0 and 60), active boolean not null default true,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(id,user_id)
);
create table if not exists public.third_party_service_payments (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 service_id uuid not null, due_date date not null, paid_date date not null default current_date,
 amount numeric(12,2) not null check(amount>0), transaction_id uuid not null unique references public.transactions(id) on delete restrict,
 created_at timestamptz not null default now(), unique(user_id,service_id,due_date),
 foreign key(service_id,user_id) references public.third_party_services(id,user_id) on delete restrict
);
alter table public.third_party_services enable row level security;
alter table public.third_party_service_payments enable row level security;
drop policy if exists "Users manage their third party services" on public.third_party_services;
create policy "Users manage their third party services" on public.third_party_services for all using(auth.uid()=user_id) with check(auth.uid()=user_id);
drop policy if exists "Users view their third party service payments" on public.third_party_service_payments;
create policy "Users view their third party service payments" on public.third_party_service_payments for select using(auth.uid()=user_id);

-- Definições canônicas versionadas na Fase 1.
-- Fase 1: extensões aditivas para integridade financeira.
-- Executável sobre o schema atual; não remove tabelas nem dados.

alter table public.payroll_movements add column if not exists idempotency_key uuid;
create unique index if not exists payroll_movements_user_idempotency_uidx
  on public.payroll_movements(user_id, idempotency_key) where idempotency_key is not null;

create or replace function public.close_collectors_cash(p_close_date date)
returns public.collector_cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid; v_total numeric(12,2); v_result public.collector_cash_closures; v_missing text;
begin
  v_user:=auth.uid();
  if v_user is null then raise exception 'Entre na sua conta para fechar os cobradores.'; end if;
  if p_close_date is null or p_close_date>current_date then raise exception 'Informe uma data válida, que não seja futura.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_user::text||':collector:'||p_close_date::text,0));
  select * into v_result from public.collector_cash_closures where user_id=v_user and close_date=p_close_date;
  if found then return v_result; end if;
  select string_agg(c.name,', ' order by c.name) into v_missing from public.cobradores c
  where c.user_id=v_user and c.active and not exists (
    select 1 from public.collector_receipts r where r.user_id=v_user and r.collector_id=c.id and r.receipt_date=p_close_date
  );
  if v_missing is not null then
    raise exception 'Registre o valor de cada cobrador (use R$ 0,00 quando não houve entrega) antes de fechar: %',v_missing;
  end if;
  select coalesce(sum(amount),0)::numeric(12,2) into v_total from public.collector_receipts
  where user_id=v_user and receipt_date=p_close_date;
  insert into public.collector_cash_closures(user_id,close_date,total_amount)
  values(v_user,p_close_date,v_total) returning * into v_result;
  insert into public.transactions(user_id,description,amount,type,category,transaction_date)
  select v_user,'Arrecadação dos cobradores',v_total,'income','Cobradores',p_close_date where v_total>0;
  return v_result;
end; $$;
revoke all on function public.close_collectors_cash(date) from public;
grant execute on function public.close_collectors_cash(date) to authenticated;

create or replace function public._close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_income numeric(12,2); v_expense numeric(12,2); v_result public.cash_closures;
begin
  if v_user is null then raise exception 'Entre na sua conta para fechar o caixa.'; end if;
  select coalesce(sum(amount) filter(where type='income'),0)::numeric(12,2),
    coalesce(sum(amount) filter(where type='expense' and category<>'RH'),0)::numeric(12,2)
  into v_income,v_expense from public.transactions where user_id=v_user and transaction_date=p_close_date;
  insert into public.cash_closures(user_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference)
  values(v_user,p_close_date,p_opening_balance,v_income,v_expense,p_opening_balance+v_income-v_expense,
    p_counted_balance,p_counted_balance-(p_opening_balance+v_income-v_expense)) returning * into v_result;
  return v_result;
end; $$;
revoke all on function public._close_daily_cash(date,numeric,numeric) from public,anon,authenticated;

create or replace function public.close_day(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_result public.cash_closures; v_collector_close public.collector_cash_closures;
begin
  if v_user is null then raise exception 'Entre na sua conta para fechar o dia.'; end if;
  if p_close_date is null or p_close_date>current_date then raise exception 'A data do fechamento não pode ser futura.'; end if;
  if p_opening_balance is null or p_counted_balance is null or p_opening_balance<0 or p_counted_balance<0 then
    raise exception 'Os saldos devem ser informados e não podem ser negativos.';
  end if;
  -- Locks sempre na ordem cobradores -> caixa para evitar deadlock.
  perform pg_advisory_xact_lock(hashtextextended(v_user::text||':collector:'||p_close_date::text,0));
  perform pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_close_date::text,0));
  select * into v_result from public.cash_closures where user_id=v_user and close_date=p_close_date;
  if found then
    if v_result.opening_balance<>p_opening_balance or v_result.counted_balance<>p_counted_balance then
      raise exception 'Este dia já foi fechado com outros valores. Consulte o fechamento existente.';
    end if;
    return v_result;
  end if;
  v_collector_close:=public.close_collectors_cash(p_close_date);
  return public._close_daily_cash(p_close_date,p_opening_balance,p_counted_balance);
end; $$;
revoke all on function public.close_day(date,numeric,numeric) from public;
grant execute on function public.close_day(date,numeric,numeric) to authenticated;

-- Compatibilidade com clientes existentes: delega para o fechamento atômico.
create or replace function public.close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
begin return public.close_day(p_close_date,p_opening_balance,p_counted_balance); end; $$;
revoke all on function public.close_daily_cash(date,numeric,numeric) from public;
grant execute on function public.close_daily_cash(date,numeric,numeric) to authenticated;

-- A chave é fornecida pela interface e reutilizada em retries da mesma operação.
create or replace function public.register_payroll_movement(
  p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text,p_idempotency_key uuid
) returns public.payroll_movements language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_salary numeric(12,2); v_advances numeric(12,2); v_expected numeric(12,2);
  v_result public.payroll_movements; v_employee_name text;
begin
  if v_user is null then raise exception 'Entre na sua conta para registrar a folha.'; end if;
  if p_idempotency_key is null then raise exception 'Chave de solicitação obrigatória. Atualize a aplicação.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'O valor deve ser maior que zero.'; end if;
  if p_payment_date is null or p_payment_date>current_date then raise exception 'A data de pagamento não pode ser futura.'; end if;
  if p_period_month is null or extract(day from p_period_month)<>1 then raise exception 'O mês deve usar o primeiro dia.'; end if;
  if p_type not in('advance','salary_payment') then raise exception 'Tipo de movimentação inválido.'; end if;
  select salary,name into v_salary,v_employee_name from public.funcionarios
  where id=p_employee_id and user_id=v_user and active for update;
  if not found then raise exception 'Funcionário não encontrado ou inativo.'; end if;
  select * into v_result from public.payroll_movements where user_id=v_user and idempotency_key=p_idempotency_key;
  if found then
    if v_result.employee_id<>p_employee_id or v_result.movement_type<>p_type or v_result.amount<>p_amount
      or v_result.period_month<>p_period_month or v_result.payment_date<>p_payment_date then
      raise exception 'A chave de solicitação já foi usada com outros dados.';
    end if;
    return v_result;
  end if;
  if p_type='advance' then
    if exists(select 1 from public.payroll_movements where employee_id=p_employee_id and user_id=v_user
      and period_month=p_period_month and movement_type='salary_payment') then
      raise exception 'A folha deste funcionário já foi paga neste mês.';
    end if;
    select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id
      and user_id=v_user and period_month=p_period_month and movement_type='advance';
    if v_advances+p_amount>v_salary then raise exception 'O total de adiantamentos excede o salário fixo.'; end if;
  else
    select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id
      and user_id=v_user and period_month=p_period_month and movement_type='advance';
    v_expected:=v_salary-v_advances;
    if v_expected<=0 then raise exception 'Não há saldo líquido a pagar neste mês.'; end if;
    if p_amount<>v_expected then raise exception 'O pagamento deve corresponder ao líquido calculado: %',v_expected; end if;
  end if;
  insert into public.payroll_movements(user_id,employee_id,movement_type,period_month,amount,payment_date,notes,idempotency_key)
  values(v_user,p_employee_id,p_type,p_period_month,p_amount,p_payment_date,p_notes,p_idempotency_key) returning * into v_result;
  -- Não criar transação: RH é contabilizado fora do caixa geral.
  return v_result;
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text,uuid) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text,uuid) to authenticated;

-- Assinatura legada continua disponível para clientes antigos; a chave estável torna retries seguros.
create or replace function public.register_payroll_movement(
  p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text default null
) returns public.payroll_movements
language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_key uuid;
begin
  if v_user is null then raise exception 'Entre na sua conta para registrar a folha.'; end if;
  v_key:=md5(concat_ws('|',v_user::text,p_employee_id::text,p_type,p_amount::text,
    p_period_month::text,p_payment_date::text,coalesce(p_notes,'')))::uuid;
  return public.register_payroll_movement(p_employee_id,p_type,p_amount,p_period_month,p_payment_date,p_notes,v_key);
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text) to authenticated;

-- p_due_date identifica o vencimento original, mesmo se a resposta anterior se perdeu.
drop function if exists public.pay_third_party_service(uuid,date);
create or replace function public.pay_third_party_service(p_service_id uuid,p_paid_date date,p_due_date date)
returns public.third_party_service_payments language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_service public.third_party_services; v_transaction_id uuid;
  v_payment public.third_party_service_payments; v_target_due date; v_next_month date; v_last_day integer; v_next_due date;
begin
  if v_user is null then raise exception 'Entre na sua conta para registrar o pagamento.'; end if;
  if p_paid_date is null or p_paid_date>current_date then raise exception 'A data de pagamento não pode ser futura.'; end if;
  select * into v_service from public.third_party_services where id=p_service_id and user_id=v_user and active for update;
  if not found then raise exception 'Serviço não encontrado ou inativo.'; end if;
  v_target_due:=coalesce(p_due_date,v_service.next_due_date);
  select * into v_payment from public.third_party_service_payments
  where user_id=v_user and service_id=p_service_id and due_date=v_target_due;
  if found then return v_payment; end if;
  if v_target_due<>v_service.next_due_date then raise exception 'O vencimento mudou. Atualize a tela antes de confirmar.'; end if;
  insert into public.transactions(user_id,description,amount,type,category,transaction_date)
  values(v_user,'Serviço terceirizado - '||v_service.name,v_service.fixed_amount,'expense','Serviços terceirizados',p_paid_date)
  returning id into v_transaction_id;
  insert into public.third_party_service_payments(user_id,service_id,due_date,paid_date,amount,transaction_id)
  values(v_user,v_service.id,v_target_due,p_paid_date,v_service.fixed_amount,v_transaction_id) returning * into v_payment;
  v_next_month:=date_trunc('month',v_target_due+interval '1 month')::date;
  v_last_day:=extract(day from (v_next_month+interval '1 month'-interval '1 day'))::integer;
  v_next_due:=v_next_month+(least(v_service.due_day,v_last_day)-1);
  update public.third_party_services set next_due_date=v_next_due,updated_at=now()
  where id=v_service.id and user_id=v_user;
  return v_payment;
end; $$;
revoke all on function public.pay_third_party_service(uuid,date,date) from public;
grant execute on function public.pay_third_party_service(uuid,date,date) to authenticated;

-- Compatibilidade da chamada antiga: registra a competência vigente e é idempotente por data.
create function public.pay_third_party_service(p_service_id uuid,p_paid_date date default current_date)
returns public.third_party_service_payments
language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_due date; v_payment public.third_party_service_payments;
begin
  if v_user is null then raise exception 'Entre na sua conta para registrar o pagamento.'; end if;
  select * into v_payment from public.third_party_service_payments
  where user_id=v_user and service_id=p_service_id and paid_date=p_paid_date
  order by created_at desc limit 1;
  if found then return v_payment; end if;
  select next_due_date into v_due from public.third_party_services
  where id=p_service_id and user_id=v_user and active;
  if not found then raise exception 'Serviço não encontrado ou inativo.'; end if;
  return public.pay_third_party_service(p_service_id,p_paid_date,v_due);
end; $$;
revoke all on function public.pay_third_party_service(uuid,date) from public;
grant execute on function public.pay_third_party_service(uuid,date) to authenticated;

-- Fase 2: organizações, RLS por papel, auditoria e reabertura administrativa.
-- Fase 2: tenancy por organização, roles e auditoria. Adiciona organization_id;
-- user_id e os dados originais permanecem para rollback/compatibilidade.

create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null check(length(trim(name)) between 1 and 160),
  legacy_owner_id uuid unique references auth.users(id) on delete restrict,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);
create table if not exists public.organization_members (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check(role in ('admin','financeiro','operador','leitura')),
  is_default boolean not null default false,
  created_at timestamptz not null default now(),
  unique(organization_id,user_id)
);
create unique index if not exists organization_members_one_default_idx
  on public.organization_members(user_id) where is_default;
alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

-- Snapshot dos dados antes do backfill. Schema privado, sem grants para clientes.
create table if not exists private.upgrade_backup_manifest(name text primary key,created_at timestamptz not null default now());
create table if not exists private.transactions_backup_20261019 as select * from public.transactions where false;
create table if not exists private.cash_closures_backup_20261019 as select * from public.cash_closures where false;
create table if not exists private.cobradores_backup_20261019 as select * from public.cobradores where false;
create table if not exists private.collector_receipts_backup_20261019 as select * from public.collector_receipts where false;
create table if not exists private.collector_cash_closures_backup_20261019 as select * from public.collector_cash_closures where false;
create table if not exists private.funcionarios_backup_20261019 as select * from public.funcionarios where false;
create table if not exists private.payroll_movements_backup_20261019 as select * from public.payroll_movements where false;
create table if not exists private.third_party_services_backup_20261019 as select * from public.third_party_services where false;
create table if not exists private.third_party_service_payments_backup_20261019 as select * from public.third_party_service_payments where false;
do $$ begin
  if not exists(select 1 from private.upgrade_backup_manifest where name='phase2_pre_org_backfill_20261019') then
    insert into private.transactions_backup_20261019(id,user_id,description,amount,type,category,transaction_date,created_at)
      select id,user_id,description,amount,type,category,transaction_date,created_at from public.transactions on conflict do nothing;
    insert into private.cash_closures_backup_20261019(id,user_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference,closed_at)
      select id,user_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference,closed_at from public.cash_closures on conflict do nothing;
    insert into private.cobradores_backup_20261019(id,user_id,name,active,created_at)
      select id,user_id,name,active,created_at from public.cobradores on conflict do nothing;
    insert into private.collector_receipts_backup_20261019(id,user_id,collector_id,receipt_date,amount,notes,created_at,updated_at)
      select id,user_id,collector_id,receipt_date,amount,notes,created_at,updated_at from public.collector_receipts on conflict do nothing;
    insert into private.collector_cash_closures_backup_20261019(id,user_id,close_date,total_amount,closed_at)
      select id,user_id,close_date,total_amount,closed_at from public.collector_cash_closures on conflict do nothing;
    insert into private.funcionarios_backup_20261019(id,user_id,name,salary,active,created_at)
      select id,user_id,name,salary,active,created_at from public.funcionarios on conflict do nothing;
    insert into private.payroll_movements_backup_20261019(id,user_id,employee_id,movement_type,period_month,amount,payment_date,notes,created_at,idempotency_key)
      select id,user_id,employee_id,movement_type,period_month,amount,payment_date,notes,created_at,idempotency_key from public.payroll_movements on conflict do nothing;
    insert into private.third_party_services_backup_20261019(id,user_id,name,fixed_amount,due_day,next_due_date,reminder_days,active,created_at,updated_at)
      select id,user_id,name,fixed_amount,due_day,next_due_date,reminder_days,active,created_at,updated_at from public.third_party_services on conflict do nothing;
    insert into private.third_party_service_payments_backup_20261019(id,user_id,service_id,due_date,paid_date,amount,transaction_id,created_at)
      select id,user_id,service_id,due_date,paid_date,amount,transaction_id,created_at from public.third_party_service_payments on conflict do nothing;
    insert into private.upgrade_backup_manifest(name) values('phase2_pre_org_backfill_20261019');
  end if;
end $$;
revoke all on all tables in schema private from public,anon,authenticated;

alter table public.transactions add column if not exists is_voided_at timestamptz;
alter table public.transactions add column if not exists void_reason text;
alter table public.transactions add column if not exists collector_cash_closure_id uuid
  references public.collector_cash_closures(id) on delete restrict;
create unique index if not exists transactions_collector_closure_uidx
  on public.transactions(collector_cash_closure_id) where collector_cash_closure_id is not null;
alter table public.cash_closures add column if not exists is_closed boolean not null default true;
alter table public.cash_closures add column if not exists reopened_at timestamptz;
alter table public.cash_closures add column if not exists reopened_by uuid references auth.users(id) on delete set null;
alter table public.cash_closures add column if not exists reopen_reason text;
alter table public.collector_cash_closures add column if not exists is_closed boolean not null default true;
alter table public.collector_cash_closures add column if not exists reopened_at timestamptz;
alter table public.collector_cash_closures add column if not exists reopened_by uuid references auth.users(id) on delete set null;
alter table public.collector_cash_closures add column if not exists reopen_reason text;

insert into public.organizations(name,legacy_owner_id,created_by)
select 'Pax Shalom',u.id,u.id from auth.users u
on conflict(legacy_owner_id) do nothing;
insert into public.organization_members(organization_id,user_id,role,is_default)
select o.id,o.legacy_owner_id,'admin',true from public.organizations o
where o.legacy_owner_id is not null
on conflict(organization_id,user_id) do nothing;

alter table public.transactions add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.cash_closures add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.cobradores add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.collector_receipts add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.collector_cash_closures add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.funcionarios add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.payroll_movements add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.third_party_services add column if not exists organization_id uuid references public.organizations(id) on delete restrict;
alter table public.third_party_service_payments add column if not exists organization_id uuid references public.organizations(id) on delete restrict;

update public.transactions t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.cash_closures t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.cobradores t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.collector_receipts t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.collector_cash_closures t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.funcionarios t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.payroll_movements t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.third_party_services t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;
update public.third_party_service_payments t set organization_id=o.id from public.organizations o where t.organization_id is null and t.user_id=o.legacy_owner_id;

-- Faz vínculo automático somente quando o fechamento antigo possui uma única entrada agregada inequívoca.
with candidates as (
  select c.id as closure_id,t.id as transaction_id,
    count(*) over(partition by c.id) as matches
  from public.collector_cash_closures c
  join public.transactions t on t.user_id=c.user_id and t.transaction_date=c.close_date
    and t.amount=c.total_amount and t.type='income' and t.category='Cobradores'
    and t.description='Arrecadação dos cobradores' and t.collector_cash_closure_id is null
  where c.total_amount>0
)
update public.transactions t set collector_cash_closure_id=candidates.closure_id
from candidates where candidates.matches=1 and t.id=candidates.transaction_id;

alter table public.transactions alter column organization_id set not null;
alter table public.cash_closures alter column organization_id set not null;
alter table public.cobradores alter column organization_id set not null;
alter table public.collector_receipts alter column organization_id set not null;
alter table public.collector_cash_closures alter column organization_id set not null;
alter table public.funcionarios alter column organization_id set not null;
alter table public.payroll_movements alter column organization_id set not null;
alter table public.third_party_services alter column organization_id set not null;
alter table public.third_party_service_payments alter column organization_id set not null;

create index if not exists transactions_org_date_idx on public.transactions(organization_id,transaction_date desc);
create index if not exists collector_receipts_org_date_idx on public.collector_receipts(organization_id,receipt_date desc);
create index if not exists payroll_movements_org_month_idx on public.payroll_movements(organization_id,period_month desc);
create index if not exists third_party_services_org_due_idx on public.third_party_services(organization_id,next_due_date);
create unique index if not exists cash_closures_org_date_uidx on public.cash_closures(organization_id,close_date);
create unique index if not exists collector_closures_org_date_uidx on public.collector_cash_closures(organization_id,close_date);
create unique index if not exists payroll_movements_org_idempotency_uidx
  on public.payroll_movements(organization_id,idempotency_key) where idempotency_key is not null;

create or replace function public.current_organization_id()
returns uuid language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select organization_id from public.organization_members
  where user_id=auth.uid() and is_default limit 1
$$;
revoke all on function public.current_organization_id() from public,anon;
grant execute on function public.current_organization_id() to authenticated;

create or replace function public.has_org_role(p_organization_id uuid,p_roles text[])
returns boolean language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select exists(select 1 from public.organization_members m
    where m.organization_id=p_organization_id and m.user_id=auth.uid() and m.role=any(p_roles))
$$;
revoke all on function public.has_org_role(uuid,text[]) from public,anon;
grant execute on function public.has_org_role(uuid,text[]) to authenticated;

create or replace function public.get_my_organizations()
returns table(id uuid,name text,role text,is_default boolean)
language sql stable security definer set search_path=pg_catalog,public,auth as $$
  select o.id,o.name,m.role,m.is_default from public.organization_members m
  join public.organizations o on o.id=m.organization_id where m.user_id=auth.uid() order by m.is_default desc,o.name
$$;
revoke all on function public.get_my_organizations() from public,anon;
grant execute on function public.get_my_organizations() to authenticated;

create or replace function public.set_default_organization(p_organization_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public,auth as $$
begin
  if not exists(select 1 from public.organization_members where user_id=auth.uid() and organization_id=p_organization_id) then
    raise exception 'Você não pertence a esta organização.';
  end if;
  update public.organization_members set is_default=false where user_id=auth.uid() and is_default;
  update public.organization_members set is_default=true where user_id=auth.uid() and organization_id=p_organization_id;
end; $$;
revoke all on function public.set_default_organization(uuid) from public,anon;
grant execute on function public.set_default_organization(uuid) to authenticated;

create or replace function public.apply_current_organization()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid; v_owner uuid;
begin
  if auth.uid() is null then raise exception 'Sessão autenticada obrigatória.'; end if;
  v_org:=coalesce(new.organization_id,public.current_organization_id());
  if v_org is null or not exists(select 1 from public.organization_members
      where organization_id=v_org and user_id=auth.uid()) then
    raise exception 'Selecione uma organização à qual você pertence.';
  end if;
  if tg_op='UPDATE' and v_org<>old.organization_id then raise exception 'Não é permitido mover dados entre organizações.'; end if;
  select legacy_owner_id into v_owner from public.organizations where id=v_org;
  new.organization_id:=v_org;
  new.user_id:=v_owner;
  return new;
end; $$;
revoke all on function public.apply_current_organization() from public,anon,authenticated;

do $$
declare t text;
begin
  foreach t in array array['transactions','cash_closures','cobradores','collector_receipts',
    'collector_cash_closures','funcionarios','payroll_movements','third_party_services','third_party_service_payments'] loop
    execute format('drop trigger if exists %I on public.%I',t||'_a_apply_org',t);
    execute format('create trigger %I before insert or update on public.%I for each row execute function public.apply_current_organization()',t||'_a_apply_org',t);
  end loop;
end $$;

-- Locks e bloqueios passam a usar o mesmo escopo da organização.
create or replace function public.guard_closed_cash_day()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid; v_date date;
begin
  if tg_op='DELETE' then v_org:=old.organization_id;v_date:=old.transaction_date;
  else v_org:=new.organization_id;v_date:=new.transaction_date; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.transaction_date<>old.transaction_date) then
    raise exception 'Não é permitido mover uma movimentação entre organizações ou dias.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':cash:'||v_date::text,0));
  if exists(select 1 from public.cash_closures c where c.organization_id=v_org and c.close_date=v_date and c.is_closed) then
    raise exception 'O caixa deste dia já foi fechado.';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end; $$;

create or replace function public.guard_collector_cash_day()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid; v_date date;
begin
  if tg_op='DELETE' then v_org:=old.organization_id;v_date:=old.receipt_date;
  else v_org:=new.organization_id;v_date:=new.receipt_date; end if;
  if tg_op='UPDATE' and (new.organization_id<>old.organization_id or new.receipt_date<>old.receipt_date or new.collector_id<>old.collector_id) then
    raise exception 'Não é permitido mover uma entrega para outra organização, dia ou cobrador.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':collector:'||v_date::text,0));
  if exists(select 1 from public.collector_cash_closures c where c.organization_id=v_org and c.close_date=v_date and c.is_closed) then
    raise exception 'O caixa dos cobradores deste dia já foi fechado.';
  end if;
  if tg_op='DELETE' then return old; end if;
  new.updated_at:=now();
  return new;
end; $$;

-- Toda consulta é limitada à organização selecionada; escrita depende do papel.
do $$
declare p record;
begin
  for p in select schemaname,tablename,policyname from pg_policies
    where schemaname='public' and tablename=any(array['transactions','cash_closures','cobradores','collector_receipts',
      'collector_cash_closures','funcionarios','payroll_movements','third_party_services','third_party_service_payments',
      'organizations','organization_members','audit_log']) loop
    execute format('drop policy %I on %I.%I',p.policyname,p.schemaname,p.tablename);
  end loop;
end $$;

create policy organizations_read on public.organizations for select to authenticated
  using(public.has_org_role(id,array['admin','financeiro','operador','leitura']));
create policy organization_members_read on public.organization_members for select to authenticated
  using(public.has_org_role(organization_id,array['admin','financeiro','operador','leitura']));

create policy transactions_read on public.transactions for select to authenticated
  using(organization_id=public.current_organization_id() and is_voided_at is null);
create policy transactions_insert on public.transactions for insert to authenticated
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','operador']));
create policy transactions_update on public.transactions for update to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']))
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));
create policy transactions_delete on public.transactions for delete to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));

create policy cash_closures_read on public.cash_closures for select to authenticated using(organization_id=public.current_organization_id());
create policy collectors_read on public.cobradores for select to authenticated using(organization_id=public.current_organization_id());
create policy collectors_manage on public.cobradores for all to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']))
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));
create policy receipts_read on public.collector_receipts for select to authenticated using(organization_id=public.current_organization_id());
create policy receipts_insert on public.collector_receipts for insert to authenticated
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','operador']));
create policy receipts_update on public.collector_receipts for update to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','operador']))
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','operador']));
create policy receipts_delete on public.collector_receipts for delete to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));
create policy collector_closures_read on public.collector_cash_closures for select to authenticated using(organization_id=public.current_organization_id());

create policy employees_read on public.funcionarios for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','leitura']));
create policy employees_manage on public.funcionarios for all to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']))
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));
create policy payroll_read on public.payroll_movements for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','leitura']));
create policy services_read on public.third_party_services for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','leitura']));
create policy services_manage on public.third_party_services for all to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']))
  with check(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));
create policy service_payments_read on public.third_party_service_payments for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro','leitura']));

-- Trilha de auditoria genérica; valores anteriores e posteriores ficam em JSONB.
create table if not exists public.audit_log (
  id bigint generated always as identity primary key,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  actor_id uuid references auth.users(id) on delete set null,
  occurred_at timestamptz not null default now(),
  action text not null check(action in ('INSERT','UPDATE','DELETE','REOPEN')),
  entity text not null,
  entity_id text not null,
  before_data jsonb,
  after_data jsonb
);
alter table public.audit_log enable row level security;
drop policy if exists audit_read on public.audit_log;
create policy audit_read on public.audit_log for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));

create or replace function public.audit_financial_change()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_old jsonb; v_new jsonb; v_org uuid; v_id text;
begin
  if tg_op<>'INSERT' then v_old:=to_jsonb(old); end if;
  if tg_op<>'DELETE' then v_new:=to_jsonb(new); end if;
  v_org:=coalesce((v_new->>'organization_id')::uuid,(v_old->>'organization_id')::uuid);
  v_id:=coalesce(v_new->>'id',v_old->>'id');
  insert into public.audit_log(organization_id,actor_id,action,entity,entity_id,before_data,after_data)
  values(v_org,auth.uid(),tg_op,tg_table_name,v_id,v_old,v_new);
  if tg_op='DELETE' then return old; end if;
  return new;
end; $$;
revoke all on function public.audit_financial_change() from public,anon,authenticated;
do $$
declare t text;
begin
  foreach t in array array['transactions','cash_closures','cobradores','collector_receipts','collector_cash_closures',
    'funcionarios','payroll_movements','third_party_services','third_party_service_payments'] loop
    execute format('drop trigger if exists %I on public.%I',t||'_audit_change',t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.audit_financial_change()',t||'_audit_change',t);
  end loop;
end $$;

create or replace function public.reopen_cash_day(p_close_date date,p_justification text)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id(); v_cash public.cash_closures; v_collectors public.collector_cash_closures;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin']) then raise exception 'Somente um administrador pode reabrir o dia.'; end if;
  if p_close_date is null then raise exception 'Informe a data que deseja reabrir.'; end if;
  if p_justification is null or length(trim(p_justification))<8 then
    raise exception 'Informe uma justificativa com pelo menos 8 caracteres.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':collector:'||p_close_date::text,0));
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':cash:'||p_close_date::text,0));
  select * into v_cash from public.cash_closures where organization_id=v_org and close_date=p_close_date for update;
  if not found or not v_cash.is_closed then raise exception 'Não existe fechamento diário fechado para reabrir.'; end if;
  select * into v_collectors from public.collector_cash_closures where organization_id=v_org and close_date=p_close_date for update;
  if found and v_collectors.is_closed and v_collectors.total_amount>0
     and not exists(select 1 from public.transactions where collector_cash_closure_id=v_collectors.id) then
    raise exception 'Este fechamento antigo não tem vínculo rastreável com a entrada consolidada. Não é seguro reabri-lo automaticamente.';
  end if;
  insert into public.audit_log(organization_id,actor_id,action,entity,entity_id,before_data,after_data)
  values(v_org,auth.uid(),'REOPEN','cash_day',p_close_date::text,
    jsonb_build_object('cash_closure',to_jsonb(v_cash),'collector_closure',to_jsonb(v_collectors)),
    jsonb_build_object('justification',trim(p_justification),'reopened_at',now()));
  update public.cash_closures set is_closed=false,reopened_at=now(),reopened_by=auth.uid(),reopen_reason=trim(p_justification)
    where id=v_cash.id returning * into v_cash;
  if v_collectors.id is not null then
    update public.collector_cash_closures set is_closed=false,reopened_at=now(),reopened_by=auth.uid(),reopen_reason=trim(p_justification)
      where id=v_collectors.id;
    update public.transactions set is_voided_at=now(),void_reason='Fechamento reaberto: '||trim(p_justification)
      where collector_cash_closure_id=v_collectors.id and is_voided_at is null;
  end if;
  return v_cash;
end; $$;
revoke all on function public.reopen_cash_day(date,text) from public,anon;
grant execute on function public.reopen_cash_day(date,text) to authenticated;

create or replace function public.close_collectors_cash(p_close_date date)
returns public.collector_cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_org uuid:=public.current_organization_id(); v_total numeric(12,2);
  v_result public.collector_cash_closures; v_missing text; v_transaction public.transactions;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin','financeiro','operador']) then
    raise exception 'Sem permissão para fechar os cobradores.';
  end if;
  if p_close_date is null or p_close_date>current_date then raise exception 'Informe uma data válida, que não seja futura.'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':collector:'||p_close_date::text,0));
  select * into v_result from public.collector_cash_closures where organization_id=v_org and close_date=p_close_date for update;
  if found and v_result.is_closed then return v_result; end if;
  select string_agg(c.name,', ' order by c.name) into v_missing from public.cobradores c
  where c.organization_id=v_org and c.active and not exists (
    select 1 from public.collector_receipts r where r.organization_id=v_org and r.collector_id=c.id and r.receipt_date=p_close_date
  );
  if v_missing is not null then raise exception 'Registre o valor de cada cobrador (use R$ 0,00 quando não houve entrega): %',v_missing; end if;
  select coalesce(sum(amount),0)::numeric(12,2) into v_total from public.collector_receipts
    where organization_id=v_org and receipt_date=p_close_date;
  if v_result.id is null then
    insert into public.collector_cash_closures(user_id,organization_id,close_date,total_amount,is_closed)
      values(v_user,v_org,p_close_date,v_total,true) returning * into v_result;
  else
    update public.collector_cash_closures set total_amount=v_total,is_closed=true,closed_at=now(),
      reopened_at=null,reopened_by=null,reopen_reason=null where id=v_result.id returning * into v_result;
  end if;
  select * into v_transaction from public.transactions where collector_cash_closure_id=v_result.id for update;
  if v_total>0 then
    if found then
      update public.transactions set amount=v_total,is_voided_at=null,void_reason=null,
        description='Arrecadação dos cobradores',category='Cobradores'
      where id=v_transaction.id;
    else
      insert into public.transactions(user_id,organization_id,collector_cash_closure_id,description,amount,type,category,transaction_date)
        values(v_user,v_org,v_result.id,'Arrecadação dos cobradores',v_total,'income','Cobradores',p_close_date);
    end if;
  elsif found and v_transaction.is_voided_at is null then
    update public.transactions set is_voided_at=now(),void_reason='Reabertura do dia: valor consolidado ajustado para zero.'
      where id=v_transaction.id;
  end if;
  return v_result;
end; $$;
revoke all on function public.close_collectors_cash(date) from public;
grant execute on function public.close_collectors_cash(date) to authenticated;

create or replace function public._close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_org uuid:=public.current_organization_id(); v_income numeric(12,2); v_expense numeric(12,2); v_result public.cash_closures;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin','financeiro','operador']) then raise exception 'Sem permissão para fechar o caixa.'; end if;
  select coalesce(sum(amount) filter(where type='income'),0)::numeric(12,2),
    coalesce(sum(amount) filter(where type='expense' and category<>'RH'),0)::numeric(12,2)
  into v_income,v_expense from public.transactions where organization_id=v_org and transaction_date=p_close_date and is_voided_at is null;
  select * into v_result from public.cash_closures where organization_id=v_org and close_date=p_close_date for update;
  if found then
    update public.cash_closures set opening_balance=p_opening_balance,income_total=v_income,expense_total=v_expense,
      expected_balance=p_opening_balance+v_income-v_expense,counted_balance=p_counted_balance,
      difference=p_counted_balance-(p_opening_balance+v_income-v_expense),closed_at=now(),is_closed=true,
      reopened_at=null,reopened_by=null,reopen_reason=null
    where id=v_result.id returning * into v_result;
  else
    insert into public.cash_closures(user_id,organization_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference,is_closed)
    values(v_user,v_org,p_close_date,p_opening_balance,v_income,v_expense,p_opening_balance+v_income-v_expense,
      p_counted_balance,p_counted_balance-(p_opening_balance+v_income-v_expense),true) returning * into v_result;
  end if;
  return v_result;
end; $$;
revoke all on function public._close_daily_cash(date,numeric,numeric) from public,anon,authenticated;

create or replace function public.close_day(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_org uuid:=public.current_organization_id(); v_result public.cash_closures; v_collector_close public.collector_cash_closures;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin','financeiro','operador']) then raise exception 'Sem permissão para fechar o dia.'; end if;
  if p_close_date is null or p_close_date>current_date then raise exception 'A data do fechamento não pode ser futura.'; end if;
  if p_opening_balance is null or p_counted_balance is null or p_opening_balance<0 or p_counted_balance<0 then
    raise exception 'Os saldos devem ser informados e não podem ser negativos.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':collector:'||p_close_date::text,0));
  perform pg_advisory_xact_lock(hashtextextended(v_org::text||':cash:'||p_close_date::text,0));
  select * into v_result from public.cash_closures where organization_id=v_org and close_date=p_close_date;
  if found and v_result.is_closed then
    if v_result.opening_balance<>p_opening_balance or v_result.counted_balance<>p_counted_balance then
      raise exception 'Este dia já foi fechado com outros valores. Consulte o fechamento existente.';
    end if;
    return v_result;
  end if;
  v_collector_close:=public.close_collectors_cash(p_close_date);
  return public._close_daily_cash(p_close_date,p_opening_balance,p_counted_balance);
end; $$;
revoke all on function public.close_day(date,numeric,numeric) from public;
grant execute on function public.close_day(date,numeric,numeric) to authenticated;
create or replace function public.close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric)
returns public.cash_closures language plpgsql security definer set search_path=pg_catalog,public,auth as $$
begin return public.close_day(p_close_date,p_opening_balance,p_counted_balance); end; $$;
revoke all on function public.close_daily_cash(date,numeric,numeric) from public;
grant execute on function public.close_daily_cash(date,numeric,numeric) to authenticated;

create or replace function public.register_payroll_movement(
  p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text,p_idempotency_key uuid
) returns public.payroll_movements language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_org uuid:=public.current_organization_id(); v_salary numeric(12,2); v_advances numeric(12,2);
  v_expected numeric(12,2); v_result public.payroll_movements; v_employee_name text;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin','financeiro']) then raise exception 'Sem permissão para acessar a folha.'; end if;
  if p_idempotency_key is null or p_amount is null or p_amount<=0 then raise exception 'Chave e valor válido são obrigatórios.'; end if;
  if p_payment_date is null or p_payment_date>current_date then raise exception 'A data de pagamento não pode ser futura.'; end if;
  if p_period_month is null or extract(day from p_period_month)<>1 then raise exception 'O mês deve usar o primeiro dia.'; end if;
  if p_type not in('advance','salary_payment') then raise exception 'Tipo de movimentação inválido.'; end if;
  select salary,name into v_salary,v_employee_name from public.funcionarios
    where id=p_employee_id and organization_id=v_org and active for update;
  if not found then raise exception 'Funcionário não encontrado ou inativo.'; end if;
  select * into v_result from public.payroll_movements where organization_id=v_org and idempotency_key=p_idempotency_key;
  if found then
    if v_result.employee_id<>p_employee_id or v_result.movement_type<>p_type or v_result.amount<>p_amount
      or v_result.period_month<>p_period_month or v_result.payment_date<>p_payment_date then raise exception 'Chave de solicitação reutilizada com outros dados.'; end if;
    return v_result;
  end if;
  if p_type='advance' then
    if exists(select 1 from public.payroll_movements where employee_id=p_employee_id and organization_id=v_org
      and period_month=p_period_month and movement_type='salary_payment') then raise exception 'A folha já foi paga neste mês.'; end if;
    select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id
      and organization_id=v_org and period_month=p_period_month and movement_type='advance';
    if v_advances+p_amount>v_salary then raise exception 'O total de adiantamentos excede o salário fixo.'; end if;
  else
    select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id
      and organization_id=v_org and period_month=p_period_month and movement_type='advance';
    v_expected:=v_salary-v_advances;
    if v_expected<=0 then raise exception 'Não há saldo líquido a pagar neste mês.'; end if;
    if p_amount<>v_expected then raise exception 'O pagamento deve corresponder ao líquido calculado: %',v_expected; end if;
  end if;
  insert into public.payroll_movements(user_id,organization_id,employee_id,movement_type,period_month,amount,payment_date,notes,idempotency_key)
    values(v_user,v_org,p_employee_id,p_type,p_period_month,p_amount,p_payment_date,p_notes,p_idempotency_key) returning * into v_result;
  return v_result;
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text,uuid) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text,uuid) to authenticated;
create or replace function public.register_payroll_movement(
  p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text default null
) returns public.payroll_movements language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_key uuid;
begin
  v_key:=md5(concat_ws('|',auth.uid()::text,p_employee_id::text,p_type,p_amount::text,p_period_month::text,p_payment_date::text,coalesce(p_notes,'')))::uuid;
  return public.register_payroll_movement(p_employee_id,p_type,p_amount,p_period_month,p_payment_date,p_notes,v_key);
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text) to authenticated;

drop function if exists public.pay_third_party_service(uuid,date,date);
create function public.pay_third_party_service(p_service_id uuid,p_paid_date date,p_due_date date)
returns public.third_party_service_payments language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_user uuid:=auth.uid(); v_org uuid:=public.current_organization_id(); v_service public.third_party_services;
  v_transaction_id uuid; v_payment public.third_party_service_payments; v_next_month date; v_last_day integer; v_next_due date;
begin
  if v_org is null or not public.has_org_role(v_org,array['admin','financeiro']) then raise exception 'Sem permissão para pagar serviços.'; end if;
  if p_paid_date is null or p_paid_date>current_date then raise exception 'A data de pagamento não pode ser futura.'; end if;
  select * into v_service from public.third_party_services where id=p_service_id and organization_id=v_org and active for update;
  if not found then raise exception 'Serviço não encontrado ou inativo.'; end if;
  select * into v_payment from public.third_party_service_payments where organization_id=v_org and service_id=p_service_id and due_date=p_due_date;
  if found then return v_payment; end if;
  if p_due_date is distinct from v_service.next_due_date then raise exception 'O vencimento mudou. Atualize a tela antes de confirmar.'; end if;
  insert into public.transactions(user_id,organization_id,description,amount,type,category,transaction_date)
    values(v_user,v_org,'Serviço terceirizado - '||v_service.name,v_service.fixed_amount,'expense','Serviços terceirizados',p_paid_date)
    returning id into v_transaction_id;
  insert into public.third_party_service_payments(user_id,organization_id,service_id,due_date,paid_date,amount,transaction_id)
    values(v_user,v_org,v_service.id,p_due_date,p_paid_date,v_service.fixed_amount,v_transaction_id) returning * into v_payment;
  v_next_month:=date_trunc('month',p_due_date+interval '1 month')::date;
  v_last_day:=extract(day from (v_next_month+interval '1 month'-interval '1 day'))::integer;
  v_next_due:=v_next_month+(least(v_service.due_day,v_last_day)-1);
  update public.third_party_services set next_due_date=v_next_due,updated_at=now() where id=v_service.id and organization_id=v_org;
  return v_payment;
end; $$;
revoke all on function public.pay_third_party_service(uuid,date,date) from public;
grant execute on function public.pay_third_party_service(uuid,date,date) to authenticated;
create or replace function public.pay_third_party_service(p_service_id uuid,p_paid_date date default current_date)
returns public.third_party_service_payments language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id(); v_due date; v_payment public.third_party_service_payments;
begin
  select * into v_payment from public.third_party_service_payments where organization_id=v_org and service_id=p_service_id and paid_date=p_paid_date order by created_at desc limit 1;
  if found then return v_payment; end if;
  select next_due_date into v_due from public.third_party_services where id=p_service_id and organization_id=v_org and active;
  if not found then raise exception 'Serviço não encontrado ou inativo.'; end if;
  return public.pay_third_party_service(p_service_id,p_paid_date,v_due);
end; $$;
revoke all on function public.pay_third_party_service(uuid,date) from public;
grant execute on function public.pay_third_party_service(uuid,date) to authenticated;

create or replace function public.list_organization_members()
returns table(id uuid,user_id uuid,email text,role text,created_at timestamptz)
language plpgsql stable security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id();
begin
  if not public.has_org_role(v_org,array['admin','financeiro']) then raise exception 'Sem permissão para consultar membros.'; end if;
  return query select m.id,m.user_id,u.email::text,m.role,m.created_at
    from public.organization_members m join auth.users u on u.id=m.user_id
    where m.organization_id=v_org order by m.created_at;
end; $$;
revoke all on function public.list_organization_members() from public,anon;
grant execute on function public.list_organization_members() to authenticated;

create or replace function public.set_organization_member_role(p_member_id uuid,p_role text)
returns void language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id(); v_target public.organization_members;
begin
  if not public.has_org_role(v_org,array['admin']) then raise exception 'Somente administradores podem alterar papéis.'; end if;
  if p_role not in ('admin','financeiro','operador','leitura') then raise exception 'Papel inválido.'; end if;
  select * into v_target from public.organization_members where id=p_member_id and organization_id=v_org for update;
  if not found then raise exception 'Membro não encontrado.'; end if;
  if v_target.user_id=auth.uid() and p_role<>'admin' and
    (select count(*) from public.organization_members where organization_id=v_org and role='admin')=1 then
    raise exception 'Promova outro administrador antes de reduzir seu próprio papel.';
  end if;
  update public.organization_members set role=p_role where id=p_member_id;
end; $$;
revoke all on function public.set_organization_member_role(uuid,text) from public,anon;
grant execute on function public.set_organization_member_role(uuid,text) to authenticated;

create or replace function public.remove_organization_member(p_member_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id(); v_target public.organization_members;
begin
  if not public.has_org_role(v_org,array['admin']) then raise exception 'Somente administradores podem remover membros.'; end if;
  select * into v_target from public.organization_members where id=p_member_id and organization_id=v_org for update;
  if not found then raise exception 'Membro não encontrado.'; end if;
  if v_target.role='admin' and (select count(*) from public.organization_members where organization_id=v_org and role='admin')=1 then
    raise exception 'A organização precisa manter pelo menos um administrador.';
  end if;
  delete from public.organization_members where id=p_member_id;
end; $$;
revoke all on function public.remove_organization_member(uuid) from public,anon;
grant execute on function public.remove_organization_member(uuid) to authenticated;

create or replace function public.add_existing_organization_member(p_email text,p_role text)
returns void language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid:=public.current_organization_id(); v_user uuid; v_default boolean;
begin
  if not public.has_org_role(v_org,array['admin']) then raise exception 'Somente administradores podem adicionar membros.'; end if;
  if p_role not in ('admin','financeiro','operador','leitura') then raise exception 'Papel inválido.'; end if;
  select id into v_user from auth.users where lower(email)=lower(trim(p_email));
  if v_user is null then raise exception 'Este e-mail ainda não possui uma conta. Envie um convite pelo módulo de equipe.'; end if;
  if exists(select 1 from public.organization_members where organization_id=v_org and user_id=v_user) then
    raise exception 'Este usuário já pertence à organização.';
  end if;
  v_default:=not exists(select 1 from public.organization_members where user_id=v_user and is_default);
  insert into public.organization_members(organization_id,user_id,role,is_default) values(v_org,v_user,p_role,v_default);
end; $$;
revoke all on function public.add_existing_organization_member(text,text) from public,anon;
grant execute on function public.add_existing_organization_member(text,text) to authenticated;

-- Usuários criados após a migração recebem organização individual inicial.
create or replace function public.create_initial_organization_for_user()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_org uuid;
begin
  insert into public.organizations(name,legacy_owner_id,created_by)
  values('Pax Shalom',new.id,new.id) returning id into v_org;
  insert into public.organization_members(organization_id,user_id,role,is_default)
  values(v_org,new.id,'admin',true);
  return new;
end; $$;
revoke all on function public.create_initial_organization_for_user() from public,anon,authenticated;
drop trigger if exists pax_create_initial_organization on auth.users;
create trigger pax_create_initial_organization after insert on auth.users
for each row execute function public.create_initial_organization_for_user();

-- Fase 3: convites e notificações externas.
-- Fase 3: convites e lembretes externos com deduplicação por vencimento/dia/destinatário.
create table if not exists public.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  email text not null,
  role text not null check(role in ('admin','financeiro','operador','leitura')),
  invited_by uuid not null references auth.users(id) on delete restrict,
  status text not null default 'pending' check(status in ('pending','accepted','expired','cancelled')),
  expires_at timestamptz not null default now()+interval '7 days',
  accepted_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists organization_invitations_email_idx
  on public.organization_invitations(lower(email),status,expires_at);
alter table public.organization_invitations enable row level security;

create table if not exists public.service_notifications (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  service_id uuid not null references public.third_party_services(id) on delete restrict,
  due_date date not null,
  notification_date date not null,
  channel text not null check(channel in ('email')),
  recipient_email text not null,
  status text not null default 'pending' check(status in ('pending','sending','sent','dry_run','failed')),
  attempts integer not null default 0 check(attempts>=0),
  sent_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(service_id,due_date,notification_date,channel,recipient_email)
);
create index if not exists service_notifications_org_date_idx
  on public.service_notifications(organization_id,notification_date desc);
alter table public.service_notifications enable row level security;
drop policy if exists service_notifications_read on public.service_notifications;
create policy service_notifications_read on public.service_notifications for select to authenticated
  using(organization_id=public.current_organization_id() and public.has_org_role(organization_id,array['admin','financeiro']));

create or replace function public.claim_service_notification(p_notification_id uuid)
returns boolean language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_claims text:=current_setting('request.jwt.claims',true);
  v_role text:=coalesce(current_setting('request.jwt.claim.role',true),(v_claims::jsonb->>'role'));
  v_updated uuid;
begin
  if v_role<>'service_role' then raise exception 'Esta operação só pode ser chamada pelo serviço de notificações.'; end if;
  update public.service_notifications set status='sending',attempts=attempts+1,last_error=null,updated_at=now()
  where id=p_notification_id and (status in ('pending','failed') or (status='sending' and updated_at<now()-interval '15 minutes'))
  returning id into v_updated;
  return v_updated is not null;
end; $$;
revoke all on function public.claim_service_notification(uuid) from public,anon,authenticated;
grant execute on function public.claim_service_notification(uuid) to service_role;

-- O ID aleatório da invitation no user_metadata só é aceito com e-mail e validade conferidos no banco.
create or replace function public.create_initial_organization_for_user()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,auth as $$
declare v_invite public.organization_invitations; v_org uuid; v_invite_id uuid;
begin
  begin v_invite_id:=(new.raw_user_meta_data->>'organization_invitation_id')::uuid;
  exception when others then v_invite_id:=null; end;
  if v_invite_id is not null then
    select * into v_invite from public.organization_invitations
      where id=v_invite_id and lower(email)=lower(new.email) and status='pending' and expires_at>now() for update;
    if found then
      insert into public.organization_members(organization_id,user_id,role,is_default)
      values(v_invite.organization_id,new.id,v_invite.role,true);
      update public.organization_invitations set status='accepted',accepted_at=now() where id=v_invite.id;
      return new;
    end if;
  end if;
  insert into public.organizations(name,legacy_owner_id,created_by)
  values('Pax Shalom',new.id,new.id) returning id into v_org;
  insert into public.organization_members(organization_id,user_id,role,is_default)
  values(v_org,new.id,'admin',true);
  return new;
end; $$;

