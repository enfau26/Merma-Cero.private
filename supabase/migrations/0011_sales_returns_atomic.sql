-- MERMA CERO · Entrega 10 · Devoluciones atómicas con reposición trazable
-- Aplicar únicamente después de validar las migraciones 0001, 0007, 0008, 0009 y 0010
-- en un proyecto Supabase aislado de pruebas. No aplicar directamente en producción.

create table if not exists public.sale_returns (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  sale_id uuid not null,
  return_number text not null,
  refund_total numeric(14,2) not null check (refund_total >= 0),
  reason text not null,
  notes text,
  returned_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, return_number),
  foreign key (tenant_id, sale_id) references public.sales(tenant_id, id)
);

create table if not exists public.sale_return_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  return_id uuid not null,
  sale_item_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0),
  refund_amount numeric(14,2) not null check (refund_amount >= 0),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, return_id) references public.sale_returns(tenant_id, id) on delete cascade,
  foreign key (tenant_id, sale_item_id) references public.sale_items(tenant_id, id)
);

create table if not exists public.sale_return_lot_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  return_item_id uuid not null,
  lot_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,4) not null check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, return_item_id) references public.sale_return_items(tenant_id, id) on delete cascade,
  foreign key (tenant_id, lot_id) references public.lots(tenant_id, id)
);

create table if not exists public.sale_return_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  return_id uuid not null,
  method text not null check (method in ('cash','card','transfer','other')),
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now(),
  foreign key (tenant_id, return_id) references public.sale_returns(tenant_id, id) on delete cascade
);

create index if not exists sale_returns_tenant_sale_idx
  on public.sale_returns(tenant_id, sale_id, returned_at desc);
create index if not exists sale_return_items_sale_item_idx
  on public.sale_return_items(tenant_id, sale_item_id);

alter table public.sale_returns enable row level security;
alter table public.sale_return_items enable row level security;
alter table public.sale_return_lot_allocations enable row level security;
alter table public.sale_return_payments enable row level security;

create policy sale_returns_select_member on public.sale_returns
  for select using (public.is_tenant_member(tenant_id));
create policy sale_return_items_select_member on public.sale_return_items
  for select using (public.is_tenant_member(tenant_id));
create policy sale_return_allocations_select_member on public.sale_return_lot_allocations
  for select using (public.is_tenant_member(tenant_id));
create policy sale_return_payments_select_member on public.sale_return_payments
  for select using (public.is_tenant_member(tenant_id));

revoke insert, update, delete on public.sale_returns, public.sale_return_items,
  public.sale_return_lot_allocations, public.sale_return_payments from authenticated;
grant select on public.sale_returns, public.sale_return_items,
  public.sale_return_lot_allocations, public.sale_return_payments to authenticated;

