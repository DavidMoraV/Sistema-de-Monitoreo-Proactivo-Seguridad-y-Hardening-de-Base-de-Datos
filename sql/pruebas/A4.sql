-- A4 — Escalada de privilegios (detecta H3). Ejecutar como postgres:
--   docker exec -i nutri_postgres psql -U postgres -d nutrianimales_db
-- 1. EMULACIÓN
GRANT INSERT ON ALL TABLES IN SCHEMA public TO agente_ia;
-- 2. RESPUESTA (después de capturar la alerta H3 en Telegram)
REVOKE INSERT ON ALL TABLES IN SCHEMA public FROM agente_ia;
-- 3. VERIFICACIÓN: ninguna fila debe tener tiene_insert = true
SELECT c.relname AS tabla, has_table_privilege('agente_ia', c.oid, 'INSERT') AS tiene_insert
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
ORDER BY tiene_insert DESC, c.relname;
-- 4. Registro de la alerta:
SELECT alerta, severidad, to_char(fecha, 'YYYY-MM-DD HH24:MI:SS') AS fecha
FROM alertas_auditoria WHERE alerta = 'H3' ORDER BY id DESC LIMIT 3;
