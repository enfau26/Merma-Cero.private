# Pruebas de aceptación — Entrega 11 Caja v1

Estado: casos definidos; no ejecutados contra PostgreSQL/Supabase.

1. Operator abre caja con fondo inicial cero.
2. Apertura con fondo inicial positivo.
3. Rechazar importe inicial negativo o nulo.
4. Rechazar almacén inexistente, inactivo o de otro tenant.
5. Rechazar nombre vacío.
6. Rechazar segunda sesión abierta con mismo nombre/almacén/tenant.
7. Permitir cajas con nombres distintos en el mismo almacén.
8. Registrar entrada de efectivo válida.
9. Registrar salida de efectivo válida.
10. Rechazar movimiento de tipo no permitido, importe nulo/cero/negativo o motivo vacío.
11. Rechazar movimiento sobre sesión cerrada o de otro tenant.
12. Viewer no puede abrir ni registrar movimientos.
13. Operator no puede cerrar caja.
14. Manager puede cerrar caja.
15. Esperado = fondo inicial + entradas − salidas.
16. Diferencia = contado − esperado, con signo correcto.
17. Rechazar arqueo contado negativo o nulo.
18. Dos cierres concurrentes: solo uno puede cerrar; el otro recibe CASH_REGISTER_NOT_OPEN.
19. Escritura directa a tablas denegada a authenticated.
20. RLS impide leer sesiones y movimientos de otro tenant.
21. Auditoría contiene apertura, cada movimiento y cierre con importes.
22. Intento de movimiento concurrente con cierre: el bloqueo de fila debe serializar; no puede quedar un movimiento posterior al cierre.

## Puerta de salida
Ejecutar los 22 casos en Supabase aislado con tenants y roles de prueba; verificar grants, políticas RLS, índices y funciones SECURITY DEFINER. Confirmar especialmente la serialización entre registro de movimiento y cierre.