create or replace function public.create_sale_return_atomic(
  p_tenant_id uuid,
  p_sale_id uuid,
  p_return_number text,
  p_lines jsonb,
  p_payments jsonb,
  p_reason text,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_sale public.sales%rowtype;
  v_sale_item public.sale_items%rowtype;
  v_original_alloc public.sale_item_lot_allocations%rowtype;
  v_lot public.lots%rowtype;
  v_line jsonb;
  v_payment jsonb;
  v_return_id uuid;
  v_return_item_id uuid;
  v_requested numeric(14,3);
  v_already_returned numeric(14,3);
  v_remaining numeric(14,3);
  v_take numeric(14,3);
  v_refund numeric(14,2);
  v_refund_total numeric(14,2) := 0;
  v_paid numeric(14,2) := 0;
  v_method text;
  v_seen uuid[] := '{}';
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.has_tenant_role(p_tenant_id,
    array['owner','admin','manager','operator']::public.tenant_role[]) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode = '42501';
  end if;
  if nullif(trim(p_return_number),'') is null or nullif(trim(p_reason),'') is null then
    raise exception 'RETURN_NUMBER_AND_REASON_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) < 1 or jsonb_array_length(p_lines) > 200 then
    raise exception 'INVALID_RETURN_LINES' using errcode = '22023';
  end if;
  if jsonb_typeof(p_payments) is distinct from 'array'
     or jsonb_array_length(p_payments) < 1 or jsonb_array_length(p_payments) > 10 then
    raise exception 'INVALID_RETURN_PAYMENTS' using errcode = '22023';
  end if;

  select * into v_sale from public.sales
   where id = p_sale_id and tenant_id = p_tenant_id for update;
  if not found then raise exception 'SALE_NOT_FOUND' using errcode = 'P0002'; end if;
  if v_sale.status <> 'completed' then
    raise exception 'SALE_NOT_RETURNABLE' using errcode = '22023';
  end if;

  -- Prevalidación de cantidades y cálculo proporcional del reembolso.
  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_line->>'sale_item_id','') is null
       or nullif(v_line->>'quantity','') is null then
      raise exception 'RETURN_LINE_FIELDS_REQUIRED' using errcode = '22023';
    end if;
    if (v_line->>'sale_item_id')::uuid = any(v_seen) then
      raise exception 'DUPLICATE_RETURN_LINE' using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, (v_line->>'sale_item_id')::uuid);
    v_requested := (v_line->>'quantity')::numeric;
    if v_requested <= 0 then raise exception 'INVALID_RETURN_QUANTITY' using errcode = '22023'; end if;

    select * into v_sale_item from public.sale_items
      where id = (v_line->>'sale_item_id')::uuid
        and tenant_id = p_tenant_id and sale_id = p_sale_id for update;
    if not found then raise exception 'SALE_ITEM_NOT_FOUND' using errcode = 'P0002'; end if;

    select coalesce(sum(ri.quantity),0) into v_already_returned
      from public.sale_return_items ri
      join public.sale_returns r on r.id = ri.return_id and r.tenant_id = ri.tenant_id
      where ri.tenant_id = p_tenant_id and ri.sale_item_id = v_sale_item.id;
    if v_already_returned + v_requested > v_sale_item.quantity then
      raise exception 'RETURN_QUANTITY_EXCEEDS_REMAINING' using errcode = '22023';
    end if;
    v_refund := round(v_sale_item.line_total * v_requested / v_sale_item.quantity, 2);
    v_refund_total := v_refund_total + v_refund;
  end loop;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    v_method := v_payment->>'method';
    if v_method is null or v_method not in ('cash','card','transfer','other')
       or nullif(v_payment->>'amount','') is null
       or (v_payment->>'amount')::numeric <= 0 then
      raise exception 'INVALID_RETURN_PAYMENT' using errcode = '22023';
    end if;
    v_paid := v_paid + (v_payment->>'amount')::numeric;
  end loop;
  if round(v_paid,2) <> round(v_refund_total,2) then
    raise exception 'RETURN_PAYMENT_TOTAL_MISMATCH' using errcode = '22023';
  end if;

  insert into public.sale_returns(tenant_id,sale_id,return_number,refund_total,reason,notes,created_by)
  values (p_tenant_id,p_sale_id,trim(p_return_number),v_refund_total,trim(p_reason),p_notes,v_actor)
  returning id into v_return_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_requested := (v_line->>'quantity')::numeric;
    select * into v_sale_item from public.sale_items
      where id = (v_line->>'sale_item_id')::uuid
        and tenant_id = p_tenant_id and sale_id = p_sale_id for update;
    v_refund := round(v_sale_item.line_total * v_requested / v_sale_item.quantity, 2);

    insert into public.sale_return_items(tenant_id,return_id,sale_item_id,quantity,refund_amount)
    values (p_tenant_id,v_return_id,v_sale_item.id,v_requested,v_refund)
    returning id into v_return_item_id;

    v_remaining := v_requested;
    -- Reponer en los mismos lotes que originaron la venta para conservar trazabilidad.
    for v_original_alloc in
      select a.* from public.sale_item_lot_allocations a
      where a.tenant_id = p_tenant_id and a.sale_item_id = v_sale_item.id
      order by a.created_at, a.id
    loop
      exit when v_remaining <= 0;
      select * into v_lot from public.lots
       where id = v_original_alloc.lot_id and tenant_id = p_tenant_id for update;
      v_already_returned := coalesce((
        select sum(ra.quantity)
        from public.sale_return_lot_allocations ra
        join public.sale_return_items ri on ri.id = ra.return_item_id and ri.tenant_id = ra.tenant_id
        where ra.tenant_id = p_tenant_id and ra.lot_id = v_lot.id
          and ri.sale_item_id = v_sale_item.id
      ),0);
      v_take := least(v_remaining, greatest(v_original_alloc.quantity - v_already_returned,0));
      if v_take > 0 then
        update public.lots set quantity_available = quantity_available + v_take
         where id = v_lot.id and tenant_id = p_tenant_id;
        insert into public.sale_return_lot_allocations(tenant_id,return_item_id,lot_id,quantity,unit_cost)
        values (p_tenant_id,v_return_item_id,v_lot.id,v_take,v_original_alloc.unit_cost);
        insert into public.stock_movements(tenant_id,lot_id,movement_type,quantity,unit_cost,
          reason,reference,created_by)
        values (p_tenant_id,v_lot.id,'return',v_take,v_original_alloc.unit_cost,
          'Devolución de venta',v_return_id::text,v_actor);
        v_remaining := v_remaining - v_take;
      end if;
    end loop;
    if v_remaining > 0 then
      raise exception 'RETURN_ALLOCATION_EXCEEDS_SOLD_LOT_QUANTITY' using errcode = '22023';
    end if;
  end loop;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    insert into public.sale_return_payments(tenant_id,return_id,method,amount,reference)
    values (p_tenant_id,v_return_id,v_payment->>'method',
      (v_payment->>'amount')::numeric,nullif(trim(v_payment->>'reference'),''));
  end loop;

  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values (p_tenant_id,v_actor,'sale.returned','sale_return',v_return_id,
    jsonb_build_object('sale_id',p_sale_id,'return_number',trim(p_return_number),
      'refund_total',v_refund_total,'reason',trim(p_reason)));
  return v_return_id;
end;
$$;

revoke all on function public.create_sale_return_atomic(uuid,uuid,text,jsonb,jsonb,text,text) from public;
grant execute on function public.create_sale_return_atomic(uuid,uuid,text,jsonb,jsonb,text,text) to authenticated;

comment on function public.create_sale_return_atomic(uuid,uuid,text,jsonb,jsonb,text,text)
is 'Registra devoluciones parciales o completas, reembolsa mediante pagos declarados, repone los lotes originales y audita en una transacción.';
