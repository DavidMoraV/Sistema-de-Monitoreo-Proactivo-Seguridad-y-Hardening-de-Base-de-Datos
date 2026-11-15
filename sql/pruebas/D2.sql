-- =====================================================================
--  D2 — Crecimiento anormal: > 20 % de filas en 30 min   Flujo: n8n/flujos/D2_Crecimiento_anormal.json
--  Fuente: snapshot_tablas (relname, filas, fecha), con foto inicial de M2 en sql/06.
-- =====================================================================

-- 1. EMULACIÓN (como postgres): gastos pasa de 200 a 260 filas (+30 %)
INSERT INTO gastos (categoria, descripcion, monto, fecha, aprobado_por)
SELECT 'prueba', 'carga D2', 1000, NOW(), 'test' FROM generate_series(1, 60);

-- 2. DETECCIÓN (usuario monitor_n8n). Versión de SOLO LECTURA.
--    Compara el conteo actual contra la foto más reciente que tenga al menos 30 minutos.
--    Se usa count(*) y no n_live_tup: n_live_tup es una estimación que cambia con
--    autovacuum/ANALYZE y podía dar alertas falsas. Las 8 tablas son pequeñas.
--    Mínimo 10 filas de diferencia para que plantas (3 filas) no alerte por 1 registro.
WITH actual AS (
  SELECT 'clientes' AS relname, count(*) AS filas FROM clientes         UNION ALL
  SELECT 'ventas',           count(*) FROM ventas           UNION ALL
  SELECT 'productos',        count(*) FROM productos        UNION ALL
  SELECT 'lotes_produccion', count(*) FROM lotes_produccion UNION ALL
  SELECT 'control_calidad',  count(*) FROM control_calidad  UNION ALL
  SELECT 'materias_primas',  count(*) FROM materias_primas  UNION ALL
  SELECT 'gastos',           count(*) FROM gastos           UNION ALL
  SELECT 'plantas',          count(*) FROM plantas
), previa AS (
  SELECT DISTINCT ON (relname) relname, filas, fecha
  FROM snapshot_tablas WHERE fecha <= now() - interval '30 minutes'
  ORDER BY relname, fecha DESC
)
SELECT a.relname, p.filas AS antes, a.filas AS ahora,
       round(100.0 * (a.filas - p.filas) / NULLIF(p.filas, 0), 1) AS crecimiento_pct, p.fecha AS desde
FROM actual a JOIN previa p USING (relname)
WHERE a.filas > p.filas * 1.2 AND a.filas - p.filas >= 10;

--    El flujo hace además, en la MISMA sentencia (CTE que modifican datos):
--      a) guarda la foto de este minuto en snapshot_tablas;
--      b) borra las fotos de más de 2 horas;
--      c) si una tabla alertó, borra sus fotos anteriores: su ventana de 30 min empieza de
--         nuevo con el conteo nuevo, y el mismo crecimiento no se vuelve a alertar.
--    La consulta completa está en el nodo "Consultar PostgreSQL" del flujo.

-- 3. LIMPIEZA
DELETE FROM gastos WHERE categoria = 'prueba' AND descripcion = 'carga D2';
