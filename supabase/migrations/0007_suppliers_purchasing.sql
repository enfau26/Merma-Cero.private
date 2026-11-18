-- MERMA CERO · Entrega 07 · Proveedores y compras
-- Versión alineada con el esquema real del starter: tenants / tenant_id.
-- Sustituye al borrador 0007 que usaba companies/company_id.
-- Aplicar SOLO si la migración anterior de proveedores/compras no se ejecutó.

create extension if not exists pgcrypto;

-- Helper de roles: la membresía y el rol se comprueban en PostgreSQL,
-- nunca se aceptan como autoridad desde el navegador.
create or replace function public.has_tenant_role(
  target_tenant uuid,
  allowed_roles public.tenant_role[]
)
returns boolean
language sql stable security definer
set search_path = pg_catalog, public
as $$
  select exists (
    select 1
    from public.tenant_members tm
    where tm.tenant_id = target_tenant
      and tm.user_id = auth.uid()
      and tm.role = any(allowed_roles)
  );
$$;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  code text,
  legal_name text not null check (length(trim(legal_name)) > 0),
  trade_name text,
  tax_id text,
  country_code char(2) not null check (country_code in ('PE','ES')),
  email text,
  phone text,
  address jsonb not null default '{}'::jsonb,
  payment_terms_days integer not null default 0 check (payment_terms_days >= 0),
  currency_code char(3) not null check (currency_code in ('PEN','EUR')),
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (tenant_id, id),
  unique (tenant_id, code)
);

create unique index if not exists suppliers_tenant_tax_id_uq
  on public.suppliers(tenant_id, country_code, tax_id)
  where tax_id is not null and trim(tax_id) <> '';

create table if not exists public.purchase_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  supplier_id uuid not null,
  order_number text not null,
  status text not null default 'draft'
    check (status in ('draft','submitted','partially_received','received','cancelled')),
  order_date date not null default current_date,
  expected_date date,
  currency_code char(3) not null check (currency_code in ('PEN','EUR')),
  subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  tax_total numeric(14,2) not null default 0 check (tax_total >= 0),
  total numeric(14,2) not null default 0 check (total >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (tenant_id, id),
  unique (tenant_id, order_number),
  constraint purchase_orders_supplier_same_tenant_fk
    foreign key (tenant_id, supplier_id)
    references public.suppliers(tenant_id, id)
);

create table if not exists public.purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_order_id uuid not null,
  product_id uuid not null,
  description text,
  quantity_ordered numeric(14,3) not null check (quantity_ordered > 0),
  unit_cost numeric(14,4) not null check (unit_cost >= 0),
  tax_rate numeric(7,4) not null default 0 check (tax_rate between 0 and 100),
  line_subtotal numeric(14,2) not null default 0 check (line_subtotal >= 0),
  line_tax numeric(14,2) not null default 0 check (line_tax >= 0),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  constraint po_items_order_same_tenant_fk
    foreign key (tenant_id, purchase_order_id)
    references public.purchase_orders(tenant_id, id) on delete cascade,
  constraint po_items_product_same_tenant_fk
    foreign key (tenant_id, product_id)
    references public.products(tenant_id, id)
);

create table if not exists public.goods_receipts (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  purchase_order_id uuid not null,
  receipt_number text not null,
  received_at timestamptz not null default now(),
  warehouse_id uuid not null,
  status text not null default 'posted' check (status in ('posted','voided')),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  unique (tenant_id, id),
  unique (tenant_id, receipt_number),
  constraint receipts_order_same_tenant_fk
    foreign key (tenant_id, purchase_order_id)
    references public.purchase_orders(tenant_id, id),
  constraint receipts_warehouse_same_tenant_fk
    foreign key (tenant_id, warehouse_id)
    references public.warehouses(tenant_id, id)
);

