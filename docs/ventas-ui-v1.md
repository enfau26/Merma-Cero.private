# MERMA CERO — Interfaz de ventas V1

## Incluido
- Ruta protegida `/dashboard/sales`.
- Selección de almacén y productos activos del tenant resuelto en servidor.
- Carrito de hasta 200 líneas (la función SQL aplica el límite definitivo).
- Captura explícita de cantidad, precio unitario, impuesto y descuento por línea.
- Cobro declarado con método y referencia opcional.
- Registro mediante `create_sale_atomic`; FEFO, asignación de lotes, stock, pagos y auditoría permanecen en la transacción PostgreSQL.
- Historial de las últimas 100 ventas de la empresa activa.

## Límites deliberados
- No existe tarifa de venta en el esquema `products`; por eso el precio se captura en el momento de vender. Se necesita aprobar un modelo de tarifas/listas de precios antes de persistir precios de catálogo.
- Los métodos tarjeta y transferencia son solo declaraciones de cobro. No hay pasarela ni movimiento de dinero real.
- No se emiten facturas ni comprobantes fiscales. La integración normativa de Perú y España se mantiene fuera del alcance de esta interfaz.
- El formulario admite una sola forma de pago por venta en esta primera iteración; la RPC admite varios pagos.

## Validación
- La acción de servidor valida UUID, líneas duplicadas, rangos, decimales y coincidencia exacta entre total y pago.
- La función SQL vuelve a validar rol, tenant, almacén, productos, existencias FEFO y suma de pagos dentro de una transacción.
- La lectura usa `tenant_id` y sigue sometida a RLS.
