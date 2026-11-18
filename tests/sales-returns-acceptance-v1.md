# Plan de aceptación — Entrega 10 devoluciones v1

Estado: interfaz web y acción servidor implementadas; los casos siguen pendientes de ejecución en PostgreSQL/Supabase de pruebas.

1. Devolución parcial de una línea: solo repone la cantidad solicitada.
2. Devolución completa de una línea.
3. Devolución de varias líneas de una misma venta.
4. Devolución acumulada en dos operaciones sin superar lo vendido.
5. Rechazo de cantidad acumulada superior a la vendida.
6. Rechazo de línea perteneciente a otra venta.
7. Rechazo de venta inexistente o de otra empresa.
8. Rechazo de venta cuyo estado no sea `completed`.
9. Rechazo de líneas vacías, nulas o con cantidades no positivas.
10. Rechazo de pagos vacíos, nulos, método no permitido o importe no positivo.
11. Rechazo si la suma de pagos no coincide con el reembolso calculado.
12. Reposición en los lotes originales de la venta.
13. Rechazo y rollback si las asignaciones originales no cubren la cantidad solicitada.
14. Dos devoluciones concurrentes de la misma línea: no deben permitir superar lo vendido.
15. Aislamiento multiempresa y lectura RLS.
16. Escritura directa denegada a `authenticated`; RPC permitida al rol autorizado.
17. Verificación de movimientos `return` y auditoría `sale.returned`.
18. Error inducido a mitad de RPC: rollback de todos los cambios.
19. Números de devolución duplicados dentro de una empresa: rechazo por restricción única.
20. Precisión monetaria y redondeo por línea en devoluciones parciales.

## Puerta de salida
No marcar la entrega como validada hasta ejecutar los 20 casos en un proyecto Supabase aislado y revisar planes/índices, permisos RPC y escenarios concurrentes.

## Interfaz web incorporada
- En `/dashboard/sales`, cada venta completada muestra el formulario de devolución.
- Permite seleccionar una línea vendida, cantidad pendiente, motivo y método/referencia de reembolso.
- El importe se calcula proporcionalmente a `line_total`; la RPC vuelve a validar cantidades, permisos y asignaciones dentro de la transacción.
- Esto no sustituye los 20 casos de aceptación: la interfaz queda `IMPLEMENTED_STATIC_PENDING_RUNTIME`.
