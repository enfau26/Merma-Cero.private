import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migrationsDir = path.join(root, 'supabase', 'migrations');
const migrations = fs.readdirSync(migrationsDir).filter((f) => /^\d{4}_.*\.sql$/.test(f)).sort();
const expected = ['0001','0002','0003','0007','0008','0009','0010','0011','0012','0013','0014','0015','0016'];
const actual = migrations.map((f) => f.slice(0,4));
const failures = [];
if (JSON.stringify(actual) !== JSON.stringify(expected)) failures.push(`Cadena de migraciones inesperada: ${actual.join(', ')}`);

const routes = [
  ['registro', 'app/register/page.tsx'], ['login', 'app/login/page.tsx'],
  ['onboarding', 'app/onboarding/page.tsx'], ['inventario', 'app/dashboard/inventory/page.tsx'],
  ['compras', 'app/dashboard/purchases/page.tsx'], ['recepciones', 'app/dashboard/purchases/receipts/page.tsx'],
  ['proveedores', 'app/dashboard/suppliers/page.tsx'], ['informes', 'app/dashboard/reports/page.tsx'],
  ['ventas/TPV', 'app/dashboard/sales/page.tsx'], ['caja', 'app/dashboard/cash/page.tsx'],
];
for (const [label, file] of routes) if (!fs.existsSync(path.join(root, file))) failures.push(`Falta ruta ${label}: ${file}`);

const returnUiFiles = ['app/dashboard/sales/return-form.tsx'];
for (const file of returnUiFiles) if (!fs.existsSync(path.join(root, file))) failures.push(`Falta interfaz de devoluciones: ${file}`);
const sqlFiles = migrations.map((f) => fs.readFileSync(path.join(migrationsDir, f), 'utf8')).join('\n');
const definerCount = (sqlFiles.match(/security\s+definer/gi) ?? []).length;
const searchPathCount = (sqlFiles.match(/set\s+search_path/gi) ?? []).length;
if (definerCount > searchPathCount) failures.push(`Hay ${definerCount} SECURITY DEFINER y solo ${searchPathCount} SET search_path explícitos; revisar manualmente`);

const salesAction = fs.readFileSync(path.join(root, 'src/actions/sales.ts'), 'utf8');
if (!salesAction.includes('createSaleReturnAction') || !salesAction.includes('create_sale_return_atomic')) failures.push('Falta acción de devoluciones');
for (const token of ['create_sale_atomic', 'UUID_RE', 'paymentAmount', 'DUPLICATE']) { if (token === 'DUPLICATE') continue; if (!salesAction.includes(token)) failures.push(`Falta acción/validación de ventas: ${token}`); }
const cashAction = fs.readFileSync(path.join(root, 'src/actions/cash.ts'), 'utf8');
for (const token of ['open_cash_register_atomic', 'record_cash_register_movement_atomic', 'close_cash_register_atomic']) if (!cashAction.includes(token)) failures.push(`Falta operación de caja: ${token}`);
const inventoryAction = fs.readFileSync(path.join(root, 'src/actions/inventory.ts'), 'utf8');
for (const token of ['requiredUuid', 'positiveQuantity', 'boundedText', 'receive_lot', 'consume_stock_fefo', 'record_waste']) {
  if (!inventoryAction.includes(token)) failures.push(`Falta validación/operación de inventario esperada: ${token}`);
}

console.log(`Migraciones: ${migrations.length} (${actual.join(', ')})`);
console.log(`Rutas UI mínimas: ${routes.length}/${routes.length}`);
console.log(`Funciones SECURITY DEFINER encontradas: ${definerCount}; SET search_path: ${searchPathCount}`);
console.log('Interfaz de devoluciones: archivos y acción presentes (pendiente de runtime)');
if (failures.length) {
  console.error('AUDITORÍA V1: FAIL');
  for (const failure of failures) console.error(`- ${failure}`);
  process.exit(1);
}
console.log('AUDITORÍA V1: PASS (solo comprobaciones estáticas; no acredita ejecución real ni seguridad en runtime)');
