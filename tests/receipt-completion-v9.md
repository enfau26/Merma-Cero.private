# Pruebas v9 — cierre por línea

Preparar una orden con dos líneas: A=10 y B=10.

1. Recibir A=10 aceptadas; omitir B. Esperado: estado `partially_received`.
2. Recibir B=10 aceptadas en una segunda recepción. Esperado: estado `received`.
3. En orden A=10/B=10, recibir A=10 y B=0 aceptadas (con rechazo documentado para B). Esperado: `partially_received`.
4. Enviar una línea sin `quantity_received`. Esperado: error `RECEIPT_QUANTITIES_REQUIRED` y rollback total.
5. Enviar una línea sin `quantity_accepted`. Esperado: error `RECEIPT_QUANTITIES_REQUIRED` y rollback total.
6. Verificar que la auditoría distingue el total aceptado de esta recepción del acumulado de la orden.

Estas pruebas están especificadas, no ejecutadas. Requieren PostgreSQL/Supabase de pruebas con usuarios autenticados y datos semilla.
