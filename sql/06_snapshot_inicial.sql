-- =====================================================================
--  06_snapshot_inicial.sql — fotos iniciales para R5 y D2
--  Va en un archivo aparte porque cada archivo de docker-entrypoint-initdb.d corre en una
--  sesión nueva: así la foto ya ve los valores aplicados por ALTER SYSTEM en 04_baseline.sql.
-- =====================================================================

-- R5: compara vw_settings_servidor contra esta foto y la refresca después de alertar:
--   DELETE FROM pg_settings_snapshot;
--   INSERT INTO pg_settings_snapshot (name, setting) SELECT name, setting FROM vw_settings_servidor;
INSERT INTO pg_settings_snapshot (name, setting)
SELECT name, setting FROM vw_settings_servidor;

-- D2: filas por tabla con fecha de hace 1 hora, para que D2 tenga contra qué comparar desde
-- el primer ciclo (count(*) porque n_live_tup todavía no está actualizado al inicializar).
INSERT INTO snapshot_tablas (relname, filas, fecha)
SELECT 'clientes',         count(*), NOW() - INTERVAL '1 hour' FROM clientes         UNION ALL
SELECT 'ventas',           count(*), NOW() - INTERVAL '1 hour' FROM ventas           UNION ALL
SELECT 'productos',        count(*), NOW() - INTERVAL '1 hour' FROM productos        UNION ALL
SELECT 'lotes_produccion', count(*), NOW() - INTERVAL '1 hour' FROM lotes_produccion UNION ALL
SELECT 'control_calidad',  count(*), NOW() - INTERVAL '1 hour' FROM control_calidad  UNION ALL
SELECT 'materias_primas',  count(*), NOW() - INTERVAL '1 hour' FROM materias_primas  UNION ALL
SELECT 'gastos',           count(*), NOW() - INTERVAL '1 hour' FROM gastos           UNION ALL
SELECT 'plantas',          count(*), NOW() - INTERVAL '1 hour' FROM plantas;
