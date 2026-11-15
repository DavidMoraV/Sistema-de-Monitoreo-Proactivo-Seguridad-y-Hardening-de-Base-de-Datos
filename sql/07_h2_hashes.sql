-- =====================================================================
--  07_h2_hashes.sql — M5: hashes de referencia para la alerta H2
--  H2 compara md5(pg_read_file('pg_hba.conf' / 'postgresql.conf')) contra esta tabla.
--  Se guarda en la BD (y no en la memoria del flujo) porque en N8N 2.x la memoria
--  de un flujo publicado no se conserva entre ejecuciones.
--  Es idempotente: se puede aplicar a una BD ya creada con
--    docker exec -i nutri_postgres psql -U postgres -d nutrianimales_db < sql/07_h2_hashes.sql
-- =====================================================================
CREATE TABLE IF NOT EXISTS config_hashes (
    archivo      TEXT PRIMARY KEY,
    hash         TEXT NOT NULL,
    actualizado  TIMESTAMP NOT NULL DEFAULT NOW()
);

GRANT SELECT, INSERT, UPDATE ON config_hashes TO monitor_n8n;
-- agente_ia (bot) no recibe nada: no puede ver ni modificar esta tabla.
