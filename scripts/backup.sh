#!/bin/bash
# =====================================================================
# backup.sh  ·  NutriAnimales S.A.  ·  Responsable: M2 (DBA)
# Respaldo con pg_dump + registro en la tabla backups (fuente de la alerta D3).
# Uso (desde la raíz del repo):   ./scripts/backup.sh
# Programar diario en el servidor: crontab -e →
#   0 2 * * * cd /ruta/nutrianimales && ./scripts/backup.sh >> backups/backup.log 2>&1
# =====================================================================
set -uo pipefail
cd "$(dirname "$0")/.."

DB="${POSTGRES_DB:-nutrianimales_db}"
FECHA=$(date +%F_%H%M)
ARCHIVO="backups/nutri_${FECHA}.sql.gz"
mkdir -p backups && chmod 700 backups

registrar() {   # $1 = ok | fallido
    docker compose exec -T postgres psql -U postgres -d "$DB" -v ON_ERROR_STOP=1 -q \
        -c "INSERT INTO backups (fecha, estado, ruta) VALUES (NOW(), '$1', '$ARCHIVO');"
}

if docker compose exec -T postgres pg_dump -U postgres "$DB" | gzip > "$ARCHIVO" \
   && [ -s "$ARCHIVO" ]; then
    chmod 600 "$ARCHIVO"
    registrar ok
    echo "$(date '+%F %T') Backup OK: $ARCHIVO ($(du -h "$ARCHIVO" | cut -f1))"
else
    rm -f "$ARCHIVO"
    registrar fallido
    echo "$(date '+%F %T') ERROR: el backup falló" >&2
    exit 1
fi
