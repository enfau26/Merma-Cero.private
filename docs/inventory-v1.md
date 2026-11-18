# MERMA CERO — Inventario v1

## Alcance de la entrega 04
- Recepción de mercancía: crea lote, movimiento y evento de auditoría en una única transacción.
- Salida FEFO: asigna cantidades desde los lotes con caducidad más próxima; los lotes sin fecha quedan al final y los caducados se excluyen.
- Registro de mermas: bloquea el lote, valida disponibilidad, descuenta stock y registra movimiento, coste estimado y auditoría en una única transacción.
- Acciones de servidor Next.js: obtienen el tenant activo mediante la resolución existente y llaman a RPC; no actualizan `quantity_available` desde el navegador.

## Aplicación en entorno de pruebas
1. Ejecutar `0001_core.sql`.
2. Ejecutar `0002_auth_tenants_and_role_policies.sql`.
3. Ejecutar `0003_inventory_transactions_fefo.sql`.
4. Probar con dos usuarios de dos empresas distintas y datos de prueba.

## Contrato RPC
- `receive_lot`: recibe empresa, producto, almacén, cantidad, coste, caducidad y metadatos del lote; devuelve `lot_id`.
- `consume_stock_fefo`: recibe empresa, producto, almacén y cantidad; devuelve JSON con la asignación por lote.
- `record_waste`: recibe empresa, lote, cantidad y motivo; devuelve `waste_id`.

## Reglas y límites
- No se permite salida desde lotes caducados.
- FEFO ordena por `expires_on ASC NULLS LAST`, luego `received_on` y UUID para desempate estable.
- Si no hay stock suficiente, PostgreSQL revierte la transacción completa, incluidas asignaciones parciales.
- Coste de merma = cantidad × coste unitario, redondeado a dos decimales. Es una estimación operativa, no un asiento contable ni valoración fiscal.
- La RPC `consume_stock_fefo` usa el tipo `sale` del enum existente como movimiento de salida. Más adelante debe decidirse si se separan ventas, consumos internos y otras salidas.
- Las RPC usan `SECURITY DEFINER` con `search_path` fijo, validan `auth.uid()` y rol por tenant y revocan ejecución a `anon`/`public`.

## Pruebas de aceptación pendientes en Supabase
1. Recepción crea un lote y exactamente un movimiento `receipt`.
2. FEFO consume primero el lote con vencimiento más próximo.
3. Lote sin vencimiento se consume después de lotes con fecha.
4. Lote caducado no se consume.
5. Stock insuficiente no deja movimientos ni cambios de cantidades parciales.
6. Dos salidas concurrentes no pueden consumir más que la existencia bloqueada.
7. Usuario de tenant A no puede recibir, consumir ni registrar mermas en tenant B.
8. `viewer` no puede ejecutar operaciones de escritura.

No se ha ejecutado esta migración contra Supabase ni se han realizado pruebas de concurrencia reales en esta entrega.
