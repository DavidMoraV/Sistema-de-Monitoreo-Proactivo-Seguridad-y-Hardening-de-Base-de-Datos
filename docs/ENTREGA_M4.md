# Entrega de M4 (alertas de seguridad de datos D1–D7) al grupo

**Fecha:** 14 de noviembre de 2026 · **Responsable:** Jorge Chaves (M4)

Las 7 alertas de datos están listas como flujos de N8N, con su escenario de prueba en `sql/pruebas/` y un script para emularlas en la demo. Todas usan el subflujo `Enviar_Alerta` de M3 y el usuario `monitor_n8n` de M2, sin cambios en el esquema ni en los permisos.

---

## 1. Qué está terminado

| Código | Qué detecta | Umbral | Severidad | Checklist |
|---|---|---|---|---|
| D1 | `DELETE` sin `WHERE` | > 100 filas por ejecución | CRÍTICA | 4.3 |
| D2 | Crecimiento anormal de una tabla | > 20 % en 30 min | ADVERTENCIA | 4.3 |
| D3 | Sin respaldo exitoso | > 24 h | CRÍTICA | 4.3 |
| D4 | Registros duplicados en tablas críticas | > 5 | ADVERTENCIA | 4.3 |
| D5 | Transacción bloqueada | > 30 s | ADVERTENCIA | 4.3 |
| D6 | `UPDATE` sin `WHERE` | > 50 filas por ejecución | CRÍTICA | 4.4 |
| D7 | Posible exfiltración en `clientes` / `ventas` (valida el ataque A5) | > 1,000 filas por consulta | CRÍTICA | 4.5 |

**Cada alerta se envía una sola vez por evento** (lo que pide el plan para M4), no cada minuto ni cada 10 minutos.

## 2. Dónde está cada cosa

| Archivo | Qué hace |
|---|---|
| `n8n/flujos/D1_Delete_masivo.json` … `D7_Exfiltracion.json` | Un flujo por alerta: *Cada 1 minuto* → *Postgres (monitor_n8n)* → *Code* → `Enviar_Alerta` |
| `sql/pruebas/D1.sql` … `D7.sql` | Emulación, detección (versión de solo lectura) y limpieza de cada alerta |
| `scripts/demo_m4.sh` | `./scripts/demo_m4.sh D6` emula; `./scripts/demo_m4.sh D6 limpiar` deja todo como estaba; `./scripts/demo_m4.sh estado` muestra las últimas alertas D |
| `docs/INFORME_M4.md` | Sección del informe (para M5) |

## 3. Cómo cargarlo

```bash
git pull
bash scripts/init_n8n_m3.sh     # el script de M3 ya incluye los IDs de D1–D7
```

**Cambio en un archivo de M3:** agregué los 7 IDs de los flujos D a la lista `IDS` de `scripts/init_n8n_m3.sh`. El paso 3 de ese script importa **toda** la carpeta `n8n/flujos/`, y N8N 2.45 no deja sobrescribir un flujo activo. Sin este cambio, la segunda vez que se corriera el script fallaría al reimportar los flujos D. Con el cambio, el mismo script los desactiva, los importa y los activa.

## 4. Cómo se evita que la alerta se repita

| Alertas | Problema | Solución |
|---|---|---|
| D1, D6, D7 | `pg_stat_statements` acumula por consulta normalizada. Una vez que `rows / calls` pasa el umbral, la condición sigue verdadera para siempre (sección 10, punto 6) | La misma consulta del flujo llama a `pg_stat_statements_reset(userid, dbid, queryid)` en cada fila detectada. Así se borra solo esa entrada. Si la consulta se vuelve a ejecutar, es un evento nuevo y vuelve a alertar |
| D2 | El crecimiento sigue siendo > 20 % durante 30 minutos | La consulta guarda una foto por minuto en `snapshot_tablas`. Cuando una tabla alerta, se borran sus fotos anteriores y su ventana de 30 min empieza de nuevo con el conteo nuevo |
| D3, D4, D5 | La condición sigue activa hasta que alguien la arregla | La consulta arma una **marca** del evento (fecha del último respaldo, id más alto de los duplicados, PID + hora de inicio del bloqueo) y no devuelve nada si ya hay una alerta con esa marca en `alertas_auditoria` |

Además, `Enviar_Alerta` sigue descartando la misma alerta enviada en los últimos 10 minutos.

> ⚠️ **No ejecuten a mano la consulta del flujo de D1, D6 o D7** (la que tiene `pg_stat_statements_reset`): consume el evento y N8N ya no lo ve. Para revisar a mano, usen la versión de solo lectura de `sql/pruebas/D*.sql`.

## 5. Correcciones respecto al enunciado y al plan

