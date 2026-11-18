-- MERMA CERO — inventario transaccional, FEFO y mermas.
-- Requiere 0001_core.sql y 0002_auth_tenants_and_role_policies.sql.
begin;

-- RPC: recepción. El lote y su movimiento se confirman o revierten juntos.
create or replace function public.receive_lot(
  p_tenant_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_quantity numeric,
  p_unit_cost numeric default 0,
  p_expires_on date default null,
  p_lot_code text default null,
  p_supplier_name text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_lot_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','manager','operator']::public.tenant_role[]
  ) then
    raise exception 'Permiso insuficiente' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 or p_unit_cost is null or p_unit_cost < 0 then
    raise exception 'Cantidad o coste no válido' using errcode = '22023';
  end if;
  if p_expires_on is not null and p_expires_on < current_date then
    raise exception 'La fecha de caducidad no puede estar en el pasado' using errcode = '22023';
  end if;
  perform 1 from public.products
    where id = p_product_id and tenant_id = p_tenant_id and is_active
    for key share;
  if not found then raise exception 'Producto no encontrado o inactivo'; end if;
  perform 1 from public.warehouses
    where id = p_warehouse_id and tenant_id = p_tenant_id and is_active
    for key share;
  if not found then raise exception 'Almacén no encontrado o inactivo'; end if;

  insert into public.lots(tenant_id, product_id, warehouse_id, lot_code,
    received_on, expires_on, quantity_received, quantity_available, unit_cost, supplier_name)
  values(p_tenant_id, p_product_id, p_warehouse_id, nullif(btrim(p_lot_code), ''),
    current_date, p_expires_on, p_quantity, p_quantity, p_unit_cost, nullif(btrim(p_supplier_name), ''))
  returning id into v_lot_id;

  insert into public.stock_movements(tenant_id, lot_id, movement_type, quantity, unit_cost, reason, created_by)
  values(p_tenant_id, v_lot_id, 'receipt', p_quantity, p_unit_cost, 'Recepción de mercancía', v_user_id);
  insert into public.audit_events(tenant_id, actor_id, action, entity_type, entity_id)
  values(p_tenant_id, v_user_id, 'lot_received', 'lot', v_lot_id);
  return v_lot_id;
end;
$$;

