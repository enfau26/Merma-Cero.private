# Entrega 08 · Recepción transaccional v8

## Objetivo
Evitar que una recepción se inserte sin generar simultáneamente sus lotes, movimientos de inventario, actualización de la orden y evento de auditoría.

## Migración
`supabase/migrations/0008_atomic_goods_receipts.sql`

Aplicar después de `0001_core.sql` y `0007_suppliers_purchasing.sql`, solo en un proyecto de pruebas primero. No ejecutar sobre una base existente sin comprobar el historial de migraciones y el estado real de las políticas/permisos.

## RPC
`public.receive_purchase_order_atomic(p_tenant_id, p_purchase_order_id, p_warehouse_id, p_receipt_number, p_lines, p_notes)`

Cada elemento de `p_lines` debe incluir:
- `purchase_order_item_id`
- `quantity_received`
- `quantity_accepted`
- `quantity_rejected`
- `rejection_reason` cuando haya rechazo
- `lot_code` opcional
- `expires_on` opcional (YYYY-MM-DD)

## Garantías implementadas
- Requiere usuario autenticado y rol `owner`, `admin`, `manager` u `operator` en el tenant indicado.
- Bloquea la orden con `FOR UPDATE` para serializar recepciones simultáneas de esa orden.
- Comprueba que la orden sea recibible y que el almacén esté activo y pertenezca al mismo tenant.
- Acepta entre 1 y 200 líneas; rechaza IDs de línea repetidos y líneas ajenas a la orden.
- Exige `recibido = aceptado + rechazado` y motivo de rechazo.
- Impide que la cantidad aceptada acumulada supere la cantidad pedida.
- Solo la cantidad aceptada genera lote y movimiento `receipt`.
- Actualiza el estado de la orden y registra auditoría en la misma transacción.
- Revoca INSERT/UPDATE/DELETE directo sobre tablas de recepción a `authenticated`; la lectura sigue disponible.

## Consideraciones y límites
- La suma de cantidades rechazadas no se considera cantidad satisfecha; puede recibirse una reposición posterior, siempre que el acumulado aceptado no supere lo pedido.
- La RPC recibe `p_tenant_id`, pero no confía en él como autorización: valida la membresía/rol mediante `has_tenant_role` y valida todas las relaciones con claves y filtros de tenant.
- La RPC se ejecuta como `SECURITY DEFINER`; revisar que el propietario de la función sea un rol confiable y que no se otorgue ejecución a `anon`.
- Esta migración no implementa todavía idempotencia por clave externa: un reintento con otro número de recepción puede generar una nueva recepción válida. El número de recepción es único por tenant.
- `received_at` usa el valor por defecto de la base de datos; zona horaria y fecha de negocio deben definirse en una futura configuración por tenant.

## Pruebas pendientes en Supabase
1. Operator autorizado recibe; viewer y usuario de otro tenant no pueden ejecutar.
2. INSERT directo a `goods_receipts` y `goods_receipt_items` falla.
3. Recepción aceptada crea exactamente un lote y un movimiento por línea aceptada.
4. Línea totalmente rechazada no crea lote ni movimiento.
5. Error en una línea revierte recepción, líneas, lotes, movimientos, estado y auditoría.
6. Rechazo sin motivo y cantidades desbalanceadas fallan.
7. Recepción acumulada aceptada superior a lo pedido falla.
8. Dos recepciones concurrentes no pueden aceptar en conjunto más de lo pedido.
9. Repetir el número de recepción falla por la restricción única tenant/receipt_number.
10. Probar tenant A intentando referenciar orden, almacén o línea de tenant B.

## Estado
Revisión estática del SQL: pendiente de ejecución en un motor PostgreSQL real. No se afirma que la migración haya sido aplicada, ni que la RPC haya sido probada contra Supabase. No desplegar a producción sin pruebas de integración y revisión de seguridad de `SECURITY DEFINER`.
