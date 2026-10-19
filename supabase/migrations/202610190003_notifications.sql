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

