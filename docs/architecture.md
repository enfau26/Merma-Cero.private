# Arquitectura de MERMA CERO

## Vista lógica

```text
Web / PWA (Next.js)
       |
       v
Server Actions + API Routes
       |
       +---- Auth / membership / tenant resolver
       |
       +---- Domain services
       |       +-- Catalog
       |       +-- Inventory & FEFO
       |       +-- Waste
       |       +-- Purchasing
       |       +-- Sales / Cash
       |       +-- Reporting
       |       +-- Subscription entitlements
       |
       v
PostgreSQL (Supabase) + RLS
       |
       +---- Storage (documentos/fotos)
       +---- Scheduled jobs (alertas)
       +---- Webhooks (pagos)
```

## Multi-tenancy
Modelo compartido con `tenant_id` en cada tabla de negocio. Las políticas RLS consultan `tenant_members` usando `auth.uid()`. Esto reduce coste operativo y permite escalar al inicio. Para clientes empresariales con requisitos especiales se podría ofrecer una base dedicada en el futuro.

## Roles
- `owner`: titular y configuración de la empresa.
- `admin`: gestión completa del negocio, sin transferir titularidad.
- `manager`: compras, inventario, ventas e informes.
- `operator`: operaciones permitidas en almacén/tienda.
- `viewer`: lectura.

Los permisos definitivos deben validarse también en el servidor; RLS es una segunda barrera, no la única.

## Inventario
Cada lote registra producto, almacén, cantidad inicial, saldo, coste unitario, fecha de recepción y caducidad. Los cambios generan `stock_movements` inmutables. FEFO ordena lotes disponibles por caducidad ascendente y luego recepción. Una salida debe ejecutarse en transacción y consumir lotes siguiendo ese orden.

## País y fiscalidad
No se codifican reglas fiscales globales. `country_code`, `currency_code` y parámetros fiscales se configuran por tenant. Los cálculos fiscales, series, numeración y documentos electrónicos se implementan como adaptadores por país tras revisión legal/contable.
