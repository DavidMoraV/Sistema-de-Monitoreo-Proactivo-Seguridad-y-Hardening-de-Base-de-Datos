-- =====================================================================
--  R1 — Consulta lenta (> 1 s)       Flujo: n8n/flujos/R1_Consulta_lenta.json
--  Ejecutar como postgres:  docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db
-- =====================================================================
-- 1. EMULACIÓN
SELECT pg_sleep(2);

-- 2. DETECCIÓN (usuario monitor_n8n): el log de PostgreSQL anota cada sentencia que supera
--    log_min_duration_statement (1000 ms, baseline de M2). El nodo Code toma las líneas
--    "duration: … ms  statement: …" del último minuto.
SELECT pg_read_file('log/' || name) AS contenido,
       to_char((now() - interval '75 seconds') AT TIME ZONE current_setting('log_timezone'),
               'YYYY-MM-DD HH24:MI:SS') AS desde
FROM pg_ls_logdir() WHERE name LIKE '%.log' ORDER BY modification DESC LIMIT 1;

-- 3. LIMPIEZA: no requiere.
