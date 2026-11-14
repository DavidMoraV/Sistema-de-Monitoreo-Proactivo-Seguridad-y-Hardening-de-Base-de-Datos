#!/bin/bash
# =====================================================================
# demo_m4.sh  ·  Responsable: M4 (alertas de datos D1–D7)
# Emula cada alerta de datos, muestra la hora (para la captura) y luego limpia.
# Uso (desde la raíz del repo, con el stack arriba y los flujos D activos):
#   ./scripts/demo_m4.sh D6            → emula D6; la alerta llega a Telegram en ≤ 1 min
#   ./scripts/demo_m4.sh D6 limpiar    → deja todo como estaba
#   ./scripts/demo_m4.sh estado        → últimas alertas D en alertas_auditoria
# Capturas: docs/capturas/D1_alerta.png … D7_alerta.png (con la hora del mensaje visible).
# Detalle de cada escenario: sql/pruebas/D1.sql … D7.sql
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")/.."
DB="${POSTGRES_DB:-nutrianimales_db}"

psql_como() {   # $1 = usuario, resto = argumentos de psql
    local u="$1"; shift
    docker compose exec -T postgres psql -U "$u" -d "$DB" -X "$@" 2>&1
}
titulo() { echo; echo "================ $1 · $(date '+%Y-%m-%d %H:%M:%S') ================"; }
esperar() { echo "→ La alerta llega a Telegram en el próximo ciclo de N8N (≤ 1 min${1:-})."; }

D1() { titulo "D1 · DELETE masivo sin WHERE (> 100 filas)"
       psql_como postgres -c "DROP TABLE IF EXISTS prueba_delete;" \
           -c "CREATE TABLE prueba_delete AS SELECT * FROM ventas LIMIT 200;" \
           -c "DELETE FROM prueba_delete;"
       esperar; }
D1_limpiar() { psql_como postgres -c "DROP TABLE IF EXISTS prueba_delete;"; }

D2() { titulo "D2 · Crecimiento > 20 % en 30 min (gastos +60 filas)"
       psql_como postgres -c "SELECT count(*) AS gastos_antes FROM gastos;" \
           -c "INSERT INTO gastos (categoria, descripcion, monto, fecha, aprobado_por) SELECT 'prueba', 'carga D2', 1000, NOW(), 'test' FROM generate_series(1, 60);" \
           -c "SELECT count(*) AS gastos_ahora FROM gastos;"
       esperar ". Compara contra la foto de hace ≥ 30 min en snapshot_tablas"; }
D2_limpiar() { psql_como postgres -c "DELETE FROM gastos WHERE categoria = 'prueba' AND descripcion = 'carga D2';"; }

D3() { titulo "D3 · Sin respaldo en más de 24 h"
       psql_como postgres -c "UPDATE backups SET fecha = NOW() - INTERVAL '30 hours';" \
           -c "SELECT id, fecha, estado, ruta FROM backups ORDER BY fecha DESC LIMIT 3;"
       esperar; }
D3_limpiar() { ./scripts/backup.sh; }

D4() { titulo "D4 · Más de 5 duplicados en clientes"
       psql_como postgres -c "INSERT INTO clientes (nombre, tipo, correo, segmento) SELECT nombre, tipo, correo, segmento FROM clientes ORDER BY id LIMIT 6;" \
           -c "SELECT correo, count(*) FROM clientes GROUP BY correo HAVING count(*) > 1 ORDER BY 1;"
       esperar; }
D4_limpiar() { psql_como postgres -c "DELETE FROM clientes c USING clientes o WHERE c.correo = o.correo AND c.id > o.id;"; }

D5() { titulo "D5 · Transacción bloqueada > 30 s (90 s de bloqueo)"
       # T1 toma el bloqueo de la fila y lo mantiene 90 s; T2 queda esperando.
       docker compose exec -d postgres psql -U postgres -d "$DB" -X \
           -c "BEGIN; UPDATE productos SET precio_unitario = precio_unitario WHERE id = 1; SELECT pg_sleep(90); ROLLBACK;"
       sleep 2
       docker compose exec -d postgres psql -U postgres -d "$DB" -X \
           -c "UPDATE productos SET precio_unitario = precio_unitario WHERE id = 1;"
       sleep 3
       psql_como postgres -c "SELECT pid, usename, wait_event_type, now() - query_start AS esperando, left(query, 60) AS query FROM pg_stat_activity WHERE wait_event_type = 'Lock';"
       esperar ": a partir de los 30 s de espera. El bloqueo se libera solo a los 90 s"; }
D5_limpiar() { psql_como postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE query LIKE 'BEGIN; UPDATE productos%' AND pid <> pg_backend_pid();"; }

D6() { titulo "D6 · UPDATE masivo sin WHERE (> 50 filas)"
       psql_como postgres -c "DROP TABLE IF EXISTS prueba_update;" \
           -c "CREATE TABLE prueba_update AS SELECT * FROM lotes_produccion LIMIT 200;" \
           -c "UPDATE prueba_update SET estado = 'cancelado';"
       esperar; }
D6_limpiar() { psql_como postgres -c "DROP TABLE IF EXISTS prueba_update;"; }

D7() { titulo "D7 · Exfiltración: SELECT masivo de clientes como agente_ia (= ataque A5)"
       psql_como agente_ia -c "SELECT * FROM clientes;" | tail -2
       esperar; }
D7_limpiar() { echo "D7 no deja datos. Respuesta al ataque A5: bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD"; }

estado() { titulo "Últimas alertas de datos (alertas_auditoria)"
           psql_como postgres -c "SELECT id, alerta, severidad, fecha, left(split_part(mensaje, E'\n', 5), 90) AS detalle FROM alertas_auditoria WHERE alerta LIKE 'D%' ORDER BY id DESC LIMIT 10;"; }

case "${1:-}" in
    D[1-7])  if [ "${2:-}" = "limpiar" ]; then "${1}_limpiar"; else "$1"; fi ;;
    estado)  estado ;;
    *)       sed -n '3,10p' "$0"; exit 1 ;;
esac
