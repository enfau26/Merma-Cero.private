# Interfaz pendiente — Entrega 13

La entrega incorpora la capa de datos y vistas SQL. No incluye todavía una pantalla web ni gráficos conectados. Contrato de lectura sugerido:

- KPI/serie temporal: `v_finance_daily_summary`, filtrada por `tenant_id` y rango de `business_date`.
- Categorías de gasto: `v_finance_expenses_daily`.
- Ranking de productos: `v_product_profitability`.
- Alta de gasto: RPC `create_operating_expense_atomic`.

Filtros que deberá exponer la interfaz: período, almacén (incluyendo consolidado sin almacén) y moneda. No sumar importes entre monedas distintas. La capa API debe derivar `tenant_id` del contexto autenticado y verificar permisos; no confiar en un tenant enviado libremente por el navegador.
