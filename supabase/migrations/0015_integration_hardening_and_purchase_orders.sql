-- MERMA CERO · Entrega 14 · Integración del baseline y alta segura multiempresa
-- Requiere el conjunto canónico: 0001, 0002, 0003 y 0007–0014.
-- No aplicar sobre una base que haya recibido la rama legacy 0004 sin auditarla.
begin;

-- Endurecer el search_path de todas las funciones SECURITY DEFINER de las entregas
-- 07–13. pg_catalog siempre queda primero y pg_temp al final cuando se necesita.
alter function public.is_tenant_member(uuid)
  set search_path = pg_catalog, public;
alter function public.has_tenant_role(uuid, public.tenant_role[])
  set search_path = pg_catalog, public;
alter function public.create_tenant_for_current_user(text, text)
  set search_path = pg_catalog, public;
alter function public.receive_purchase_order_atomic(uuid, uuid, uuid, text, jsonb, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.create_sale_atomic(uuid, uuid, text, jsonb, jsonb, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.create_sale_return_atomic(uuid, uuid, text, jsonb, jsonb, text, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.open_cash_register_atomic(uuid, uuid, text, numeric, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.record_cash_register_movement_atomic(uuid, uuid, text, numeric, text, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.close_cash_register_atomic(uuid, uuid, numeric, text)
  set search_path = pg_catalog, public, pg_temp;
alter function public.post_cash_document_to_register_atomic(uuid, uuid, text, uuid)
  set search_path = pg_catalog, public, pg_temp;
alter function public.create_operating_expense_atomic(uuid, date, text, text, numeric, uuid, text)
  set search_path = pg_catalog, public, pg_temp;

-- El RPC original sigue siendo el único mecanismo que crea tenant + owner.
-- Se oculta su ejecución directa y se expone un wrapper que añade almacén inicial
-- y auditoría dentro de la misma transacción.
create or replace function public.create_tenant_with_default_warehouse(
  p_name text,
  p_country_code text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_actor uuid := auth.uid();
  v_tenant_id uuid;
  v_warehouse_id uuid;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '28000';
  end if;

  v_tenant_id := public.create_tenant_for_current_user(p_name, p_country_code);

  insert into public.warehouses(tenant_id, name, is_active)
  values (v_tenant_id, 'Almacén principal', true)
  returning id into v_warehouse_id;

  insert into public.audit_events(tenant_id, actor_id, action, entity_type, entity_id, details)
  values (
    v_tenant_id,
    v_actor,
    'tenant.onboarding_completed',
    'tenant',
    v_tenant_id,
    jsonb_build_object('default_warehouse_id', v_warehouse_id)
  );

  return v_tenant_id;
end;
$$;

revoke all on function public.create_tenant_for_current_user(text, text) from public, anon, authenticated;
revoke all on function public.create_tenant_with_default_warehouse(text, text) from public, anon;
grant execute on function public.create_tenant_with_default_warehouse(text, text) to authenticated;

-- Alta atómica de órdenes compatible con el esquema canónico 0007.
-- Se crean como submitted para que 0009 permita recepciones parciales/completas.
create or replace function public.create_purchase_order_atomic(
  p_tenant_id uuid,
  p_supplier_id uuid,
  p_order_number text,
  p_order_date date default null,
  p_expected_date date default null,
  p_notes text default null,
  p_lines jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_currency char(3);
  v_supplier public.suppliers%rowtype;
  v_line jsonb;
  v_product_id uuid;
  v_quantity numeric;
  v_unit_cost numeric;
  v_tax_rate numeric;
  v_line_subtotal numeric(14,2);
  v_line_tax numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_tax_total numeric(14,2) := 0;
  v_order_id uuid;
  v_line_count integer;
  v_order_date date;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.has_tenant_role(
    p_tenant_id,
    array['owner','admin','manager']::public.tenant_role[]
  ) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode = '42501';
  end if;

  if nullif(btrim(coalesce(p_order_number, '')), '') is null
     or char_length(btrim(p_order_number)) > 60
     or char_length(coalesce(p_notes, '')) > 2000 then
    raise exception 'INVALID_ORDER_NUMBER' using errcode = '22023';
  end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    raise exception 'INVALID_PURCHASE_LINES' using errcode = '22023';
  end if;
  v_line_count := jsonb_array_length(p_lines);
  if v_line_count < 1 or v_line_count > 200 then
    raise exception 'PURCHASE_LINES_OUT_OF_RANGE' using errcode = '22023';
  end if;

  select t.currency_code into v_currency
  from public.tenants t
  where t.id = p_tenant_id;
  if not found then
    raise exception 'TENANT_NOT_FOUND' using errcode = 'P0002';
  end if;

  select * into v_supplier
  from public.suppliers s
  where s.id = p_supplier_id
    and s.tenant_id = p_tenant_id
    and s.is_active
  for key share;
  if not found then
    raise exception 'SUPPLIER_NOT_FOUND_OR_INACTIVE' using errcode = 'P0002';
  end if;
  if v_supplier.currency_code <> v_currency then
    raise exception 'SUPPLIER_CURRENCY_MISMATCH' using errcode = '22023';
  end if;

  v_order_date := coalesce(p_order_date, current_date);
  if p_expected_date is not null and p_expected_date < v_order_date then
    raise exception 'EXPECTED_DATE_BEFORE_ORDER_DATE' using errcode = '22023';
  end if;

  insert into public.purchase_orders(
    tenant_id, supplier_id, order_number, status, order_date,
    expected_date, currency_code, notes, created_by
  ) values (
    p_tenant_id, p_supplier_id, btrim(p_order_number), 'submitted',
    v_order_date, p_expected_date, v_currency,
    nullif(btrim(coalesce(p_notes, '')), ''), v_actor
  ) returning id into v_order_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if jsonb_typeof(v_line) <> 'object'
       or nullif(v_line->>'product_id', '') is null
       or nullif(v_line->>'quantity_ordered', '') is null then
      raise exception 'INVALID_PURCHASE_LINE' using errcode = '22023';
    end if;

    v_product_id := (v_line->>'product_id')::uuid;
    v_quantity := (v_line->>'quantity_ordered')::numeric;
    v_unit_cost := coalesce(nullif(v_line->>'unit_cost', '')::numeric, 0);
    v_tax_rate := coalesce(nullif(v_line->>'tax_rate', '')::numeric, 0);

    if v_quantity::text in ('NaN','Infinity','-Infinity')
       or v_unit_cost::text in ('NaN','Infinity','-Infinity')
       or v_tax_rate::text in ('NaN','Infinity','-Infinity')
       or v_quantity <= 0 or v_quantity <> round(v_quantity, 3)
       or v_unit_cost < 0 or v_unit_cost <> round(v_unit_cost, 4)
       or v_tax_rate < 0 or v_tax_rate > 100 or v_tax_rate <> round(v_tax_rate, 4) then
      raise exception 'INVALID_PURCHASE_LINE_AMOUNTS' using errcode = '22023';
    end if;
    if char_length(coalesce(v_line->>'description', '')) > 500 then
      raise exception 'PURCHASE_LINE_DESCRIPTION_TOO_LONG' using errcode = '22023';
    end if;

    perform 1
    from public.products p
    where p.id = v_product_id
      and p.tenant_id = p_tenant_id
      and p.is_active
    for share;
    if not found then
      raise exception 'PRODUCT_NOT_FOUND_OR_INACTIVE' using errcode = 'P0002';
    end if;

    v_line_subtotal := round(v_quantity * v_unit_cost, 2);
    v_line_tax := round(v_line_subtotal * v_tax_rate / 100, 2);

    insert into public.purchase_order_items(
      tenant_id, purchase_order_id, product_id, description,
      quantity_ordered, unit_cost, tax_rate, line_subtotal, line_tax
    ) values (
      p_tenant_id, v_order_id, v_product_id,
      nullif(btrim(coalesce(v_line->>'description', '')), ''),
      v_quantity, v_unit_cost, v_tax_rate, v_line_subtotal, v_line_tax
    );

    v_subtotal := v_subtotal + v_line_subtotal;
    v_tax_total := v_tax_total + v_line_tax;
  end loop;

  update public.purchase_orders
  set subtotal = v_subtotal,
      tax_total = v_tax_total,
      total = v_subtotal + v_tax_total,
      updated_at = now()
  where id = v_order_id and tenant_id = p_tenant_id;

  insert into public.audit_events(tenant_id, actor_id, action, entity_type, entity_id, details)
  values (
    p_tenant_id, v_actor, 'purchase_order.created', 'purchase_order', v_order_id,
    jsonb_build_object(
      'supplier_id', p_supplier_id,
      'order_number', btrim(p_order_number),
      'line_count', v_line_count,
      'subtotal', v_subtotal,
      'tax_total', v_tax_total,
      'currency_code', v_currency
    )
  );

  return v_order_id;
end;
$$;

revoke all on function public.create_purchase_order_atomic(uuid, uuid, text, date, date, text, jsonb) from public, anon;
grant execute on function public.create_purchase_order_atomic(uuid, uuid, text, date, date, text, jsonb) to authenticated;

-- Evitar que un cliente cree cabeceras o líneas parciales fuera de la RPC.
-- Las lecturas siguen disponibles por RLS; recepción y cambios de estado se hacen
-- exclusivamente mediante las RPC SECURITY DEFINER auditadas.
revoke insert, update, delete on public.purchase_orders, public.purchase_order_items from authenticated;
grant select on public.purchase_orders, public.purchase_order_items to authenticated;

comment on function public.create_tenant_with_default_warehouse(text, text)
  is 'Crea empresa, propietario, almacén principal y auditoría en una sola transacción.';
comment on function public.create_purchase_order_atomic(uuid, uuid, text, date, date, text, jsonb)
  is 'Crea orden y líneas de compra con totales y auditoría; estado inicial submitted para permitir recepción atómica.';

commit;
