# MERMA CERO V1.0 — Plan de cierre del producto

**Estado:** candidato de integración RC0; no apto aún para producción.  
**Regla de proyecto:** no se abrirán más entregas numeradas. El trabajo restante se gestiona como cierre de V1.0 y correcciones sobre una única línea base.

## Línea base revisada

Paquete de partida: `MERMA_CERO_entrega_16_recepcion_compras_ui_v1.zip`.

- Next.js 15 App Router, React 19, TypeScript y Supabase SSR.
- Migraciones canónicas: `0001`, `0002`, `0003`, `0007`–`0016` (13 archivos).
- Interfaz disponible: registro, login, onboarding, dashboard, inventario, informes, proveedores, compras, recepción, ventas/TPV y caja.
- Backend SQL descrito: compras/recepciones atómicas, ventas FEFO, devoluciones, caja y panel financiero.
- La UI de devoluciones sigue pendiente. Ventas/TPV y caja se han incorporado en este incremento; su validación runtime sigue pendiente. El backend existente no equivale por sí solo a una funcionalidad operativa terminada.

## Incremento de integración de ventas y caja

- `app/dashboard/sales`: pantalla TPV con selección de almacén/productos, carrito, impuestos, descuentos, método de cobro declarado e historial.
- `src/actions/sales.ts`: validación server-side y llamada a `create_sale_atomic`; el descuento FEFO sigue dentro de la transacción SQL.
- `app/dashboard/cash`: apertura de sesión, movimientos de efectivo y cierre con arqueo.
- `src/actions/cash.ts`: llamadas a las RPC `open_cash_register_atomic`, `record_cash_register_movement_atomic` y `close_cash_register_atomic`.
- Se amplió la auditoría estática para exigir las rutas y acciones nuevas.

Límites: no hay pasarela real; la venta acepta un único método de pago por operación en la UI; el registro automático de pagos de venta/devolución en caja mediante `post_cash_document_to_register_atomic` aún necesita interfaz. La UI de devoluciones sigue pendiente.

## Corrección incorporada en RC0

`src/actions/inventory.ts` valida ahora en servidor los UUID, cantidades positivas, coste unitario, longitudes de texto y fecha de caducidad antes de invocar las RPC `receive_lot`, `consume_stock_fefo` y `record_waste`. Se revalidan también los informes tras los movimientos. La autorización final y el aislamiento siguen correspondiendo a PostgreSQL/RLS/RPC.

## Alcance funcional que debe quedar cerrado en V1.0

1. Identidad: registro, confirmación de correo, login, logout y recuperación de contraseña.
2. Multiempresa: alta, membresías, cambio de tenant y aislamiento probado entre empresas.
3. Catálogo: categorías, productos, unidades, SKU y estado activo.
4. Almacenes: alta, consulta y restricciones de uso.
5. Inventario: lotes, entradas, salidas FEFO, mermas, trazabilidad y alertas.
6. Compras: proveedores, órdenes, recepción parcial/completa y rechazos.
7. Ventas: UI TPV, carrito, descuentos, impuestos configurables y pagos declarados; prueba runtime pendiente.
8. Devoluciones: UI, límites acumulados y decisión de estado físico antes de reponer.
9. Caja: apertura, movimientos y cierre disponibles en UI; integración de cobros/reembolsos de documentos pendiente de interfaz y prueba.
10. Informes: existencias, caducidades, mermas, ventas, compras y margen operativo.
11. Localización: moneda, zona horaria, formatos y configuración fiscal separada para Perú y España.

## Puertas obligatorias de salida

- `npm ci` reproducible desde lockfile (actualmente el paquete no incluye lockfile).
- `npm run typecheck` y `npm run build` correctos.
- Aplicar las 13 migraciones en Supabase de pruebas vacío y revisar el esquema resultante.
- Pruebas RLS con dos usuarios y dos tenants; intentar lecturas y escrituras cruzadas.
- Pruebas de concurrencia para consumo FEFO, recepción, venta y devolución; rollback completo ante error.
- Pruebas de permisos por rol en UI, Server Actions y PostgreSQL.
- Recorrido de extremo a extremo: alta → empresa → producto → recepción → venta → devolución → caja → informes.
- Copias de seguridad, observabilidad, límites de abuso y procedimiento de restauración documentados antes de producción.

## Bloqueos y decisiones del propietario

- Proporcionar/autorizar un proyecto Supabase de pruebas; no incluir secretos en el repositorio ni en el chat.
- Confirmar política de lotes/caducidad para perecederos y mercancía caducada.
- Confirmar tratamiento de devoluciones no vendibles (cuarentena, merma o reposición).
- Confirmar si V1.0 emitirá documentos fiscales. Por defecto, no se afirmará cumplimiento de factura electrónica, IVA/IGV ni integración con SUNAT/AEAT sin diseño y validación específica.
- Confirmar si V1.0 solo registra pagos manuales o integra una pasarela. No se realizarán cobros reales en esta fase.

## Lo que no se debe hacer

- No aplicar migraciones a producción ni a una base con historial desconocido.
- No ejecutar la cadena canónica sobre una base que ya tenga la rama legacy `0004` sin una migración de conversión revisada.
- No exponer `service_role`, tokens ni credenciales en cliente, variables públicas o archivos versionados.
- No describir informes operativos como contabilidad legal o liquidación fiscal.
- No declarar V1.0 lista hasta superar todas las puertas de salida.
