-- =====================================================================
--  H3 — Permisos de escritura otorgados a agente_ia   Flujo: n8n/flujos/H3_Escalada_privilegios.json
--  (es también la detección del ataque A4)
-- =====================================================================
-- 1. EMULACIÓN (como postgres)
GRANT INSERT ON ALL TABLES IN SCHEMA public TO agente_ia;

-- 2. DETECCIÓN (usuario monitor_n8n) → filas = alerta CRÍTICA
SELECT c.relname AS tabla, p.priv
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
CROSS JOIN unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) AS p(priv)
WHERE n.nspname = 'public' AND c.relkind = 'r' AND has_table_privilege('agente_ia', c.oid, p.priv);

-- 3. LIMPIEZA (respuesta)
REVOKE INSERT ON ALL TABLES IN SCHEMA public FROM agente_ia;
