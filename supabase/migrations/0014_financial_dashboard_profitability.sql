-- MERMA CERO · Entrega 13 · Panel financiero y rentabilidad v1
-- PostgreSQL/Supabase. Aplicar primero en entorno aislado y validar el esquema completo.

-- Gastos operativos registrados por empresa. Registros inmutables desde el cliente.
create table if not exists public.operating_expenses (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  warehouse_id uuid,
  expense_date date not null,
  category text not null check (length(trim(category)) between 1 and 80),
  description text not null check (length(trim(description)) between 1 and 240),
  amount numeric(14,2) not null check (amount > 0),
  currency_code char(3) not null,
  reference text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique (tenant_id, id),
  foreign key (tenant_id, warehouse_id) references public.warehouses(tenant_id, id)
);

create index if not exists operating_expenses_tenant_date_idx
  on public.operating_expenses(tenant_id, expense_date desc);
create index if not exists operating_expenses_tenant_warehouse_idx
  on public.operating_expenses(tenant_id, warehouse_id, expense_date desc);

alter table public.operating_expenses enable row level security;
drop policy if exists operating_expenses_select_member on public.operating_expenses;
create policy operating_expenses_select_member on public.operating_expenses
  for select using (public.is_tenant_member(tenant_id));
revoke insert, update, delete on public.operating_expenses from authenticated;
grant select on public.operating_expenses to authenticated;

-- Registro controlado de gastos. Sin edición/borrado directo; correcciones mediante
-- asiento compensatorio en una futura entrega para conservar trazabilidad.
create or replace function public.create_operating_expense_atomic(
  p_tenant_id uuid,
  p_expense_date date,
  p_category text,
  p_description text,
  p_amount numeric,
  p_warehouse_id uuid default null,
  p_reference text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_actor uuid := auth.uid();
  v_currency char(3);
  v_id uuid;
begin
  if v_actor is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;
  if not public.has_tenant_role(p_tenant_id,
    array['owner','admin','manager']::public.tenant_role[]) then
    raise exception 'TENANT_ROLE_FORBIDDEN' using errcode = '42501';
  end if;
  if p_expense_date is null or nullif(trim(p_category),'') is null
     or nullif(trim(p_description),'') is null or p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_EXPENSE_FIELDS' using errcode = '22023';
  end if;
  select currency_code into v_currency from public.tenants where id = p_tenant_id;
  if not found then raise exception 'TENANT_NOT_FOUND' using errcode = 'P0002'; end if;
  if p_warehouse_id is not null and not exists (
    select 1 from public.warehouses w where w.id = p_warehouse_id
      and w.tenant_id = p_tenant_id and w.is_active
  ) then
    raise exception 'WAREHOUSE_NOT_FOUND_OR_INACTIVE' using errcode = '22023';
  end if;

  insert into public.operating_expenses(
    tenant_id, warehouse_id, expense_date, category, description,
    amount, currency_code, reference, created_by
  ) values (
    p_tenant_id, p_warehouse_id, p_expense_date, trim(p_category),
    trim(p_description), round(p_amount,2), v_currency,
    nullif(trim(p_reference),''), v_actor
  ) returning id into v_id;

  insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details)
  values (p_tenant_id,v_actor,'operating_expense.created','operating_expense',v_id,
    jsonb_build_object('amount',round(p_amount,2),'currency_code',v_currency,
      'category',trim(p_category),'warehouse_id',p_warehouse_id));
  return v_id;
end;
$$;
revoke all on function public.create_operating_expense_atomic(uuid,date,text,text,numeric,uuid,text) from public;
grant execute on function public.create_operating_expense_atomic(uuid,date,text,text,numeric,uuid,text) to authenticated;

