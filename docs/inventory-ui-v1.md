# MERMA CERO — Entrega 05: interfaz de inventario

## Incluido
- Panel de inventario por empresa activa.
- Alta de productos y categorías para roles owner/admin/manager (RLS vuelve a validar permisos).
- Alta de almacenes para roles owner/admin/manager.
- Recepción de lotes con cantidad, coste unitario, caducidad, código y proveedor mediante `receive_lot`.
- Salida de stock mediante `consume_stock_fefo`; no se modifica stock directamente desde formularios.
- Registro de mermas mediante `record_waste`.
- Consulta de existencias por lote, ordenada por caducidad, y actividad reciente.
- Interfaz localizada por país para fecha/hora y moneda PEN/EUR.
- Pantalla de error del módulo para fallos de carga/operación.

## Seguridad aplicada en esta capa
- Cada lectura y escritura obtiene el tenant mediante `requireActiveTenant()` en servidor.
- No se acepta `tenant_id` enviado por el navegador.
- Las altas directas de catálogo/almacén se hacen con sesión autenticada y quedan sujetas a RLS y grants de 0002.
- Las mutaciones de stock siguen usando exclusivamente las RPC transaccionales de 0003.
- La UI oculta formularios según rol como ayuda de usabilidad; la autorización real sigue en PostgreSQL/RLS/RPC.

## Límites conocidos
- No hay todavía edición/desactivación de productos, importación CSV, inventario físico, transferencias entre almacenes ni alertas automáticas.
- No se ha probado contra un proyecto Supabase real ni con usuarios concurrentes.
- La tabla de lotes muestra hasta 100 registros con existencias; la actividad muestra los últimos 12 movimientos.
- Las acciones devuelven errores mediante el límite de error de Next.js; falta una experiencia de confirmación/validación inline más pulida.

## Pruebas de aceptación manuales
1. Un owner crea categoría, almacén y producto; aparecen en sus listas.
2. Un operator no ve altas de catálogo/almacén, pero puede registrar recepción, salida y merma.
3. Un viewer solo consulta y no ve formularios de operaciones.
4. Un usuario de empresa A no ve registros de empresa B al cambiar de tenant.
5. Una recepción crea lote, movimiento receipt y evento de auditoría.
6. Una salida parcial consume primero el lote con caducidad más cercana.
7. Una salida sin stock suficiente falla sin dejar descuentos parciales.
8. Una merma reduce stock disponible y registra waste + movimiento + auditoría.
9. Fechas y moneda se presentan según la empresa PE o ES.
