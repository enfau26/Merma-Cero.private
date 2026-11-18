# Pruebas de aceptación — Entrega 14

Ejecutar solo en un Supabase de pruebas con la cadena canónica completa.

## Auth y alta de empresa

1. Usuario anónimo no puede ejecutar `create_tenant_with_default_warehouse`.
2. Usuario autenticado crea empresa PE: moneda PEN, zona `America/Lima`, rol owner y almacén principal.
3. Usuario autenticado crea empresa ES: moneda EUR, zona `Europe/Madrid`, rol owner y almacén principal.
4. El usuario puede crear una segunda empresa y cambiar entre ellas.
5. Manipular `mc_active_tenant` con el UUID de una empresa ajena no permite consultar ni modificar sus datos.
6. Un usuario no miembro no puede ejecutar RPC de compras aunque conozca `tenant_id` y UUID de proveedor/producto.
7. El usuario puede leer solo sus membresías mediante `list_my_tenants()`.

## Compras atómicas

1. Owner/admin/manager crea una orden con proveedor y productos activos del mismo tenant.
2. Operator/viewer no puede crear una orden.
3. Proveedor de otro tenant, producto de otro tenant o proveedor inactivo son rechazados.
4. Cantidad <= 0, coste negativo, impuesto fuera de 0–100, precisión superior a 3/4 decimales y más de 200 líneas son rechazados.
5. Una orden válida crea cabecera, líneas, subtotal, impuestos, total y evento de auditoría en una sola transacción.
6. Si una línea es inválida, no queda cabecera ni ninguna línea parcial.
7. La orden nace en `submitted` y puede recibir una primera entrega.
8. La recepción parcial crea lote y movimiento solo por la cantidad aceptada; rechazos exigen motivo.
9. Una excepción durante recepción revierte recepción, lotes, movimientos y actualización de estado.
10. Dos recepciones concurrentes de la misma orden no pueden aceptar más que la cantidad pedida por línea.

## Integridad de migraciones

1. La migración 0007 crea `UNIQUE (tenant_id,id)` en `purchase_order_items` antes de crear la FK compuesta.
2. La cadena canónica no contiene `0012_secure_tenant_onboarding.sql`.
3. Las RPC usadas por `src/actions/purchases.ts` existen con los mismos nombres y parámetros.
4. Ningún usuario autenticado puede escribir directamente `quantity_available`, `stock_movements` ni registros de merma.
5. Revisar `search_path` efectivo de las funciones `SECURITY DEFINER` después de aplicar 0015.
