# Entrega de M1 (Infra/DevOps) al grupo

**Fecha:** 29 de octubre de 2026 · **Responsable:** David (M1)

El stack base, la base de datos completa y el hardening de PostgreSQL están listos y probados.
Cada integrante levanta **su propia copia** siguiendo el [README](../README.md) (≈ 5 min).
La VM de David es el **servidor de integración** donde se ejecuta la demo final.

---

## 1. Qué está terminado

| Bloque | Detalle | Checklist |
|---|---|---|
| Stack Docker | postgres 16, n8n 2.45.5, nginx; red `nutrianimales-net` | 1.2, 1.3 |
| Hardening 1–12 | Los 12 puntos implementados con evidencia | 1.1 |
| Base de datos | 12 tablas del enunciado + 2 auxiliares (R5, D2). 1,500 clientes y 1,500 ventas (para D7/A5) | — |
| Auditoría | `auditoria_datos`, `fn_auditoria()` (SECURITY DEFINER), triggers en 4 tablas | 3.1–3.4 |
| Baseline | `pg_settings_baseline` (6 parámetros) + `pg_settings_snapshot` | 1.4 |
| RBAC | 3 roles, vistas del gerente, usuarios `agente_ia` y `monitor_n8n` | 2.2, 2.3 |
| `pg_stat_statements` | Activo (R1, D1, D6, D7) | — |
| Logs de PostgreSQL | En `$PGDATA/log`, legibles por `monitor_n8n` vía `pg_read_file` (R4) | — |

### Ajustes respecto al enunciado (documentar en el informe)

1. `fn_auditoria()` es `SECURITY DEFINER` y registra `session_user`: así un UPDATE de `ti_db` queda auditado sin darle permiso sobre `auditoria_datos`.
2. `rol_gerente` solo ve **vistas** (`vw_ventas_resumen`, `vw_produccion_planta`), no tablas.
3. `rol_auditor` recibe `pg_read_all_stats` (para `pg_stat_statements` / `pg_stat_activity`).
4. Contraseñas de usuarios leídas del `.env` (no escritas en el SQL).
5. Clientes y ventas con 1,500 filas (el mínimo de 200 no permite disparar D7 > 1,000).

---

## 2. Qué necesita cada integrante para empezar

1. Aceptar la invitación al repositorio de GitHub.
2. Una VM/servidor **Ubuntu** con Docker (UID 1000).
3. Seguir el README → `docker compose ps` con los 3 servicios arriba.
4. Trabajar en una **rama propia** (`git checkout -b m3-alertas-r`) y abrir Pull Request a `main`.

---

## 3. Pendientes por integrante

### M2 — DBA (gran parte ya resuelta por M1)
- [ ] `scripts/backup.sh`: `pg_dump` + `INSERT INTO backups` (alimenta D3)
- [ ] Apoyar a M3 en la prueba de H5 con `ALTER SYSTEM`
- [ ] Semana 4: pgbench (BD aparte `pgbench_db`) y reporte pgBadger
- [ ] Informe: modelo de datos, triggers, RBAC, hardening 5–7, 11, 12 (capturas ya tomadas por M1)

### M3 — N8N + alertas R y H  ← **siguiente en la cadena crítica**
- [ ] Bot de Telegram (@BotFather) + `chat_id` del grupo + API key de Groq → completar en `.env`
- [ ] **Decidir cómo entra el bot:** el servidor no es público y el webhook de Telegram no acepta el certificado autofirmado → usar **sondeo con `getUpdates`** o un túnel (cloudflared/ngrok)
- [ ] Credenciales en N8N: Postgres `monitor_n8n`, Postgres `agente_ia`, Telegram, Groq (`Bearer {{ $env.GROQ_API_KEY }}`)
- [ ] Subflujo `Enviar_Alerta` (contrato abajo) — **desbloquea a M4 y M5**
- [ ] R1–R5, H3–H5, bot conversacional; exportar JSON a `n8n/flujos/`

### M4 — Alertas D1–D7
- [ ] Ya puede escribir y probar las queries en psql (`sql/pruebas/D1.sql` … `D7.sql`)
- [ ] Usar `rows / NULLIF(calls, 0)` y `pg_stat_statements_reset(0, 0, queryid)` (permiso ya otorgado a `monitor_n8n`)

### M5 — Seguridad ofensiva + host
- [ ] Matriz de riesgos y plantilla del informe (sin dependencias)
- [ ] UFW en el servidor; desactivar servicios innecesarios (vsftpd)
- [ ] Recolección de logs (consultar al profesor Filebeat→Loki), H1, H2, filtro anti-SQLi, ataques A1–A5

### M1 — pendiente
- [ ] Inventario de secretos y política de rotación (checklist 2.4)
- [ ] Demo de rotación de la API key de Groq (6.1) — cuando M3 tenga Groq funcionando
- [ ] README final, prueba en limpio < 5 min, ZIP (7.1, 7.2)

---

## 4. Contrato del subflujo `Enviar_Alerta` (M3 lo construye, M4/M5 lo usan)

```json
{
  "codigo": "D6",
  "severidad": "CRÍTICA",
  "tipo": "UPDATE masivo sin WHERE detectado",
  "tabla": "lotes_produccion",
  "detalle": "Filas modificadas: 200 (umbral: 50)",
  "query": "UPDATE lotes_produccion SET estado = 'cancelado'",
  "usuario": "postgres",
  "accion": "Verificar intención. Consultar auditoria_datos."
}
```

Hace: 1) envía el mensaje a Telegram con el formato oficial · 2) `INSERT INTO alertas_auditoria (tipo, alerta, mensaje, severidad)`.

---

## 5. Reglas del grupo

- **Nunca** compartir el `.env` ni contraseñas por el chat. Cada uno genera el suyo.
- Capturas en `docs/capturas/<código>_<descripción>.png`, mostrando la **hora** en las alertas.
- Escenarios de prueba en `sql/pruebas/<código>.sql` con tres secciones: emulación, detección y limpieza.
- Flujos de N8N exportados a `n8n/flujos/<código>.json` antes de cada commit.
