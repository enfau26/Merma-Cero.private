# Cadena canónica de migraciones MERMA CERO

## Instalación nueva en Supabase de pruebas

Aplicar en este orden exacto:

1. `migrations/0001_core.sql`
2. `migrations/0002_auth_tenants_and_role_policies.sql`
3. `migrations/0003_inventory_transactions_fefo.sql`
4. `migrations/0007_suppliers_purchasing.sql`
5. `migrations/0008_atomic_goods_receipts.sql`
6. `migrations/0009_receipt_completion_integrity.sql`
7. `migrations/0010_sales_atomic_fefo.sql`
8. `migrations/0011_sales_returns_atomic.sql`
9. `migrations/0012_cash_register_sessions.sql`
10. `migrations/0013_cash_sales_returns_integration.sql`
11. `migrations/0014_financial_dashboard_profitability.sql`
12. `migrations/0015_integration_hardening_and_purchase_orders.sql`
13. `migrations/0016_receipt_input_hardening.sql`

Los huecos 0004–0006 no son migraciones pendientes de esta cadena. La `0004_suppliers_purchasing.sql` de una entrega anterior es una rama legacy con otro modelo de compras (`lot_id`, RPC `create_purchase_order` / `receive_purchase_order`) y no se debe aplicar junto con la cadena 0007–0009 (`lot_code`, `expires_on`, RPC `receive_purchase_order_atomic`). No se ha encontrado una fuente fiable para 0005 o 0006.

## Colisión resuelta: migración 0012

En los archivos históricos hay dos migraciones distintas llamadas `0012`:

- `0012_cash_register_sessions.sql`: se conserva como la 0012 canónica.
- `0012_secure_tenant_onboarding.sql`: no se aplica. Además de colisionar en nombre, redefine `list_my_tenants()` con una forma de retorno distinta de la migración 0002.

El alta segura y el almacén inicial se implementan en `0015` mediante `create_tenant_with_default_warehouse(text,text)`. El tenant activo continúa siendo una cookie HttpOnly de selección, nunca una autorización: `requireActiveTenant()` vuelve a validar la membresía con `list_my_tenants()`.

La migración 0016 endurece las longitudes de número de recepción, notas, motivo de rechazo y código de lote mediante restricciones `CHECK NOT VALID`: las nuevas escrituras quedan protegidas sin exigir que una base histórica supere inmediatamente la validación de registros antiguos. También fija un `search_path` seguro en la RPC de recepción.

## Bases de datos existentes

No ejecutar la cadena completa sobre una base existente sin revisar antes:

- `supabase_migrations.schema_migrations` (versiones aplicadas).
- Tablas/columnas reales de `suppliers`, `purchase_orders`, `purchase_order_items`, `goods_receipts` y `goods_receipt_items`.
- RPC existentes y sus firmas.
- Políticas RLS y grants efectivos.

Si la rama legacy 0004 ya se aplicó, detenerse y preparar una migración de conversión específica. No borrar tablas ni reiniciar el historial para forzar esta cadena.

## Comprobaciones previas a producción

- Aplicar primero en un proyecto Supabase de pruebas vacío.
- Verificar que `purchase_order_items` tiene `UNIQUE (tenant_id,id)`; es requerido por la FK compuesta de `goods_receipt_items`.
- Probar alta de empresa, membresías y aislamiento con dos usuarios y dos tenants.
- Probar compras/recepciones parciales, rechazo, caducidades y concurrencia.
- Revisar `SECURITY DEFINER`, `search_path`, RLS y permisos después de aplicar todas las migraciones.
