#!/usr/bin/env bash
# A3 — Apertura no autorizada del puerto 5432 (detecta H1). Ejecutar como usuario normal (NO con
# "sudo bash"): H1 lee la línea de sudo "COMMAND=/usr/sbin/ufw ..." y solo aparece si cada
# comando de ufw lo ejecuta sudo directamente.
set -euo pipefail
read -r -p "Solo VM del proyecto. Escribe LAB para continuar: " c; [[ "$c" == "LAB" ]] || exit 1
echo "Inicio: $(date '+%Y-%m-%d %H:%M:%S')"
sudo ufw allow 5432/tcp
sudo ufw status numbered
echo "Espera la alerta H1. RESPUESTA después de capturarla:  sudo ufw delete allow 5432/tcp"
