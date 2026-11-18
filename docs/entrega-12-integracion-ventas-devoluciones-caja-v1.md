# Entrega 12 — Integración de ventas, devoluciones y caja

## Comportamiento
- RPC `post_cash_document_to_register_atomic(tenant, session, 'sale'|'return', document)` incorpora pagos cash de ventas como `cash_in` y reembolsos cash de devoluciones como `cash_out`.
- Tarjeta, transferencia y otros medios no alteran el efectivo físico.
- Valida tenant, rol, caja abierta y almacén de origen. Bloquea la sesión `FOR UPDATE`.
- Índice único por pago de origen impide doble contabilización; repetir la RPC no duplica.
- Registra auditoría si incorpora uno o más pagos.

## Flujo
1. Crear venta/devolución con RPC de entregas 09/10. 2. Invocar esta RPC para sincronizar con la sesión de caja. 3. Verificar movimientos y cerrar con RPC de entrega 11.

## Límite importante
La sincronización es explícita y posterior al documento. Esta entrega no modifica `create_sale_atomic` ni `create_sale_return_atomic`; la futura interfaz/API debe invocar la RPC. No afirmar integración automática hasta probar el flujo completo.

## Validación
Casos definidos, no ejecutados contra PostgreSQL/Supabase. Aplicar solo en proyecto aislado y revisar grants, RLS, concurrencia y rollback.
