# MERMA CERO · Entrega 08 · Auditoría de esquema y seguridad

## Hallazgo bloqueante corregido en el paquete

El ZIP de base de proveedores/compras recibido contenía una migración que utilizaba `company_id`, `public.companies` y `public.company_memberships`. El starter real utiliza `tenant_id`, `public.tenants`, `public.tenant_members` y el enum `public.tenant_role`. Por tanto, esa migración no era compatible con el núcleo y no debía ejecutarse tal cual.

Se ha preparado `supabase/migrations/0007_suppliers_purchasing.sql` alineada con el starter. Esta versión:

- Usa `tenant_id` en todas las tablas de proveedores, órdenes y recepciones.
- Aplica claves foráneas compuestas para impedir referencias cruzadas entre empresas en proveedores, productos, almacenes, órdenes y recepciones.
- Usa `is_tenant_member()` y añade `has_tenant_role()` para comprobar roles en PostgreSQL.
- Permite lectura a miembros; escritura de proveedores y órdenes a owner/admin/manager; inserción de recepciones a owner/admin/manager/operator.
- No concede borrado y bloquea actualización directa de recepciones; los movimientos de stock deberán realizarse desde RPC transaccional auditada.
- Comprueba que la cantidad recibida sea igual a aceptada más rechazada y exige motivo para rechazos.

**Importante:** sustituye el borrador anterior no aplicado. No ejecutar ambas versiones. Si la migración incompatible ya se aplicó en una base real, detenerse y preparar una migración de reparación específica tras inspeccionar el esquema existente.

## Pruebas de aceptación que deben ejecutarse en Supabase

1. Dos tenants A y B con usuarios distintos: SELECT de A no devuelve filas de B.
2. Usuario viewer: puede leer; no puede insertar ni actualizar proveedores/órdenes.
3. Usuario operator: puede insertar recepción; no puede editar órdenes ni actualizar/anular recepciones directamente.
4. Manager: puede gestionar proveedores y órdenes.
5. FK compuesta: no permite asociar una orden del tenant A a un proveedor del tenant B.
6. FK compuesta: no permite asociar una línea a un producto o almacén de otro tenant.
7. CHECK: rechaza cantidades recibidas que no sumen aceptadas y rechazadas.
8. CHECK: rechaza cantidad rechazada sin motivo.
9. Reintento y concurrencia: deben probarse en las RPC de creación/recepción cuando estén incorporadas.
10. Rollback: fallo en cualquier línea no debe dejar lotes ni movimientos parciales.

## Estado real

- Revisión estática de compatibilidad con `0001_core.sql`: realizada.
- Migración corregida incluida: sí.
- Ejecución contra PostgreSQL/Supabase: pendiente.
- Pruebas RLS con usuarios reales: pendientes.
- RPC de creación y recepción y su integración de inventario: requieren revisión/validación adicional.
- Build de Next.js: no ejecutado; el ZIP de origen no contiene un frontend Next.js completo ni dependencias instaladas.

No considerar esta entrega lista para producción hasta ejecutar migraciones y pruebas de integración en un proyecto Supabase de pruebas.
