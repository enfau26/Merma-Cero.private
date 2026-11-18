'use client'

import { useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createPurchaseOrderAction } from '@/actions/purchases'

type Supplier = { id: string; legal_name: string }
type Product = { id: string; name: string; sku: string | null; unit: string }
type Line = { product_id: string; quantity_ordered: string; unit_cost: string; tax_rate: string }

export default function PurchaseOrderForm({ suppliers, products, currency }: { suppliers: Supplier[]; products: Product[]; currency: string }) {
  const router = useRouter()
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState('')
  const [supplierId, setSupplierId] = useState('')
  const [orderNumber, setOrderNumber] = useState('')
  const [expectedDate, setExpectedDate] = useState('')
  const [notes, setNotes] = useState('')
  const [lines, setLines] = useState<Line[]>([{ product_id: '', quantity_ordered: '1', unit_cost: '0', tax_rate: '0' }])
  const updateLine = (index: number, patch: Partial<Line>) => setLines(current => current.map((line, i) => i === index ? { ...line, ...patch } : line))
  const total = lines.reduce((sum, line) => sum + (Number(line.quantity_ordered) || 0) * (Number(line.unit_cost) || 0) * (1 + (Number(line.tax_rate) || 0) / 100), 0)
  function submit() {
    setError('')
    startTransition(async () => {
      try {
        await createPurchaseOrderAction({ supplierId, orderNumber, expectedDate: expectedDate || null, notes,
          lines: lines.map(line => ({ product_id: line.product_id, quantity_ordered: Number(line.quantity_ordered), unit_cost: Number(line.unit_cost), tax_rate: Number(line.tax_rate) })) })
        setOrderNumber(''); setNotes(''); setLines([{ product_id: '', quantity_ordered: '1', unit_cost: '0', tax_rate: '0' }])
        router.refresh()
      } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo crear la orden') }
    })
  }
  return <section className="panel">
    <h2>Nueva orden de compra</h2>
    {!suppliers.length || !products.length ? <p className="notice">Necesitas al menos un proveedor y un producto activo para crear una orden.</p> : <>
      <div className="form-grid">
        <label className="field"><span>Proveedor</span><select value={supplierId} onChange={e => setSupplierId(e.target.value)}><option value="">Selecciona proveedor</option>{suppliers.map(s => <option key={s.id} value={s.id}>{s.legal_name}</option>)}</select></label>
        <label className="field"><span>Número de orden</span><input value={orderNumber} onChange={e => setOrderNumber(e.target.value)} maxLength={60} placeholder="OC-2026-001" /></label>
        <label className="field"><span>Fecha prevista</span><input type="date" value={expectedDate} onChange={e => setExpectedDate(e.target.value)} /></label>
        <label className="field"><span>Notas</span><input value={notes} onChange={e => setNotes(e.target.value)} maxLength={1000} /></label>
      </div>
      <h3>Productos</h3>
      {lines.map((line, index) => <div className="form-grid" key={index} style={{marginBottom:12}}>
        <label className="field"><span>Producto</span><select value={line.product_id} onChange={e => updateLine(index, { product_id: e.target.value })}><option value="">Selecciona producto</option>{products.map(p => <option key={p.id} value={p.id}>{p.name}{p.sku ? ` · ${p.sku}` : ''}</option>)}</select></label>
        <label className="field"><span>Cantidad</span><input type="number" min="0.001" step="0.001" value={line.quantity_ordered} onChange={e => updateLine(index, { quantity_ordered: e.target.value })}/></label>
        <label className="field"><span>Coste unitario ({currency})</span><input type="number" min="0" step="0.0001" value={line.unit_cost} onChange={e => updateLine(index, { unit_cost: e.target.value })}/></label>
        <label className="field"><span>Impuesto (%)</span><input type="number" min="0" max="100" step="0.01" value={line.tax_rate} onChange={e => updateLine(index, { tax_rate: e.target.value })}/></label>
        {lines.length > 1 && <button className="btn secondary" type="button" onClick={() => setLines(current => current.filter((_, i) => i !== index))}>Eliminar línea</button>}
      </div>)}
      <div className="row" style={{justifyContent:'space-between',alignItems:'center'}}><button className="btn secondary" type="button" onClick={() => setLines(current => [...current, { product_id:'', quantity_ordered:'1', unit_cost:'0', tax_rate:'0' }])} disabled={lines.length >= 200}>Añadir producto</button><strong>Total estimado: {total.toFixed(2)} {currency}</strong></div>
      {error && <p className="error" role="alert">{error}</p>}
      <button className="btn" type="button" disabled={pending || !supplierId || !orderNumber.trim() || lines.some(l => !l.product_id || !(Number(l.quantity_ordered)>0) || !(Number(l.unit_cost)>=0) || !(Number(l.tax_rate)>=0) || Number(l.tax_rate)>100)} onClick={submit}>{pending ? 'Guardando…' : 'Crear orden de compra'}</button>
    </>}
  </section>
}
