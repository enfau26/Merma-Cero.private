-- MERMA CERO · Entrega 16 · Endurecimiento de entradas de recepción
-- Aplicar después de 0015_integration_hardening_and_purchase_orders.sql.
-- NOT VALID evita bloquear una base histórica por datos antiguos, pero las
-- restricciones se aplican inmediatamente a todas las nuevas escrituras.

begin;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.goods_receipts'::regclass
      and conname = 'goods_receipts_receipt_number_length_check'
  ) then
    alter table public.goods_receipts
      add constraint goods_receipts_receipt_number_length_check
      check (char_length(btrim(receipt_number)) between 1 and 60) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.goods_receipts'::regclass
      and conname = 'goods_receipts_notes_length_check'
  ) then
    alter table public.goods_receipts
      add constraint goods_receipts_notes_length_check
      check (notes is null or char_length(notes) <= 2000) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.goods_receipt_items'::regclass
      and conname = 'goods_receipt_items_rejection_reason_length_check'
  ) then
    alter table public.goods_receipt_items
      add constraint goods_receipt_items_rejection_reason_length_check
      check (rejection_reason is null or char_length(rejection_reason) <= 500) not valid;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.goods_receipt_items'::regclass
      and conname = 'goods_receipt_items_lot_code_length_check'
  ) then
    alter table public.goods_receipt_items
      add constraint goods_receipt_items_lot_code_length_check
      check (lot_code is null or char_length(lot_code) <= 120) not valid;
  end if;
end;
$$;

-- La RPC es SECURITY DEFINER; prioriza pg_catalog y mantiene los objetos
-- de negocio referenciados con esquema explícito.
alter function public.receive_purchase_order_atomic(uuid, uuid, uuid, text, jsonb, text)
  set search_path = pg_catalog, public, pg_temp;

comment on function public.receive_purchase_order_atomic(uuid, uuid, uuid, text, jsonb, text)
  is 'Registra recepciones de compra atómicamente; valida tenant/rol/orden/almacén/líneas, crea lotes y movimientos aceptados y audita la operación.';

commit;