1. **D7 corregida** (sección 10, punto 1): el filtro de tablas va entre paréntesis (el umbral aplica a `clientes` **y** a `ventas`) y el usuario sale de `pg_roles.rolname`.
2. **D1, D6, D7 con `rows / calls`** + reset por `queryid` (sección 10, punto 6). `monitor_n8n` ya tenía el `GRANT EXECUTE` de M2.
3. **Expresiones regulares en vez de `ILIKE`.** `ILIKE '%WHERE%'` falla con nombres que contienen "where", y `'SELECT%FROM clientes%'` también acepta `clientes_xyz`. Se usan `\m` y `\M` (inicio y fin de palabra en PostgreSQL; `\b` en PostgreSQL es *backspace*).
4. **D1 y D6 ignoran `pg_settings_snapshot` y `snapshot_tablas`.** El flujo R5 de M3 hace `DELETE FROM pg_settings_snapshot;` sin `WHERE` cada minuto (~380 filas): sin esta exclusión, D1 saltaría cada minuto.
5. **D2 usa `count(*)`, no `n_live_tup`.** `n_live_tup` es una estimación que cambia con autovacuum o `ANALYZE` y puede dar alertas falsas. Además pide un mínimo de 10 filas de diferencia, para que `plantas` (3 filas) no alerte por un solo registro.
6. **D7 no excluye a `agente_ia`**, porque el ataque A5 se hace justamente con ese usuario. No hace falta: el bot nunca devuelve más de 50 filas (M3 fuerza `LIMIT 50`), y el gerente usa vistas (`vw_ventas_resumen` no coincide con la palabra `ventas`). Solo se excluye a `monitor_n8n`. `pg_dump` usa `COPY`, así que `backup.sh` tampoco dispara D7.

## 6. Pruebas

Las 7 consultas de los flujos se probaron el 14 de noviembre de 2026 contra una base creada con `sql/00`–`06` de este repo, conectado como `monitor_n8n`:

| Alerta | Emulación | Primer ciclo | Ciclo siguiente |
|---|---|---|---|
| D1 | `DELETE FROM prueba_delete` (200 filas) | 1 fila: `postgres`, 200 filas | 0 filas. El `DELETE` de R5 no aparece |
| D2 | +60 filas en `gastos` | `gastos 200 → 260 (+30 %)` | 0 filas |
| D3 | `backups` con 30 h | `Último respaldo exitoso: … (30 h)` | 0 filas tras guardar la alerta; 0 filas tras un respaldo nuevo |
| D4 | 6 clientes duplicados | `Duplicados en clientes: 6` | 0 filas tras guardar la alerta. Con 2 duplicados más: alerta nueva (`8`) |
| D5 | 2 sesiones con `UPDATE` sobre `productos` id 1 | A los 34 s: PID bloqueado, bloqueador y tabla `productos` | — |
| D6 | `UPDATE prueba_update` (200) y `UPDATE lotes_produccion SET estado = estado` (500) | 2 filas | 0 filas. `UPDATE backups` (1 fila) no alerta |
| D7 | `SELECT * FROM clientes` y un `JOIN` ventas–clientes como `agente_ia` | 2 filas (1,508 y 1,500) | 0 filas. `LIMIT 50` y `vw_ventas_resumen` no alertan |

**Pendiente en el servidor de la demo:** importar los flujos, ver las 7 alertas en Telegram y tomar las capturas (sección 7).

## 7. Capturas pendientes (en el servidor de la demo)

`docs/capturas/D1_alerta.png` … `D7_alerta.png`, cada una con la hora del mensaje en Telegram.

```bash
./scripts/demo_m4.sh D1      # esperar ≤ 1 min → captura de Telegram → ./scripts/demo_m4.sh D1 limpiar
./scripts/demo_m4.sh D2      # …
./scripts/demo_m4.sh estado  # confirma que cada alerta quedó en alertas_auditoria
```

## 8. Para M5

- **A5 → D7:** `psql -U agente_ia -d nutrianimales_db -c "SELECT * FROM clientes;"` dispara D7 en ≤ 1 min, con usuario `agente_ia` y 1,500+ filas. La respuesta es `bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD`.
- Si van a repetir A5 en el ensayo y en la demo, no hay que limpiar nada: cada ejecución es un evento nuevo.
- La sección del informe de M4 está en `docs/INFORME_M4.md`.

## 9. Demo en vivo (7:00–9:30)

```bash
./scripts/demo_m4.sh D6           # UPDATE masivo → alerta CRÍTICA en Telegram
./scripts/demo_m4.sh D7           # SELECT masivo de clientes como agente_ia → alerta CRÍTICA
./scripts/demo_m4.sh estado       # las dos alertas en alertas_auditoria
./scripts/demo_m4.sh D6 limpiar
```

Para mostrar también la auditoría, D6 se puede hacer sobre la tabla real sin cambiar ningún dato: `UPDATE lotes_produccion SET estado = estado;`. Dispara D6 y deja 500 registros en `auditoria_datos` con valor antes y después.
