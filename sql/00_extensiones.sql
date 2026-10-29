-- =====================================================================
--  00_extensiones.sql — se ejecuta una sola vez al crear el volumen de PostgreSQL
--  Requerido por las alertas R1, D1, D6 y D7 (pg_stat_statements)
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
