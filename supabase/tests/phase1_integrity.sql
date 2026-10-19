-- Integration checks for Supabase local development. Run inside a transaction;
-- every fixture is rolled back. Requires at least one auth.users row.
begin;
do $$
declare
  v_user uuid;
  v_day date := current_date - (10000 + floor(random()*100000)::int);
  v_collector uuid := gen_random_uuid();
  v_employee uuid := gen_random_uuid();
  v_service uuid := gen_random_uuid();
  v_key uuid := gen_random_uuid();
  v_first public.cash_closures;
  v_again public.cash_closures;
  v_payroll1 public.payroll_movements;
  v_payroll2 public.payroll_movements;
  v_service_payment1 public.third_party_service_payments;
  v_service_payment2 public.third_party_service_payments;
  v_message text;
begin
  select id into v_user from auth.users order by created_at limit 1;
  if v_user is null then raise exception 'Crie um usuário local no Supabase Auth antes de executar estes testes.'; end if;
  perform set_config('request.jwt.claim.sub',v_user::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',v_user::text,'role','authenticated')::text,true);

  insert into public.cobradores(id,user_id,name) values(v_collector,v_user,'Teste integridade '||v_collector::text);
  begin
    perform public.close_day(v_day,0,0);
    raise exception 'Esperava bloqueio de cobrador sem lançamento explícito.';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message not like 'Registre o valor de cada cobrador%' then raise; end if;
  end;

  insert into public.collector_receipts(user_id,collector_id,receipt_date,amount)
  values(v_user,v_collector,v_day,300);
  insert into public.transactions(user_id,description,amount,type,category,transaction_date)
  values(v_user,'Teste RH excluído',500,'expense','RH',v_day),
        (v_user,'Teste despesa geral',100,'expense','Outros',v_day);

  v_first := public.close_day(v_day,50,250);
  if v_first.income_total <> 300 or v_first.expense_total <> 100 or v_first.expected_balance <> 250 then
    raise exception 'close_day calculou totais incorretos: entrada %, saída %, esperado %',
      v_first.income_total,v_first.expense_total,v_first.expected_balance;
  end if;
  v_again := public.close_day(v_day,50,250);
  if v_again.id <> v_first.id then raise exception 'Retry de close_day não retornou o mesmo fechamento.'; end if;
  begin
    perform public.close_day(v_day,50,251);
    raise exception 'Esperava rejeição de fechamento repetido com valores divergentes.';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message not like 'Este dia já foi fechado%' then raise; end if;
  end;
  begin
    insert into public.transactions(user_id,description,amount,type,transaction_date)
    values(v_user,'Não pode inserir após fechar',1,'expense',v_day);
    raise exception 'Esperava bloqueio de alteração após fechamento.';
  exception when others then
    get stacked diagnostics v_message = message_text;
    if v_message not like 'O caixa deste dia já foi fechado%' then raise; end if;
  end;

  insert into public.funcionarios(id,user_id,name,salary) values(v_employee,v_user,'Teste folha',1000);
  v_payroll1 := public.register_payroll_movement(v_employee,'advance',200,date_trunc('month',current_date)::date,current_date,'teste idempotência',v_key);
  v_payroll2 := public.register_payroll_movement(v_employee,'advance',200,date_trunc('month',current_date)::date,current_date,'teste idempotência',v_key);
  if v_payroll1.id <> v_payroll2.id then raise exception 'Retry de folha criou uma segunda linha.'; end if;
  if (select count(*) from public.payroll_movements where user_id=v_user and idempotency_key=v_key) <> 1 then
    raise exception 'Chave de idempotência da folha não foi respeitada.';
  end if;
  if (select count(*) from public.transactions where user_id=v_user and transaction_date=v_day and category='RH') <> 1 then
    raise exception 'Movimentação de RH alterou o caixa geral.';
  end if;

  insert into public.third_party_services(id,user_id,name,fixed_amount,due_day,next_due_date)
  values(v_service,v_user,'Teste vencimento',75,31,date '2024-01-31');
  v_service_payment1 := public.pay_third_party_service(v_service,current_date,date '2024-01-31');
  v_service_payment2 := public.pay_third_party_service(v_service,current_date,date '2024-01-31');
  if v_service_payment1.id <> v_service_payment2.id then raise exception 'Retry de serviço criou outra baixa.'; end if;
  if (select next_due_date from public.third_party_services where id=v_service) <> date '2024-02-29' then
    raise exception 'Próximo vencimento de janeiro não respeitou o último dia de fevereiro bissexto.';
  end if;
  perform public.pay_third_party_service(v_service,current_date,date '2024-02-29');
  if (select next_due_date from public.third_party_services where id=v_service) <> date '2024-03-31' then
    raise exception 'Cálculo mensal do dia 31 não foi preservado após fevereiro.';
  end if;
  if (select count(*) from public.third_party_service_payments where service_id=v_service) <> 2 then
    raise exception 'Baixas de serviço duplicadas ou ausentes.';
  end if;
  if (select count(*) from public.transactions where user_id=v_user and category='Serviços terceirizados') <> 2 then
    raise exception 'Saídas de serviços não correspondem às baixas.';
  end if;
end;
$$;
rollback;
