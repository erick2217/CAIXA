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
create or replace function public.close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric) returns public.cash_closures language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_income numeric(12,2); v_expense numeric(12,2); v_result public.cash_closures;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 if p_opening_balance<0 or p_counted_balance<0 then raise exception 'Os saldos nao podem ser negativos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_close_date::text,0));
 select coalesce(sum(amount) filter(where type='income'),0),coalesce(sum(amount) filter(where type='expense'),0) into v_income,v_expense from public.transactions where user_id=v_user and transaction_date=p_close_date;
 insert into public.cash_closures(user_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference) values(v_user,p_close_date,p_opening_balance,v_income,v_expense,p_opening_balance+v_income-v_expense,p_counted_balance,p_counted_balance-(p_opening_balance+v_income-v_expense)) returning * into v_result;
 return v_result;
end; $$;
revoke all on function public.close_daily_cash(date,numeric,numeric) from public;
grant execute on function public.close_daily_cash(date,numeric,numeric) to authenticated;

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

create or replace function public.close_collectors_cash(p_close_date date) returns public.collector_cash_closures language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_total numeric(12,2); v_result public.collector_cash_closures; r record;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':collector:'||p_close_date::text,0));
 select coalesce(sum(amount),0) into v_total from public.collector_receipts where user_id=v_user and receipt_date=p_close_date;
 insert into public.collector_cash_closures(user_id,close_date,total_amount) values(v_user,p_close_date,v_total) returning * into v_result;
 for r in select cr.amount,c.name from public.collector_receipts cr join public.cobradores c on c.id=cr.collector_id and c.user_id=cr.user_id where cr.user_id=v_user and cr.receipt_date=p_close_date and cr.amount>0 loop
  insert into public.transactions(user_id,description,amount,type,category,transaction_date) values(v_user,'Arrecadacao do cobrador: '||r.name,r.amount,'income','Cobradores',p_close_date);
 end loop;
 return v_result;
end; $$;
revoke all on function public.close_collectors_cash(date) from public;
grant execute on function public.close_collectors_cash(date) to authenticated;

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

create or replace function public.register_payroll_movement(p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text default null) returns public.payroll_movements language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_salary numeric(12,2); v_advances numeric(12,2); v_expected numeric(12,2); v_result public.payroll_movements; v_employee_name text;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 if p_period_month is null or extract(day from p_period_month)<>1 then raise exception 'O mes de referencia deve usar o primeiro dia do mes.'; end if;
 if p_type not in('advance','salary_payment') then raise exception 'Tipo de movimentacao invalido.'; end if;
 select salary,name into v_salary,v_employee_name from public.funcionarios where id=p_employee_id and user_id=v_user and active for update;
 if not found then raise exception 'Funcionario nao encontrado ou inativo.'; end if;
 if p_type='advance' then
  if p_amount<=0 then raise exception 'O adiantamento deve ser maior que zero.'; end if;
  if exists(select 1 from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='salary_payment') then raise exception 'A folha deste funcionario ja foi paga neste mes.'; end if;
  select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='advance';
  if v_advances+p_amount>v_salary then raise exception 'O total de adiantamentos excede o salario fixo.'; end if;
 else
  select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='advance';
  v_expected:=v_salary-v_advances;
  if v_expected<=0 then raise exception 'Nao ha saldo liquido a pagar neste mes.'; end if;
  if p_amount<>v_expected then raise exception 'O pagamento deve corresponder ao liquido calculado: %',v_expected; end if;
 end if;
 insert into public.payroll_movements(user_id,employee_id,movement_type,period_month,amount,payment_date,notes) values(v_user,p_employee_id,p_type,p_period_month,p_amount,p_payment_date,p_notes) returning * into v_result;
 insert into public.transactions(user_id,description,amount,type,category,transaction_date) values(v_user,case when p_type='advance' then 'Vale salarial - ' else 'Pagamento de salario - ' end||v_employee_name,p_amount,'expense','RH',p_payment_date);
 return v_result;
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text) to authenticated;

-- RH fica fora do caixa geral; mantenha apenas o registro na folha.
create or replace function public.close_daily_cash(p_close_date date,p_opening_balance numeric,p_counted_balance numeric) returns public.cash_closures language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_income numeric(12,2); v_expense numeric(12,2); v_result public.cash_closures;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 if p_opening_balance<0 or p_counted_balance<0 then raise exception 'Os saldos nao podem ser negativos.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_user::text||':'||p_close_date::text,0));
 select coalesce(sum(amount) filter(where type='income'),0),coalesce(sum(amount) filter(where type='expense' and category<>'RH'),0) into v_income,v_expense from public.transactions where user_id=v_user and transaction_date=p_close_date;
 insert into public.cash_closures(user_id,close_date,opening_balance,income_total,expense_total,expected_balance,counted_balance,difference) values(v_user,p_close_date,p_opening_balance,v_income,v_expense,p_opening_balance+v_income-v_expense,p_counted_balance,p_counted_balance-(p_opening_balance+v_income-v_expense)) returning * into v_result;
 return v_result;
