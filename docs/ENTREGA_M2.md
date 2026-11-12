# Entrega de M2 (DBA) al grupo

**Fecha:** 12 de noviembre de 2026 · **Responsable:** Jean Rabbat (M2)

La base de datos, la auditoría, el RBAC y el hardening de PostgreSQL están probados y con evidencia. Este documento junta en un solo lugar todo lo de M2 que está repartido en el repo.

> **⚠️ Todos tienen que recrear la base de datos una vez** (sobre todo el servidor de la demo). Si no, PostgreSQL arranca sin SSL y salta la alerta H5:
> ```bash
> git pull && docker compose down && sudo rm -rf volumes/pgdata && docker compose up -d
> ```

---

## 1. Qué está terminado

| Bloque | Detalle | Checklist |
|---|---|---|
| Esquema y datos | 12 tablas del enunciado + 2 auxiliares (R5, D2). 1,500 clientes y 1,500 ventas | — |
| Auditoría | `auditoria_datos`, `fn_auditoria()` (SECURITY DEFINER), triggers en lotes, ventas, clientes y productos | 3.1–3.4 |
| RBAC | `rol_gerente` (solo vistas), `rol_ti`, `rol_auditor`; usuarios `agente_ia` y `monitor_n8n` | 2.2, 2.3 |
| Hardening de BD | scram-sha-256, SSL, agente_ia solo lectura, consultas lentas, baseline | HD05–07, HD11, HD12, 1.4 |
| Corrección de H5 | Ahora la prueba `ALTER SYSTEM ... 'md5'` sí dispara H5 | 4.2 |
| Corrección de R5 | Ya no salta en falso al conectarse N8N | 4.1 |
| Respaldos | `backup.sh` registra cada respaldo en `backups` (alerta D3) | 4.3 |
| Rendimiento | pgbench: 2,531 tps, 5.89 ms de latencia, 0 fallos. Reporte pgBadger | Semana 4 |

## 2. Dónde está cada cosa

| Archivo | Qué hace |
|---|---|
| [`sql/00`](../sql/00_extensiones.sql) … [`sql/06`](../sql/06_snapshot_inicial.sql) | Crean toda la base al iniciar el contenedor (00–05 los hizo M1; 04 y 06 los ajustó M2) |
| [`sql/pruebas/H5.sql`](../sql/pruebas/H5.sql) | Escenario de H5: emulación, detección y limpieza |
| [`sql/pruebas/R5.sql`](../sql/pruebas/R5.sql) | Escenario de R5: emulación, detección y limpieza |
| [`scripts/backup.sh`](../scripts/backup.sh) | Respaldo con `pg_dump` + registro en `backups` |
| [`scripts/evidencias_m2.sh`](../scripts/evidencias_m2.sh) | Muestra cada evidencia de M2 con su código y la hora (sirve para la demo) |
| [`scripts/rendimiento.sh`](../scripts/rendimiento.sh) | pgbench + reporte pgBadger |
| [`docs/pgbench_resultado.txt`](pgbench_resultado.txt) | Salida completa de pgbench |
| [`docs/pgbadger/reporte.html`](pgbadger/reporte.html) | Reporte de pgBadger (descargarlo y abrirlo en el navegador) |

## 3. Capturas (todas en [`docs/capturas/`](capturas/))

| Código | Archivo | Muestra |
|---|---|---|
| HD05 | [`HD05_scram.png`](capturas/HD05_scram.png) | `password_encryption = scram-sha-256` y hashes SCRAM |
| HD06 | [`HD06_ssl.png`](capturas/HD06_ssl.png) | `ssl = on` |
| HD07 | [`HD07_agente_ia_denied.png`](capturas/HD07_agente_ia_denied.png) | INSERT de agente_ia → permission denied |
| HD11 | [`HD11_consulta_lenta.png`](capturas/HD11_consulta_lenta.png) | `pg_sleep(2)` en pg_stat_statements y en el log |
| HD12 / 1.4 | [`HD12_baseline.png`](capturas/HD12_baseline.png) | Baseline: esperado = actual |
| 2.2 | [`C2_2_roles_rbac.png`](capturas/C2_2_roles_rbac.png) | Los 3 roles y sus usuarios |
| 2.3 | [`C2_3_gerente_denied.png`](capturas/C2_3_gerente_denied.png) | Gerente sin acceso a auditoria_datos |
| 3.1 | [`C3_1_tabla_auditoria.png`](capturas/C3_1_tabla_auditoria.png) | Estructura de auditoria_datos |
| 3.2 | [`C3_2_fn_auditoria.png`](capturas/C3_2_fn_auditoria.png) | fn_auditoria en pg_proc |
| 3.3 | [`C3_3_triggers.png`](capturas/C3_3_triggers.png) | Triggers activos |
| 3.4 | [`C3_4_trigger_update_delete.png`](capturas/C3_4_trigger_update_delete.png) | UPDATE y DELETE con valor antes/después |
| — | [`M2_pgbench.png`](capturas/M2_pgbench.png) | Resultado de pgbench |
| — | [`M2_pgbadger_resumen.png`](capturas/M2_pgbadger_resumen.png) | Vista general de pgBadger |
| — | [`M2_pgbadger_consultas.png`](capturas/M2_pgbadger_consultas.png) | Consultas que más tiempo consumieron |

Para repetir cualquier captura: `./scripts/evidencias_m2.sh HD07` (o `2.3`, `3.4`, etc.).

## 4. Cambios que afectan a otros

**M1 (David):** `ssl`, `password_encryption`, `log_min_duration_statement` y `log_connections` salieron del `command:` del `docker-compose.yml` y ahora se aplican con `ALTER SYSTEM` en `sql/04_baseline.sql`. Con `-c` en el compose, el `ALTER SYSTEM` de la prueba H5 no tenía efecto (la línea de comandos tiene prioridad).

**M3:** R5 tiene que comparar contra la vista **`vw_settings_servidor`**, no contra `pg_settings`. `pg_settings` incluye valores de sesión (TimeZone, application_name, tcp_keepalives) y hace saltar R5 apenas N8N se conecta. Query lista en [`sql/pruebas/R5.sql`](../sql/pruebas/R5.sql). Para la prueba de H5 usar [`sql/pruebas/H5.sql`](../sql/pruebas/H5.sql).

**M4:** `snapshot_tablas` ya trae una foto inicial (de hace 1 hora) para D2. `backups` arranca con un registro `ok`, así que D3 no salta al iniciar. Para emular D3: `UPDATE backups SET fecha = NOW() - INTERVAL '30 hours';`.

**M5:** la sección del informe de M2 (modelo de datos, triggers, RBAC, hardening 5–7, 11 y 12, problemas resueltos, rendimiento) se entrega aparte en Word, con las 14 capturas ya puestas como figuras.

## 5. Demo en vivo (2:00–4:30)

```bash
./scripts/evidencias_m2.sh 3.4    # UPDATE + DELETE quedan en auditoria_datos con antes/después
./scripts/evidencias_m2.sh 2.3    # el gerente ve su reporte pero no la auditoría
./scripts/evidencias_m2.sh HD05   # scram-sha-256
```
`3.4` borra el lote 500. Si ya se borró en un ensayo, cambiar el `id` del DELETE en el script por otro lote sin controles de calidad (por ejemplo 499).
