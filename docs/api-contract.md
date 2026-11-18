# Contrato de integración — MERMA CERO

Todas las operaciones requieren sesión válida. El `tenant_id` enviado a una RPC no constituye autorización: la función debe comprobar membresía y rol con `has_tenant_role()` y las lecturas deben respetar RLS. La aplicación resuelve el tenant desde `list_my_tenants()` y una cookie HttpOnly que solo selecciona.

## Auth y empresas

| Operación | Mecanismo |
|---|---|
| Registro | Supabase Auth `signUp` con confirmación de correo |
| Inicio | Supabase Auth `signInWithPassword` |
| Callback | `exchangeCodeForSession` |
| Crear empresa | RPC `create_tenant_with_default_warehouse(text,text)` |
| Listar membresías | RPC `list_my_tenants()` |
| Cambiar empresa activa | Server Action valida contra `list_my_tenants()` y cambia cookie HttpOnly |

## Inventario

| Operación | RPC / tabla |
|---|---|
| Crear categoría/producto/almacén | Tablas `categories`, `products`, `warehouses` con RLS |
| Recibir lote directo | `receive_lot` |
| Salida FEFO | `consume_stock_fefo` |
| Registrar merma | `record_waste` |
| Consultar lotes/movimientos | Lectura RLS de `lots`, `stock_movements`, `waste_records` |

No se permite que el cliente modifique `quantity_available` ni cree movimientos manualmente.

## Compras

| Operación | RPC |
|---|---|
| Crear orden | `create_purchase_order_atomic(uuid,uuid,text,date,date,text,jsonb)` |
| Recibir orden | `receive_purchase_order_atomic(uuid,uuid,uuid,text,jsonb,text)` |

La creación de órdenes valida proveedor/productos del mismo tenant, rol de gestión, cantidades, costes e impuestos; calcula totales en servidor y registra auditoría. La recepción acepta entregas parciales y crea lotes/movimientos solo por la cantidad aceptada.

## Otras áreas backend

- Ventas: `create_sale_atomic`.
- Devoluciones: `create_sale_return_atomic`.
- Caja: `open_cash_register_atomic`, `record_cash_register_movement_atomic`, `close_cash_register_atomic` y `post_cash_document_to_register_atomic`.
- Gastos: `create_operating_expense_atomic`.
- Panel financiero: vistas `v_finance_daily_summary`, `v_finance_expenses_daily` y `v_product_profitability`.

Estas áreas no deben considerarse listas para usuarios finales hasta conectar sus pantallas y superar las pruebas de aceptación.
