'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createSaleReturnAction } from '@/actions/sales'

type Item = { id: string; label: string; quantity: number; remaining: number; line_total: number }

export default function ReturnForm({ saleId, items, currency }: { saleId: string; items: Item[]; currency: string }) {
  const router = useRouter()
  const [itemId, setItemId] = useState(items.find(item => item.remaining > 0)?.id ?? '')
  const [quantity, setQuantity] = useState('1')
  const [reason, setReason] = useState('')
  const [method, setMethod] = useState<'cash' | 'card' | 'transfer' | 'other'>('cash')
  const [reference, setReference] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  const [pending, startTransition] = useTransition()
  const selected = items.find(item => item.id === itemId)
  const qty = Number(quantity)
  const refund = selected && Number.isFinite(qty) && qty > 0
    ? Math.round(selected.line_total * qty / selected.quantity * 100) / 100 : 0

  function submit() {
    if (!selected || !reason.trim() || !Number.isFinite(qty) || qty <= 0 || qty > selected.remaining) {
      setError('Selecciona una línea, una cantidad pendiente válida y el motivo de devolución.')
      return
    }
    setError(''); setSuccess('')
    startTransition(async () => {
      try {
        const result = await createSaleReturnAction({ saleId, saleItemId: itemId, quantity: qty, reason, paymentMethod: method, paymentReference: reference })
        setSuccess(`Devolución registrada. Reembolso declarado: ${result.refund.toFixed(2)} ${currency}.`)
        setReason(''); setReference(''); setQuantity('1'); router.refresh()
      } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo registrar la devolución') }
    })
  }

  return <section className="panel">
    <h3>Registrar devolución</h3>
    {items.some(item => item.remaining > 0) ? <>
      <div className="formgrid">
        <label>Producto vendido<select className="select" value={itemId} onChange={e => setItemId(e.target.value)}>{items.filter(item => item.remaining > 0).map(item => <option key={item.id} value={item.id}>{item.label} · pendiente {item.remaining.toFixed(3)}</option>)}</select></label>
        <label>Cantidad a devolver<input className="input" type="number" min="0.001" step="0.001" max={selected?.remaining ?? 0} value={quantity} onChange={e => setQuantity(e.target.value)} /></label>
        <label>Motivo<input className="input" maxLength={500} required value={reason} onChange={e => setReason(e.target.value)} placeholder="Ej. producto defectuoso" /></label>
        <label>Forma de reembolso<select className="select" value={method} onChange={e => setMethod(e.target.value as typeof method)}><option value="cash">Efectivo</option><option value="card">Tarjeta</option><option value="transfer">Transferencia</option><option value="other">Otro</option></select></label>
        <label>Referencia (opcional)<input className="input" maxLength={120} value={reference} onChange={e => setReference(e.target.value)} /></label>
      </div>
      <div className="split" style={{ marginTop: 12 }}><strong>Reembolso calculado: {refund.toFixed(2)} {currency}</strong><button className="btn" type="button" disabled={pending || !selected || qty <= 0 || qty > (selected?.remaining ?? 0)} onClick={submit}>{pending ? 'Registrando…' : 'Confirmar devolución'}</button></div>
    </> : <p className="muted">Esta venta ya no tiene cantidades pendientes de devolución.</p>}
    {error && <p className="error" role="alert">{error}</p>}{success && <p className="success" role="status">{success}</p>}
  </section>
}
