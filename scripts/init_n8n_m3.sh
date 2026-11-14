#!/usr/bin/env bash
# =====================================================================
#  init_n8n_m3.sh — M3: carga credenciales y flujos de N8N y los activa
#  Uso (desde la raíz del repo, con "docker compose up -d" ya corriendo):
#      bash scripts/init_n8n_m3.sh
#  Lee del .env: POSTGRES_DB, AGENTE_IA_PASSWORD, MONITOR_N8N_PASSWORD,
#                TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (GROQ_API_KEY la lee N8N en cada uso)
#  Las contraseñas no se escriben en disco del host: se pasan al contenedor como
#  variables de entorno del proceso y el JSON temporal se borra al terminar.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "No existe .env (ejecute antes scripts/preparar_entorno.sh)"; exit 1; }

leer() { grep -E "^$1=" .env | tail -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'; }
for V in AGENTE_IA_PASSWORD MONITOR_N8N_PASSWORD TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID GROQ_API_KEY; do
  VAL="$(leer "$V")"
  if [ -z "$VAL" ] || [ "$VAL" = "__cambiar__" ]; then echo "Falta $V en el .env"; exit 1; fi
done
PG_SSL="${PG_SSL:-require}"   # PostgreSQL tiene ssl=on (HD06)

echo "1) Copiando flujos al contenedor..."
docker compose exec -T n8n sh -c 'rm -rf /tmp/flujos && mkdir -p /tmp/flujos'
docker compose cp n8n/flujos/. n8n:/tmp/flujos/

echo "2) Creando credenciales..."
docker compose exec -T \
  -e PG_SSL="$PG_SSL" -e PG_DB="$(leer POSTGRES_DB)" \
  -e PW_AGENTE="$(leer AGENTE_IA_PASSWORD)" -e PW_MONITOR="$(leer MONITOR_N8N_PASSWORD)" \
  -e TG_TOKEN="$(leer TELEGRAM_BOT_TOKEN)" \
  n8n sh -c '
node -e "
const e = process.env;
const pg = (user, pass) => ({ host: \"postgres\", database: e.PG_DB || \"nutrianimales_db\", user, password: pass,
  port: 5432, ssl: e.PG_SSL, allowUnauthorizedCerts: e.PG_SSL !== \"disable\" });
const creds = [
  { id: \"pgMonitorN8N0001\", name: \"Postgres monitor_n8n\", type: \"postgres\", data: pg(\"monitor_n8n\", e.PW_MONITOR) },
  { id: \"pgAgenteIA000001\", name: \"Postgres agente_ia\", type: \"postgres\", data: pg(\"agente_ia\", e.PW_AGENTE) },
  { id: \"telegramNA000001\", name: \"Telegram Bot NutriAnimales\", type: \"telegramApi\", data: { accessToken: e.TG_TOKEN } },
  // La key de Groq NO se copia: se lee del .env en cada uso (rotación 6.1 = editar .env + restart)
  { id: \"groqHeaderNA0001\", name: \"Groq API\", type: \"httpHeaderAuth\", data: { name: \"Authorization\", value: \"=Bearer {{ \$env.GROQ_API_KEY }}\" } }
];
require(\"fs\").writeFileSync(\"/tmp/creds.json\", JSON.stringify(creds), { mode: 0o600 });
" && n8n import:credentials --input=/tmp/creds.json; r=$?; rm -f /tmp/creds.json; exit $r'

IDS="enviarAlertaNA01 botTelegramNA001 alertaR1Lenta001 alertaR2Conex001 alertaR3Horar001 alertaR4Auth0001 alertaR5Param001 alertaH3Privi001 alertaH4RedEx001 alertaH5Basel001"

echo "3) Importando flujos..."
# Si ya estaban activos (segunda vez que se corre el script), hay que desactivarlos antes:
# n8n 2.45 no deja sobrescribir un flujo activo al importar.
for id in $IDS; do docker compose exec -T n8n n8n unpublish:workflow --id="$id" >/dev/null 2>&1 || true; done
docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/flujos

echo "4) Activando flujos de M3..."
for id in $IDS; do
  docker compose exec -T n8n n8n publish:workflow --id="$id" >/dev/null && echo "   activo: $id"
done
docker compose exec -T n8n rm -rf /tmp/flujos

echo "5) Reiniciando N8N..."
docker compose restart n8n
echo "Listo. Entre a https://<SERVIDOR_IP>:8443 → Workflows."