-- RPC: salida FEFO. Consume primero la caducidad más próxima;
-- los lotes sin caducidad quedan al final. Los locks evitan sobreventa concurrente.
create or replace function public.consume_stock_fefo(
  p_tenant_id uuid,
  p_product_id uuid,
  p_warehouse_id uuid,
  p_quantity numeric,
  p_reason text default 'Salida de mercancía',
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_user_id uuid := auth.uid();
  v_remaining numeric := p_quantity;
  v_take numeric;
  v_lot record;
  v_allocations jsonb := '[]'::jsonb;
  v_reason text := coalesce(nullif(btrim(p_reason), ''), 'Salida de mercancía');
begin
  if v_user_id is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','manager','operator']::public.tenant_role[]
  ) then
    raise exception 'Permiso insuficiente' using errcode = '42501';
  end if;
  if p_quantity is null or p_quantity <= 0 then
    raise exception 'Cantidad debe ser mayor que cero' using errcode = '22023';
  end if;
  perform 1 from public.products
    where id = p_product_id and tenant_id = p_tenant_id and is_active
    for key share;
  if not found then raise exception 'Producto no encontrado o inactivo'; end if;
  perform 1 from public.warehouses
    where id = p_warehouse_id and tenant_id = p_tenant_id and is_active
    for key share;
  if not found then raise exception 'Almacén no encontrado o inactivo'; end if;

  -- Bloquea todos los lotes elegibles en orden FEFO para serializar las salidas.
  for v_lot in
    select id, quantity_available, unit_cost, expires_on
    from public.lots
    where tenant_id = p_tenant_id and product_id = p_product_id
      and warehouse_id = p_warehouse_id and quantity_available > 0
      and (expires_on is null or expires_on >= current_date)
    order by expires_on asc nulls last, received_on asc, id asc
    for update
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, v_lot.quantity_available);
    update public.lots set quantity_available = quantity_available - v_take
      where id = v_lot.id and tenant_id = p_tenant_id;
    insert into public.stock_movements(tenant_id, lot_id, movement_type, quantity,
      unit_cost, reason, reference, created_by)
    values(p_tenant_id, v_lot.id, 'sale', v_take, v_lot.unit_cost, v_reason, p_reference, v_user_id);
    v_allocations := v_allocations || jsonb_build_array(jsonb_build_object(
      'lot_id', v_lot.id, 'quantity', v_take, 'unit_cost', v_lot.unit_cost,
      'expires_on', v_lot.expires_on
    ));
    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0 then
    raise exception 'Stock insuficiente o disponible solo en lotes caducados' using errcode = '23514';
  end if;
  insert into public.audit_events(tenant_id, actor_id, action, entity_type, details)
  values(p_tenant_id, v_user_id, 'stock_consumed_fefo', 'product',
    jsonb_build_object('product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'quantity', p_quantity, 'allocations', v_allocations, 'reference', p_reference));
  return jsonb_build_object('product_id', p_product_id, 'quantity', p_quantity,
    'allocation_method', 'FEFO', 'allocations', v_allocations);
end;
$$;

-- RPC: merma. La actualización de stock, movimiento, merma y auditoría son atómicos.
create or replace function public.record_waste(
  p_tenant_id uuid,
  p_lot_id uuid,
  p_quantity numeric,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_available numeric;
  v_unit_cost numeric;
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_loss numeric;
  v_waste_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null or not public.has_tenant_role(
    p_tenant_id, array['owner','admin','manager','operator']::public.tenant_role[]
  ) then
    raise exception 'Permiso insuficiente' using errcode = '42501';
  end if;
  if v_reason is null or p_quantity is null or p_quantity <= 0 then
    raise exception 'Datos de merma no válidos' using errcode = '22023';
  end if;
  select quantity_available, unit_cost into v_available, v_unit_cost
    from public.lots where id = p_lot_id and tenant_id = p_tenant_id for update;
  if not found then raise exception 'Lote no encontrado'; end if;
  if p_quantity > v_available then raise exception 'Stock insuficiente' using errcode = '23514'; end if;
  v_loss := round(p_quantity * v_unit_cost, 2);
  update public.lots set quantity_available = quantity_available - p_quantity
    where id = p_lot_id and tenant_id = p_tenant_id;
  insert into public.stock_movements(tenant_id, lot_id, movement_type, quantity,
    unit_cost, reason, created_by)
  values(p_tenant_id, p_lot_id, 'waste', p_quantity, v_unit_cost, v_reason, v_user_id);
  insert into public.waste_records(tenant_id, lot_id, quantity, reason, estimated_loss, recorded_by)
  values(p_tenant_id, p_lot_id, p_quantity, v_reason, v_loss, v_user_id)
  returning id into v_waste_id;
  insert into public.audit_events(tenant_id, actor_id, action, entity_type, entity_id, details)
  values(p_tenant_id, v_user_id, 'waste_recorded', 'waste_record', v_waste_id,
    jsonb_build_object('lot_id', p_lot_id, 'quantity', p_quantity, 'estimated_loss', v_loss));
  return v_waste_id;
end;
$$;

-- Las RPC son el único canal de escritura de cantidades y movimientos.
revoke all on function public.receive_lot(uuid,uuid,uuid,numeric,numeric,date,text,text) from public, anon;
revoke all on function public.consume_stock_fefo(uuid,uuid,uuid,numeric,text,text) from public, anon;
revoke all on function public.record_waste(uuid,uuid,numeric,text) from public, anon;
grant execute on function public.receive_lot(uuid,uuid,uuid,numeric,numeric,date,text,text) to authenticated;
grant execute on function public.consume_stock_fefo(uuid,uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.record_waste(uuid,uuid,numeric,text) to authenticated;

commit;
