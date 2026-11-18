-- MERMA CERO · Entrega 09 · Ventas atómicas con descuento FEFO
-- Ejecutar solo después de validar Entregas 01–08 en un proyecto de pruebas.
-- No emite comprobantes fiscales; la localización tributaria ES/PE queda pendiente.

create table if not exists public.sales (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  warehouse_id uuid not null,
  sale_number text not null,
  currency_code char(3) not null,
  status text not null default 'completed' check (status in ('completed','voided')),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  tax_total numeric(14,2) not null check (tax_total >= 0),
  discount_total numeric(14,2) not null default 0 check (discount_total >= 0),
  total numeric(14,2) not null check (total >= 0),
  notes text,
  sold_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, sale_number),
  foreign key (tenant_id, warehouse_id) references public.warehouses(tenant_id, id)
);

create table if not exists public.sale_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  sale_id uuid not null,
  product_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,4) not null check (unit_price >= 0),
  tax_rate numeric(7,4) not null default 0 check (tax_rate >= 0 and tax_rate <= 100),
  discount_amount numeric(14,2) not null default 0 check (discount_amount >= 0),
  line_subtotal numeric(14,2) not null check (line_subtotal >= 0),
  line_tax numeric(14,2) not null check (line_tax >= 0),
  line_total numeric(14,2) not null check (line_total >= 0),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, sale_id) references public.sales(tenant_id, id) on delete cascade,
  foreign key (tenant_id, product_id) references public.products(tenant_id, id)
);

create table if not exists public.sale_item_lot_allocations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  sale_item_id uuid not null,
  lot_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,4) not null check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, sale_item_id) references public.sale_items(tenant_id, id) on delete cascade,
  foreign key (tenant_id, lot_id) references public.lots(tenant_id, id)
);

create table if not exists public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null,
  sale_id uuid not null,
  method text not null check (method in ('cash','card','transfer','other')),
  amount numeric(14,2) not null check (amount > 0),
  reference text,
  created_at timestamptz not null default now(),
  foreign key (tenant_id, sale_id) references public.sales(tenant_id, id) on delete cascade
);

create index if not exists sales_tenant_sold_at_idx on public.sales(tenant_id, sold_at desc);
create index if not exists sale_items_tenant_sale_idx on public.sale_items(tenant_id, sale_id);
create index if not exists sale_allocations_tenant_lot_idx on public.sale_item_lot_allocations(tenant_id, lot_id);

alter table public.sales enable row level security;
alter table public.sale_items enable row level security;
alter table public.sale_item_lot_allocations enable row level security;
alter table public.sale_payments enable row level security;

create policy sales_select_member on public.sales for select using (public.is_tenant_member(tenant_id));
create policy sale_items_select_member on public.sale_items for select using (public.is_tenant_member(tenant_id));
create policy sale_allocations_select_member on public.sale_item_lot_allocations for select using (public.is_tenant_member(tenant_id));
create policy sale_payments_select_member on public.sale_payments for select using (public.is_tenant_member(tenant_id));

revoke insert, update, delete on public.sales, public.sale_items,
  public.sale_item_lot_allocations, public.sale_payments from authenticated;
grant select on public.sales, public.sale_items,
  public.sale_item_lot_allocations, public.sale_payments to authenticated;

