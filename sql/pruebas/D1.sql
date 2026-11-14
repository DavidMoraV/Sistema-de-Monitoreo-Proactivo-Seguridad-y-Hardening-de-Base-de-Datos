-- =====================================================================
--  D1 — DELETE masivo sin WHERE (> 100 filas)   Flujo: n8n/flujos/D1_Delete_masivo.json
--  Ejecutar como postgres:  docker compose exec postgres psql -U postgres -d nutrianimales_db
--  Fuente: pg_stat_statements (filas promedio por ejecución = rows / calls).
-- =====================================================================

-- 1. EMULACIÓN (sobre una copia, para no borrar datos reales)
CREATE TABLE prueba_delete AS SELECT * FROM ventas LIMIT 200;
DELETE FROM prueba_delete;                       -- 200 filas, sin WHERE → alerta CRÍTICA

-- 2. DETECCIÓN (usuario monitor_n8n). Versión de SOLO LECTURA para revisar a mano.
--    El flujo usa la misma consulta + pg_stat_statements_reset(userid, dbid, queryid) en cada fila
--    detectada: así el mismo DELETE no se vuelve a alertar en el siguiente ciclo (sección 10, punto 6).
--    No ejecute la versión del flujo a mano: consumiría el evento y N8N ya no lo vería.
SELECT s.queryid, r.rolname AS usuario, s.query, s.calls, s.rows,
       s.rows / NULLIF(s.calls, 0) AS filas_por_ejecucion
FROM pg_stat_statements s
JOIN pg_roles r ON r.oid = s.userid
WHERE s.query ~* '^\s*delete\M'                                  -- empieza con DELETE
  AND s.query !~* '\mwhere\M'                                    -- sin WHERE
  AND s.query !~* '\m(pg_settings_snapshot|snapshot_tablas)\M'   -- fotos propias de R5 y D2
  AND s.rows / NULLIF(s.calls, 0) > 100;

-- 3. LIMPIEZA
DROP TABLE IF EXISTS prueba_delete;