create table if not exists public.goods_receipt_items (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  goods_receipt_id uuid not null,
  purchase_order_item_id uuid not null,
  quantity_received numeric(14,3) not null check (quantity_received > 0),
  quantity_accepted numeric(14,3) not null check (quantity_accepted >= 0),
  quantity_rejected numeric(14,3) not null default 0 check (quantity_rejected >= 0),
  rejection_reason text,
  lot_code text,
  expires_on date,
  created_at timestamptz not null default now(),
  constraint receipt_items_receipt_same_tenant_fk
    foreign key (tenant_id, goods_receipt_id)
    references public.goods_receipts(tenant_id, id) on delete cascade,
  constraint receipt_items_po_item_same_tenant_fk
    foreign key (tenant_id, purchase_order_item_id)
    references public.purchase_order_items(tenant_id, id),
  constraint receipt_item_quantity_balance
    check (quantity_received = quantity_accepted + quantity_rejected),
  constraint rejected_quantity_requires_reason
    check (quantity_rejected = 0 or nullif(trim(rejection_reason), '') is not null)
);

create index if not exists suppliers_tenant_name_idx
  on public.suppliers(tenant_id, legal_name);
create index if not exists purchase_orders_tenant_date_idx
  on public.purchase_orders(tenant_id, order_date desc);
create index if not exists purchase_orders_tenant_supplier_idx
  on public.purchase_orders(tenant_id, supplier_id);
create index if not exists goods_receipts_tenant_received_idx
  on public.goods_receipts(tenant_id, received_at desc);

-- RLS: lectura para cualquier miembro; escritura según rol.
alter table public.suppliers enable row level security;
alter table public.purchase_orders enable row level security;
alter table public.purchase_order_items enable row level security;
alter table public.goods_receipts enable row level security;
alter table public.goods_receipt_items enable row level security;

 drop policy if exists suppliers_select_member on public.suppliers;
create policy suppliers_select_member on public.suppliers
  for select to authenticated using (public.is_tenant_member(tenant_id));
drop policy if exists suppliers_write_manager on public.suppliers;
create policy suppliers_write_manager on public.suppliers
  for all to authenticated
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));

drop policy if exists purchase_orders_select_member on public.purchase_orders;
create policy purchase_orders_select_member on public.purchase_orders
  for select to authenticated using (public.is_tenant_member(tenant_id));
drop policy if exists purchase_orders_write_manager on public.purchase_orders;
create policy purchase_orders_write_manager on public.purchase_orders
  for all to authenticated
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));

drop policy if exists purchase_order_items_select_member on public.purchase_order_items;
create policy purchase_order_items_select_member on public.purchase_order_items
  for select to authenticated using (public.is_tenant_member(tenant_id));
drop policy if exists purchase_order_items_write_manager on public.purchase_order_items;
create policy purchase_order_items_write_manager on public.purchase_order_items
  for all to authenticated
  using (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]))
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager']::public.tenant_role[]));

drop policy if exists goods_receipts_select_member on public.goods_receipts;
create policy goods_receipts_select_member on public.goods_receipts
  for select to authenticated using (public.is_tenant_member(tenant_id));
drop policy if exists goods_receipts_insert_operator on public.goods_receipts;
create policy goods_receipts_insert_operator on public.goods_receipts
  for insert to authenticated
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager','operator']::public.tenant_role[]));

drop policy if exists goods_receipt_items_select_member on public.goods_receipt_items;
create policy goods_receipt_items_select_member on public.goods_receipt_items
  for select to authenticated using (public.is_tenant_member(tenant_id));
drop policy if exists goods_receipt_items_insert_operator on public.goods_receipt_items;
create policy goods_receipt_items_insert_operator on public.goods_receipt_items
  for insert to authenticated
  with check (public.has_tenant_role(tenant_id, array['owner','admin','manager','operator']::public.tenant_role[]));

-- No se concede DELETE. La actualización directa de recepciones tampoco se permite:
-- las operaciones de stock deben entrar mediante RPC transaccional auditada.
revoke delete, update on public.goods_receipts, public.goods_receipt_items from authenticated;
revoke delete on public.suppliers, public.purchase_orders,
  public.purchase_order_items from authenticated;

grant select on public.suppliers, public.purchase_orders,
  public.purchase_order_items, public.goods_receipts,
  public.goods_receipt_items to authenticated;
grant insert, update on public.suppliers, public.purchase_orders,
  public.purchase_order_items to authenticated;
grant insert on public.goods_receipts, public.goods_receipt_items to authenticated;

comment on table public.suppliers is 'Proveedores aislados por tenant_id.';
comment on table public.purchase_orders is 'Órdenes de compra multiempresa; transiciones mediante RPC transaccionales.';
comment on table public.goods_receipts is 'Recepciones; no deben modificar existencias fuera de una RPC transaccional.';
