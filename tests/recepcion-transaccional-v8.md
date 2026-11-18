# Casos de prueba · Recepción transaccional v8

| ID | Caso | Resultado esperado |
|---|---|---|
| R01 | Operator del tenant recibe orden propia | RPC autorizada |
| R02 | Viewer ejecuta RPC | `42501` |
| R03 | Usuario de tenant B indica tenant A | `42501` |
| R04 | INSERT directo en goods_receipts | Permiso denegado |
| R05 | INSERT directo en goods_receipt_items | Permiso denegado |
| R06 | Recibido = aceptado + rechazado | Continúa |
| R07 | Cantidades desbalanceadas | Rechazo y rollback |
| R08 | Rechazo sin motivo | Rechazo y rollback |
| R09 | Línea repetida en el mismo JSON | Rechazo y rollback |
| R10 | Línea pertenece a otra orden | Rechazo y rollback |
| R11 | Almacén de otro tenant/inactivo | Rechazo y rollback |
| R12 | Aceptado acumulado supera pedido | Rechazo y rollback |
| R13 | Línea parcialmente aceptada | Lote/movimiento solo por aceptado |
| R14 | Línea totalmente rechazada | Sin lote ni movimiento |
| R15 | Fallo en segunda línea | No queda ningún efecto parcial |
| R16 | Dos recepciones concurrentes | No sobrepasan cantidad pedida aceptada |
| R17 | Número repetido en el tenant | Violación de unicidad y rollback |
| R18 | Recepción completa acumulada | Orden pasa a `received` |
| R19 | Recepción parcial | Orden pasa a `partially_received` |

Estas pruebas están especificadas, no ejecutadas. Ejecutarlas en una base Supabase aislada con usuarios y tenants de prueba antes de aplicar en producción.
