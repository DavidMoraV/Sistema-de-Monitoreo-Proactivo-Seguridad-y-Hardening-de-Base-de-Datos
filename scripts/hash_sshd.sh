#!/usr/bin/env bash
# =====================================================================
# hash_sshd.sh · Proyecto II · NutriAnimales S.A.
# Calcula el hash SHA-256 de sshd_config y lo envía al webhook de N8N (alertas C1 y C2).
#
# Uso (desde cualquier carpeta):
#   ./scripts/hash_sshd.sh            -> calcula el hash y lo envía a N8N
#   ./scripts/hash_sshd.sh --dry-run  -> solo muestra el JSON, no envía nada
#
# La primera vez que N8N recibe el hash de un servidor lo guarda como línea base
# (tabla sshd_baseline); desde ahí, cualquier hash distinto dispara C1 y, sin un
# Change aprobado en GLPI, también C2 y el incidente con SLA de 1 hora.
#
# Programación con cron (cada 5 minutos), con "crontab -e" del usuario dueño del repo:
#   */5 * * * * /home/<usuario>/nutrianimales/scripts/hash_sshd.sh >> /home/<usuario>/nutrianimales/logs/hash_sshd.log 2>&1
# =====================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RAIZ="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${RAIZ}/.env"

# Configuración: se leen SOLO las variables que usa el script.
# No se hace "source" del .env: una contraseña con $, | o espacios rompería el script
# y además cargaría en memoria secretos que este script no necesita.
leer() {
  [[ -r "$ENV_FILE" ]] || return 0
  # "|| true": si la variable no está en el .env, grep falla y con "set -eo pipefail" cortaría el script
  { grep -E "^$1=" "$ENV_FILE" || true; } | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
}
SSHD_CONFIG="${SSHD_CONFIG_PATH:-$(leer SSHD_CONFIG_PATH)}"; SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
WEBHOOK_URL="${N8N_WEBHOOK_URL:-$(leer N8N_WEBHOOK_URL)}"
HOST_NAME="${HOST_NAME:-$(leer HOST_NAME)}"; HOST_NAME="${HOST_NAME:-nutrianimales-srv01}"
TOKEN="${HASH_WEBHOOK_TOKEN:-$(leer HASH_WEBHOOK_TOKEN)}"
TLS_INSECURE="${N8N_TLS_INSECURE:-$(leer N8N_TLS_INSECURE)}"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Validación: el archivo a vigilar debe existir y poder leerse (sshd_config es 644: no hace falta sudo)
if [[ ! -r "$SSHD_CONFIG" ]]; then
  echo "[ERROR] No se puede leer $SSHD_CONFIG" >&2
  exit 1
fi
# El nombre del host viaja en el JSON y N8N lo usa para buscar el activo en la CMDB
if [[ ! "$HOST_NAME" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
  echo "[ERROR] HOST_NAME inválido: use letras, números, punto, guion o guion bajo" >&2
  exit 1
fi

# Cálculo: huella SHA-256 del archivo y hora en UTC
HASH="$(sha256sum "$SSHD_CONFIG" | awk '{print $1}')"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Mensaje: JSON con el formato exacto que pide el enunciado
PAYLOAD=$(printf '{"hash_sshd":"%s","timestamp":"%s","host":"%s"}' "$HASH" "$TIMESTAMP" "$HOST_NAME")

if [[ "$DRY_RUN" == true ]]; then
  echo "$PAYLOAD"
  exit 0
fi

# Envío: POST al webhook de N8N con el secreto compartido en un header
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "[ERROR] Falta N8N_WEBHOOK_URL en el .env" >&2
  exit 1
fi
if [[ -z "$TOKEN" || "$TOKEN" == "__cambiar__" ]]; then
  echo "[ERROR] Falta HASH_WEBHOOK_TOKEN en el .env (generar con: openssl rand -hex 24)" >&2
  exit 1
fi

# TLS: N8N va detrás de Nginx con certificado autofirmado (Proyecto I).
# Se valida contra nginx/certs/nginx.crt (no se desactiva la verificación).
# N8N_TLS_INSECURE=true queda solo como último recurso.
CURL_TLS=()
CA_CERT="${RAIZ}/nginx/certs/nginx.crt"
if [[ "${TLS_INSECURE:-false}" == "true" ]]; then
  CURL_TLS=(-k)
elif [[ -f "$CA_CERT" ]]; then
  CURL_TLS=(--cacert "$CA_CERT")
  # El certificado de Nginx se emitió para nutrianimales.local (preparar_entorno.sh).
  # Si ese nombre no existe en el DNS, se apunta a 127.0.0.1: el script corre en el mismo servidor.
  if [[ "$WEBHOOK_URL" =~ ^https://nutrianimales\.local:([0-9]+)/ ]] && ! getent hosts nutrianimales.local > /dev/null; then
    CURL_TLS+=(--resolve "nutrianimales.local:${BASH_REMATCH[1]}:127.0.0.1")
  fi
fi

# El token va por stdin (-H @-) para que no aparezca en la lista de procesos (ps)
if printf 'X-Hash-Token: %s\n' "$TOKEN" | curl -fsS "${CURL_TLS[@]}" --max-time 15 -X POST \
     -H "Content-Type: application/json" -H @- \
     -d "$PAYLOAD" "$WEBHOOK_URL" > /dev/null; then
  echo "[OK] ${TIMESTAMP} hash enviado: ${HASH}"
else
  echo "[ERROR] ${TIMESTAMP} no se pudo enviar el hash a N8N" >&2
  exit 1
fi
