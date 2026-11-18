# Pruebas de aceptación — Entrega 09 Ventas/TPV v1

> Estado inicial: casos definidos; no ejecutados contra PostgreSQL/Supabase.

1. **Venta simple:** vender 2 unidades con stock suficiente. Debe crear venta, línea, pago, asignación de lote, movimiento `sale` y auditoría.
2. **FEFO:** crear dos lotes con caducidades distintas; consumir primero el que caduca antes.
3. **Lote sin caducidad:** debe consumirse después de los lotes con fecha de caducidad.
4. **Varios lotes:** una línea que supera el saldo del primer lote debe continuar en el siguiente lote FEFO.
5. **Stock insuficiente:** la RPC debe fallar con `INSUFFICIENT_STOCK` y no dejar venta, pago, asignación, movimiento ni auditoría parcial.
6. **Pagos mixtos:** efectivo + tarjeta cuya suma coincide con el total debe aceptarse.
7. **Pago incorrecto:** suma inferior o superior al total debe fallar con `PAYMENT_TOTAL_MISMATCH` y rollback.
8. **Producto ajeno/inactivo:** debe fallar sin filtrar ni modificar datos de otra empresa.
9. **Almacén ajeno/inactivo:** debe fallar.
10. **Descuento excesivo:** descuento mayor que el importe bruto de la línea debe fallar.
11. **Doble venta concurrente:** dos sesiones que intentan vender las mismas últimas unidades no pueden dejar stock negativo ni vender más de lo disponible.
12. **Aislamiento RLS:** usuario de empresa A no puede leer ventas, pagos, líneas ni asignaciones de empresa B.
13. **Escritura directa:** `authenticated` no puede insertar/actualizar/borrar tablas de ventas directamente.
14. **Idempotencia de referencia:** repetir `sale_number` en el mismo tenant debe fallar por restricción única sin efectos parciales.
15. **Precisión:** verificar redondeo a dos decimales en importes y tres decimales en cantidades.
16. **JSON nulo:** `p_lines = NULL` debe fallar con `INVALID_SALE_LINES`; no debe crear una venta vacía.
17. **Pagos nulos:** `p_payments = NULL` debe fallar con `INVALID_SALE_PAYMENTS`; no debe crear una venta sin cobro.
18. **Método de pago nulo:** un elemento con `method = null` debe fallar con `INVALID_PAYMENT`.

## Puerta de salida
No marcar la entrega como terminada hasta ejecutar los casos 1–15 en Supabase de pruebas, comprobar `EXPLAIN`/índices en consultas relevantes y revisar permisos efectivos de las RPC `SECURITY DEFINER`.
