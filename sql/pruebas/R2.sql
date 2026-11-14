-- =====================================================================
--  R2 — Más de 10 conexiones activas   Flujo: n8n/flujos/R2_Exceso_conexiones.json
-- =====================================================================
-- 1. EMULACIÓN (desde la terminal del servidor, en la carpeta del repo):
--   for i in $(seq 1 12); do docker compose exec -d postgres \
--     psql -U postgres -d nutrianimales_db -c "SELECT pg_sleep(120)"; done

-- 2. DETECCIÓN (usuario monitor_n8n) → conexiones > 10
SELECT count(*)::int AS conexiones, string_agg(DISTINCT usename, ', ') AS usuarios
FROM pg_stat_activity WHERE backend_type = 'client backend';

-- 3. LIMPIEZA: las sesiones terminan solas a los 120 s.