create or replace function public.create_sale_atomic(
  p_tenant_id uuid,
  p_warehouse_id uuid,
  p_sale_number text,
  p_lines jsonb,
  p_payments jsonb,
  p_notes text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_currency char(3);
  v_sale_id uuid;
  v_sale_item_id uuid;
  v_line jsonb;
  v_payment jsonb;
  v_product public.products%rowtype;
  v_lot public.lots%rowtype;
  v_qty numeric(14,3);
  v_remaining numeric(14,3);
  v_take numeric(14,3);
  v_price numeric(14,4);
  v_tax_rate numeric(7,4);
  v_discount numeric(14,2);
  v_subtotal numeric(14,2) := 0;
  v_tax_total numeric(14,2) := 0;
  v_discount_total numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_line_base numeric(14,2);
  v_line_tax numeric(14,2);
  v_line_total numeric(14,2);
  v_paid numeric(14,2) := 0;
  v_method text;
  v_seen uuid[] := '{}';
  v_line_count integer := 0;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.has_tenant_role(p_tenant_id,
    array['owner','admin','manager','operator']::public.tenant_role[]) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode = '42501';
  end if;
  if p_sale_number is null or length(trim(p_sale_number)) = 0 then
    raise exception 'SALE_NUMBER_REQUIRED' using errcode = '22023';
  end if;
  if jsonb_typeof(p_lines) is distinct from 'array'
     or jsonb_array_length(p_lines) < 1
     or jsonb_array_length(p_lines) > 200 then
    raise exception 'INVALID_SALE_LINES' using errcode = '22023';
  end if;
  if jsonb_typeof(p_payments) is distinct from 'array'
     or jsonb_array_length(p_payments) < 1
     or jsonb_array_length(p_payments) > 10 then
    raise exception 'INVALID_SALE_PAYMENTS' using errcode = '22023';
  end if;

  select t.currency_code into v_currency
  from public.tenants t where t.id = p_tenant_id;
  if not found then raise exception 'TENANT_NOT_FOUND' using errcode = 'P0002'; end if;
  if not exists (select 1 from public.warehouses w where w.id = p_warehouse_id
    and w.tenant_id = p_tenant_id and w.is_active) then
    raise exception 'WAREHOUSE_NOT_FOUND_OR_INACTIVE' using errcode = '22023';
  end if;

  -- Prevalidar y calcular importes antes de insertar. La función completa es atómica.
  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    if nullif(v_line->>'product_id','') is null
       or nullif(v_line->>'quantity','') is null
       or nullif(v_line->>'unit_price','') is null then
      raise exception 'SALE_LINE_FIELDS_REQUIRED' using errcode = '22023';
    end if;
    if (v_line->>'product_id')::uuid = any(v_seen) then
      raise exception 'DUPLICATE_SALE_PRODUCT_LINE' using errcode = '22023';
    end if;
    v_seen := array_append(v_seen, (v_line->>'product_id')::uuid);
    v_qty := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    v_tax_rate := coalesce(nullif(v_line->>'tax_rate','')::numeric,0);
    v_discount := coalesce(nullif(v_line->>'discount_amount','')::numeric,0);
    if v_qty <= 0 or v_price < 0 or v_tax_rate < 0 or v_tax_rate > 100 or v_discount < 0 then
      raise exception 'INVALID_SALE_LINE_VALUES' using errcode = '22023';
    end if;
    select * into v_product from public.products p
      where p.id = (v_line->>'product_id')::uuid and p.tenant_id = p_tenant_id and p.is_active;
    if not found then raise exception 'PRODUCT_NOT_FOUND_OR_INACTIVE' using errcode = 'P0002'; end if;
    v_line_base := round(v_qty * v_price - v_discount, 2);
    if v_line_base < 0 then raise exception 'DISCOUNT_EXCEEDS_LINE_AMOUNT' using errcode = '22023'; end if;
    v_line_tax := round(v_line_base * v_tax_rate / 100, 2);
    v_subtotal := v_subtotal + v_line_base;
    v_tax_total := v_tax_total + v_line_tax;
    v_discount_total := v_discount_total + v_discount;
    v_total := v_total + v_line_base + v_line_tax;
    v_line_count := v_line_count + 1;
  end loop;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    v_method := v_payment->>'method';
    if v_method is null
       or v_method not in ('cash','card','transfer','other')
       or nullif(v_payment->>'amount','') is null
       or (v_payment->>'amount')::numeric <= 0 then
      raise exception 'INVALID_PAYMENT' using errcode = '22023';
    end if;
    v_paid := v_paid + (v_payment->>'amount')::numeric;
  end loop;
  if round(v_paid,2) <> round(v_total,2) then
    raise exception 'PAYMENT_TOTAL_MISMATCH' using errcode = '22023';
  end if;

  insert into public.sales(tenant_id,warehouse_id,sale_number,currency_code,
    subtotal,tax_total,discount_total,total,notes,created_by)
  values (p_tenant_id,p_warehouse_id,trim(p_sale_number),v_currency,
    v_subtotal,v_tax_total,v_discount_total,v_total,p_notes,v_actor)
  returning id into v_sale_id;

  for v_line in select value from jsonb_array_elements(p_lines)
  loop
    v_qty := (v_line->>'quantity')::numeric;
    v_price := (v_line->>'unit_price')::numeric;
    v_tax_rate := coalesce(nullif(v_line->>'tax_rate','')::numeric,0);
    v_discount := coalesce(nullif(v_line->>'discount_amount','')::numeric,0);
    v_line_base := round(v_qty * v_price - v_discount, 2);
    v_line_tax := round(v_line_base * v_tax_rate / 100, 2);
    v_line_total := v_line_base + v_line_tax;

    insert into public.sale_items(tenant_id,sale_id,product_id,quantity,unit_price,
      tax_rate,discount_amount,line_subtotal,line_tax,line_total)
    values (p_tenant_id,v_sale_id,(v_line->>'product_id')::uuid,v_qty,v_price,
      v_tax_rate,v_discount,v_line_base,v_line_tax,v_line_total)
    returning id into v_sale_item_id;

    v_remaining := v_qty;
    -- FEFO: caduca antes primero; sin caducidad al final. Bloqueo por lote evita
    -- que dos cajas consuman simultáneamente las mismas unidades.
    for v_lot in
      select l.* from public.lots l
      where l.tenant_id = p_tenant_id
        and l.product_id = (v_line->>'product_id')::uuid
        and l.warehouse_id = p_warehouse_id
        and l.quantity_available > 0
      order by l.expires_on asc nulls last, l.received_on asc, l.id asc
      for update
    loop
      exit when v_remaining <= 0;
      v_take := least(v_remaining, v_lot.quantity_available);
      update public.lots set quantity_available = quantity_available - v_take
        where id = v_lot.id and tenant_id = p_tenant_id;
      insert into public.sale_item_lot_allocations(tenant_id,sale_item_id,lot_id,quantity,unit_cost)
      values (p_tenant_id,v_sale_item_id,v_lot.id,v_take,v_lot.unit_cost);
      insert into public.stock_movements(tenant_id,lot_id,movement_type,quantity,unit_cost,
        reason,reference,created_by)
      values (p_tenant_id,v_lot.id,'sale',v_take,v_lot.unit_cost,
        'Venta TPV',v_sale_id::text,v_actor);
      v_remaining := v_remaining - v_take;
    end loop;
    if v_remaining > 0 then
      raise exception 'INSUFFICIENT_STOCK' using errcode = '22023';
    end if;
  end loop;

  for v_payment in select value from jsonb_array_elements(p_payments)
  loop
    insert into public.sale_payments(tenant_id,sale_id,method,amount,reference)
    values (p_tenant_id,v_sale_id,v_payment->>'method',
      (v_payment->>'amount')::numeric,nullif(trim(v_payment->>'reference'),''));
  end loop;

  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values (p_tenant_id,v_actor,'sale.completed','sale',v_sale_id,
    jsonb_build_object('sale_number',trim(p_sale_number),'line_count',v_line_count,
      'subtotal',v_subtotal,'tax_total',v_tax_total,'discount_total',v_discount_total,
      'total',v_total,'currency_code',v_currency));
  return v_sale_id;
end;
$$;

revoke all on function public.create_sale_atomic(uuid,uuid,text,jsonb,jsonb,text) from public;
grant execute on function public.create_sale_atomic(uuid,uuid,text,jsonb,jsonb,text) to authenticated;

comment on function public.create_sale_atomic(uuid,uuid,text,jsonb,jsonb,text)
is 'Crea una venta y sus pagos de forma atómica, descuenta lotes FEFO y registra movimientos y auditoría.';
