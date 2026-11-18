# Entrega 11 — Caja y arqueo v1

## Incluido
- Apertura de sesiones de caja por empresa, almacén y nombre de caja.
- Restricción para impedir dos sesiones abiertas simultáneas con el mismo nombre en el mismo almacén.
- Entradas y salidas manuales de efectivo con motivo obligatorio y referencia opcional.
- Cierre con importe esperado, importe contado y diferencia (sobrante/faltante).
- Roles: owner/admin/manager/operator pueden abrir y registrar movimientos; solo owner/admin/manager pueden cerrar.
- Lectura RLS por empresa; escrituras exclusivamente mediante RPC `SECURITY DEFINER`.
- Auditoría de apertura, movimientos y cierre.

## RPC
- `open_cash_register_atomic(tenant, warehouse, register_name, opening_amount, note)`
- `record_cash_register_movement_atomic(tenant, session, cash_in|cash_out, amount, reason, reference)`
- `close_cash_register_atomic(tenant, session, counted_amount, note)`

El esperado se calcula como fondo inicial + entradas manuales − salidas manuales. La diferencia es contado − esperado.

## Límites explícitos
Esta versión NO concilia automáticamente los cobros de ventas ni los reembolsos de devoluciones; tampoco integra terminales bancarios, facturación, cierres fiscales ni varias cajas físicas sincronizadas. Por tanto, el importe esperado solo es fiable si se registran todos los movimientos manuales de efectivo y el arqueo no debe presentarse como cierre contable/fiscal. La integración de ventas/retornos con la sesión de caja queda para una siguiente entrega.

## Orden
Aplicar después de `0011_sales_returns_atomic.sql`.

## Validación
Migración y casos definidos, no ejecutados contra PostgreSQL/Supabase. Aplicar primero en proyecto aislado; no aplicar en producción sin ejecutar los casos de aceptación y revisar permisos efectivos, RLS, concurrencia y rollback.
