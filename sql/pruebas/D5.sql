-- =====================================================================
--  D5 — Transacción bloqueada más de 30 s   Flujo: n8n/flujos/D5_Bloqueo.json
-- =====================================================================

-- 1. EMULACIÓN con 2 terminales (o automática: ./scripts/demo_m4.sh D5)
--   T1: BEGIN; UPDATE productos SET precio_unitario = precio_unitario WHERE id = 1;   (sin COMMIT)
--   T2: UPDATE productos SET precio_unitario = precio_unitario WHERE id = 1;          (queda esperando)
--   Esperar más de 30 s → alerta. Luego ROLLBACK en T1 y T2 termina.

-- 2. DETECCIÓN (usuario monitor_n8n; pg_monitor le deja ver las consultas de otros usuarios)
--    "marca" = PID + hora en que empezó a esperar: una alerta por bloqueo.
SELECT a.pid, a.usename AS usuario,
       round(extract(epoch FROM now() - a.query_start))::int AS segundos,
       left(a.query, 200) AS query,
       (SELECT string_agg(b.usename || ' (PID ' || b.pid || ', ' || b.state || '): ' || left(b.query, 80), '; ')
          FROM pg_stat_activity b WHERE b.pid = ANY (pg_blocking_pids(a.pid))) AS bloqueadores,
       (SELECT string_agg(DISTINCT c.relname, ', ')
          FROM pg_locks l JOIN pg_class c ON c.oid = l.relation AND c.relkind = 'r'
         WHERE l.pid = a.pid AND l.locktype = 'relation') AS tablas,
       'PID ' || a.pid || ' esperando desde ' || to_char(a.query_start, 'HH24:MI:SS') AS marca
FROM pg_stat_activity a
WHERE a.wait_event_type = 'Lock'
  AND now() - a.query_start > interval '30 seconds';

-- 3. LIMPIEZA: ROLLBACK en T1 (o terminar al bloqueador):
--   SELECT pg_terminate_backend(<pid del bloqueador>);