-- Coste de ventas calculado con el coste unitario capturado en la asignación FEFO.
-- Devoluciones reducen ingresos y revierten el coste de las unidades reincorporadas.
create or replace view public.v_finance_sales_daily
with (security_invoker = true) as
with sold as (
  select s.tenant_id, s.warehouse_id, s.currency_code,
    (s.sold_at at time zone t.timezone)::date as business_date,
    s.id as sale_id, s.total as gross_sales,
    coalesce(c.cost_of_goods,0)::numeric(14,2) as cost_of_goods
  from public.sales s
  join public.tenants t on t.id = s.tenant_id
  left join lateral (
    select sum(a.quantity * a.unit_cost) as cost_of_goods
    from public.sale_items si
    join public.sale_item_lot_allocations a
      on a.tenant_id = si.tenant_id and a.sale_item_id = si.id
    where si.tenant_id = s.tenant_id and si.sale_id = s.id
  ) c on true
  where s.status = 'completed'
), returned as (
  select r.tenant_id, r.sale_id, sum(r.refund_total) as refunds,
    sum(coalesce(rc.returned_cost,0)) as returned_cost
  from public.sale_returns r
  left join lateral (
    select sum(a.quantity * a.unit_cost) as returned_cost
    from public.sale_return_items ri
    join public.sale_return_lot_allocations a
      on a.tenant_id = ri.tenant_id and a.return_item_id = ri.id
    where ri.tenant_id = r.tenant_id and ri.return_id = r.id
  ) rc on true
  group by r.tenant_id,r.sale_id
)
select s.tenant_id,s.warehouse_id,s.currency_code,s.business_date,
  count(*)::bigint as sales_count,
  sum(s.gross_sales)::numeric(14,2) as gross_sales,
  sum(coalesce(r.refunds,0))::numeric(14,2) as refunds,
  (sum(s.gross_sales)-sum(coalesce(r.refunds,0)))::numeric(14,2) as net_sales,
  sum(s.cost_of_goods)::numeric(14,2) as gross_cogs,
  sum(coalesce(r.returned_cost,0))::numeric(14,2) as returned_cogs,
  (sum(s.cost_of_goods)-sum(coalesce(r.returned_cost,0)))::numeric(14,2) as net_cogs,
  (sum(s.gross_sales)-sum(coalesce(r.refunds,0))
    -sum(s.cost_of_goods)+sum(coalesce(r.returned_cost,0)))::numeric(14,2) as gross_profit
from sold s
left join returned r on r.tenant_id=s.tenant_id and r.sale_id=s.sale_id
group by s.tenant_id,s.warehouse_id,s.currency_code,s.business_date;

grant select on public.v_finance_sales_daily to authenticated;

create or replace view public.v_finance_expenses_daily
with (security_invoker = true) as
select tenant_id,warehouse_id,currency_code,expense_date as business_date,
  category,sum(amount)::numeric(14,2) as expense_total,count(*)::bigint as expense_count
from public.operating_expenses
group by tenant_id,warehouse_id,currency_code,expense_date,category;
grant select on public.v_finance_expenses_daily to authenticated;

-- Resumen diario combinado: beneficio operativo estimado = beneficio bruto - gastos.
-- No incluye impuestos sobre beneficios, nóminas, amortizaciones ni costes no registrados.
create or replace view public.v_finance_daily_summary
with (security_invoker = true) as
with sales as (
  select tenant_id,warehouse_id,currency_code,business_date,
    sum(sales_count)::bigint as sales_count,
    sum(gross_sales)::numeric(14,2) as gross_sales,
    sum(refunds)::numeric(14,2) as refunds,
    sum(net_sales)::numeric(14,2) as net_sales,
    sum(net_cogs)::numeric(14,2) as net_cogs,
    sum(gross_profit)::numeric(14,2) as gross_profit
  from public.v_finance_sales_daily
  group by tenant_id,warehouse_id,currency_code,business_date
), expenses as (
  select tenant_id,warehouse_id,currency_code,business_date,
    sum(expense_total)::numeric(14,2) as expenses
  from public.v_finance_expenses_daily
  group by tenant_id,warehouse_id,currency_code,business_date
), keys as (
  select tenant_id,warehouse_id,currency_code,business_date from sales
  union
  select tenant_id,warehouse_id,currency_code,business_date from expenses
)
select k.tenant_id,k.warehouse_id,k.currency_code,k.business_date,
  coalesce(s.sales_count,0)::bigint as sales_count,
  coalesce(s.gross_sales,0)::numeric(14,2) as gross_sales,
  coalesce(s.refunds,0)::numeric(14,2) as refunds,
  coalesce(s.net_sales,0)::numeric(14,2) as net_sales,
  coalesce(s.net_cogs,0)::numeric(14,2) as net_cogs,
  coalesce(s.gross_profit,0)::numeric(14,2) as gross_profit,
  coalesce(e.expenses,0)::numeric(14,2) as operating_expenses,
  (coalesce(s.gross_profit,0)-coalesce(e.expenses,0))::numeric(14,2) as operating_result
