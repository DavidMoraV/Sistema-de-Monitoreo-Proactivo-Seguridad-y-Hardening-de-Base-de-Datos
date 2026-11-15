#!/usr/bin/env bash
# =====================================================================
#  init_n8n_m5.sh — M5: importa y activa SOLO los flujos H1 y H2
#  Uso (desde la raíz del repo, con el stack arriba y init_n8n_m3.sh ya ejecutado,
#  porque necesita la credencial "Postgres monitor_n8n" y el subflujo Enviar_Alerta):
#      bash scripts/init_n8n_m5.sh
#  No toca los flujos de M3 ni sus credenciales.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
IDS="alertaH1Ufw00001 alertaH2Hash0001"

echo "1) Copiando H1 y H2 al contenedor..."
docker compose exec -T n8n sh -c 'rm -rf /tmp/flujos_m5 && mkdir -p /tmp/flujos_m5'
docker compose cp n8n/flujos/H1_Cambio_reglas_UFW.json n8n:/tmp/flujos_m5/
docker compose cp n8n/flujos/H2_Integridad_config_PG.json n8n:/tmp/flujos_m5/

echo "2) Importando (si ya estaban activos, se desactivan antes)..."
for id in $IDS; do docker compose exec -T n8n n8n unpublish:workflow --id="$id" >/dev/null 2>&1 || true; done
docker compose exec -T n8n n8n import:workflow --separate --input=/tmp/flujos_m5

echo "3) Activando..."
for id in $IDS; do
  docker compose exec -T n8n n8n publish:workflow --id="$id" >/dev/null && echo "   activo: $id"
done
docker compose exec -T n8n rm -rf /tmp/flujos_m5

echo "4) Reiniciando N8N (los cambios de publicación se aplican al reiniciar)..."
docker compose restart n8n
echo "Listo. H1 y H2 corren cada minuto."
