#!/usr/bin/env bash
# =====================================================================
#  rotar_password_bd.sh — rota la contraseña de un usuario de PostgreSQL
#  Uso:   bash scripts/rotar_password_bd.sh <usuario_bd> <VARIABLE_ENV>
#  Ej.:   bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD
#
#  1. Genera una contraseña aleatoria
#  2. La aplica en PostgreSQL (ALTER USER)
#  3. La actualiza en el .env (manteniendo chmod 600)
#  La contraseña nueva nunca se imprime en pantalla.
# =====================================================================
set -euo pipefail

USUARIO="${1:-}"
VARIABLE="${2:-}"
CONTENEDOR="nutri_postgres"

if [[ -z "$USUARIO" || -z "$VARIABLE" ]]; then
    echo "Uso: bash scripts/rotar_password_bd.sh <usuario_bd> <VARIABLE_ENV>"
    exit 1
fi

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

if ! grep -q "^${VARIABLE}=" .env; then
    echo "ERROR: la variable ${VARIABLE} no existe en .env"
    exit 1
fi

NUEVA="$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)"

# El usuario debe existir antes de cambiar nada
EXISTE="$(docker exec "$CONTENEDOR" psql -U postgres -d nutrianimales_db -tAc \
          "SELECT 1 FROM pg_roles WHERE rolname = '${USUARIO}';")"
if [[ "$EXISTE" != "1" ]]; then
    echo "ERROR: el usuario ${USUARIO} no existe en PostgreSQL"
    exit 1
fi

# Se pasa por stdin para que la contraseña no aparezca en la lista de procesos
docker exec -i "$CONTENEDOR" psql -q -U postgres -d nutrianimales_db -v ON_ERROR_STOP=1 \
    -v usuario="$USUARIO" -v clave="$NUEVA" <<'EOSQL'
ALTER USER :"usuario" WITH PASSWORD :'clave';
EOSQL

sed -i "s|^${VARIABLE}=.*|${VARIABLE}=${NUEVA}|" .env
chmod 600 .env

echo "✔ Contraseña de '${USUARIO}' rotada y guardada en .env (${VARIABLE})."
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
if [[ "$USUARIO" == "agente_ia" || "$USUARIO" == "monitor_n8n" ]]; then
    echo "  Pendiente: actualizar la credencial Postgres de '${USUARIO}' en N8N (Credentials)."
fi
