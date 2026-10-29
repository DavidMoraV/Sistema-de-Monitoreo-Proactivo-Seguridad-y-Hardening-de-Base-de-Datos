-- =====================================================================
--  02_semilla.sql — Datos de prueba reproducibles
--  Se carga ANTES de los triggers (03) para no llenar auditoria_datos con la carga inicial.
--  clientes y ventas superan 1,000 filas para que D7 / A5 (> 1,000 filas) puedan dispararse.
-- =====================================================================
SELECT setseed(0.2026);

-- 3 plantas
INSERT INTO plantas (nombre, ubicacion, capacidad_produccion, estado) VALUES
  ('Planta Alajuela', 'El Coyol, Alajuela',        4500, 'activa'),
  ('Planta Cartago',  'Zona Industrial, Cartago',  3200, 'activa'),
  ('Planta Heredia',  'Barreal, Heredia',          2800, 'mantenimiento');

-- 50 productos
INSERT INTO productos (codigo, nombre, tipo, precio_unitario, activo)
SELECT 'PRD-' || LPAD(g::TEXT, 3, '0'),
       'Concentrado ' || t.tipo || ' ' ||
       (ARRAY['Inicio','Crecimiento','Engorde','Mantenimiento','Premium'])[1 + (g % 5)] || ' ' || g,
       t.tipo,
       ROUND((9000 + random() * 16000)::NUMERIC, 2),
       g % 12 <> 0
FROM generate_series(1, 50) AS g
CROSS JOIN LATERAL (SELECT (ARRAY['aves','cerdos','ganado','peces'])[1 + (g % 4)] AS tipo) t;

-- 100 materias primas
INSERT INTO materias_primas (nombre, categoria, stock_actual, stock_minimo, proveedor)
SELECT (ARRAY['Maíz amarillo','Harina de soya','Sorgo','Harina de pescado','Melaza',
              'Carbonato de calcio','Premezcla vitamínica','Sal mineral','Aceite vegetal','Afrecho de trigo'])[1 + (g % 10)]
         || ' lote ' || g,
       (ARRAY['cereal','proteína','energía','mineral','aditivo'])[1 + (g % 5)],
       ROUND((500 + random() * 49500)::NUMERIC, 2),
       ROUND((1000 + random() * 4000)::NUMERIC, 2),
       (ARRAY['Granos del Norte S.A.','Agroinsumos CR','Proteínas del Pacífico','Minerales Centroamericanos'])[1 + (g % 4)]
FROM generate_series(1, 100) AS g;

-- 1,500 clientes (mínimo del enunciado: 200)
INSERT INTO clientes (nombre, tipo, correo, segmento)
SELECT 'Cliente ' || LPAD(g::TEXT, 4, '0'),
       (ARRAY['distribuidor','empresa','persona'])[1 + (g % 3)],
       'cliente' || g || '@correo.cr',
       (ARRAY['A','B','C'])[1 + (g % 3)]
FROM generate_series(1, 1500) AS g;

-- 500 lotes de producción
INSERT INTO lotes_produccion (codigo, planta_id, producto_id, cantidad_producida, fecha_inicio, estado)
SELECT 'LOT-' || LPAD(g::TEXT, 5, '0'),
       1 + (g % 3),
       1 + (g % 50),
       ROUND((2000 + random() * 18000)::NUMERIC, 2),
       NOW() - (random() * INTERVAL '180 days'),
       (ARRAY['planificado','en_proceso','completado','completado','pausado'])[1 + (g % 5)]
FROM generate_series(1, 500) AS g;

-- 1,500 ventas (mínimo del enunciado: 1,000)
INSERT INTO ventas (cliente_id, producto_id, cantidad, precio_total, fecha, estado)
SELECT v.cliente_id, v.producto_id, v.cantidad,
       ROUND(v.cantidad * p.precio_unitario, 2),
       NOW() - (random() * INTERVAL '365 days'),
       (ARRAY['pagada','pagada','pendiente','anulada'])[1 + (v.g % 4)]
FROM (SELECT g,
             1 + floor(random() * 1500)::INT AS cliente_id,
             1 + floor(random() * 50)::INT   AS producto_id,
             1 + floor(random() * 200)::INT  AS cantidad
      FROM generate_series(1, 1500) AS g) v
JOIN productos p ON p.id = v.producto_id;

-- 300 controles de calidad
INSERT INTO control_calidad (lote_id, parametro, valor_obtenido, valor_esperado, aprobado)
SELECT c.lote_id, c.parametro, c.obtenido, c.esperado, ABS(c.obtenido - c.esperado) <= c.esperado * 0.05
FROM (SELECT 1 + (g % 500) AS lote_id,
             (ARRAY['proteína %','humedad %','grasa %','fibra %','cenizas %'])[1 + (g % 5)] AS parametro,
             (ARRAY[18, 12, 5, 6, 8])[1 + (g % 5)]::NUMERIC AS esperado,
             ROUND(((ARRAY[18, 12, 5, 6, 8])[1 + (g % 5)] * (0.9 + random() * 0.2))::NUMERIC, 2) AS obtenido
      FROM generate_series(1, 300) AS g) c;

-- 200 gastos
INSERT INTO gastos (categoria, descripcion, monto, fecha, aprobado_por)
SELECT (ARRAY['materia prima','mantenimiento','energía','transporte','planilla'])[1 + (g % 5)],
       'Gasto operativo #' || g,
       ROUND((50000 + random() * 4950000)::NUMERIC, 2),
       NOW() - (random() * INTERVAL '180 days'),
       (ARRAY['Gerencia General','Gerencia de Planta','Finanzas'])[1 + (g % 3)]
FROM generate_series(1, 200) AS g;

-- Respaldo inicial (para que D3 no se dispare apenas arranca el sistema)
INSERT INTO backups (fecha, estado, ruta) VALUES (NOW(), 'ok', 'backups/carga_inicial.sql');
