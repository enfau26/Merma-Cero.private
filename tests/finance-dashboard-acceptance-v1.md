# Pruebas de aceptación — Entrega 13

> Casos definidos; todavía no ejecutados contra PostgreSQL/Supabase real.

- [ ] Owner/admin/manager pueden registrar un gasto válido; operator/viewer reciben `TENANT_ROLE_FORBIDDEN`.
- [ ] Un gasto con importe cero/negativo, categoría vacía o descripción vacía falla sin insertar fila.
- [ ] Un almacén de otro tenant o inactivo falla; `warehouse_id = null` se acepta.
- [ ] La moneda del gasto siempre coincide con `tenants.currency_code`; el cliente no puede imponer otra moneda.
- [ ] Cada gasto crea exactamente un evento `operating_expense.created` en `audit_events`.
- [ ] Cliente autenticado no puede insertar, modificar ni borrar directamente gastos.
- [ ] Un tenant no puede consultar filas del otro tenant mediante tabla o vistas.
- [ ] Venta con varias capas FEFO calcula COGS como suma de cantidad asignada por coste unitario capturado.
- [ ] Devolución parcial resta el reembolso y revierte únicamente el coste de lotes repuestos.
- [ ] Venta sin devolución no muestra reembolsos ni coste revertido.
- [ ] Gastos sin almacén aparecen en el consolidado con `warehouse_id = null`; no deben duplicarse al filtrar por almacén.
- [ ] Días con solo gastos aparecen en `v_finance_daily_summary`; días con solo ventas también.
- [ ] Producto sin coste capturado debe quedar identificado para revisión; no interpretar automáticamente coste cero como margen real.
- [ ] Verificar precisión/redondeo, zona horaria de cada tenant y límites de fechas alrededor de cambios de horario.
- [ ] Ejecutar `EXPLAIN (ANALYZE, BUFFERS)` con volumen representativo y revisar índices/planes.
- [ ] Confirmar compatibilidad de `security_invoker=true` y PostgreSQL 15+.
