-- =====================================================================
--  04_baseline.sql — HD12: valores de seguridad esperados (base de la alerta H5)
--  H5 compara pg_settings contra esta tabla; cualquier diferencia es una alerta CRÍTICA.
-- =====================================================================
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

-- Foto inicial de pg_settings para la alerta R5
INSERT INTO pg_settings_snapshot (name, setting)
SELECT name, setting FROM pg_settings;
