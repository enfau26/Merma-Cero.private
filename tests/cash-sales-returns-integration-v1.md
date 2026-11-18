# Pruebas de aceptación — Entrega 12

Estado: definidas; no ejecutadas en PostgreSQL/Supabase.

1. Operator sincroniza venta completada del mismo tenant/almacén.
2. Cada pago cash de venta crea cash_in exacto.
3. Card/transfer/other no crean movimientos de efectivo.
4. Repetir venta devuelve cero y no duplica.
5. Devolución genera cash_out solo por pagos cash.
6. Repetir devolución no duplica.
7. Documento inexistente, venta no completada o tenant ajeno se rechaza.
8. Caja cerrada/inexistente se rechaza.
9. Almacén distinto se rechaza.
10. Viewer no ejecuta RPC.
11. Escritura directa sigue denegada.
12. Arqueo incluye cobros cash y resta reembolsos cash.
13. Llamadas concurrentes del mismo pago crean un solo movimiento.
14. Sincronización/cierre concurrentes se serializan.
15. Un pago no se puede asociar a dos sesiones.
16. Auditoría contiene documento y cantidad insertada.
17. Error intermedio revierte la llamada completa.
18. Verificar search_path, grants, RLS e aislamiento entre tenants.
