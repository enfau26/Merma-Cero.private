-- MERMA CERO: registro de empresas, resolución de membresías y permisos por rol.
-- Ejecutar SOLO después de 0001_core.sql y primero en un proyecto Supabase de pruebas.
begin;

-- Endurecer helper heredado de 0001: search_path fijo y sin ejecución anónima.
create or replace function public.is_tenant_member(target_tenant uuid)
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (select 1 from public.tenant_members tm
    where tm.tenant_id = target_tenant and tm.user_id = auth.uid());
$$;

create or replace function public.has_tenant_role(target_tenant uuid, allowed_roles public.tenant_role[])
returns boolean language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (select 1 from public.tenant_members tm
    where tm.tenant_id = target_tenant and tm.user_id = auth.uid()
      and tm.role = any(allowed_roles));
$$;

create or replace function public.create_tenant_for_current_user(p_name text, p_country_code text)
returns uuid language plpgsql security definer
set search_path = pg_catalog, public
as $$
declare
  v_user uuid := auth.uid();
  v_name text := nullif(btrim(p_name), '');
  v_country text := upper(btrim(coalesce(p_country_code, '')));
  v_currency text;
  v_timezone text;
  v_tenant uuid;
begin
  if v_user is null then raise exception 'Autenticación requerida' using errcode = '28000'; end if;
  if v_name is null or char_length(v_name) < 2 or char_length(v_name) > 100 then
    raise exception 'Nombre de empresa no válido' using errcode = '22023';
  end if;
  if v_country = 'PE' then v_currency := 'PEN'; v_timezone := 'America/Lima';
  elsif v_country = 'ES' then v_currency := 'EUR'; v_timezone := 'Europe/Madrid';
  else raise exception 'País no admitido' using errcode = '22023'; end if;
  insert into public.tenants(name, country_code, currency_code, timezone)
    values (v_name, v_country, v_currency, v_timezone) returning id into v_tenant;
  insert into public.tenant_members(tenant_id, user_id, role) values (v_tenant, v_user, 'owner');
  return v_tenant;
end;
$$;

create or replace function public.list_my_tenants()
returns table (tenant_id uuid, tenant_name text, country_code char(2), currency_code char(3), timezone text, role public.tenant_role)
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select t.id, t.name, t.country_code, t.currency_code, t.timezone, tm.role
  from public.tenant_members tm join public.tenants t on t.id = tm.tenant_id
  where tm.user_id = auth.uid() order by t.name;
$$;

-- Las políticas permisivas se combinan con OR: se eliminan las amplias iniciales.
drop policy if exists "members read own tenants" on public.tenants;
drop policy if exists "members read membership" on public.tenant_members;
drop policy if exists "tenant isolation warehouses" on public.warehouses;
drop policy if exists "tenant isolation categories" on public.categories;
drop policy if exists "tenant isolation products" on public.products;
drop policy if exists "tenant isolation lots" on public.lots;
drop policy if exists "tenant isolation movements" on public.stock_movements;
drop policy if exists "tenant isolation waste" on public.waste_records;
drop policy if exists "tenant isolation audit" on public.audit_events;

create policy tenants_read_member on public.tenants for select using (public.is_tenant_member(id));
create policy memberships_read_self on public.tenant_members for select using (user_id = auth.uid());

create policy warehouses_read on public.warehouses for select using (public.is_tenant_member(tenant_id));
create policy warehouses_insert on public.warehouses for insert with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy warehouses_update on public.warehouses for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy warehouses_delete on public.warehouses for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.tenant_role[]));

create policy categories_read on public.categories for select using (public.is_tenant_member(tenant_id));
create policy categories_insert on public.categories for insert with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy categories_update on public.categories for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy categories_delete on public.categories for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.tenant_role[]));

create policy products_read on public.products for select using (public.is_tenant_member(tenant_id));
create policy products_insert on public.products for insert with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy products_update on public.products for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy products_delete on public.products for delete using (public.has_tenant_role(tenant_id, array['owner','admin']::public.tenant_role[]));

create policy lots_read on public.lots for select using (public.is_tenant_member(tenant_id));
create policy lots_metadata_update on public.lots for update
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));
create policy movements_read on public.stock_movements for select using (public.is_tenant_member(tenant_id));
create policy waste_read on public.waste_records for select using (public.is_tenant_member(tenant_id));
create policy audit_read on public.audit_events for select
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));

revoke all on public.tenants, public.tenant_members, public.warehouses, public.categories,
  public.products, public.lots, public.stock_movements, public.waste_records, public.audit_events
  from anon, authenticated;
grant usage on schema public to authenticated;
grant usage on type public.tenant_role to authenticated;
grant select on public.tenants, public.tenant_members to authenticated;
grant select, insert, update, delete on public.warehouses, public.categories, public.products to authenticated;
grant select on public.lots, public.stock_movements, public.waste_records, public.audit_events to authenticated;
-- Nunca conceder UPDATE sobre quantity_available desde el cliente.
grant update (lot_code, received_on, expires_on, supplier_name) on public.lots to authenticated;

revoke all on function public.is_tenant_member(uuid) from public, anon;
revoke all on function public.has_tenant_role(uuid, public.tenant_role[]) from public, anon;
revoke all on function public.create_tenant_for_current_user(text, text) from public, anon;
revoke all on function public.list_my_tenants() from public, anon;
grant execute on function public.is_tenant_member(uuid) to authenticated;
grant execute on function public.has_tenant_role(uuid, public.tenant_role[]) to authenticated;
grant execute on function public.create_tenant_for_current_user(text, text) to authenticated;
grant execute on function public.list_my_tenants() to authenticated;
commit;
