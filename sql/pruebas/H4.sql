-- =====================================================================
--  H4 — Conexión desde fuera de la red Docker (172.16.0.0/12)   Flujo: n8n/flujos/H4_Conexion_externa.json
-- =====================================================================
-- 1. EMULACIÓN (desde la terminal del servidor):
--   docker network create --subnet 10.99.0.0/24 red_prueba
--   docker network connect red_prueba nutri_postgres
--   docker run --rm --network red_prueba -e PGPASSWORD=<AGENTE_IA_PASSWORD del .env> postgres:16 \
--     psql "host=nutri_postgres user=agente_ia dbname=nutrianimales_db" -c "SELECT pg_sleep(90)"

-- 2. DETECCIÓN (usuario monitor_n8n)
SELECT usename, client_addr::text, to_char(backend_start, 'YYYY-MM-DD HH24:MI:SS') AS inicio
FROM pg_stat_activity
WHERE client_addr IS NOT NULL AND NOT (client_addr <<= inet '172.16.0.0/12');

-- 3. LIMPIEZA:
--   docker network disconnect red_prueba nutri_postgres && docker network rm red_prueba
