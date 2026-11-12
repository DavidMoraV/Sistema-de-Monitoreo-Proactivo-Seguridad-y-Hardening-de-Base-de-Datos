#!/bin/bash
# =====================================================================
# rendimiento.sh  ·  Responsable: M2 (DBA)  ·  Semana 4 del cronograma
# 1) pgbench en una BD aparte (no ensucia nutrianimales_db)
# 2) pgBadger sobre los logs de PostgreSQL → docs/pgbadger/reporte.html
#
# ¡OJO! pgbench abre 15 conexiones durante 2 minutos: R2 (> 10 conexiones)
# se va a disparar. Sirve como evidencia de R2; avisen al grupo antes.
# Uso (desde la raíz del repo):  ./scripts/rendimiento.sh
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== 1. Preparando pgbench_db"
docker compose exec -T postgres psql -U postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname='pgbench_db'" | grep -q 1 \
  || docker compose exec -T postgres createdb -U postgres pgbench_db
# Solo en esta BD se registran TODAS las consultas (para que pgBadger tenga
# material). Es por base de datos, así que no cambia pg_settings del
# servidor: no dispara H5 ni R5.
docker compose exec -T postgres psql -U postgres -qc \
    "ALTER DATABASE pgbench_db SET log_min_duration_statement = 0;"
docker compose exec -T postgres pgbench -U postgres -i -s 10 pgbench_db

echo "== 2. Carga: 15 clientes, 2 hilos, 120 s"
docker compose exec -T postgres pgbench -U postgres -c 15 -j 2 -T 120 -P 10 pgbench_db \
    | tee docs/pgbench_resultado.txt

echo "== 3. Reporte pgBadger"
mkdir -p docs/pgbadger logs/pg
docker compose cp postgres:/var/lib/postgresql/data/log/. logs/pg/
command -v pgbadger >/dev/null || sudo apt-get install -y pgbadger
pgbadger --prefix '%m [%p] %u@%d %h ' logs/pg/*.log -o docs/pgbadger/reporte.html
echo "Listo: docs/pgbench_resultado.txt y docs/pgbadger/reporte.html"
