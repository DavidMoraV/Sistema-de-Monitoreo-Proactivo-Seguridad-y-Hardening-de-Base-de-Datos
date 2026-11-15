#!/usr/bin/env bash
# A1 — Fuerza bruta SSH (20 intentos con usuario inexistente). Detecta R4 (vía auth.log → Loki).
# Ejecutar DESDE OTRA MÁQUINA (portátil o PC anfitrión), nunca desde la que usas para administrar el
# servidor: la respuesta (ufw deny from <ip>) bloquea la IP de origen.
# Solo contra la VM del proyecto. Requiere sshpass.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "Uso: $0 <IP_DE_LA_VM>"; exit 1; }
command -v sshpass >/dev/null || { echo "Instala sshpass (sudo apt install sshpass)"; exit 1; }
read -r -p "¿Es la VM del proyecto? Escribe LAB para continuar: " c; [[ "$c" == "LAB" ]] || exit 1
echo "Inicio: $(date '+%Y-%m-%d %H:%M:%S')"
for i in $(seq 1 20); do
  sshpass -p 'clave_mala_no_real' ssh -o ConnectTimeout=3 -o PreferredAuthentications=password \
    -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    "falso@$1" true >/dev/null 2>&1 || true
  echo -n "$i "
done
echo; echo "Fin: $(date '+%Y-%m-%d %H:%M:%S') — espera la alerta R4 (≤ 1–2 min)"
