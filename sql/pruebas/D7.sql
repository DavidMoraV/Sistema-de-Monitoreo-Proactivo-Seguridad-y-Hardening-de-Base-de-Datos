-- =====================================================================
--  D7 — Posible exfiltración: > 1,000 filas por consulta en tablas sensibles (clientes, ventas)
--  Flujo: n8n/flujos/D7_Exfiltracion.json   ·   Es también la detección del ataque A5 (M5).
-- =====================================================================

-- 1. EMULACIÓN (desde la terminal del servidor; agente_ia entra por el socket local)
--   docker compose exec postgres psql -U agente_ia -d nutrianimales_db -c "SELECT * FROM clientes;" > /dev/null
--   → 1,500 filas en una sola consulta → alerta CRÍTICA

-- 2. DETECCIÓN (usuario monitor_n8n). Versión de SOLO LECTURA (query corregida, sección 10, punto 1):
--    - OR/AND con paréntesis: el umbral aplica a clientes y a ventas.
--    - usuario = pg_roles.rolname (pg_roles no tiene usename).
--    El flujo agrega pg_stat_statements_reset(userid, dbid, queryid) para alertar una sola vez.
SELECT s.queryid, r.rolname AS usuario, s.query, s.calls, s.rows,
       s.rows / NULLIF(s.calls, 0) AS filas_por_ejecucion
FROM pg_stat_statements s
JOIN pg_roles r ON r.oid = s.userid
WHERE s.query ~* '^\s*(select|with)\M'
  AND s.query ~* '\mfrom\M.*\m(clientes|ventas)\M'
  AND r.rolname <> 'monitor_n8n'                 -- consultas del propio monitoreo
  AND s.rows / NULLIF(s.calls, 0) > 1000
ORDER BY s.rows DESC;
-- Falsos positivos: el bot nunca supera 50 filas (M3 fuerza LIMIT 50) y el gerente usa vistas
-- (vw_ventas_resumen no coincide con \mventas\M). pg_dump usa COPY, no SELECT, así que backup.sh
-- tampoco dispara D7. Para excluir un reporte legítimo: AND s.queryid NOT IN (<queryid>).

-- 3. RESPUESTA (ataque A5): rotar la contraseña de agente_ia
--   bash scripts/rotar_password_bd.sh agente_ia    (script de M1)
