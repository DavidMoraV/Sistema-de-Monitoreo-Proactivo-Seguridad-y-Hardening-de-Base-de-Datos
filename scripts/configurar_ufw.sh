#!/usr/bin/env bash
set -euo pipefail

# Ejecutar SOLO en la VM Ubuntu de integración autorizada.
# Confirmar acceso de consola/respaldo antes de habilitar el firewall.
if [[ "${EUID}" -ne 0 ]]; then
  echo "Ejecute con sudo: sudo bash scripts/configurar_ufw.sh"
  exit 1
fi

command -v ufw >/dev/null || { echo "UFW no está instalado."; exit 1; }

echo "Reglas: SSH/22 solo desde la red de administración (192.168.56.0/24) y HTTPS/8443."
echo "Verifique que el puerto SSH real sea 22 antes de continuar."
read -r -p "¿Confirmó acceso de consola y puerto SSH? Escriba SI para continuar: " confirm
[[ "$confirm" == "SI" ]] || { echo "Cancelado."; exit 1; }

ufw default deny incoming
ufw default allow outgoing
# Ajuste de integración (M1): SSH solo desde la red solo-anfitrión, no desde cualquier origen.
ufw allow from 192.168.56.0/24 to any port 22 proto tcp comment 'SSH desde red solo-anfitrion'
ufw allow 8443/tcp
ufw logging medium
ufw --force enable
ufw status verbose
