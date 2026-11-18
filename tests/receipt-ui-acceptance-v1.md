# Pruebas de aceptación — Entrega 16

## Preparación
Usar un proyecto Supabase de pruebas vacío con la cadena canónica 0001–0003 y 0007–0015. Crear dos usuarios y dos empresas. No ejecutar sobre producción.

## Casos funcionales
1. Crear proveedor, producto y orden de compra; la orden queda `submitted`.
2. Abrir `/dashboard/purchases/receipts` y comprobar que aparece la orden con todas sus líneas.
3. Registrar recepción parcial con una línea aceptada y otra parcialmente rechazada.
4. Confirmar que solo la cantidad aceptada crea un lote y un movimiento `receipt`.
5. Confirmar que la cantidad rechazada se guarda con su motivo y no aumenta existencias.
6. Comprobar que la orden queda `partially_received` mientras alguna línea tenga cantidad aceptada pendiente.
7. Registrar una segunda recepción y completar todas las líneas; la orden queda `received`.
8. Comprobar que una línea totalmente aceptada deja de aparecer como pendiente aunque otras líneas de la orden sigan abiertas.
9. Comprobar que el historial muestra número, orden, almacén, fecha y totales recibidos/aceptados/rechazados.

## Casos negativos y de seguridad
10. Rechazar una recepción sin número, sin almacén o sin líneas.
11. Rechazar IDs de orden, almacén o línea que no sean UUID.
12. Rechazar dos entradas para el mismo `purchase_order_item_id` en una recepción.
13. Rechazar cantidades negativas, infinitas o con más de 3 decimales.
14. Rechazar balance incorrecto: recibida distinta de aceptada + rechazada.
15. Rechazar cantidad aceptada mayor que la pendiente de la línea.
16. Rechazar cantidad rechazada sin motivo.
17. Rechazar número de recepción duplicado dentro de la empresa.
18. Rechazar orden, almacén o línea pertenecientes a otro tenant.
19. Rechazar usuario sin membresía y roles no autorizados.
20. Ejecutar dos recepciones concurrentes para la misma orden: no debe sobreaceptarse cantidad; una operación puede fallar y no dejar escrituras parciales.
21. Provocar error en una línea tardía y comprobar que no quedan cabecera, lotes, movimientos ni auditoría parciales.

22. Comprobar que 0016 rechaza números de recepción mayores de 60 caracteres, notas mayores de 2.000, motivos mayores de 500 y códigos de lote mayores de 120.
23. Comprobar el `search_path` de la RPC con `pg_proc.proconfig` tras aplicar 0016.

## Validación técnica pendiente
- `npm install`, `npm run typecheck`, `npm run build`.
- Aplicación real de migraciones y pruebas SQL.
- RLS cruzada con dos tenants.
- Prueba de concurrencia en PostgreSQL.
