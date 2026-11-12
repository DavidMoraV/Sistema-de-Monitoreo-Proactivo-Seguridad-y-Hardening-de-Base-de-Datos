-- =====================================================================
--  H5 — SSL desactivado o autenticación degradada a MD5 (pg_settings vs. baseline)
--  Ejecutar como postgres:  docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db
--  Esta misma prueba dispara también R5 (cambio de parámetros).
-- =====================================================================

-- 1. EMULACIÓN (cronograma, semana 3)
ALTER SYSTEM SET password_encryption = 'md5';
SELECT pg_reload_conf();
SELECT pg_sleep(2);  -- la recarga es asincrona: esperar antes de detectar

-- 2. DETECCIÓN (query del flujo H5, usuario monitor_n8n) → debe devolver 1 fila
SELECT s.name, s.setting AS actual, b.valor_esperado
FROM pg_settings s
JOIN pg_settings_baseline b ON b.name = s.name
WHERE s.setting <> b.valor_esperado;

-- 3. LIMPIEZA (volver al valor seguro)
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
SELECT pg_reload_conf();
-- La detección vuelve a quedar vacía. R5 alertará una vez más por el regreso a scram,
-- y luego refresca su foto.
