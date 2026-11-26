#!/usr/bin/env bash
# =====================================================================
# hash_sshd.sh · Proyecto II · NutriAnimales S.A.
# Calcula el hash SHA-256 de sshd_config y lo envía al webhook de N8N.
#
# Uso:
#   ./hash_sshd.sh            -> calcula el hash y lo envía a N8N
#   ./hash_sshd.sh --dry-run  -> solo muestra el JSON, no envía nada
#
# Programación con cron (cada 5 minutos):
#   */5 * * * * /ruta/al/proyecto/script/hash_sshd.sh >> /var/log/hash_sshd.log 2>&1
# =====================================================================

set -euo pipefail

# Configuración: carga variables del archivo .env del proyecto
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

SSHD_CONFIG="${SSHD_CONFIG_PATH:-/etc/ssh/sshd_config}"
WEBHOOK_URL="${N8N_WEBHOOK_URL:-}"
HOST_NAME="${HOST_NAME:-nutrianimales-srv01}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validación: el archivo a vigilar debe existir y poder leerse
if [[ ! -r "$SSHD_CONFIG" ]]; then
  echo "[ERROR] No se puede leer $SSHD_CONFIG" >&2
  exit 1
fi

# Cálculo: huella SHA-256 del archivo y hora en UTC
HASH="$(sha256sum "$SSHD_CONFIG" | awk '{print $1}')"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Mensaje: JSON con el formato exacto que pide el enunciado
PAYLOAD=$(printf '{"hash_sshd":"%s","timestamp":"%s","host":"%s"}' \
  "$HASH" "$TIMESTAMP" "$HOST_NAME")

# Modo prueba: muestra el JSON sin enviarlo
if [[ "$DRY_RUN" == true ]]; then
  echo "$PAYLOAD"
  exit 0
fi

# Envío: POST al webhook de N8N
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "[ERROR] Falta N8N_WEBHOOK_URL en el archivo .env" >&2
  exit 1
fi

# TLS: N8N va detrás de Nginx con certificado autofirmado (Proyecto I).
# Se valida contra nginx/certs/nginx.crt; si el nombre del certificado no
# coincide con la URL, se puede poner N8N_TLS_INSECURE=true en el .env.
CURL_TLS=()
CA_CERT="${SCRIPT_DIR}/../nginx/certs/nginx.crt"
if [[ "${N8N_TLS_INSECURE:-false}" == "true" ]]; then
  CURL_TLS=(-k)
elif [[ -f "$CA_CERT" ]]; then
  CURL_TLS=(--cacert "$CA_CERT")
fi

if curl -fsS "${CURL_TLS[@]}" --max-time 15 -X POST \
     -H "Content-Type: application/json" \
     -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null; then
  echo "[OK] ${TIMESTAMP} hash enviado: ${HASH}"
else
  echo "[ERROR] ${TIMESTAMP} no se pudo enviar el hash a N8N" >&2
  exit 1
fi
