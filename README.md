# MERMA CERO — baseline integrado v1

ERP SaaS multiempresa para Perú y España. Este paquete consolida la aplicación Next.js y las migraciones canónicas hasta la Entrega 16, con las interfaces de compras y recepción conectadas a las RPC existentes. Es código listo para integrar y probar; no está conectado a un Supabase real ni desplegado.

## Stack

- Next.js 15 App Router, React 19 y TypeScript.
- Supabase Auth + `@supabase/ssr`.
- PostgreSQL con RLS y RPC transaccionales.
- Perú: PEN / `America/Lima`; España: EUR / `Europe/Madrid`.

## Configuración local

1. Node.js 22 LTS o compatible.
2. `npm install`
3. Copiar `.env.example` a `.env.local`.
4. Configurar `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` y `NEXT_PUBLIC_APP_URL`. La clave anon antigua puede usarse como alternativa.
5. Crear un proyecto Supabase de pruebas y aplicar las migraciones canónicas en el orden indicado en `supabase/MIGRATIONS.md`.
6. En Supabase Auth, habilitar email/password y añadir la URL `/auth/callback` a las Redirect URLs.
7. Ejecutar `npm run dev`.

Nunca añadir `service_role` a variables `NEXT_PUBLIC_*`, al navegador ni al repositorio. En producción, `NEXT_PUBLIC_APP_URL` debe ser HTTPS.

## Funcionalidad integrada

- Registro, inicio y cierre de sesión; confirmación de correo mediante callback.
- Alta de empresa con propietario, almacén principal y evento de auditoría en una transacción.
- Creación de empresas adicionales y cambio de empresa activa. La cookie HttpOnly solo selecciona; la membresía se vuelve a validar en servidor mediante `list_my_tenants()`.
- Catálogo, categorías, almacenes, lotes, movimientos, FEFO, mermas, alertas e informes.
- Proveedores y compras con interfaz; creación de órdenes atómica y recepción parcial/completa desde `/dashboard/purchases/receipts`.
- Migraciones backend de ventas, devoluciones, caja y panel financiero. Algunas de estas áreas todavía no tienen interfaz web integrada.

## Cadena canónica de migraciones

El paquete incluye `0001`, `0002`, `0003` y `0007`–`0016`. Los saltos son intencionados: la antigua `0004_suppliers_purchasing.sql` pertenece a una rama de compras incompatible y no debe aplicarse junto con `0007`–`0009`. La migración `0012` canónica es la de caja; la antigua `0012_secure_tenant_onboarding.sql` se descarta porque colisiona en nombre y reemplaza `list_my_tenants()` con una firma incompatible. El alta segura y el almacén inicial se consolidan en `0015`.

No se encontraron fuentes fiables de migraciones `0005` y `0006`. No se inventan ni se simulan. Consulta `supabase/MIGRATIONS.md` antes de aplicar a una base existente.

## Seguridad y límites

- La autorización real reside en RLS y en las RPC; las cookies y los parámetros del navegador no autorizan acceso.
- Las escrituras de stock se mantienen detrás de RPC transaccionales.
- Las RPC privilegiadas relevantes fijan explícitamente su `search_path`; la recepción se endurece en `0016` con `pg_catalog, public, pg_temp`.
- No se incluyen credenciales, pagos reales ni despliegue.
- Las vistas financieras son gerenciales, no contabilidad legal ni cálculo fiscal oficial.

## Entrega 16 — Interfaz de recepción de mercancía

- Nueva ruta `/dashboard/purchases/receipts` con selección de orden y almacén.
- Consulta de cantidades pedidas, aceptadas previamente y pendientes por línea.
- Registro de cantidades recibidas, aceptadas y rechazadas, motivo de rechazo, lote y caducidad.
- Solo las cantidades aceptadas generan lotes y movimientos mediante `receive_purchase_order_atomic`; las rechazadas quedan documentadas.
- Historial de recepciones con totales y almacén.
- La acción de servidor valida UUID, duplicados, precisión de 3 decimales, balance de cantidades y longitudes antes de invocar la RPC.
- La pantalla permite registrar recepciones a owner, admin, manager y operator; la autorización definitiva sigue en PostgreSQL.

