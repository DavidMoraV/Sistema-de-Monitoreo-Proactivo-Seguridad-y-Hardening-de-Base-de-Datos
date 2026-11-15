-- =====================================================================
--  D6 — UPDATE masivo sin WHERE (> 50 filas)   Flujo: n8n/flujos/D6_Update_masivo.json
--  Ejecutar como postgres:  docker compose exec postgres psql -U postgres -d nutrianimales_db
--  Fuente: pg_stat_statements (filas promedio por ejecución = rows / calls).
-- =====================================================================

-- 1. EMULACIÓN (enunciado: sobre una copia de lotes_produccion)
CREATE TABLE prueba_update AS SELECT * FROM lotes_produccion LIMIT 200;
UPDATE prueba_update SET estado = 'cancelado';  -- 200 filas, sin WHERE → alerta CRÍTICA

--    Variante para la demo (tabla real y auditada, sin cambiar ningún valor):
--    UPDATE lotes_produccion SET estado = estado;
--    Modifica 500 filas "en papel": dispara D6 y deja 500 registros en auditoria_datos
--    con valor_antes / valor_nuevo, que es justo la acción que recomienda la alerta.

-- 2. DETECCIÓN (usuario monitor_n8n). Versión de SOLO LECTURA para revisar a mano.
--    El flujo agrega pg_stat_statements_reset(userid, dbid, queryid) para alertar una sola vez.
SELECT s.queryid, r.rolname AS usuario, s.query, s.calls, s.rows,
       s.rows / NULLIF(s.calls, 0) AS filas_por_ejecucion
FROM pg_stat_statements s
JOIN pg_roles r ON r.oid = s.userid
WHERE s.query ~* '^\s*update\M'
  AND s.query !~* '\mwhere\M'
  AND s.query !~* '\m(pg_settings_snapshot|snapshot_tablas)\M'
  AND s.rows / NULLIF(s.calls, 0) > 50;

-- Después de la alerta: qué cambió (solo aplica a la variante sobre lotes_produccion)
SELECT usuario, operacion, fecha, count(*) AS filas
FROM auditoria_datos WHERE tabla = 'lotes_produccion' AND fecha > now() - interval '10 minutes'
GROUP BY 1, 2, 3 ORDER BY fecha DESC;

-- 3. LIMPIEZA
DROP TABLE IF EXISTS prueba_update;
