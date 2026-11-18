-- MERMA CERO · Entrega 08 · Corrección de cierre por línea y auditoría de recepción
-- Aplicar después de 0008_atomic_goods_receipts.sql. Reemplaza la RPC existente.
-- Las recepciones solo se registran mediante esta RPC: orden, recepción,
-- lotes, movimientos de stock y auditoría se confirman en una transacción.

-- Elimina las vías directas que permitirían crear recepciones sin actualizar stock.
drop policy if exists goods_receipts_insert_operator on public.goods_receipts;
drop policy if exists goods_receipt_items_insert_operator on public.goods_receipt_items;
revoke insert, update, delete on public.goods_receipts, public.goods_receipt_items from authenticated;
grant select on public.goods_receipts, public.goods_receipt_items to authenticated;

create or replace function public.receive_purchase_order_atomic(
  p_tenant_id uuid,
  p_purchase_order_id uuid,
  p_warehouse_id uuid,
  p_receipt_number text,
  p_lines jsonb,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_order public.purchase_orders%rowtype;
  v_line jsonb;
  v_item public.purchase_order_items%rowtype;
  v_receipt_id uuid;
  v_receipt_item_id uuid;
  v_received numeric(14,3);
  v_accepted numeric(14,3);
  v_rejected numeric(14,3);
  v_previously_accepted numeric(14,3);
  v_lot_id uuid;
  v_lot_code text;
  v_expiry date;
  v_reason text;
  v_seen uuid[] := '{}';
  v_ordered_total numeric(14,3);
  v_accepted_total numeric(14,3);
  v_receipt_accepted_total numeric(14,3) := 0;
  v_currency char(3);
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not public.has_tenant_role(
    p_tenant_id,
    array['owner','admin','manager','operator']::public.tenant_role[]
  ) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode = '42501';
  end if;

  if p_receipt_number is null or length(trim(p_receipt_number)) = 0 then
    raise exception 'RECEIPT_NUMBER_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) < 1
     or jsonb_array_length(p_lines) > 200 then
    raise exception 'INVALID_RECEIPT_LINES' using errcode = '22023';
  end if;

  -- Bloquea la orden para serializar recepciones concurrentes de la misma orden.
  select * into v_order
  from public.purchase_orders
  where id = p_purchase_order_id and tenant_id = p_tenant_id
  for update;
  if not found then
    raise exception 'PURCHASE_ORDER_NOT_FOUND' using errcode = 'P0002';
  end if;
  if v_order.status not in ('submitted','partially_received') then
    raise exception 'PURCHASE_ORDER_NOT_RECEIVABLE' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.warehouses w
    where w.id = p_warehouse_id and w.tenant_id = p_tenant_id and w.is_active
  ) then
    raise exception 'WAREHOUSE_NOT_FOUND_OR_INACTIVE' using errcode = '22023';
  end if;

  -- Prevalidación completa antes de crear registros; cualquier excepción revierte todo.
  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_line->>'purchase_order_item_id','') is null then
      raise exception 'PURCHASE_ORDER_ITEM_REQUIRED' using errcode = '22023';
    end if;
    if (v_line->>'purchase_order_item_id')::uuid = any(v_seen) then
      raise exception 'DUPLICATE_PURCHASE_ORDER_ITEM' using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, (v_line->>'purchase_order_item_id')::uuid);

    select * into v_item
    from public.purchase_order_items poi
    where poi.id = (v_line->>'purchase_order_item_id')::uuid
      and poi.tenant_id = p_tenant_id
      and poi.purchase_order_id = p_purchase_order_id
    for update;
    if not found then
      raise exception 'PURCHASE_ORDER_ITEM_NOT_FOUND' using errcode = 'P0002';
    end if;

    if nullif(v_line->>'quantity_received','') is null
       or nullif(v_line->>'quantity_accepted','') is null then
      raise exception 'RECEIPT_QUANTITIES_REQUIRED' using errcode = '22023';
    end if;
    v_received := (v_line->>'quantity_received')::numeric;
    v_accepted := (v_line->>'quantity_accepted')::numeric;
    v_rejected := coalesce(nullif(v_line->>'quantity_rejected','')::numeric, 0);
    v_reason := nullif(trim(v_line->>'rejection_reason'), '');

    if v_received <= 0 or v_accepted < 0 or v_rejected < 0
       or v_received <> v_accepted + v_rejected then
      raise exception 'INVALID_RECEIPT_QUANTITIES' using errcode = '22023';
    end if;
    if v_rejected > 0 and v_reason is null then
      raise exception 'REJECTION_REASON_REQUIRED' using errcode = '22023';
    end if;

    select coalesce(sum(gri.quantity_accepted),0)
      into v_previously_accepted
    from public.goods_receipt_items gri
    join public.goods_receipts gr
      on gr.id = gri.goods_receipt_id and gr.tenant_id = gri.tenant_id
    where gri.tenant_id = p_tenant_id
      and gri.purchase_order_item_id = v_item.id
      and gr.status = 'posted';

    if v_previously_accepted + v_accepted > v_item.quantity_ordered then
      raise exception 'ACCEPTED_QUANTITY_EXCEEDS_ORDERED' using errcode = '22023';
    end if;
  end loop;

  insert into public.goods_receipts(
    tenant_id, purchase_order_id, receipt_number, warehouse_id, notes, created_by
  ) values (
    p_tenant_id, p_purchase_order_id, trim(p_receipt_number), p_warehouse_id,
    p_notes, v_actor
  ) returning id into v_receipt_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    select * into v_item
    from public.purchase_order_items poi
    where poi.id = (v_line->>'purchase_order_item_id')::uuid
      and poi.tenant_id = p_tenant_id
      and poi.purchase_order_id = p_purchase_order_id;

    v_received := (v_line->>'quantity_received')::numeric;
    v_accepted := (v_line->>'quantity_accepted')::numeric;
    v_rejected := coalesce(nullif(v_line->>'quantity_rejected','')::numeric, 0);
    v_receipt_accepted_total := v_receipt_accepted_total + v_accepted;
    v_reason := nullif(trim(v_line->>'rejection_reason'), '');
    v_lot_code := nullif(trim(v_line->>'lot_code'), '');
    v_expiry := nullif(v_line->>'expires_on','')::date;

    insert into public.goods_receipt_items(
      tenant_id, goods_receipt_id, purchase_order_item_id,
      quantity_received, quantity_accepted, quantity_rejected,
      rejection_reason, lot_code, expires_on
    ) values (
      p_tenant_id, v_receipt_id, v_item.id,
      v_received, v_accepted, v_rejected,
      v_reason, v_lot_code, v_expiry
    ) returning id into v_receipt_item_id;

    if v_accepted > 0 then
      insert into public.lots(
        tenant_id, product_id, warehouse_id, lot_code, received_on, expires_on,
        quantity_received, quantity_available, unit_cost, supplier_name
      ) values (
        p_tenant_id, v_item.product_id, p_warehouse_id, v_lot_code, current_date,
        v_expiry, v_accepted, v_accepted, v_item.unit_cost,
        (select s.legal_name from public.suppliers s
         where s.tenant_id = p_tenant_id and s.id = v_order.supplier_id)
      ) returning id into v_lot_id;

      insert into public.stock_movements(
        tenant_id, lot_id, movement_type, quantity, unit_cost,
        reason, reference, created_by
      ) values (
        p_tenant_id, v_lot_id, 'receipt', v_accepted, v_item.unit_cost,
        'Recepción de compra', v_receipt_id::text, v_actor
      );
    end if;
  end loop;

  select coalesce(sum(quantity_ordered),0) into v_ordered_total
  from public.purchase_order_items
  where tenant_id = p_tenant_id and purchase_order_id = p_purchase_order_id;

  select coalesce(sum(gri.quantity_accepted),0) into v_accepted_total
  from public.goods_receipt_items gri
  join public.goods_receipts gr
    on gr.id = gri.goods_receipt_id and gr.tenant_id = gri.tenant_id
  join public.purchase_order_items poi
    on poi.id = gri.purchase_order_item_id and poi.tenant_id = gri.tenant_id
  where gri.tenant_id = p_tenant_id
    and gr.purchase_order_id = p_purchase_order_id
    and gr.status = 'posted';

  -- La orden solo queda recibida cuando CADA línea alcanza su cantidad pedida.
  -- Comparar únicamente los totales globales podía ocultar una línea incompleta.
  update public.purchase_orders
  set status = case when not exists (
        select 1
        from public.purchase_order_items poi
        where poi.tenant_id = p_tenant_id
          and poi.purchase_order_id = p_purchase_order_id
          and coalesce((
            select sum(gri.quantity_accepted)
            from public.goods_receipt_items gri
            join public.goods_receipts gr
              on gr.id = gri.goods_receipt_id and gr.tenant_id = gri.tenant_id
            where gri.tenant_id = p_tenant_id
              and gri.purchase_order_item_id = poi.id
              and gr.status = 'posted'
          ), 0) < poi.quantity_ordered
      ) then 'received' else 'partially_received' end,
      updated_at = now()
  where id = p_purchase_order_id and tenant_id = p_tenant_id;

  insert into public.audit_events(
    tenant_id, actor_id, action, entity_type, entity_id, details
  ) values (
    p_tenant_id, v_actor, 'purchase_order.received', 'goods_receipt',
    v_receipt_id,
    jsonb_build_object(
      'purchase_order_id', p_purchase_order_id,
      'receipt_number', trim(p_receipt_number),
      'line_count', jsonb_array_length(p_lines),
      'accepted_quantity_this_receipt', v_receipt_accepted_total,
      'accepted_quantity_order_total', v_accepted_total
    )
  );

  return v_receipt_id;
end;
$$;

revoke all on function public.receive_purchase_order_atomic(uuid,uuid,uuid,text,jsonb,text) from public;
grant execute on function public.receive_purchase_order_atomic(uuid,uuid,uuid,text,jsonb,text) to authenticated;

comment on function public.receive_purchase_order_atomic(uuid,uuid,uuid,text,jsonb,text)
is 'Registra una recepción de compra de forma atómica: recepción, lotes, movimientos, estado de orden y auditoría.';