## Verificación realizada en esta entrega

- Revisión cruzada de los ZIP de las Entregas 06, 07, 08, 09, 10, 11 (caja), 12 y 13.
- Detectada y corregida la ausencia de `UNIQUE (tenant_id, id)` en `purchase_order_items`, requerida por una FK compuesta de `goods_receipt_items`.
- Alineadas las acciones de compras con `create_purchase_order_atomic` y `receive_purchase_order_atomic`.
- Añadido RPC de creación de órdenes con validación de rol, pertenencia al tenant, productos activos, importes y auditoría.
- Añadida creación de empresas adicionales y alta inicial con almacén principal.
- Verificación estática del paquete, sintaxis TypeScript/TSX y comprobaciones de presencia de la interfaz de recepción. No se ejecutó Postgres ni Supabase; no se instalaron las dependencias ni se ejecutó `next build`.

## Bloqueos para una versión funcional real

1. Elegir/confirmar un proyecto Supabase de pruebas y aplicar migraciones allí.
2. Si ya existe una base con la rama antigua `0004`, inspeccionar su historial y esquema antes de migrar; no ejecutar este paquete a ciegas.
3. Instalar dependencias y ejecutar `npm run typecheck` y `npm run build`.
4. Ejecutar pruebas RLS con dos usuarios y dos tenants, además de pruebas concurrentes FEFO/recepción.
5. Conectar las interfaces pendientes de ventas, devoluciones, caja y finanzas; ejecutar el recorrido completo de compras y recepción en Supabase de pruebas.

## Entrega 15 — UI de compras y proveedores

Se añaden `/dashboard/suppliers` y `/dashboard/purchases`. La primera permite registrar y consultar proveedores; la segunda permite crear órdenes con varias líneas y consultar su historial. La acción deriva el tenant en servidor y usa la RPC transaccional `create_purchase_order_atomic`. La recepción desde interfaz se incorporó en la Entrega 16. Consulta `docs/entrega-15-compras-proveedores-ui.md` y `docs/entrega-16-recepcion-compras-ui.md`.


## Decisiones funcionales pendientes de aprobación

- Política de aceptación de mercancía con fecha de caducidad vencida. La interfaz no la acepta ni la rechaza automáticamente; la decisión se deja al operador y debe convertirse en una regla validada por PostgreSQL tras aprobación del negocio.
- Reglas de lote obligatorio para productos perecederos y formato de numeración de recepciones. Actualmente el código de lote y la caducidad son opcionales según el esquema existente.


## Cierre MERMA CERO V1.0 (RC0)

Esta línea base se gestiona como candidato de integración, no como producto listo para producción. No se crearán más entregas numeradas. Consulta `docs/release/MERMA-CERO-V1.0-CIERRE.md` y `tests/MERMA-CERO-V1.0-GATE.md` para el alcance, bloqueos y puertas de aceptación.

Comprobaciones estáticas adicionales: `npm run audit:v1`. El script no sustituye pruebas con dependencias instaladas ni pruebas PostgreSQL/RLS.


## Integración de ventas y caja

Se han añadido `/dashboard/sales` y `/dashboard/cash`. Ejecuta `npm run verify:release` y `npm run audit:v1` para comprobaciones estáticas. La UI de devoluciones y las pruebas reales con Supabase siguen pendientes.

## Estado de interfaz de devoluciones
La ruta `/dashboard/sales` incorpora ahora un formulario por venta completada para registrar devoluciones parciales por línea. La acción de servidor valida los datos y delega el registro, cálculo definitivo, reposición en lotes originales y auditoría en `create_sale_return_atomic`. La interfaz y la acción están implementadas estáticamente; siguen pendientes los 20 casos de aceptación en Supabase/PostgreSQL de pruebas. Los reembolsos se registran como método e importe declarados: no se ejecutan transferencias ni abonos bancarios reales.
