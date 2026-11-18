# MERMA CERO — Entrega 06: alertas e informes

## Incluido
- Ruta `/dashboard/reports`, aislada por la empresa activa y protegida por `requireActiveTenant()`.
- Alerta de stock mínimo: agrega `quantity_available` de los lotes por producto y compara con `products.min_stock`.
- Caducidades: muestra lotes con stock que caducan desde hoy hasta 30 días.
- Lotes caducados: muestra existencias, coste unitario y valor estimado a coste.
- Resumen de mermas: últimos 100 registros disponibles, con importe `estimated_loss`.
- Edición de nombre, SKU, unidad, stock mínimo y condición perecedera.
- Desactivación lógica de productos y almacenes (`is_active=false`), sin borrado físico ni pérdida del historial.

## Permisos
Las acciones usan `requireActiveTenant()` en servidor y filtran siempre por `tenant_id`. La política de migración 0002 permite actualizar productos/almacenes a owner, admin y manager. Los usuarios de solo lectura no ven controles de gestión. La desactivación es lógica; los registros históricos permanecen.

## Criterios y límites
- El stock se calcula sumando lotes visibles con cantidad positiva; los lotes caducados siguen incluidos en el cálculo de stock mínimo para no ocultar existencias bloqueadas. La alerta de caducidad se presenta por separado.
- Los avisos cubren 30 días naturales y usan la fecha local de la empresa para el día actual.
- Los lotes mostrados se limitan a 1.000 y las mermas a los 100 registros más recientes. No se debe interpretar el informe de mermas como un histórico contable completo.
- La valoración de lotes caducados es cantidad disponible × coste unitario registrado; es orientativa, no un asiento contable.
- No se ha añadido una acción de reactivación en esta entrega.

## Pruebas de aceptación pendientes en Supabase de pruebas
1. Un producto con stock total inferior o igual al mínimo aparece en alertas.
2. Al recibir stock, la alerta se recalcula al recargar.
3. Un lote que caduca hoy o dentro de 30 días aparece en caducidades próximas.
4. Un lote caducado con stock aparece en la tabla de revisión.
5. Una merma registra y refleja `estimated_loss`.
6. Un manager puede editar y desactivar productos/almacenes.
7. Un operator no ve controles de gestión y no puede ejecutar la acción directamente por RLS.
8. Una empresa no puede consultar alertas de otra empresa.
