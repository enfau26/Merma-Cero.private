# Checklist de aceptación · Proveedores y compras

- [ ] Aplicar núcleo y migración de compras corregida en Supabase de pruebas.
- [ ] Crear tenants A y B y usuarios owner/admin/manager/operator/viewer.
- [ ] Confirmar aislamiento de SELECT entre tenants.
- [ ] Confirmar denegación de INSERT/UPDATE para viewer.
- [ ] Confirmar operator puede registrar recepción, pero no editar órdenes.
- [ ] Confirmar manager puede crear y modificar órdenes.
- [ ] Intentar FK cruzada proveedor-producto-almacén entre tenants; debe fallar.
- [ ] Probar cantidad recibida = aceptada + rechazada.
- [ ] Probar rechazo sin motivo; debe fallar.
- [ ] Probar recepción parcial y recepción final mediante RPC.
- [ ] Probar sobre-recepción y doble envío concurrente; deben rechazarse.
- [ ] Provocar error en una línea y verificar rollback completo.
- [ ] Verificar audit_events y stock_movements para cada operación válida.
