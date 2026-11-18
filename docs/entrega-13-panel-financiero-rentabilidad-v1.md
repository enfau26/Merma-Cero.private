# Entrega 13 — Panel financiero y rentabilidad v1

## Objetivo
Añadir una primera capa de información financiera multiempresa para España y Perú, calculada desde ventas, asignaciones de coste FEFO, devoluciones y gastos operativos.

## Incluye
- `operating_expenses`: gastos por empresa, fecha, categoría y almacén opcional; moneda tomada de la empresa.
- `create_operating_expense_atomic`: alta transaccional de gastos para owner/admin/manager, validación de almacén, auditoría y sin escritura directa desde clientes autenticados.
- `v_finance_sales_daily`: ventas, reembolsos, coste de ventas y beneficio bruto por día/almacén/moneda.
- `v_finance_expenses_daily`: gastos diarios por categoría.
- `v_finance_daily_summary`: resultado operativo estimado por día/almacén/moneda.
- `v_product_profitability`: ventas netas, coste neto y beneficio bruto por producto/almacén/moneda.

## Reglas contables y límites
- El coste de ventas usa `sale_item_lot_allocations.quantity * unit_cost`, que conserva el coste capturado al vender mediante FEFO.
- Las devoluciones descuentan el importe reembolsado y revierten el coste de las unidades reincorporadas usando `sale_return_lot_allocations`.
- Los gastos operativos solo incluyen los que se registren en esta tabla. El resultado operativo es una estimación de gestión, no una cuenta de resultados legal.
- Los importes de venta incluyen el total cobrado (con impuestos indirectos). El beneficio bruto mostrado es una métrica gerencial preliminar; no sustituye la contabilidad fiscal ni separa IVA/IGV deducible.
- No se incluyen nóminas, amortizaciones, impuestos sobre beneficios, comisiones de pago, coste financiero ni gastos no registrados.
- No se permite editar o borrar gastos desde el cliente. En una siguiente entrega se puede implementar anulación compensatoria con permisos y auditoría.
- Las vistas usan `security_invoker=true` (requiere PostgreSQL 15+) para respetar RLS de las tablas subyacentes.

## Aplicación
1. Aplicar migraciones 0001–0013 en un proyecto Supabase de pruebas y comprobar que las funciones auxiliares y tablas coinciden con este paquete.
2. Aplicar `0014_financial_dashboard_profitability.sql`.
3. Probar con dos tenants y al menos dos almacenes, productos con lotes de costes distintos, ventas parciales, devoluciones parciales y gastos con/sin almacén.
4. Comprobar que el usuario de un tenant no puede leer gastos, ventas ni rentabilidad de otro tenant.
5. Comparar manualmente cada cálculo con los documentos de origen antes de habilitarlo en producción.

## Próximo bloque
Conectar estas vistas a la interfaz: filtros de período, almacén y categoría; tarjetas de ventas netas, coste, beneficio bruto y gastos; gráficos diarios/mensuales y tabla de productos más/menos rentables. Después habrá que validar fiscalidad y plan contable específico de España y Perú.
