-- =====================================================================
--  R3 — Conexión fuera de horario (23:00–06:00)   Flujo: n8n/flujos/R3_Fuera_de_horario.json
-- =====================================================================
-- 1. EMULACIÓN: conectarse en ese horario. De día: en N8N, nodo "¿Hay alerta? (arma JSON)",
--    cambiar temporalmente HORA_INICIO = 23 por la hora actual y abrir una sesión:
--    docker compose exec -d postgres psql -U postgres -d nutrianimales_db -c "SELECT pg_sleep(90)"

-- 2. DETECCIÓN (usuario monitor_n8n); el flujo filtra por hora en el nodo Code
SELECT usename, client_addr::text, to_char(backend_start, 'YYYY-MM-DD HH24:MI:SS') AS inicio,
       extract(hour FROM now())::int AS hora_actual
FROM pg_stat_activity WHERE backend_type = 'client backend' AND usename <> 'monitor_n8n';

-- 3. LIMPIEZA: volver HORA_INICIO = 23 en el flujo y documentarlo en el informe.
