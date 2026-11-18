# Entrega 16 — Interfaz de recepción de compras

## Objetivo
Conectar el proceso de recepción parcial/completa ya implementado en PostgreSQL con una pantalla operativa del ERP.

## Ruta
`/dashboard/purchases/receipts`

## Funcionalidad
- Lista órdenes con estado `submitted` o `partially_received`.
- Obtiene las líneas de cada orden y suma las cantidades aceptadas en recepciones con estado `posted`.
- Calcula la cantidad todavía aceptable por línea: `max(0, quantity_ordered - accepted_previously)`.
- Permite seleccionar almacén receptor y número único de recepción.
- Registra cantidades recibidas, aceptadas y rechazadas.
- Si existe rechazo, exige un motivo.
- Para cantidades aceptadas permite indicar código de lote y fecha de caducidad.
- Presenta el historial de las últimas 50 recepciones.

## Flujo transaccional
La interfaz invoca la acción `receivePurchaseOrderAction`, que deriva el tenant activo en servidor con `requireActiveTenant()` y llama a `receive_purchase_order_atomic`. No se acepta `tenant_id` desde el navegador. La RPC existente bloquea la orden, comprueba membresía/rol, almacén y pertenencia de líneas, valida que la cantidad aceptada acumulada no supere la pedida, crea la recepción, genera lotes y movimientos únicamente por cantidad aceptada, actualiza el estado por línea y registra auditoría. Cualquier error revierte toda la transacción.

## Controles añadidos en servidor
- UUID de orden, almacén y líneas.
- Número de recepción obligatorio, máximo 60 caracteres.
- Notas hasta 2.000 caracteres.
- Entre 1 y 200 líneas sin IDs repetidos.
- Cantidades finitas, positivas/no negativas según corresponda, con máximo 3 decimales.
- Igualdad exacta a milésimas: recibida = aceptada + rechazada.
- Motivo obligatorio para cantidad rechazada.
- Código de lote hasta 120 caracteres y fecha real `YYYY-MM-DD`.

## Migración 0016
Añade restricciones `CHECK NOT VALID` para limitar número de recepción (60), notas (2.000), motivo de rechazo (500) y código de lote (120). Estas restricciones protegen nuevas escrituras sin bloquear automáticamente bases históricas que pudieran contener valores anteriores fuera de rango. También fija `search_path = pg_catalog, public, pg_temp` en la RPC `receive_purchase_order_atomic`.

## Seguridad
- La pantalla se sirve después de `requireActiveTenant()`.
- Las consultas incluyen `tenant_id` y siguen sujetas a RLS.
- El tenant se deriva exclusivamente en servidor.
- La base de datos vuelve a validar rol, empresa, orden, almacén y líneas.
- Los operadores pueden registrar recepciones porque la RPC 0009 autoriza `operator`; el UI refleja esa matriz.
- No hay uso de `service_role`, credenciales nuevas ni escritura directa en tablas de recepción.

## Limitaciones y decisiones pendientes
- No se ha ejecutado la aplicación contra Supabase real.
- El código de lote y la caducidad siguen opcionales por compatibilidad con el esquema actual. La migración 0016 limita el código de lote a 120 caracteres.
- La regla para aceptar o rechazar mercancía ya caducada requiere decisión de negocio y validación server-side en una migración posterior. La interfaz no pretende imponer una política de forma aislada.
- La numeración de recepciones debe ser acordada (manual, prefijo por almacén o secuencia automática). Actualmente el usuario introduce el número y PostgreSQL garantiza unicidad por tenant.
