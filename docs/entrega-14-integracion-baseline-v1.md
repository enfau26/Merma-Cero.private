# Entrega 14 — Consolidación del baseline y alta multiempresa v1

## Hallazgos de revisión

La revisión cruzada de los paquetes disponibles encontró varias ramas que no eran intercambiables:

1. La aplicación inicial usa `create_tenant_for_current_user`, cookie `mc_active_tenant` y `list_my_tenants()` para resolver el tenant.
2. La migración 0007 de compras exige claves foráneas compuestas hacia `purchase_order_items(tenant_id,id)`, pero la tabla no declaraba esa unicidad. Se añade `UNIQUE (tenant_id,id)` antes de instalar la migración.
3. Las acciones de compra de la aplicación llamaban a RPC de la rama legacy (`create_purchase_order` y `receive_purchase_order`), mientras la cadena más reciente expone `receive_purchase_order_atomic` y no tenía una RPC de alta de orden. Se incorpora `create_purchase_order_atomic` y se alinean las acciones.
4. Hay dos archivos históricos llamados 0012: onboarding y caja. Se conserva caja como 0012 y se traslada el alta completa de empresa a 0015.
5. Varias funciones `SECURITY DEFINER` de las entregas 07–13 fijaban `search_path` sin `pg_catalog` al principio. La migración 0015 endurece su configuración.

## Cambios

- `create_tenant_with_default_warehouse`: reutiliza la RPC segura de creación de tenant, crea el almacén principal y registra auditoría en una transacción.
- `create_purchase_order_atomic`: comprueba usuario, rol, proveedor activo, productos activos del tenant, cantidades, precisión decimal e impuestos; calcula importes y audita la operación.
- Las órdenes nuevas se crean en estado `submitted`, que es el estado aceptado por la RPC de recepción parcial/completa 0009.
- Las acciones de compra usan las firmas de RPC de la cadena canónica.
- La aplicación permite añadir empresas adicionales. La cookie activa sigue siendo solo selector; la membresía se revalida en servidor.
- El callback de Auth gestiona enlaces sin código y errores de intercambio; el registro exige URL HTTPS en producción.
- Cliente Supabase acepta publishable key y mantiene compatibilidad con anon key.

## No incluido / no validado

No se ha conectado un proyecto Supabase, no se ha ejecutado SQL en PostgreSQL y no se ha desplegado. Tampoco se han instalado dependencias, por lo que no se afirma un `next build` exitoso. La interfaz de compras/ventas/caja/finanzas sigue pendiente de integración; algunas capas backend sí están presentes.

## Decisión operativa

Esta cadena está preparada para una instalación nueva en un Supabase de pruebas. Si existe una base que ya aplicó la migración legacy 0004 o el archivo onboarding 0012, se necesita una auditoría de su historial y esquema antes de modificarla.
