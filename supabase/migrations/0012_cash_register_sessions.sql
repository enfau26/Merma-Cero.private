-- MERMA CERO · Entrega 11 · Caja: sesiones, movimientos y arqueo
-- Requiere migraciones 0001, 0007–0011 aplicadas en entorno de pruebas.

create table public.cash_register_sessions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  warehouse_id uuid not null,
  register_name text not null,
  status text not null default 'open' check (status in ('open','closed')),
  opening_amount numeric(14,2) not null check (opening_amount >= 0),
  expected_amount numeric(14,2),
  counted_amount numeric(14,2),
  difference_amount numeric(14,2),
  opening_note text,
  closing_note text,
  opened_by uuid not null references auth.users(id),
  closed_by uuid references auth.users(id),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  unique (tenant_id,id),
  foreign key (tenant_id,warehouse_id) references public.warehouses(tenant_id,id),
  check ((status = 'open' and closed_at is null and counted_amount is null)
      or (status = 'closed' and closed_at is not null and counted_amount is not null))
);

create table public.cash_register_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  session_id uuid not null,
  movement_type text not null check (movement_type in ('cash_in','cash_out')),
  amount numeric(14,2) not null check (amount > 0),
  reason text not null,
  reference text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (tenant_id,session_id) references public.cash_register_sessions(tenant_id,id) on delete cascade
);

create unique index cash_register_one_open_per_register
  on public.cash_register_sessions(tenant_id,warehouse_id,lower(register_name)) where status='open';
create index cash_register_sessions_tenant_opened_idx
  on public.cash_register_sessions(tenant_id,opened_at desc);
create index cash_register_movements_session_idx
  on public.cash_register_movements(tenant_id,session_id,created_at);

alter table public.cash_register_sessions enable row level security;
alter table public.cash_register_movements enable row level security;
create policy cash_register_sessions_select_member on public.cash_register_sessions
  for select using (public.is_tenant_member(tenant_id));
create policy cash_register_movements_select_member on public.cash_register_movements
  for select using (public.is_tenant_member(tenant_id));
revoke insert,update,delete on public.cash_register_sessions,public.cash_register_movements from authenticated;
grant select on public.cash_register_sessions,public.cash_register_movements to authenticated;

create or replace function public.open_cash_register_atomic(
  p_tenant_id uuid,p_warehouse_id uuid,p_register_name text,
  p_opening_amount numeric,p_opening_note text default null
) returns uuid language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','operator']::public.tenant_role[]) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode='42501'; end if;
  if p_register_name is null or length(trim(p_register_name))=0 or p_opening_amount is null or p_opening_amount<0 then
    raise exception 'INVALID_CASH_REGISTER_OPENING' using errcode='22023'; end if;
  if not exists(select 1 from public.warehouses where tenant_id=p_tenant_id and id=p_warehouse_id and is_active) then
    raise exception 'WAREHOUSE_NOT_FOUND_OR_INACTIVE' using errcode='22023'; end if;
  insert into public.cash_register_sessions(tenant_id,warehouse_id,register_name,opening_amount,opening_note,opened_by)
  values(p_tenant_id,p_warehouse_id,trim(p_register_name),p_opening_amount,nullif(trim(p_opening_note),''),v_actor)
  returning id into v_id;
  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values(p_tenant_id,v_actor,'cash_register.opened','cash_register_session',v_id,
    jsonb_build_object('warehouse_id',p_warehouse_id,'register_name',trim(p_register_name),'opening_amount',p_opening_amount));
  return v_id;
end $$;

create or replace function public.record_cash_register_movement_atomic(
  p_tenant_id uuid,p_session_id uuid,p_movement_type text,p_amount numeric,
  p_reason text,p_reference text default null
) returns uuid language plpgsql security definer
set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_id uuid;
begin
  if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','operator']::public.tenant_role[]) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode='42501'; end if;
  if p_movement_type is null or p_movement_type not in ('cash_in','cash_out') or p_amount is null or p_amount<=0
     or p_reason is null or length(trim(p_reason))=0 then
    raise exception 'INVALID_CASH_REGISTER_MOVEMENT' using errcode='22023'; end if;
  perform 1 from public.cash_register_sessions where id=p_session_id and tenant_id=p_tenant_id and status='open' for update;
  if not found then raise exception 'CASH_REGISTER_NOT_OPEN' using errcode='22023'; end if;
  insert into public.cash_register_movements(tenant_id,session_id,movement_type,amount,reason,reference,created_by)
  values(p_tenant_id,p_session_id,p_movement_type,p_amount,trim(p_reason),nullif(trim(p_reference),''),v_actor)
  returning id into v_id;
  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values(p_tenant_id,v_actor,'cash_register.movement','cash_register_movement',v_id,
    jsonb_build_object('session_id',p_session_id,'movement_type',p_movement_type,'amount',p_amount,'reason',trim(p_reason)));
  return v_id;
end $$;

create or replace function public.close_cash_register_atomic(
  p_tenant_id uuid,p_session_id uuid,p_counted_amount numeric,p_closing_note text default null
) returns table(expected_amount numeric,counted_amount numeric,difference_amount numeric)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_session public.cash_register_sessions%rowtype; v_expected numeric(14,2);
begin
  if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
  if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager']::public.tenant_role[]) then
    raise exception 'CASH_REGISTER_CLOSE_FORBIDDEN' using errcode='42501'; end if;
  if p_counted_amount is null or p_counted_amount<0 then raise exception 'INVALID_COUNTED_AMOUNT' using errcode='22023'; end if;
  select * into v_session from public.cash_register_sessions
    where id=p_session_id and tenant_id=p_tenant_id and status='open' for update;
  if not found then raise exception 'CASH_REGISTER_NOT_OPEN' using errcode='22023'; end if;
  select round(v_session.opening_amount + coalesce(sum(case when movement_type='cash_in' then amount else -amount end),0),2)
    into v_expected from public.cash_register_movements where tenant_id=p_tenant_id and session_id=p_session_id;
  update public.cash_register_sessions set status='closed',expected_amount=v_expected,
    counted_amount=p_counted_amount,difference_amount=round(p_counted_amount-v_expected,2),
    closing_note=nullif(trim(p_closing_note),''),closed_by=v_actor,closed_at=now()
    where id=p_session_id and tenant_id=p_tenant_id;
  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values(p_tenant_id,v_actor,'cash_register.closed','cash_register_session',p_session_id,
    jsonb_build_object('expected_amount',v_expected,'counted_amount',p_counted_amount,
      'difference_amount',round(p_counted_amount-v_expected,2)));
  return query select v_expected,p_counted_amount,round(p_counted_amount-v_expected,2);
end $$;

revoke all on function public.open_cash_register_atomic(uuid,uuid,text,numeric,text) from public;
revoke all on function public.record_cash_register_movement_atomic(uuid,uuid,text,numeric,text,text) from public;
revoke all on function public.close_cash_register_atomic(uuid,uuid,numeric,text) from public;
grant execute on function public.open_cash_register_atomic(uuid,uuid,text,numeric,text) to authenticated;
grant execute on function public.record_cash_register_movement_atomic(uuid,uuid,text,numeric,text,text) to authenticated;
grant execute on function public.close_cash_register_atomic(uuid,uuid,numeric,text) to authenticated;

comment on table public.cash_register_sessions is 'Sesiones de caja con arqueo físico y diferencia; no liquida pagos bancarios.';
