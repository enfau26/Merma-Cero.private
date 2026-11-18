# Pruebas de aceptación — Ventas UI V1

- [ ] Usuario no autenticado redirigido a login.
- [ ] Usuario sin tenant redirigido a onboarding.
- [ ] Usuario solo ve productos, almacenes y ventas del tenant activo.
- [ ] No se acepta producto duplicado en dos líneas.
- [ ] No se acepta cantidad cero/negativa o con más de tres decimales.
- [ ] No se acepta impuesto fuera de 0–100.
- [ ] No se acepta descuento superior al importe de línea.
- [ ] No se acepta importe de pago distinto del total calculado.
- [ ] La RPC rechaza stock insuficiente y revierte toda la venta.
- [ ] Dos ventas concurrentes no consumen dos veces la misma existencia.
- [ ] Asignaciones de lote respetan FEFO.
- [ ] La venta y sus pagos quedan asociados al tenant correcto.
- [ ] Operador puede vender; cierre de caja queda reservado a owner/admin/manager.
- [ ] Confirmar que la venta aparece en historial y actualiza inventario.
