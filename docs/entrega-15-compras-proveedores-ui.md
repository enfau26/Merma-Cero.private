# Entrega 15 — Interfaz de proveedores y compras

## Alcance
- Pantalla de directorio de proveedores con alta desde servidor.
- Formulario cliente para crear órdenes de compra con hasta 200 líneas.
- Cálculo orientativo del total en moneda de la empresa.
- Listado de órdenes con estado, proveedor, fechas y total.
- Navegación desde el panel principal.

## Seguridad
- Las páginas requieren tenant activo en servidor.
- Todas las consultas filtran por `tenant_id` y además dependen de RLS.
- El formulario no envía un `tenant_id`; la acción `createPurchaseOrderAction` lo deriva de `requireActiveTenant()`.
- La creación se ejecuta mediante `create_purchase_order_atomic`; la base de datos debe volver a validar membresía, roles, proveedor y productos.
- La creación de proveedores usa el usuario autenticado y `tenant_id` del contexto servidor; RLS sigue siendo obligatoria.
- No se usa `service_role` ni se incorporan secretos.

## Limitaciones
- La pantalla permite crear órdenes y consultar historial. No implementa todavía el envío/cambio de estado ni la recepción parcial desde UI.
- La recepción transaccional existe como RPC/acción de servidor; su interfaz se incorporó en la Entrega 16.
- La pantalla no ha sido ejecutada contra Supabase; no se afirma validación funcional de base real.

## Pruebas pendientes
1. `npm install`, `npm run typecheck`, `npm run build`.
2. Probar alta de proveedor con dos tenants y verificar aislamiento.
3. Probar orden con producto de otro tenant (debe rechazarse en RPC).
4. Probar cantidades/costes/impuestos negativos, excesivos y líneas vacías.
5. Confirmar que operador no puede crear órdenes ni proveedores.
