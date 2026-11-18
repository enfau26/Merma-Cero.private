-- MERMA CERO core schema — PostgreSQL / Supabase
create extension if not exists pgcrypto;

create type public.tenant_role as enum ('owner','admin','manager','operator','viewer');
create type public.stock_movement_type as enum
  ('receipt','sale','waste','adjustment_in','adjustment_out','return','transfer_in','transfer_out');

create table public.tenants (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  country_code char(2) not null check (country_code in ('PE','ES')),
  currency_code char(3) not null check (currency_code in ('PEN','EUR')),
  timezone text not null default 'Europe/Madrid',
  created_at timestamptz not null default now()
);

create table public.tenant_members (
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.tenant_role not null default 'operator',
  created_at timestamptz not null default now(),
  primary key (tenant_id, user_id)
);

create table public.warehouses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  unique (tenant_id, name),
  unique (tenant_id, id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  category_id uuid,
  sku text,
  barcode text,
  name text not null,
  unit text not null default 'unidad',
  is_perishable boolean not null default true,
  min_stock numeric(14,3) not null default 0 check (min_stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  unique (tenant_id, sku),
  foreign key (tenant_id, category_id) references public.categories(tenant_id, id)
);

create table public.lots (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  product_id uuid not null,
  warehouse_id uuid not null,
  lot_code text,
  received_on date not null default current_date,
  expires_on date,
  quantity_received numeric(14,3) not null check (quantity_received > 0),
  quantity_available numeric(14,3) not null check (quantity_available >= 0),
  unit_cost numeric(14,4) not null default 0 check (unit_cost >= 0),
  supplier_name text,
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, product_id) references public.products(tenant_id, id),
  foreign key (tenant_id, warehouse_id) references public.warehouses(tenant_id, id),
  check (quantity_available <= quantity_received)
);

create index lots_fefo_idx on public.lots
  (tenant_id, product_id, warehouse_id, expires_on, received_on)
  where quantity_available > 0;

create table public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  lot_id uuid not null,
  movement_type public.stock_movement_type not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,4) not null default 0 check (unit_cost >= 0),
  reason text,
  reference text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, lot_id) references public.lots(tenant_id, id)
);

create table public.waste_records (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  lot_id uuid not null,
  quantity numeric(14,3) not null check (quantity > 0),
  reason text not null,
  estimated_loss numeric(14,2) not null check (estimated_loss >= 0),
  recorded_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (tenant_id, lot_id) references public.lots(tenant_id, id)
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Helper: user must be a member of the tenant.
create or replace function public.is_tenant_member(target_tenant uuid)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tenant_members tm
    where tm.tenant_id = target_tenant and tm.user_id = auth.uid()
  );
$$;

alter table public.tenants enable row level security;
alter table public.tenant_members enable row level security;
alter table public.warehouses enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.lots enable row level security;
alter table public.stock_movements enable row level security;
alter table public.waste_records enable row level security;
alter table public.audit_events enable row level security;

create policy "members read own tenants" on public.tenants
for select using (public.is_tenant_member(id));

create policy "members read membership" on public.tenant_members
for select using (public.is_tenant_member(tenant_id));

create policy "tenant isolation warehouses" on public.warehouses
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation categories" on public.categories
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation products" on public.products
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation lots" on public.lots
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation movements" on public.stock_movements
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation waste" on public.waste_records
for all using (public.is_tenant_member(tenant_id))
with check (public.is_tenant_member(tenant_id));

create policy "tenant isolation audit" on public.audit_events
for select using (public.is_tenant_member(tenant_id));

-- Important: tenant creation and first-owner membership should be performed
-- by a server-side transactional function after verifying the authenticated user.
-- Do not allow anonymous clients to insert tenant_members directly.