from keys k
left join sales s using (tenant_id,warehouse_id,currency_code,business_date)
left join expenses e using (tenant_id,warehouse_id,currency_code,business_date);
grant select on public.v_finance_daily_summary to authenticated;

-- Rentabilidad por producto: ventas netas y coste trazable desde asignaciones FEFO.
create or replace view public.v_product_profitability
with (security_invoker = true) as
with sale_item_costs as (
  select si.tenant_id,si.id as sale_item_id,si.product_id,s.warehouse_id,s.currency_code,
    si.line_total,
    coalesce(a.cogs,0)::numeric(14,2) as cogs
  from public.sale_items si
  join public.sales s on s.tenant_id=si.tenant_id and s.id=si.sale_id
  left join lateral (
    select sum(x.quantity*x.unit_cost) as cogs
    from public.sale_item_lot_allocations x
    where x.tenant_id=si.tenant_id and x.sale_item_id=si.id
  ) a on true
  where s.status='completed'
), sales as (
  select tenant_id,warehouse_id,product_id,currency_code,
    sum(line_total)::numeric(14,2) as gross_sales,
    sum(cogs)::numeric(14,2) as cogs
  from sale_item_costs
  group by tenant_id,warehouse_id,product_id,currency_code
), return_item_costs as (
  select ri.tenant_id,ri.id as return_item_id,ri.refund_amount,
    si.product_id,s.warehouse_id,s.currency_code,
    coalesce(a.returned_cogs,0)::numeric(14,2) as returned_cogs
  from public.sale_return_items ri
  join public.sale_returns r on r.tenant_id=ri.tenant_id and r.id=ri.return_id
  join public.sale_items si on si.tenant_id=ri.tenant_id and si.id=ri.sale_item_id
  join public.sales s on s.tenant_id=r.tenant_id and s.id=r.sale_id
  left join lateral (
    select sum(x.quantity*x.unit_cost) as returned_cogs
    from public.sale_return_lot_allocations x
    where x.tenant_id=ri.tenant_id and x.return_item_id=ri.id
  ) a on true
), returns as (
  select tenant_id,product_id,warehouse_id,currency_code,
    sum(refund_amount)::numeric(14,2) as refunds,
    sum(returned_cogs)::numeric(14,2) as returned_cogs
  from return_item_costs
  group by tenant_id,product_id,warehouse_id,currency_code
)
select x.tenant_id,x.warehouse_id,x.product_id,p.name as product_name,x.currency_code,
  x.gross_sales,coalesce(r.refunds,0)::numeric(14,2) as refunds,
  (x.gross_sales-coalesce(r.refunds,0))::numeric(14,2) as net_sales,
  x.cogs,coalesce(r.returned_cogs,0)::numeric(14,2) as returned_cogs,
  (x.cogs-coalesce(r.returned_cogs,0))::numeric(14,2) as net_cogs,
  (x.gross_sales-coalesce(r.refunds,0)-x.cogs+coalesce(r.returned_cogs,0))::numeric(14,2) as gross_profit
from sales x
join public.products p on p.tenant_id=x.tenant_id and p.id=x.product_id
left join returns r on r.tenant_id=x.tenant_id and r.warehouse_id=x.warehouse_id
  and r.product_id=x.product_id and r.currency_code=x.currency_code;
grant select on public.v_product_profitability to authenticated;
