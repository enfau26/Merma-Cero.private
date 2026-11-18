# Entrega 08 — Integridad de cierre por línea (v9)

## Corrección
La versión anterior determinaba el estado `received` comparando la suma global aceptada con la suma global pedida. Esa comparación podía marcar una orden como recibida aunque una línea estuviera incompleta y otra tuviera una recepción superior a su propia cantidad (si las reglas previas no lo detectaban por otro camino).

La migración `0009_receipt_completion_integrity.sql` reemplaza la RPC `receive_purchase_order_atomic` para que el estado sea `received` únicamente cuando cada línea de la orden haya alcanzado individualmente su `quantity_ordered` mediante unidades aceptadas.

También:
- exige cantidades recibidas y aceptadas explícitas;
- conserva el control de duplicados de línea, permisos y pertenencia al tenant;
- registra por separado las unidades aceptadas en esta recepción y el acumulado aceptado de la orden en auditoría.

## Orden de migraciones
1. `0001_core.sql`
2. `0007_suppliers_purchasing.sql`
3. `0008_atomic_goods_receipts.sql`
4. `0009_receipt_completion_integrity.sql`

No ejecutar sobre producción sin copia de seguridad y validación previa en un proyecto Supabase de pruebas.

## Pruebas de aceptación nuevas
- Orden con dos líneas: recibir toda la línea A y nada de B debe dejar la orden `partially_received`.
- Recibir el resto de B en una segunda recepción debe cambiar la orden a `received`.
- Recepción con `quantity_received` o `quantity_accepted` ausente debe fallar sin insertar recepción, lote, movimiento ni auditoría.
- `accepted_quantity_this_receipt` debe representar solo la recepción recién creada.
- `accepted_quantity_order_total` debe representar el acumulado de la orden.
