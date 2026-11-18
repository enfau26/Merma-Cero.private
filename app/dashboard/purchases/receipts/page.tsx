import Link from 'next/link'
import { requireActiveTenant } from '@/lib/tenant'
import { createClient } from '@/lib/supabase/server'
import GoodsReceiptForm, { type ReceivableOrder } from './receipt-form'

export const dynamic = 'force-dynamic'

type Relation<T> = T | T[] | null
function one<T>(value: Relation<T> | undefined): T | null {
  if (Array.isArray(value)) return value[0] ?? null
  return value ?? null
}

export default async function PurchaseReceiptsPage() {
  const { tenant } = await requireActiveTenant()
  const supabase = await createClient()
  const [ordersRes, warehousesRes, receiptsRes] = await Promise.all([
    supabase.from('purchase_orders')
      .select('id,order_number,status,order_date,expected_date,suppliers(legal_name)')
      .eq('tenant_id', tenant.tenant_id)
      .in('status', ['submitted', 'partially_received'])
      .order('created_at', { ascending: false })
      .limit(100),
    supabase.from('warehouses')
      .select('id,name')
      .eq('tenant_id', tenant.tenant_id)
      .eq('is_active', true)
      .order('name'),
    supabase.from('goods_receipts')
      .select('id,receipt_number,received_at,status,notes,purchase_orders(order_number),warehouses(name),goods_receipt_items(quantity_received,quantity_accepted,quantity_rejected)')
      .eq('tenant_id', tenant.tenant_id)
      .order('received_at', { ascending: false })
      .limit(50),
  ])

  const orderIds = (ordersRes.data ?? []).map(order => order.id)
  let orderItems: any[] = []
  let acceptedReceiptItems: any[] = []
  let detailError: string | null = null

  if (orderIds.length) {
    const [itemsRes, acceptedRes] = await Promise.all([
      supabase.from('purchase_order_items')
        .select('id,purchase_order_id,product_id,quantity_ordered,unit_cost,products(name,sku,unit)')
        .eq('tenant_id', tenant.tenant_id)
        .in('purchase_order_id', orderIds)
        .order('created_at', { ascending: true }),
      supabase.from('goods_receipt_items')
        .select('purchase_order_item_id,quantity_accepted,goods_receipts!inner(purchase_order_id,status)')
        .eq('tenant_id', tenant.tenant_id)
        .eq('goods_receipts.status', 'posted')
        .in('goods_receipts.purchase_order_id', orderIds),
    ])
    orderItems = itemsRes.data ?? []
    acceptedReceiptItems = acceptedRes.data ?? []
    detailError = itemsRes.error?.message ?? acceptedRes.error?.message ?? null
  }

  const acceptedByItem = new Map<string, number>()
  for (const receiptItem of acceptedReceiptItems) {
    const key = receiptItem.purchase_order_item_id as string
    acceptedByItem.set(key, (acceptedByItem.get(key) ?? 0) + Number(receiptItem.quantity_accepted ?? 0))
  }

  const itemsByOrder = new Map<string, ReceivableOrder['items']>()
  for (const item of orderItems) {
    const product = one(item.products)
    const quantityOrdered = Number(item.quantity_ordered)
    const acceptedPreviously = acceptedByItem.get(item.id) ?? 0
    const remaining = Math.max(0, Math.round((quantityOrdered - acceptedPreviously) * 1000) / 1000)
    if (remaining <= 0) continue
    const current = itemsByOrder.get(item.purchase_order_id) ?? []
    current.push({
      itemId: item.id,
      productName: product?.name ?? 'Producto sin nombre',
      sku: product?.sku ?? null,
      unit: product?.unit ?? 'ud.',
      quantityOrdered,
      acceptedPreviously,
      remaining,
    })
    itemsByOrder.set(item.purchase_order_id, current)
  }

  const receivableOrders: ReceivableOrder[] = (ordersRes.data ?? []).map(order => {
    const supplier = one(order.suppliers)
    return {
      id: order.id,
      orderNumber: order.order_number,
      status: order.status,
      supplierName: supplier?.legal_name ?? 'Proveedor',
      items: itemsByOrder.get(order.id) ?? [],
    }
  }).filter(order => order.items.length > 0)

  const history = (receiptsRes.data ?? []).map(receipt => {
    const order = one(receipt.purchase_orders)
    const warehouse = one(receipt.warehouses)
    const items = receipt.goods_receipt_items ?? []
    return {
      id: receipt.id,
      receiptNumber: receipt.receipt_number,
      receivedAt: receipt.received_at,
      status: receipt.status,
      orderNumber: order?.order_number ?? '—',
      warehouseName: warehouse?.name ?? '—',
      received: items.reduce((sum, item) => sum + Number(item.quantity_received ?? 0), 0),
      accepted: items.reduce((sum, item) => sum + Number(item.quantity_accepted ?? 0), 0),
      rejected: items.reduce((sum, item) => sum + Number(item.quantity_rejected ?? 0), 0),
    }
  })

  const canReceive = ['owner', 'admin', 'manager', 'operator'].includes(tenant.role)
  const formDataReady = !ordersRes.error && !warehousesRes.error && !detailError
  const pageError = ordersRes.error?.message ?? warehousesRes.error?.message ?? receiptsRes.error?.message ?? detailError

  return <>
    <header className="top">
      <Link href="/dashboard" className="brand">🌿 MERMA <span>CERO</span></Link>
      <div className="row">
        <Link className="btn secondary" href="/dashboard/purchases">Órdenes</Link>
        <Link className="btn secondary" href="/dashboard">Panel</Link>
      </div>
    </header>
    <main className="dashboard inventory-page">
      <div className="split">
        <div>
          <p className="eyebrow">COMPRAS · RECEPCIÓN DE MERCANCÍA</p>
          <h1>Recepciones</h1>
          <p>Registra cantidades aceptadas y rechazadas. Solo la cantidad aceptada crea lotes y aumenta el stock.</p>
        </div>
        <span className="tenant-chip">{tenant.tenant_name} · {tenant.currency_code}</span>
      </div>

      {pageError && <p className="error">No se pudieron cargar todos los datos: {pageError}. Comprueba las migraciones 0007–0009 y las relaciones de Supabase.</p>}

      {!canReceive && <p className="notice">Tu rol permite consultar las recepciones, pero no registrar nuevas entradas.</p>}
      {canReceive && formDataReady && <GoodsReceiptForm orders={receivableOrders} warehouses={warehousesRes.data ?? []} />}
      {canReceive && !formDataReady && <p className="notice">No se muestra el formulario porque no se pudieron cargar de forma fiable las órdenes, líneas, recepciones previas o almacenes. Corrige el acceso y vuelve a intentarlo.</p>}

      <section className="section">
        <div className="section-heading">
          <div><h2>Historial de recepciones</h2><p>Últimas 50 recepciones de esta empresa.</p></div>
        </div>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Recepción</th><th>Orden</th><th>Almacén</th><th>Fecha</th><th>Recibido</th><th>Aceptado</th><th>Rechazado</th><th>Estado</th></tr></thead>
            <tbody>
              {history.map(receipt => <tr key={receipt.id}>
                <td>{receipt.receiptNumber}</td>
                <td>{receipt.orderNumber}</td>
                <td>{receipt.warehouseName}</td>
                <td>{new Date(receipt.receivedAt).toLocaleString(tenant.country_code === 'PE' ? 'es-PE' : 'es-ES', { dateStyle: 'short', timeStyle: 'short', timeZone: tenant.timezone })}</td>
                <td>{receipt.received.toFixed(3)}</td>
                <td>{receipt.accepted.toFixed(3)}</td>
                <td>{receipt.rejected.toFixed(3)}</td>
                <td>{receipt.status === 'posted' ? 'Registrada' : 'Anulada'}</td>
              </tr>)}
              {!history.length && <tr><td colSpan={8} className="empty">Todavía no hay recepciones registradas.</td></tr>}
            </tbody>
          </table>
        </div>
      </section>
      <p className="muted footnote">La confirmación llama a receive_purchase_order_atomic. La base de datos bloquea la orden, valida las cantidades y registra recepción, lotes, movimientos, estado y auditoría dentro de una transacción.</p>
    </main>
  </>
}
