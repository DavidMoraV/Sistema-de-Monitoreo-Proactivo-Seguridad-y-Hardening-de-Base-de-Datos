-- =====================================================================
--  R4 — Más de 5 autenticaciones fallidas en 10 min   Flujo: n8n/flujos/R4_Autenticaciones_fallidas.json
-- =====================================================================
-- 1. EMULACIÓN (desde la terminal del servidor, en la carpeta del repo):
--   for i in $(seq 1 8); do docker compose exec -T -e PGPASSWORD=mala postgres \
--     psql -h postgres -U agente_ia -d nutrianimales_db -c "select 1"; done

-- 2. DETECCIÓN (usuario monitor_n8n): último log de PostgreSQL; el nodo Code cuenta las líneas
--    "password authentication failed" de los últimos 10 min. También suma "Failed password"
--    de auth.log vía Loki (A1 por SSH) cuando M5 tenga Loki; si no existe, se ignora.
SELECT pg_read_file('log/' || name) AS contenido,
       to_char((now() - interval '10 minutes') AT TIME ZONE current_setting('log_timezone'),
               'YYYY-MM-DD HH24:MI:SS') AS desde
FROM pg_ls_logdir() WHERE name LIKE '%.log' ORDER BY modification DESC LIMIT 1;

-- 3. LIMPIEZA: no requiere.
