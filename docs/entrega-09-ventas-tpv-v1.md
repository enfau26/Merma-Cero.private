# Entrega 09 — Ventas y TPV (v1)

## Objetivo
Registrar ventas de mostrador por empresa y almacén, cobrar con uno o varios medios de pago y descontar existencias por FEFO dentro de una única transacción PostgreSQL.

## Incluido en esta base
- Cabecera de venta con moneda heredada de la empresa.
- Líneas con cantidad, precio unitario, descuento e impuesto parametrizado por línea.
- Pagos mixtos: efectivo, tarjeta, transferencia u otro.
- Asignación de cada línea a uno o varios lotes.
- Descuento de lotes FEFO: caducidad más próxima primero; lotes sin caducidad al final.
- Movimiento de inventario tipo `sale` y evento de auditoría.
- RLS de lectura por empresa y escritura exclusivamente mediante RPC.
- Validación de total cobrado igual al total de la venta.

## RPC
`create_sale_atomic(p_tenant_id, p_warehouse_id, p_sale_number, p_lines, p_payments, p_notes)`

La función valida rol, empresa, almacén, productos activos, cantidades, precios, impuestos, descuentos y pagos. Bloquea los lotes mientras asigna unidades. Si no hay stock suficiente o cualquier inserción falla, PostgreSQL revierte venta, pagos, asignaciones y movimientos.

### Ejemplo de líneas
```json
[
  {"product_id":"UUID_PRODUCTO","quantity":2,"unit_price":3.50,"tax_rate":0,"discount_amount":0}
]
```

### Ejemplo de pagos
```json
[
  {"method":"cash","amount":7.00}
]
```

## Endurecimiento previo a validación
- Los parámetros JSON de líneas y pagos rechazan explícitamente `NULL` (evita que una condición SQL de tres valores permita crear una venta vacía).
- El método de pago nulo se rechaza con `INVALID_PAYMENT`.
- Se amplía la batería de aceptación con los casos 16–18.

## Límites conocidos
- Esta entrega crea la capa transaccional de ventas, no una interfaz gráfica TPV.
- No implementa anulaciones, devoluciones, arqueo/cierre de caja, turnos, impresión de tickets ni modo offline.
- `tax_rate` es un dato operativo; no constituye cálculo fiscal certificado ni emisión de factura/boleta. España (IVA) y Perú (IGV/comprobantes) requieren módulos y validación local antes de producción.
- La asignación FEFO debe probarse con lotes reales de distintas caducidades y concurrencia.
- No aplicar a producción antes de probar la secuencia completa de migraciones en un proyecto Supabase aislado.

## Orden de migraciones
`0001_core.sql` → `0007_suppliers_purchasing.sql` → `0008_atomic_goods_receipts.sql` → `0009_receipt_completion_integrity.sql` → `0010_sales_atomic_fefo.sql`.
