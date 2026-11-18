import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const ts = require('typescript');
const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, '..');
const migrationsDir = path.join(root, 'supabase', 'migrations');
const expected = [
  '0001_core.sql',
  '0002_auth_tenants_and_role_policies.sql',
  '0003_inventory_transactions_fefo.sql',
  '0007_suppliers_purchasing.sql',
  '0008_atomic_goods_receipts.sql',
  '0009_receipt_completion_integrity.sql',
  '0010_sales_atomic_fefo.sql',
  '0011_sales_returns_atomic.sql',
  '0012_cash_register_sessions.sql',
  '0013_cash_sales_returns_integration.sql',
  '0014_financial_dashboard_profitability.sql',
  '0015_integration_hardening_and_purchase_orders.sql',
  '0016_receipt_input_hardening.sql',
];
const actual = fs.readdirSync(migrationsDir).filter((f) => f.endsWith('.sql')).sort();
const failures = [];
for (const file of expected) if (!actual.includes(file)) failures.push(`Falta migración ${file}`);
for (const file of actual) if (!expected.includes(file)) failures.push(`Migración no prevista en cadena canónica: ${file}`);
if (actual.includes('0012_secure_tenant_onboarding.sql')) failures.push('Colisión histórica 0012 onboarding presente en la cadena');

const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const m7 = read('supabase/migrations/0007_suppliers_purchasing.sql');
if (!/create table if not exists public\.purchase_order_items\s*\([\s\S]*?unique\s*\(tenant_id,\s*id\)/i.test(m7)) {
  failures.push('purchase_order_items no declara UNIQUE (tenant_id,id)');
}
const m15 = read('supabase/migrations/0015_integration_hardening_and_purchase_orders.sql');
const m16 = read('supabase/migrations/0016_receipt_input_hardening.sql');
for (const name of ['create_tenant_with_default_warehouse', 'create_purchase_order_atomic']) {
  if (!m15.includes(`function public.${name}(`)) failures.push(`No existe RPC ${name} en 0015`);
}
if (!m16.includes('receive_purchase_order_atomic(uuid, uuid, uuid, text, jsonb, text)')) failures.push('0016 no endurece la RPC de recepción');
for (const name of ['goods_receipts_receipt_number_length_check','goods_receipts_notes_length_check','goods_receipt_items_rejection_reason_length_check','goods_receipt_items_lot_code_length_check']) {
  if (!m16.includes(name)) failures.push(`Falta restricción de recepción ${name}`);
}
const purchaseActions = read('src/actions/purchases.ts');
for (const rpc of ['create_purchase_order_atomic', 'receive_purchase_order_atomic']) {
  if (!purchaseActions.includes(`rpc('${rpc}'`)) failures.push(`La acción de compras no llama a ${rpc}`);
  if (!m15.includes(`function public.${rpc}(`) && rpc === 'create_purchase_order_atomic') failures.push(`No se define ${rpc}`);
}
if (!read('src/actions/tenant.ts').includes("rpc('create_tenant_with_default_warehouse'")) {
  failures.push('La acción de tenant no llama al RPC de onboarding integrado');
}

const receiptPage = read('app/dashboard/purchases/receipts/page.tsx');
const receiptForm = read('app/dashboard/purchases/receipts/receipt-form.tsx');
for (const token of ["goods_receipt_items", "purchase_order_items", "warehouses"]) {
  if (!receiptPage.includes(token)) failures.push(`La pantalla de recepciones no integra ${token}`);
}
if (!receiptForm.includes('receivePurchaseOrderAction')) failures.push('El formulario no invoca receivePurchaseOrderAction');
for (const token of ["quantityReceived", "quantityAccepted", "rejectionReason", "lotCode", "expiresOn", "Confirmar recepción"]) {
  if (!receiptForm.includes(token)) failures.push(`El formulario de recepción no contempla ${token}`);
}
if (!purchaseActions.includes("milliUnits(received) !== milliUnits(accepted) + milliUnits(rejected)")) {
  failures.push('La acción de recepción no valida el balance de cantidades a 3 decimales');
}
if (!purchaseActions.includes("seenItems.has(line.purchase_order_item_id)")) {
  failures.push('La acción de recepción no rechaza líneas duplicadas');
}
if (!purchaseActions.includes("revalidatePath('/dashboard/purchases/receipts')")) {
  failures.push('La acción de recepción no invalida la pantalla de historial');
}
if (!read('app/dashboard/page.tsx').includes('/dashboard/purchases/receipts')) {
  failures.push('El panel no enlaza la pantalla de recepciones');
}

if (/^SUPABASE_SERVICE_ROLE_KEY\s*=/m.test(read('.env.example'))) {
  failures.push('No debe haber service_role en .env.example');
}

const walk = (dir) => fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
  const full = path.join(dir, entry.name);
  if (entry.isDirectory()) return walk(full);
  return /\.(ts|tsx)$/.test(entry.name) ? [full] : [];
});
for (const file of walk(path.join(root, 'app')).concat(walk(path.join(root, 'src')))) {
  const source = fs.readFileSync(file, 'utf8');
  const kind = file.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
  const parsed = ts.createSourceFile(file, source, ts.ScriptTarget.Latest, true, kind);
  for (const diagnostic of parsed.parseDiagnostics) {
    failures.push(`${path.relative(root, file)}: error de sintaxis TypeScript en ${diagnostic.start ?? 0}`);
  }
}

if (failures.length) {
  console.error('MERMA CERO release verification: FAILED');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log(`MERMA CERO release verification: OK (${actual.length} migraciones; TypeScript/TSX parseados)`);
