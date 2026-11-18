# Entrega 10 — Devoluciones y reposición de inventario (v1)

## Objetivo
Registrar devoluciones parciales o completas de una venta existente, asociar el reembolso a uno o varios medios de pago, reponer unidades en los lotes originales y dejar movimientos y auditoría dentro de una única transacción.

## Incluido
- Cabecera de devolución con número único por empresa y motivo obligatorio.
- Devolución parcial o completa por línea de venta.
- Control acumulado: no permite devolver más unidades que las vendidas, descontando devoluciones previas.
- Cálculo proporcional del importe reembolsable a partir del total de la línea.
- Pagos de reembolso mixtos: efectivo, tarjeta, transferencia u otro.
- Reposición en los lotes que se asignaron a la venta original.
- Movimiento de inventario `return` y evento `sale.returned`.
- RLS de lectura por empresa y escrituras exclusivamente mediante RPC.

## RPC
`create_sale_return_atomic(p_tenant_id, p_sale_id, p_return_number, p_lines, p_payments, p_reason, p_notes)`

Líneas:
```json
[{"sale_item_id":"UUID_LINEA_VENTA","quantity":1}]
```

Pagos:
```json
[{"method":"cash","amount":12.50}]
```

## Reglas y límites
- Solo admite ventas existentes con estado `completed`.
- Cada línea debe pertenecer a la venta indicada.
- La suma devuelta de cada línea no puede superar la cantidad vendida.
- El importe se calcula proporcionalmente sobre `line_total`, redondeado a dos decimales por línea.
- La reposición se asigna a los lotes originales, respetando como máximo la cantidad originalmente consumida de cada lote.
- La RPC es transaccional: un error revierte cabecera, líneas, reembolsos, stock, movimientos y auditoría.
- Esta versión no cambia automáticamente el estado de la venta a `voided`; una devolución completa queda reflejada en el historial acumulado de devoluciones.
- No evalúa el estado físico del producto devuelto (apto, dañado, cuarentena). Se requiere una decisión operativa antes de reponer producto no vendible.
- No implementa aún interfaz, permisos de aprobación separados, arqueo/cierre de caja ni integración con pasarelas.
- Los pagos de devolución son un registro del medio e importe; no ejecutan una transferencia real ni una devolución bancaria automática.
- No constituye comprobante fiscal rectificativo ni define obligaciones de IVA/IGV.

## Orden de migraciones
`0001_core.sql` → `0007_suppliers_purchasing.sql` → `0008_atomic_goods_receipts.sql` → `0009_receipt_completion_integrity.sql` → `0010_sales_atomic_fefo.sql` → `0011_sales_returns_atomic.sql`.

## Estado de validación
Migración y casos de aceptación definidos; todavía no ejecutados contra PostgreSQL/Supabase. No aplicar en producción hasta completar revisión SQL y pruebas de concurrencia, permisos, RLS y rollback.
