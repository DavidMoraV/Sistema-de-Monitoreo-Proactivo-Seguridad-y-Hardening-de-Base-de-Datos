#!/usr/bin/env bash
# =====================================================================
#  05_rbac.sh — Control de acceso por roles (sección 7) + usuarios de servicio
#  Es .sh (no .sql) para leer las contraseñas desde variables de entorno (.env)
#  en lugar de dejarlas escritas en el repositorio.
#
#  Ajustes respecto al enunciado:
#   - rol_gerente: SELECT solo sobre VISTAS de reportes (no sobre tablas).
#   - rol_auditor: se agrega pg_read_all_stats (pg_stat_statements / pg_stat_activity).
#   - USAGE en secuencias para los roles que hacen INSERT.
# =====================================================================
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
     -v pw_agente="$AGENTE_IA_PASSWORD" \
     -v pw_monitor="$MONITOR_N8N_PASSWORD" \
     -v pw_gerente="$GERENTE_DB_PASSWORD" \
     -v pw_ti="$TI_DB_PASSWORD" \
     -v pw_auditor="$AUDITOR_DB_PASSWORD" <<'EOSQL'

-- ---------------------------------------------------------------- Mínimo privilegio por defecto
REVOKE CONNECT ON DATABASE nutrianimales_db FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

-- ---------------------------------------------------------------- Vistas de reportes (gerencia)
CREATE VIEW vw_ventas_resumen AS
SELECT p.nombre                      AS producto,
       p.tipo,
       date_trunc('month', v.fecha)  AS mes,
       SUM(v.cantidad)               AS unidades,
       SUM(v.precio_total)           AS total_colones
FROM ventas v
JOIN productos p ON p.id = v.producto_id
WHERE v.estado <> 'anulada'
GROUP BY 1, 2, 3;

CREATE VIEW vw_produccion_planta AS
SELECT pl.nombre                  AS planta,
       l.estado,
       COUNT(*)                   AS lotes,
       SUM(l.cantidad_producida)  AS kg_producidos
FROM lotes_produccion l
JOIN plantas pl ON pl.id = l.planta_id
GROUP BY 1, 2;

-- ---------------------------------------------------------------- 3 roles (sección 7.2)
CREATE ROLE rol_gerente NOLOGIN;
CREATE ROLE rol_ti      NOLOGIN;
CREATE ROLE rol_auditor NOLOGIN;

-- Gerente: solo vistas de reportes
GRANT CONNECT ON DATABASE nutrianimales_db TO rol_gerente;
GRANT USAGE   ON SCHEMA public TO rol_gerente;
GRANT SELECT  ON vw_ventas_resumen, vw_produccion_planta TO rol_gerente;

-- Administrador TI: lectura total + registro de backups y alertas
GRANT CONNECT ON DATABASE nutrianimales_db TO rol_ti;
GRANT USAGE   ON SCHEMA public TO rol_ti;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO rol_ti;
GRANT INSERT  ON backups, alertas_auditoria TO rol_ti;
GRANT USAGE   ON SEQUENCE backups_id_seq, alertas_auditoria_id_seq TO rol_ti;

-- Auditor: tablas de monitoreo + estadísticas del servidor
GRANT CONNECT ON DATABASE nutrianimales_db TO rol_auditor;
GRANT USAGE   ON SCHEMA public TO rol_auditor;
GRANT SELECT  ON auditoria_datos, backups, alertas_auditoria TO rol_auditor;
GRANT pg_read_all_stats TO rol_auditor;

-- Usuarios humanos
CREATE USER gerente_db WITH PASSWORD :'pw_gerente' IN ROLE rol_gerente;
CREATE USER ti_db      WITH PASSWORD :'pw_ti'      IN ROLE rol_ti;
CREATE USER auditor_db WITH PASSWORD :'pw_auditor' IN ROLE rol_auditor;

-- ---------------------------------------------------------------- HD07: agente_ia (bot) solo lectura
CREATE USER agente_ia WITH PASSWORD :'pw_agente';
GRANT CONNECT ON DATABASE nutrianimales_db TO agente_ia;
GRANT USAGE   ON SCHEMA public TO agente_ia;
GRANT SELECT  ON ALL TABLES IN SCHEMA public TO agente_ia;

-- ---------------------------------------------------------------- monitor_n8n (flujos de alertas)
CREATE USER monitor_n8n WITH PASSWORD :'pw_monitor' IN ROLE rol_ti;
GRANT pg_monitor, pg_read_server_files TO monitor_n8n;     -- pg_stat_*, logs, hash de pg_hba.conf (H2)
GRANT INSERT ON auditoria_datos TO monitor_n8n;              -- registro de bloqueos SQLi (A2)
GRANT USAGE  ON SEQUENCE auditoria_datos_id_seq TO monitor_n8n;
GRANT SELECT, INSERT, UPDATE, DELETE ON pg_settings_snapshot, snapshot_tablas TO monitor_n8n;
GRANT EXECUTE ON FUNCTION pg_stat_statements_reset(oid, oid, bigint) TO monitor_n8n;
GRANT EXECUTE ON FUNCTION pg_read_file(text) TO monitor_n8n;               -- R4 (logs) y H2 (hash)
EOSQL

echo "05_rbac.sh: roles y usuarios creados."
