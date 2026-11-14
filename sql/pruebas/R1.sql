-- =====================================================================
--  R1 — Consulta lenta (> 1 s)       Flujo: n8n/flujos/R1_Consulta_lenta.json
--  Ejecutar como postgres:  docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db
-- =====================================================================
-- 1. EMULACIÓN
SELECT pg_sleep(2);

-- 2. DETECCIÓN (query del flujo, usuario monitor_n8n). El flujo compara contra la lectura
--    anterior y solo alerta por ejecuciones NUEVAS lentas (pg_stat_statements acumula).
SELECT s.queryid::text, left(s.query, 300) AS query, s.calls, s.total_exec_time,
       round(s.mean_exec_time) AS ms, r.rolname AS usuario
FROM pg_stat_statements s LEFT JOIN pg_roles r ON r.oid = s.userid
WHERE s.max_exec_time > 1000 AND s.query NOT ILIKE '%pg_stat_statements%'
ORDER BY s.mean_exec_time DESC LIMIT 20;

-- 3. LIMPIEZA: no requiere.
