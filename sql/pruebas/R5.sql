-- =====================================================================
--  R5 — Cualquier cambio en los parámetros del servidor
--  Usar vw_settings_servidor (no pg_settings): pg_settings incluye valores de sesión
--  (TimeZone, application_name, tcp_keepalives_*) que hacen saltar R5 en falso.
-- =====================================================================

-- 1. EMULACIÓN (como postgres)
ALTER SYSTEM SET work_mem = '16MB';
SELECT pg_reload_conf();
SELECT pg_sleep(2);  -- la recarga es asincrona: esperar antes de detectar

-- 2. DETECCIÓN (query del flujo R5, usuario monitor_n8n) → debe devolver work_mem
SELECT s.name, sn.setting AS antes, s.setting AS ahora
FROM vw_settings_servidor s
JOIN pg_settings_snapshot sn USING (name)
WHERE s.setting IS DISTINCT FROM sn.setting;

-- 2b. Después de enviar la alerta, el flujo refresca la foto (monitor_n8n tiene permiso):
DELETE FROM pg_settings_snapshot;
INSERT INTO pg_settings_snapshot (name, setting) SELECT name, setting FROM vw_settings_servidor;

-- 3. LIMPIEZA (como postgres)
ALTER SYSTEM RESET work_mem;
SELECT pg_reload_conf();
