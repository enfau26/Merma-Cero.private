# Compras — contrato backend canónico v1

## Modelo

La rama canónica utiliza `tenant_id` y las tablas `suppliers`, `purchase_orders`, `purchase_order_items`, `goods_receipts` y `goods_receipt_items` creadas en `0007_suppliers_purchasing.sql`.

## Migraciones

Aplicar `0007`, `0008`, `0009` y `0015` después de `0001`, `0002` y `0003`, siguiendo el orden completo de `supabase/MIGRATIONS.md`. No aplicar la migración legacy `0004_suppliers_purchasing.sql` junto con esta rama.

## Operaciones

- Alta de proveedor mediante Server Action con RLS y rol owner/admin/manager.
- Alta de orden mediante `create_purchase_order_atomic`: valida pertenencia y rol, proveedor activo, productos activos del mismo tenant, cantidades, costes, impuestos y precisión decimal; calcula subtotal, impuesto y total en PostgreSQL; crea auditoría.
- La orden nace en `submitted`, estado aceptado por la RPC de recepción.
- Recepción mediante `receive_purchase_order_atomic`: admite entregas parciales, separa recibida/aceptada/rechazada, exige motivo para rechazos y crea lotes/movimientos solo por unidades aceptadas.
- La RPC 0009 bloquea la orden y sus líneas para evitar sobre-recepción concurrente y solo marca `received` cuando cada línea alcanza su cantidad pedida.

## Límites

Las acciones y RPC están preparadas, pero la interfaz web de compras aún debe conectarse. No considerar el módulo listo para usuarios finales hasta implementar pantalla, permisos visibles, estados de error y pruebas de integración.

## Pruebas

Consultar `tests/tenant-and-purchase-acceptance-v1.md` y `tests/receipt-completion-v9.md`. Probar en una base vacía con dos tenants y concurrencia antes de producción.