end; $$;

create or replace function public.register_payroll_movement(p_employee_id uuid,p_type text,p_amount numeric,p_period_month date,p_payment_date date,p_notes text default null) returns public.payroll_movements language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_salary numeric(12,2); v_advances numeric(12,2); v_expected numeric(12,2); v_result public.payroll_movements; v_employee_name text;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 if p_period_month is null or extract(day from p_period_month)<>1 then raise exception 'O mes de referencia deve usar o primeiro dia do mes.'; end if;
 if p_type not in('advance','salary_payment') then raise exception 'Tipo de movimentacao invalido.'; end if;
 select salary,name into v_salary,v_employee_name from public.funcionarios where id=p_employee_id and user_id=v_user and active for update;
 if not found then raise exception 'Funcionario nao encontrado ou inativo.'; end if;
 if p_type='advance' then
  if p_amount<=0 then raise exception 'O adiantamento deve ser maior que zero.'; end if;
  if exists(select 1 from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='salary_payment') then raise exception 'A folha deste funcionario ja foi paga neste mes.'; end if;
  select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='advance';
  if v_advances+p_amount>v_salary then raise exception 'O total de adiantamentos excede o salario fixo.'; end if;
 else
  select coalesce(sum(amount),0) into v_advances from public.payroll_movements where employee_id=p_employee_id and user_id=v_user and period_month=p_period_month and movement_type='advance';
  v_expected:=v_salary-v_advances;
  if v_expected<=0 then raise exception 'Nao ha saldo liquido a pagar neste mes.'; end if;
  if p_amount<>v_expected then raise exception 'O pagamento deve corresponder ao liquido calculado: %',v_expected; end if;
 end if;
 insert into public.payroll_movements(user_id,employee_id,movement_type,period_month,amount,payment_date,notes) values(v_user,p_employee_id,p_type,p_period_month,p_amount,p_payment_date,p_notes) returning * into v_result;
 return v_result;
end; $$;
revoke all on function public.register_payroll_movement(uuid,text,numeric,date,date,text) from public;
grant execute on function public.register_payroll_movement(uuid,text,numeric,date,date,text) to authenticated;

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

create or replace function public.pay_third_party_service(p_service_id uuid,p_paid_date date default current_date) returns public.third_party_service_payments language plpgsql security definer set search_path=public,auth as $$
declare v_user uuid; v_service public.third_party_services; v_transaction_id uuid; v_payment public.third_party_service_payments; v_next_month date; v_next_due date;
begin
 v_user:=auth.uid(); if v_user is null then raise exception 'E necessario entrar na conta.'; end if;
 if p_paid_date is null or p_paid_date>current_date then raise exception 'A data de pagamento nao pode estar no futuro.'; end if;
 select * into v_service from public.third_party_services where id=p_service_id and user_id=v_user and active for update;
 if not found then raise exception 'Servico nao encontrado ou inativo.'; end if;
 if exists(select 1 from public.third_party_service_payments where user_id=v_user and service_id=p_service_id and due_date=v_service.next_due_date) then raise exception 'Este vencimento ja foi pago.'; end if;
 insert into public.transactions(user_id,description,amount,type,category,transaction_date) values(v_user,'Servico terceirizado - '||v_service.name,v_service.fixed_amount,'expense','Servicos terceirizados',p_paid_date) returning id into v_transaction_id;
 insert into public.third_party_service_payments(user_id,service_id,due_date,paid_date,amount,transaction_id) values(v_user,v_service.id,v_service.next_due_date,p_paid_date,v_service.fixed_amount,v_transaction_id) returning * into v_payment;
 v_next_month:=date_trunc('month',v_service.next_due_date+interval '1 month')::date;
 v_next_due:=v_next_month+(least(v_service.due_day,extract(day from (date_trunc('month',v_service.next_due_date+interval '2 month')-interval '1 day'))::int)-1);
 update public.third_party_services set next_due_date=v_next_due,updated_at=now() where id=v_service.id and user_id=v_user;
 return v_payment;
end; $$;
revoke all on function public.pay_third_party_service(uuid,date) from public;
grant execute on function public.pay_third_party_service(uuid,date) to authenticated;
