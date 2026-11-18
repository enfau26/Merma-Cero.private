# MERMA CERO V1.0 — Acta de cierre de candidato RC1

**Fecha de revisión:** 2026-11-18  
**Resultado:** candidato de versión consolidado; **NO autorizado para producción**.

## Línea base

Se revisó el paquete `MERMA_CERO_V1.0_RC1_ventas_caja.zip` (derivado del paquete de recepción de compras). No hay repositorio remoto ni instancia Supabase conectados en este entorno. Esta acta y el paquete no implican cambios en servicios externos.

## Verificaciones ejecutadas en esta revisión

| Control | Resultado | Alcance |
|---|---|---|
| `node scripts/audit-v1.mjs` | PASS | Comprobaciones estáticas definidas por el script |
| `node scripts/verify-release.mjs` | PASS | 13 migraciones esperadas y análisis sintáctico TS/TSX |
| Rutas mínimas auditadas | 10/10 | Existencia de registro, login, onboarding, inventario, compras, recepción, proveedores, informes, ventas y caja |
| Funciones `SECURITY DEFINER` / `SET search_path` | 23 / 32 | Conteo textual; requiere revisión SQL semántica y runtime |
| `npm ci` | NO EJECUTADO | No hay lockfile en el paquete |
| `npm run typecheck` | NO EJECUTADO | No hay `node_modules`; además falta lockfile reproducible |
| `npm run build` | NO EJECUTADO | No hay dependencias instaladas ni configuración de entorno de prueba |
| Migraciones en PostgreSQL | NO EJECUTADO | No hay Supabase/PostgreSQL de pruebas conectado |
| RLS entre dos tenants | NO EJECUTADO | Requiere dos usuarios y una base de pruebas |
| Concurrencia/rollback | NO EJECUTADO | Requiere pruebas de integración reales |
| Flujo E2E completo | NO EJECUTADO | Requiere entorno desplegado de pruebas y datos semilla |

La auditoría estática informa explícitamente que la UI de devoluciones no está acreditada. La documentación de cierre también indica que falta integrar la contabilización automática de cobros/reembolsos de documentos en caja.

## Estado funcional declarado por los artefactos

- Identidad y onboarding multiempresa: hay pantallas, acciones y migraciones; aislamiento real no probado.
- Catálogo e inventario: hay interfaz/acciones; integridad real y FEFO concurrente no probados.
- Compras y recepción: hay interfaz/acciones/RPC; migraciones y concurrencia no probadas en PostgreSQL.
- Ventas/TPV y caja: hay interfaz/acciones/RPC; runtime y conciliación automática no probados.
- Devoluciones: hay backend SQL descrito, pero falta UI integrada y recorrido completo de reembolso/reposición.
- Informes: hay ruta y backend de rentabilidad; cálculos no contrastados contra operaciones reales.
- Fiscalidad Perú/España: no se acredita facturación electrónica ni cumplimiento SUNAT/AEAT, IVA/IGV o libros legales.
- Pagos: no hay pasarela real; el registro de método de pago no equivale a cobro procesado.

## Decisiones del propietario pendientes

1. Política de lotes/caducidad: qué productos exigen lote y fecha; tratamiento de mercancía caducada.
2. Devoluciones: cuándo reponer, poner en cuarentena o registrar merma según estado físico.
3. Alcance fiscal: confirmar si V1.0 será solo gestión operativa o incluirá documentos fiscales homologados en Perú y España. La recomendación para esta RC es **no emitir documentos fiscales**.
4. Pagos: confirmar que esta primera versión solo registra cobros manualmente y no procesa dinero real.
5. Política de numeración de recepciones, ventas y documentos por empresa/país.

## Condiciones obligatorias para declarar producción

1. Resolver la cadena de migraciones con historial limpio. Los números `0004`–`0006` no están presentes en la cadena canónica actual; no ejecutar esta cadena sobre una base histórica sin reconciliar el historial. Existe una colisión histórica de `0012` documentada en el verificador.
2. Añadir y validar un lockfile; ejecutar `npm ci`, `npm run typecheck` y `npm run build` en CI.
3. Aplicar migraciones sobre Supabase de pruebas vacío y revisar esquema, grants, RLS y funciones privilegiadas.
4. Probar con dos usuarios y dos empresas lecturas/escrituras cruzadas, roles y accesos directos a RPC.
5. Probar concurrencia, idempotencia y rollback de recepciones, ventas FEFO, mermas y devoluciones.
6. Completar UI de devoluciones y conciliación de cobros/reembolsos con caja.
7. Ejecutar recorrido E2E: registro → empresa → producto → compra → recepción → venta → devolución → caja → informes.
8. Preparar backup/restauración, monitorización, límites de abuso, privacidad y procedimiento de incidentes.

## Decisión de cierre

Se cierra la **fase de empaquetado incremental** y se congela esta línea base como **MERMA CERO V1.0 RC1**. No se declara V1.0 final ni producción. El trabajo futuro, si se autoriza, debe limitarse a cerrar los bloqueos anteriores sobre esta misma línea base, sin crear nuevas entregas numeradas.
