#!/usr/bin/env bash
# =====================================================================
#  preparar_entorno.sh — deja el servidor listo para "docker compose up -d"
#  Uso (desde la raíz del repo):  bash scripts/preparar_entorno.sh
#
#  1. Crea el .env con contraseñas aleatorias (si no existe) y chmod 600   → HD02
#  2. Crea los directorios de volúmenes con dueño correcto y chmod 700     → HD10
#  3. Genera el certificado autofirmado de Nginx                           → HD09
#  4. Genera el certificado de PostgreSQL (para HD06, lo activa M2)
#  Es idempotente: no sobrescribe nada que ya exista.
# =====================================================================
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

UID_N8N=1000          # usuario con el que corre N8N (user: "1000:1000")
UID_POSTGRES=999      # usuario interno de la imagen oficial postgres:16

generar_clave() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }

echo "== 1/4  Archivo .env =="
if [[ -f .env ]]; then
    echo "   .env ya existe: no se modifica."
else
    IP_SERVIDOR="$(ip -4 -o addr show enp0s8 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)"
    IP_SERVIDOR="${IP_SERVIDOR:-192.168.56.102}"
    sed -e "s|^SERVIDOR_IP=.*|SERVIDOR_IP=${IP_SERVIDOR}|" \
        -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(generar_clave)|" \
        -e "s|^AGENTE_IA_PASSWORD=.*|AGENTE_IA_PASSWORD=$(generar_clave)|" \
        -e "s|^MONITOR_N8N_PASSWORD=.*|MONITOR_N8N_PASSWORD=$(generar_clave)|" \
        -e "s|^N8N_PASSWORD=.*|N8N_PASSWORD=$(generar_clave)Aa1|" \
        -e "s|^N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)|" \
        .env.example > .env
    echo "   .env creado con contraseñas aleatorias (IP del servidor: ${IP_SERVIDOR})."
    echo "   Pendiente: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID y GROQ_API_KEY (los completa M3)."
fi
chmod 600 .env

echo "== 2/4  Volúmenes =="
mkdir -p volumes/pgdata volumes/n8n
sudo chown -R "${UID_N8N}:${UID_N8N}" volumes/n8n
chmod 700 volumes volumes/n8n
sudo chmod 700 volumes/pgdata          # PostgreSQL ajusta el dueño (999) al iniciar

echo "== 3/4  Certificado de Nginx =="
if [[ -f nginx/certs/nginx.crt ]]; then
    echo "   Ya existe: no se regenera."
else
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout nginx/certs/nginx.key -out nginx/certs/nginx.crt \
        -subj "/C=CR/O=NutriAnimales S.A./CN=nutrianimales.local" 2>/dev/null
    chmod 600 nginx/certs/nginx.key
    echo "   nginx.crt / nginx.key generados."
fi

echo "== 4/4  Certificado de PostgreSQL =="
if sudo test -f certs/postgres/server.crt; then
    echo "   Ya existe: no se regenera."
else
    openssl req -new -x509 -days 365 -nodes -subj "/CN=nutri_postgres" \
        -keyout certs/postgres/server.key -out certs/postgres/server.crt 2>/dev/null
    sudo chown "${UID_POSTGRES}:${UID_POSTGRES}" certs/postgres/server.key certs/postgres/server.crt
    sudo chmod 600 certs/postgres/server.key
    echo "   server.crt / server.key generados (dueño UID ${UID_POSTGRES})."
fi

echo
echo "Listo. Siguiente paso:  docker compose up -d && docker compose ps"
