-- =====================================================================
--  D4 — Más de 5 registros duplicados en tablas críticas   Flujo: n8n/flujos/D4_Duplicados.json
--  clientes: mismo correo (M2 dejó correo sin UNIQUE a propósito).
--  ventas:   mismo cliente, producto, cantidad y fecha exacta.
-- =====================================================================

-- 1. EMULACIÓN (como postgres): 6 clientes repetidos
INSERT INTO clientes (nombre, tipo, correo, segmento)
SELECT nombre, tipo, correo, segmento FROM clientes ORDER BY id LIMIT 6;

-- 2. DETECCIÓN (usuario monitor_n8n) → 1 fila por tabla con > 5 duplicados
--    "marca" incluye el id más alto de los duplicados: el mismo estado se alerta una sola vez,
--    y una nueva carga de duplicados (ids nuevos) es un evento nuevo.
WITH dup AS (
  SELECT 'clientes'::text AS tabla, 'correo'::text AS criterio,
         COALESCE(sum(n - 1), 0)::int AS duplicados, max(ultimo_id) AS ultimo_id,
         array_to_string((array_agg(clave ORDER BY n DESC, clave))[1:3], ', ') AS ejemplos
  FROM (SELECT correo AS clave, count(*) AS n, max(id) AS ultimo_id
        FROM clientes GROUP BY correo HAVING count(*) > 1) d
  UNION ALL
  SELECT 'ventas', 'cliente, producto, cantidad y fecha',
         COALESCE(sum(n - 1), 0)::int, max(ultimo_id),
         array_to_string((array_agg(clave ORDER BY n DESC, clave))[1:3], ', ')
  FROM (SELECT 'cliente ' || cliente_id || ' / producto ' || producto_id AS clave,
               count(*) AS n, max(id) AS ultimo_id
        FROM ventas GROUP BY cliente_id, producto_id, cantidad, fecha HAVING count(*) > 1) d
)
SELECT tabla, criterio, duplicados, ultimo_id, ejemplos,
       'Duplicados en ' || tabla || ': ' || duplicados || ' (último id ' || ultimo_id || ')' AS marca
FROM dup WHERE duplicados > 5;

-- 3. LIMPIEZA: borrar las copias (se queda el id más bajo de cada correo)
DELETE FROM clientes c USING clientes o
WHERE c.correo = o.correo AND c.id > o.id;
