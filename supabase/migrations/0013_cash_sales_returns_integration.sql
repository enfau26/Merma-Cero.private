-- MERMA CERO · Entrega 12 · Integración idempotente ventas/devoluciones ↔ caja
-- Requiere migraciones 0001 y 0007–0012 aplicadas en un entorno aislado.
alter table public.cash_register_movements add column if not exists source_type text, add column if not exists source_payment_id uuid;
alter table public.cash_register_movements add constraint cash_register_source_type_check check (source_type is null or source_type in ('sale_payment','return_payment'));
create unique index if not exists cash_register_source_payment_unique on public.cash_register_movements(tenant_id,source_type,source_payment_id) where source_type is not null and source_payment_id is not null;
create or replace function public.post_cash_document_to_register_atomic(p_tenant_id uuid,p_session_id uuid,p_document_type text,p_document_id uuid)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_actor uuid:=auth.uid(); v_session public.cash_register_sessions%rowtype; v_warehouse_id uuid; v_payment record; v_inserted integer:=0; v_rows integer:=0; v_movement_type text; v_source_type text; v_reason text;
begin
 if v_actor is null then raise exception 'AUTH_REQUIRED' using errcode='42501'; end if;
 if not public.has_tenant_role(p_tenant_id,array['owner','admin','manager','operator']::public.tenant_role[]) then raise exception 'TENANT_ROLE_FORBIDDEN' using errcode='42501'; end if;
 if p_document_type not in ('sale','return') or p_document_id is null then raise exception 'INVALID_CASH_DOCUMENT' using errcode='22023'; end if;
 select * into v_session from public.cash_register_sessions where id=p_session_id and tenant_id=p_tenant_id and status='open' for update;
 if not found then raise exception 'CASH_REGISTER_NOT_OPEN' using errcode='22023'; end if;
 if p_document_type='sale' then
  select warehouse_id into v_warehouse_id from public.sales where id=p_document_id and tenant_id=p_tenant_id and status='completed';
  if not found then raise exception 'SALE_NOT_FOUND_OR_NOT_COMPLETED' using errcode='P0002'; end if;
  v_movement_type:='cash_in'; v_source_type:='sale_payment'; v_reason:='Cobro en efectivo de venta';
  if v_warehouse_id<>v_session.warehouse_id then raise exception 'CASH_REGISTER_WAREHOUSE_MISMATCH' using errcode='22023'; end if;
  for v_payment in select id,amount,reference from public.sale_payments where tenant_id=p_tenant_id and sale_id=p_document_id and method='cash' loop
   insert into public.cash_register_movements(tenant_id,session_id,movement_type,amount,reason,reference,created_by,source_type,source_payment_id)
   values(p_tenant_id,p_session_id,v_movement_type,v_payment.amount,v_reason,coalesce(v_payment.reference,p_document_id::text),v_actor,v_source_type,v_payment.id)
   on conflict (tenant_id,source_type,source_payment_id) where source_type is not null and source_payment_id is not null do nothing;
   get diagnostics v_rows=row_count; v_inserted:=v_inserted+v_rows;
  end loop;
 else
  select s.warehouse_id into v_warehouse_id from public.sale_returns r join public.sales s on s.id=r.sale_id and s.tenant_id=r.tenant_id where r.id=p_document_id and r.tenant_id=p_tenant_id;
  if not found then raise exception 'RETURN_NOT_FOUND' using errcode='P0002'; end if;
  v_movement_type:='cash_out'; v_source_type:='return_payment'; v_reason:='Reembolso en efectivo de devolución';
  if v_warehouse_id<>v_session.warehouse_id then raise exception 'CASH_REGISTER_WAREHOUSE_MISMATCH' using errcode='22023'; end if;
  for v_payment in select id,amount,reference from public.sale_return_payments where tenant_id=p_tenant_id and return_id=p_document_id and method='cash' loop
   insert into public.cash_register_movements(tenant_id,session_id,movement_type,amount,reason,reference,created_by,source_type,source_payment_id)
   values(p_tenant_id,p_session_id,v_movement_type,v_payment.amount,v_reason,coalesce(v_payment.reference,p_document_id::text),v_actor,v_source_type,v_payment.id)
   on conflict (tenant_id,source_type,source_payment_id) where source_type is not null and source_payment_id is not null do nothing;
   get diagnostics v_rows=row_count; v_inserted:=v_inserted+v_rows;
  end loop;
 end if;
 if v_inserted>0 then insert into public.audit_events(tenant_id,actor_id,action,entity_type,entity_id,details) values(p_tenant_id,v_actor,'cash_register.document_posted','cash_register_session',p_session_id,jsonb_build_object('document_type',p_document_type,'document_id',p_document_id,'inserted_cash_payments',v_inserted)); end if;
 return v_inserted;
end $$;
revoke all on function public.post_cash_document_to_register_atomic(uuid,uuid,text,uuid) from public;
grant execute on function public.post_cash_document_to_register_atomic(uuid,uuid,text,uuid) to authenticated;
comment on function public.post_cash_document_to_register_atomic(uuid,uuid,text,uuid) is 'Incorpora pagos/reembolsos en efectivo a una sesión de caja, con idempotencia por pago de origen y validación de almacén.';
