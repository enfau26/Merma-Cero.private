'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { receivePurchaseOrderAction } from '@/actions/purchases'

export type ReceivableOrder = {
  id: string
  orderNumber: string
  status: string
  supplierName: string
  items: Array<{
    itemId: string
    productName: string
    sku: string | null
    unit: string
    quantityOrdered: number
    acceptedPreviously: number
    remaining: number
  }>
}

type Warehouse = { id: string; name: string }
type LineInput = {
  quantityReceived: string
  quantityAccepted: string
  rejectionReason: string
  lotCode: string
  expiresOn: string
}

function emptyLine(): LineInput {
  return { quantityReceived: '0', quantityAccepted: '0', rejectionReason: '', lotCode: '', expiresOn: '' }
}

function round3(value: number) {
  return Math.round(value * 1000) / 1000
}

function safeNumber(value: string) {
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : 0
}

export default function GoodsReceiptForm({ orders, warehouses }: { orders: ReceivableOrder[]; warehouses: Warehouse[] }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState('')
  const [selectedOrderId, setSelectedOrderId] = useState(orders[0]?.id ?? '')
  const [warehouseId, setWarehouseId] = useState(warehouses[0]?.id ?? '')
  const [receiptNumber, setReceiptNumber] = useState('')
  const [notes, setNotes] = useState('')
  const [lineValues, setLineValues] = useState<Record<string, LineInput>>(() => Object.fromEntries((orders[0]?.items ?? []).map(item => [item.itemId, emptyLine()])))
  const selectedOrder = orders.find(order => order.id === selectedOrderId) ?? orders[0]

  const totalAccepted = useMemo(() => (selectedOrder?.items ?? []).reduce((sum, item) => {
    const value = lineValues[item.itemId]
    return sum + (value ? Math.max(0, safeNumber(value.quantityAccepted)) : 0)
  }, 0), [selectedOrder, lineValues])

  function changeOrder(nextId: string) {
    const nextOrder = orders.find(order => order.id === nextId)
    setSelectedOrderId(nextId)
    setLineValues(Object.fromEntries((nextOrder?.items ?? []).map(item => [item.itemId, emptyLine()])))
    setError('')
  }

  function updateLine(itemId: string, patch: Partial<LineInput>) {
    setLineValues(current => ({ ...current, [itemId]: { ...(current[itemId] ?? emptyLine()), ...patch } }))
  }

  function submit() {
    setError('')
    if (!selectedOrder || !warehouseId || !receiptNumber.trim()) {
      setError('Selecciona una orden y un almacén e indica el número de recepción.')
      return
    }
    const lines = selectedOrder.items.flatMap(item => {
      const value = lineValues[item.itemId] ?? emptyLine()
      const received = round3(safeNumber(value.quantityReceived))
      const accepted = round3(safeNumber(value.quantityAccepted))
      if (received <= 0) return []
      const rejected = round3(received - accepted)
      return [{
        purchase_order_item_id: item.itemId,
        quantity_received: received,
        quantity_accepted: accepted,
        quantity_rejected: rejected,
        rejection_reason: value.rejectionReason.trim() || null,
        lot_code: value.lotCode.trim() || null,
        expires_on: value.expiresOn || null,
      }]
    })

    if (!lines.length) {
      setError('Indica una cantidad recibida en al menos una línea.')
      return
    }

    for (const line of lines) {
      const source = selectedOrder.items.find(item => item.itemId === line.purchase_order_item_id)!
      if (line.quantity_accepted < 0 || line.quantity_accepted > line.quantity_received) {
        setError(`La cantidad aceptada de ${source.productName} no puede superar la recibida.`)
        return
      }
      if (line.quantity_accepted > source.remaining) {
        setError(`La cantidad aceptada de ${source.productName} supera las ${source.remaining.toFixed(3)} ${source.unit} pendientes.`)
        return
      }
      if (line.quantity_rejected > 0 && !line.rejection_reason) {
        setError(`Indica el motivo del rechazo de ${source.productName}.`)
        return
      }
    }

    startTransition(async () => {
      try {
        await receivePurchaseOrderAction({
          purchaseOrderId: selectedOrder.id,
          warehouseId,
          receiptNumber: receiptNumber.trim(),
          notes,
          lines,
        })
        setReceiptNumber('')
        setNotes('')
        setLineValues(Object.fromEntries(selectedOrder.items.map(item => [item.itemId, emptyLine()])))
        router.refresh()
      } catch (cause) {
        setError(cause instanceof Error ? cause.message : 'No se pudo registrar la recepción.')
      }
    })
  }

  if (!orders.length) {
    return <section className="section"><h2>Registrar recepción</h2><p className="notice">No hay órdenes pendientes de recepción. Crea una orden de compra o termina las recepciones parciales existentes.</p></section>
  }

  return <section className="section">
    <div className="section-heading"><div><h2>Nueva recepción</h2><p>La cantidad aceptada se convierte en existencias; la rechazada queda documentada sin aumentar el stock.</p></div></div>
    {!warehouses.length ? <p className="notice">No hay almacenes activos. Crea o activa un almacén antes de recibir mercancía.</p> : <>
      <div className="form-grid">
        <label className="field"><span>Orden de compra</span><select value={selectedOrder?.id ?? ''} onChange={event => changeOrder(event.target.value)}>{orders.map(order => <option key={order.id} value={order.id}>{order.orderNumber} · {order.supplierName} · {order.status === 'partially_received' ? 'Parcial' : 'Pendiente'}</option>)}</select></label>
        <label className="field"><span>Almacén receptor</span><select value={warehouseId} onChange={event => setWarehouseId(event.target.value)}>{warehouses.map(warehouse => <option key={warehouse.id} value={warehouse.id}>{warehouse.name}</option>)}</select></label>
        <label className="field"><span>Número de recepción</span><input value={receiptNumber} onChange={event => setReceiptNumber(event.target.value)} maxLength={60} placeholder="REC-2026-001" /></label>
        <label className="field"><span>Notas</span><input value={notes} onChange={event => setNotes(event.target.value)} maxLength={2000} placeholder="Observaciones de entrega" /></label>
      </div>
      {selectedOrder && <>
        <div className="table-wrap">
          <table>
            <thead><tr><th>Producto</th><th>Pedido</th><th>Aceptado antes</th><th>Pendiente</th><th>Recibido ahora</th><th>Aceptado ahora</th><th>Rechazado</th></tr></thead>
            <tbody>
              {selectedOrder.items.map(item => {
                const value = lineValues[item.itemId] ?? emptyLine()
                const received = Math.max(0, safeNumber(value.quantityReceived))
                const accepted = Math.max(0, safeNumber(value.quantityAccepted))
                const rejected = Math.max(0, received - accepted)
                return <tr key={item.itemId}>
                  <td><strong>{item.productName}</strong><br/><span className="muted">{item.sku || 'Sin SKU'} · {item.unit}</span></td>
                  <td>{item.quantityOrdered.toFixed(3)}</td>
                  <td>{item.acceptedPreviously.toFixed(3)}</td>
                  <td><strong>{item.remaining.toFixed(3)}</strong></td>
                  <td><input aria-label={`Cantidad recibida ${item.productName}`} type="number" min="0" step="0.001" value={value.quantityReceived} onChange={event => { const next = event.target.value; const received = Math.max(0, Number(next) || 0); updateLine(item.itemId, { quantityReceived: next, quantityAccepted: String(Math.min(round3(received), item.remaining)) }) }}/></td>
                  <td><input aria-label={`Cantidad aceptada ${item.productName}`} type="number" min="0" step="0.001" max={item.remaining} value={value.quantityAccepted} onChange={event => updateLine(item.itemId, { quantityAccepted: event.target.value })}/></td>
                  <td>{rejected.toFixed(3)}</td>
                </tr>
              })}
            </tbody>
          </table>
        </div>
        <div className="two-col" style={{marginTop:16}}>
          {selectedOrder.items.map(item => {
            const value = lineValues[item.itemId] ?? emptyLine()
            const received = Math.max(0, safeNumber(value.quantityReceived))
            const accepted = Math.max(0, safeNumber(value.quantityAccepted))
            const rejected = Math.max(0, round3(received - accepted))
            if (received <= 0) return null
            return <div className="form-card" key={item.itemId}>
              <h3>{item.productName}</h3>
              {rejected > 0 && <label className="field"><span>Motivo de rechazo ({rejected.toFixed(3)} {item.unit})</span><input value={value.rejectionReason} onChange={event => updateLine(item.itemId, { rejectionReason: event.target.value })} maxLength={500} placeholder="Daño, caducidad, diferencia…" /></label>}
              {accepted > 0 && <div className="form-grid">
                <label className="field"><span>Código de lote (opcional)</span><input value={value.lotCode} onChange={event => updateLine(item.itemId, { lotCode: event.target.value })} maxLength={120}/></label>
                <label className="field"><span>Caducidad (opcional)</span><input type="date" value={value.expiresOn} onChange={event => updateLine(item.itemId, { expiresOn: event.target.value })}/></label>
              </div>}
            </div>
          })}
        </div>
      </>}
      <div className="row split" style={{marginTop:18}}>
        <p className="muted">Cantidad aceptada en esta recepción: <strong>{totalAccepted.toFixed(3)}</strong></p>
        <button className="btn" type="button" onClick={submit} disabled={pending || !warehouseId || !receiptNumber.trim()}>{pending ? 'Registrando…' : 'Confirmar recepción'}</button>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      <p className="muted footnote">La cantidad rechazada no entra en inventario. Si una entrega supera lo pendiente, solo se admite la parte aceptada que aún queda por recibir; el exceso debe marcarse como rechazado. La regla para mercancía ya caducada queda pendiente de aprobación del negocio.</p>
    </>}
  </section>
}
