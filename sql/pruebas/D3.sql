-- =====================================================================
--  D3 — Sin respaldo exitoso en más de 24 h   Flujo: n8n/flujos/D3_Sin_backup.json
--  Fuente: tabla backups, que llena scripts/backup.sh (M2). M2 dejó un registro 'ok' inicial.
-- =====================================================================

-- 1. EMULACIÓN (como postgres): el último respaldo pasa a tener 30 horas
UPDATE backups SET fecha = NOW() - INTERVAL '30 hours';

-- 2. DETECCIÓN (usuario monitor_n8n) → 1 fila = alerta CRÍTICA
--    "marca" identifica el evento (la fecha exacta del último respaldo). El flujo descarta
--    la fila si ya existe una alerta D3 con esa misma marca: avisa UNA vez por evento y no cada
--    10 minutos mientras nadie haga el respaldo. Un respaldo nuevo cierra el evento.
SELECT b.ultimo_ok, b.ultimo_estado, b.ultimo_intento,
       round(extract(epoch FROM now() - b.ultimo_ok) / 3600)::int AS horas,
       'Último respaldo exitoso: ' || COALESCE(to_char(b.ultimo_ok, 'YYYY-MM-DD HH24:MI:SS'), 'ninguno') AS marca
FROM (SELECT max(fecha) FILTER (WHERE estado = 'ok') AS ultimo_ok,
             max(fecha) AS ultimo_intento,
             (SELECT estado FROM backups ORDER BY fecha DESC, id DESC LIMIT 1) AS ultimo_estado
      FROM backups) b
WHERE b.ultimo_ok IS NULL OR b.ultimo_ok < now() - interval '24 hours';

-- 3. LIMPIEZA (la respuesta real): hacer un respaldo
--   ./scripts/backup.sh
