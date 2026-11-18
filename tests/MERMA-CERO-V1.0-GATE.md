# MERMA CERO V1.0 — Matriz de aceptación de cierre

Marcar `PASS` solo con evidencia reproducible (log, captura de prueba o resultado SQL). `PENDING` no significa aprobado.

| ID | Área | Caso mínimo | Estado inicial |
|---|---|---|---|
| AUTH-01 | Auth | Registro y confirmación de email | PENDING |
| AUTH-02 | Auth | Login, logout y sesión renovada | PENDING |
| AUTH-03 | Auth | Recuperación de contraseña | PENDING |
| TEN-01 | Multiempresa | Crear empresa y almacén principal en una transacción | PENDING |
| TEN-02 | Multiempresa | Usuario A no lee ni modifica tenant de usuario B | PENDING |
| TEN-03 | Multiempresa | Cookie de tenant manipulada no concede acceso | PENDING |
| RBAC-01 | Roles | Cada rol solo ejecuta acciones autorizadas | PENDING |
| CAT-01 | Catálogo | Crear/editar/desactivar producto y categoría | PENDING |
| INV-01 | Inventario | Entrada crea lote y movimiento coherentes | PENDING |
| INV-02 | FEFO | Consumo usa primero el lote con caducidad más próxima | PENDING |
| INV-03 | FEFO | Dos consumos concurrentes no producen stock negativo | PENDING |
| INV-04 | Mermas | Merma reduce lote y genera auditoría | PENDING |
| PUR-01 | Compras | Orden multi-línea se crea atómicamente | PENDING |
| PUR-02 | Recepción | Recepción parcial actualiza pendiente correctamente | PENDING |
| PUR-03 | Recepción | Exceso o duplicación provoca rollback | PENDING |
| SALE-01 | Ventas | Venta y pagos suman el total y descuentan FEFO | PENDING |
| SALE-02 | Ventas | Stock insuficiente revierte toda la venta | PENDING |
| RET-01 | Devoluciones | No permite devolver más de lo vendido menos devoluciones previas | PENDING |
| CASH-01 | Caja | Apertura, entradas/salidas y cierre cuadran | PENDING |
| UI-01 | Interfaz | TPV conectado a create_sale_atomic y FEFO | IMPLEMENTED_STATIC_PENDING_RUNTIME |
| UI-02 | Interfaz | Caja conectada a apertura, movimientos y cierre RPC | IMPLEMENTED_STATIC_PENDING_RUNTIME |
| UI-03 | Interfaz | Devoluciones conectadas a create_sale_return_atomic | IMPLEMENTED_STATIC_PENDING_RUNTIME |
| REP-01 | Informes | Totales concilian con ventas, compras y movimientos | PENDING |
| LOC-01 | Localización | PE/PEN/Lima y ES/EUR/Madrid se muestran correctamente | PENDING |
| BUILD-01 | Build | Typecheck y build limpios desde instalación reproducible | PENDING |
| DB-01 | Base de datos | Cadena de migraciones aplicada en proyecto de pruebas vacío | PENDING |
| SEC-01 | Seguridad | Auditoría de grants, RLS y SECURITY DEFINER | PENDING |
| E2E-01 | E2E | Recorrido completo de compra a informes | PENDING |

## Evidencia exigida

Para cada caso: entorno y versión, identidad/rol usado, tenant, pasos, resultado esperado, resultado real y referencia al log. Nunca adjuntar claves, JWT o datos personales reales.
