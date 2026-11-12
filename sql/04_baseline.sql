-- =====================================================================
--  04_baseline.sql — HD12: valores de seguridad esperados (base de la alerta H5)
--  H5 compara pg_settings contra esta tabla; cualquier diferencia es una alerta CRÍTICA.
-- =====================================================================

-- ---------------------------------------------------------------- Parámetros de seguridad
-- HD05, HD06 y HD11 se aplican con ALTER SYSTEM (quedan en postgresql.auto.conf) y no con
-- "-c" en el command: del docker-compose. Un parámetro de línea de comandos tiene prioridad
-- sobre ALTER SYSTEM: con ellos en el compose, la prueba de H5 del cronograma
-- (ALTER SYSTEM SET password_encryption = 'md5') no cambia nada y la alerta nunca se dispara.
-- Requiere certs/postgres/server.{crt,key} (los crea scripts/preparar_entorno.sh).
ALTER SYSTEM SET ssl = 'on';
ALTER SYSTEM SET ssl_cert_file = '/certs/server.crt';
ALTER SYSTEM SET ssl_key_file = '/certs/server.key';
ALTER SYSTEM SET password_encryption = 'scram-sha-256';
ALTER SYSTEM SET log_min_duration_statement = '1000';
ALTER SYSTEM SET log_connections = 'on';
SELECT pg_reload_conf();

-- ---------------------------------------------------------------- Baseline (H5)
CREATE TABLE pg_settings_baseline (
    name            TEXT PRIMARY KEY,
    valor_esperado  TEXT NOT NULL,
    descripcion     TEXT
);

INSERT INTO pg_settings_baseline (name, valor_esperado, descripcion) VALUES
  ('ssl',                        'on',                 'Conexiones cifradas con TLS (HD06)'),
  ('password_encryption',        'scram-sha-256',      'Hash de contraseñas fuerte (HD05)'),
  ('log_min_duration_statement', '1000',               'Registrar consultas de más de 1 s (HD11)'),
  ('log_connections',            'on',                 'Registrar conexiones (soporte de R4)'),
  ('logging_collector',          'on',                 'Logs en archivo dentro de PGDATA'),
  ('shared_preload_libraries',   'pg_stat_statements', 'Estadísticas de consultas (R1, D1, D6, D7)');

-- ---------------------------------------------------------------- Parámetros del servidor (R5)
-- pg_settings mezcla parámetros del servidor con valores de la sesión: application_name,
-- TimeZone, DateStyle o tcp_keepalives_* cambian según quién se conecta y cómo (socket
-- local vs. TCP). Si R5 compara pg_settings directo, se dispara apenas N8N se conecta.
-- Esta vista deja solo los del servidor: R5 debe usar vw_settings_servidor.
-- listen_addresses se excluye porque durante la inicialización vale '' y luego '*'.
CREATE VIEW vw_settings_servidor AS
SELECT name, setting
FROM pg_settings
WHERE name NOT IN (
    'application_name', 'client_encoding', 'DateStyle', 'IntervalStyle',
    'TimeZone', 'search_path', 'role', 'session_authorization', 'is_superuser',
    'transaction_isolation', 'transaction_read_only', 'transaction_deferrable',
    'default_transaction_read_only', 'statement_timeout', 'listen_addresses',
    'tcp_keepalives_idle', 'tcp_keepalives_interval', 'tcp_keepalives_count',
    'tcp_user_timeout'
);

-- La foto inicial de R5 se toma en 06_snapshot_inicial.sql (en otra sesión): log_connections
-- solo cambia en sesiones nuevas, y tomarla aquí dejaría 'off' y dispararía R5 al arrancar.
