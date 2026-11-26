-- =====================================================================
--  08_itsm_glpi.sql — Proyecto II: estado del flujo de sshd_config (C1, C2, C3)
--  Se guarda en PostgreSQL y no en la memoria del flujo porque en N8N 2.x la
--  memoria de un flujo publicado no se conserva entre ejecuciones (mismo motivo que H2).
--  Todas las horas salen del reloj de PostgreSQL: no dependen de la zona horaria de GLPI.
--  Es idempotente: se puede aplicar a una BD ya creada con
--    docker exec -i nutri_postgres psql -U postgres -d nutrianimales_db < sql/08_itsm_glpi.sql
-- =====================================================================

-- Línea base del hash SHA-256 de sshd_config por servidor (control A.8.9)
CREATE TABLE IF NOT EXISTS sshd_baseline (
    host         TEXT PRIMARY KEY,
    hash         CHAR(64)  NOT NULL CHECK (hash ~ '^[a-f0-9]{64}$'),
    actualizado  TIMESTAMP NOT NULL DEFAULT NOW(),
    motivo       TEXT      NOT NULL DEFAULT 'Línea base inicial'
);

-- Incidentes que N8N abrió en GLPI: línea de tiempo del estudio de caso y marca de C3 (A.5.26)
CREATE TABLE IF NOT EXISTS glpi_incidentes (
    ticket_id       INTEGER   PRIMARY KEY,           -- id del ticket en GLPI
    host            TEXT      NOT NULL,
    hash_detectado  CHAR(64)  NOT NULL,
    hash_base       CHAR(64)  NOT NULL,
    creado          TIMESTAMP NOT NULL DEFAULT NOW(),
    c3_enviada      TIMESTAMP,                       -- NULL = C3 todavía no se envió
    cerrado         TIMESTAMP,                       -- NULL = incidente abierto
    cierre          TEXT                             -- automático (hash a línea base) o manual en GLPI
);
CREATE INDEX IF NOT EXISTS idx_glpi_incidentes_abiertos ON glpi_incidentes (host) WHERE cerrado IS NULL;

-- Vista para la tabla de tiempos del estudio de caso
CREATE OR REPLACE VIEW vw_tiempos_incidentes AS
SELECT ticket_id, host,
       to_char(creado,  'YYYY-MM-DD HH24:MI:SS') AS creado,
       to_char(cerrado, 'YYYY-MM-DD HH24:MI:SS') AS cerrado,
       round(extract(epoch FROM coalesce(cerrado, now()) - creado) / 60, 1) AS minutos_abierto,
       (coalesce(cerrado, now()) - creado) <= interval '1 hour' AS dentro_sla_1h,
       c3_enviada IS NOT NULL AS c3_enviada,
       cierre
FROM glpi_incidentes
ORDER BY ticket_id DESC;

-- monitor_n8n (credencial de los flujos) puede leer y escribir solo estas tablas
GRANT SELECT, INSERT, UPDATE ON sshd_baseline, glpi_incidentes TO monitor_n8n;
GRANT SELECT ON vw_tiempos_incidentes TO monitor_n8n, rol_auditor;
GRANT SELECT ON sshd_baseline, glpi_incidentes TO rol_auditor;
-- agente_ia (bot) no recibe nada.
