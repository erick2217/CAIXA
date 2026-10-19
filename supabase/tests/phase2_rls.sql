-- Execute em uma conexão autenticada do Supabase local após definir o JWT do usuário:
-- SET request.jwt.claim.sub = '<uuid do usuário de teste>';
-- SET request.jwt.claims = '{"sub":"<uuid>","role":"authenticated"}';
-- SET ROLE authenticated;
-- Cada bloco lança exceção se uma regra falhar. Envolva com BEGIN/ROLLBACK.
do $$
declare v_org uuid:=public.current_organization_id(); v_role text;
begin
  if v_org is null then raise exception 'Usuário de teste sem organização padrão.'; end if;
  if exists(select 1 from public.transactions where organization_id<>v_org) then
    raise exception 'RLS permitiu leitura de transação de outra organização.';
  end if;
  if exists(select 1 from public.cash_closures where organization_id<>v_org) then
    raise exception 'RLS permitiu leitura de fechamento de outra organização.';
  end if;
  select role into v_role from public.organization_members
  where organization_id=v_org and user_id=auth.uid();
  if v_role='leitura' then
    begin
      insert into public.transactions(user_id,description,amount,type,transaction_date)
      values(auth.uid(),'Teste RLS leitura',1,'income',current_date);
      raise exception 'Papel leitura conseguiu inserir uma movimentação.';
    exception when insufficient_privilege then null;
    end;
  elsif v_role='operador' then
    begin
      perform public.register_payroll_movement(gen_random_uuid(),'advance',1,date_trunc('month',current_date)::date,current_date,
        'Teste papel operador',gen_random_uuid());
      raise exception 'Papel operador conseguiu acessar a folha.';
    exception when raise_exception then
      if sqlerrm not like 'Sem permissão para acessar a folha%' then raise; end if;
    end;
  end if;
end;
$$;
