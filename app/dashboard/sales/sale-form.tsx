'use client'

import { useMemo, useState, useTransition } from 'react'
import { useRouter } from 'next/navigation'
import { createSaleAction } from '@/actions/sales'

type Product = { id: string; name: string; sku: string | null; unit: string }
type Warehouse = { id: string; name: string }
type Line = { product_id: string; quantity: number; unit_price: number; tax_rate: number; discount_amount: number }

export default function SaleForm({ products, warehouses, currency }: { products: Product[]; warehouses: Warehouse[]; currency: string }) {
  const router = useRouter()
  const [warehouseId, setWarehouseId] = useState(warehouses[0]?.id ?? '')
  const [productId, setProductId] = useState(products[0]?.id ?? '')
  const [quantity, setQuantity] = useState('1')
  const [price, setPrice] = useState('0')
  const [tax, setTax] = useState('0')
  const [discount, setDiscount] = useState('0')
  const [lines, setLines] = useState<Line[]>([])
  const [method, setMethod] = useState<'cash'|'card'|'transfer'|'other'>('cash')
  const [reference, setReference] = useState('')
  const [notes, setNotes] = useState('')
  const [error, setError] = useState('')
  const [pending, startTransition] = useTransition()
  const total = useMemo(() => lines.reduce((sum, l) => {
    const base = Math.round((l.quantity * l.unit_price - l.discount_amount) * 100) / 100
    return sum + base + Math.round(base * l.tax_rate) / 100
  }, 0), [lines])
  function addLine() {
    const q = Number(quantity), p = Number(price), t = Number(tax), d = Number(discount)
    if (!productId || lines.some(l => l.product_id === productId) || ![q,p,t,d].every(Number.isFinite) || q <= 0 || p < 0 || t < 0 || t > 100 || d < 0 || q*p < d) { setError('Revisa la línea: producto único, cantidad, precio, impuesto y descuento válidos.'); return }
    setLines(current => [...current, { product_id: productId, quantity: q, unit_price: p, tax_rate: t, discount_amount: d }])
    setError('')
  }
  function submit() {
    if (!warehouseId || !lines.length || total <= 0) { setError('Selecciona almacén y añade al menos una línea con importe positivo.'); return }
    const amount = Math.round(total * 100) / 100
    const saleNumber = `V-${new Date().toISOString().replace(/[-:TZ.]/g, '').slice(0, 14)}`
    startTransition(async () => {
      try {
        await createSaleAction({ warehouseId, saleNumber, notes, lines, paymentMethod: method, paymentAmount: amount, paymentReference: reference })
        setLines([]); setNotes(''); setReference(''); setError('')
        router.refresh()
      } catch (e) { setError(e instanceof Error ? e.message : 'No se pudo registrar la venta') }
    })
  }
  return <section className="panel">
    <h2>Nueva venta</h2>
    <p className="muted">El precio se introduce en cada operación; el catálogo no contiene una tarifa de venta configurada. La salida de existencias se asigna en PostgreSQL mediante FEFO.</p>
    <div className="formgrid">
      <label>Almacén<select className="select" value={warehouseId} onChange={e=>setWarehouseId(e.target.value)}>{warehouses.map(w=><option key={w.id} value={w.id}>{w.name}</option>)}</select></label>
      <label>Producto<select className="select" value={productId} onChange={e=>setProductId(e.target.value)}>{products.map(p=><option key={p.id} value={p.id}>{p.name}{p.sku ? ` · ${p.sku}` : ''}</option>)}</select></label>
      <label>Cantidad<input className="input" type="number" min="0.001" step="0.001" value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
      <label>Precio unitario ({currency})<input className="input" type="number" min="0" step="0.0001" value={price} onChange={e=>setPrice(e.target.value)}/></label>
      <label>Impuesto (%)<input className="input" type="number" min="0" max="100" step="0.01" value={tax} onChange={e=>setTax(e.target.value)}/></label>
      <label>Descuento de línea ({currency})<input className="input" type="number" min="0" step="0.01" value={discount} onChange={e=>setDiscount(e.target.value)}/></label>
    </div>
    <div className="row" style={{marginTop:12}}><button className="btn secondary" type="button" onClick={addLine}>Añadir producto</button></div>
    {lines.length > 0 && <div className="table-wrap" style={{marginTop:16}}><table><thead><tr><th>Producto</th><th>Cantidad</th><th>Precio</th><th>Impuesto</th><th>Descuento</th><th></th></tr></thead><tbody>{lines.map((l,i)=><tr key={l.product_id}><td>{products.find(p=>p.id===l.product_id)?.name ?? 'Producto'}</td><td>{l.quantity}</td><td>{l.unit_price.toFixed(2)}</td><td>{l.tax_rate}%</td><td>{l.discount_amount.toFixed(2)}</td><td><button className="btn danger" type="button" onClick={()=>setLines(current=>current.filter((_,j)=>j!==i))}>Quitar</button></td></tr>)}</tbody></table></div>}
    <div className="formgrid" style={{marginTop:16}}>
      <label>Método de pago<select className="select" value={method} onChange={e=>setMethod(e.target.value as typeof method)}><option value="cash">Efectivo</option><option value="card">Tarjeta</option><option value="transfer">Transferencia</option><option value="other">Otro</option></select></label>
      <label>Referencia (opcional)<input className="input" maxLength={120} value={reference} onChange={e=>setReference(e.target.value)}/></label>
      <label>Notas<input className="input" maxLength={2000} value={notes} onChange={e=>setNotes(e.target.value)}/></label>
    </div>
    <div className="split" style={{marginTop:16}}><strong>Total: {total.toFixed(2)} {currency}</strong><button className="btn" type="button" disabled={pending || !lines.length || total <= 0} onClick={submit}>{pending ? 'Registrando…' : 'Confirmar venta'}</button></div>
    {error && <p className="error" role="alert">{error}</p>}
  </section>
}
