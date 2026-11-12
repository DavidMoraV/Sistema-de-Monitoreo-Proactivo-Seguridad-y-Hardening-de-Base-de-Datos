#!/bin/bash
# =====================================================================
# evidencias_m2.sh  ·  Responsable: M2 (DBA)
# Ejecuta cada evidencia de M2 con su código y la hora, lista para captura.
# Uso (desde la raíz del repo, con el stack arriba):
#   ./scripts/evidencias_m2.sh            → todas, una tras otra
#   ./scripts/evidencias_m2.sh HD07       → solo una
# Guardar cada captura como docs/capturas/<CÓDIGO>_<descripción>.png
# =====================================================================
cd "$(dirname "$0")/.."
DB="${POSTGRES_DB:-nutrianimales_db}"

psql_como() {   # $1 = usuario, resto = argumentos de psql
    local u="$1"; shift
    docker compose exec -T postgres psql -U "$u" -d "$DB" -X "$@" 2>&1
}
titulo() { echo; echo "================ $1 · $(date '+%Y-%m-%d %H:%M:%S') ================"; }

HD05() { titulo "HD05 · Autenticación scram-sha-256";
         psql_como postgres -c "SHOW password_encryption;" \
                            -c "SELECT rolname, left(rolpassword, 14) AS hash FROM pg_authid WHERE rolname IN ('agente_ia','monitor_n8n','gerente_db');"; }
HD06() { titulo "HD06 · SSL en PostgreSQL";
         psql_como postgres -c "SHOW ssl;" -c "SHOW ssl_cert_file;"; }
HD07() { titulo "HD07 · agente_ia es solo lectura";
         psql_como agente_ia -c "SELECT count(*) AS clientes_visibles FROM clientes;" \
             -c "INSERT INTO gastos (categoria, descripcion, monto, aprobado_por) VALUES ('prueba','HD07',1,'agente_ia');"; }
HD11() { titulo "HD11 · Consulta lenta registrada";
         psql_como postgres -c "SHOW log_min_duration_statement;" -c "SELECT pg_sleep(2);" \
             -c "SELECT queryid, query, calls, round(mean_exec_time) AS ms FROM pg_stat_statements WHERE mean_exec_time > 1000 ORDER BY mean_exec_time DESC LIMIT 5;"
         echo "--- log de PostgreSQL:"
         docker compose exec -T postgres bash -c 'grep -h "duration" "$PGDATA"/log/*.log | tail -3'; }
HD12() { titulo "HD12 / 1.4 · Baseline de seguridad";
         psql_como postgres -c "SELECT * FROM pg_settings_baseline;" \
             -c "SELECT b.name, b.valor_esperado, s.setting AS valor_actual FROM pg_settings_baseline b JOIN pg_settings s USING (name);"; }
C22()  { titulo "2.2 · Roles RBAC";
         psql_como postgres -c "SELECT rolname FROM pg_roles WHERE rolname LIKE 'rol_%' ORDER BY 1;" \
             -c "SELECT r.rolname AS usuario, g.rolname AS rol FROM pg_auth_members m JOIN pg_roles r ON r.oid = m.member JOIN pg_roles g ON g.oid = m.roleid WHERE g.rolname LIKE 'rol_%' ORDER BY 2;"; }
C23()  { titulo "2.3 · rol_gerente NO accede a auditoria_datos";
         psql_como gerente_db -c "SELECT * FROM vw_ventas_resumen ORDER BY mes DESC LIMIT 5;" \
             -c "SELECT * FROM auditoria_datos;"; }
C31()  { titulo "3.1 · Tabla auditoria_datos"; psql_como postgres -c "\d auditoria_datos"; }
C32()  { titulo "3.2 · Función fn_auditoria()";
         psql_como postgres -c "SELECT proname FROM pg_proc WHERE proname = 'fn_auditoria';"; }
C33()  { titulo "3.3 · Triggers activos";
         psql_como postgres -c "SELECT trigger_name, event_manipulation, event_object_table FROM information_schema.triggers WHERE trigger_schema = 'public' ORDER BY event_object_table, event_manipulation;"; }
C34()  { titulo "3.4 · Demo UPDATE y DELETE con valor_antes y valor_nuevo";
         psql_como postgres -c "UPDATE lotes_produccion SET estado = 'pausado' WHERE id = 1;" \
             -c "DELETE FROM lotes_produccion WHERE id = 500;" \
             -c "SELECT usuario, operacion, fecha, ip_cliente, fila_id, valor_antes->>'estado' AS antes, valor_nuevo->>'estado' AS despues FROM auditoria_datos WHERE tabla = 'lotes_produccion' ORDER BY fecha DESC LIMIT 2;"; }

TODAS="HD05 HD06 HD07 HD11 HD12 C22 C23 C31 C32 C33 C34"
for e in ${1:-$TODAS}; do
    case "$e" in 1.4) e=HD12;; 2.2) e=C22;; 2.3) e=C23;; 3.1) e=C31;; 3.2) e=C32;; 3.3) e=C33;; 3.4) e=C34;; esac
    "$e"
    [ -z "${1:-}" ] && read -rp "  [Enter para la siguiente captura] " _ </dev/tty
done
