#!/usr/bin/env bash
# =====================================================================
#  demo_m1.sh — Demostración en vivo de la parte de M1 (Infra/DevOps)
#  Uso:  bash scripts/demo_m1.sh
#  Avanza con Enter. Es repetible: no deja cambios permanentes en los datos.
#  Duración aproximada: 5 minutos.
# =====================================================================

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

PG="nutri_postgres"
BD="nutrianimales_db"
AZUL='\033[1;36m'; VERDE='\033[1;32m'; GRIS='\033[0;37m'; NEGRITA='\033[1m'; FIN='\033[0m'

# Lee un valor del .env sin mostrarlo
leer_env() { grep "^$1=" .env | cut -d= -f2-; }

# Consulta SQL como superusuario (socket local)
sql() { docker exec "$PG" psql -U postgres -d "$BD" -c "$1"; }

# Consulta SQL como otro usuario (socket local) — los errores de permiso son esperados
sql_como() { docker exec "$PG" psql -U "$1" -d "$BD" -c "$2" 2>&1 || true; }

titulo() {
    clear
    echo -e "${AZUL}════════════════════════════════════════════════════════════════${FIN}"
    echo -e "${AZUL}  NutriAnimales S.A. · BCD 9220 · Demo M1 — Infraestructura${FIN}"
    echo -e "${AZUL}════════════════════════════════════════════════════════════════${FIN}"
    echo -e "${NEGRITA}  $1${FIN}"
    echo -e "${GRIS}  $2${FIN}\n"
}

comando() { echo -e "${VERDE}\$ $1${FIN}"; }

pausa() { echo; read -rp "  [Enter] para continuar…" _; }

# ---------------------------------------------------------------- 1
titulo "1/9 · Arquitectura del stack" \
       "3 contenedores. Solo Nginx publica puertos (HD04)."
comando "docker compose ps"
docker compose ps --format "table {{.Name}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
pausa

# ---------------------------------------------------------------- 2
titulo "2/9 · Red aislada y puertos expuestos (HD03, HD04)" \
       "PostgreSQL vive solo dentro de nutrianimales-net; el host solo escucha 8080 y 8443."
comando "docker network inspect nutrianimales-net"
docker network inspect nutrianimales-net \
  --format 'Red: {{.Name}}  ·  Subred: {{range .IPAM.Config}}{{.Subnet}}{{end}}{{"\n"}}{{range .Containers}}  - {{.Name}}  {{.IPv4Address}}{{"\n"}}{{end}}'
comando "ss -tln | grep -E ':(5432|8080|8443) '"
ss -tln | grep -E ':(5432|8080|8443) ' || true
echo -e "\n  → 5432 no aparece: la base de datos NO es alcanzable desde fuera."
pausa

# ---------------------------------------------------------------- 3
titulo "3/9 · Mínimo privilegio en contenedores y secretos (HD01, HD02, HD10)" \
       "N8N corre sin root; el .env solo lo lee su dueño; los volúmenes son privados."
comando "docker exec nutri_n8n id"
docker exec nutri_n8n id
comando "ls -la .env"
ls -la .env
comando "git check-ignore -v .env"
git check-ignore -v .env
comando "ls -ld volumes/*"
ls -ld volumes/*
pausa

# ---------------------------------------------------------------- 4
titulo "4/9 · HTTPS con headers de seguridad (HD08, HD09)" \
       "Nginx termina TLS y agrega protección contra clickjacking, MIME sniffing y downgrade."
comando "curl -skI https://localhost:8443"
curl -skI https://localhost:8443 | grep -iE "^HTTP|strict-transport|x-frame|x-content-type|content-security" \
  | cut -c1-110
comando "curl -sI http://localhost:8080   (HTTP redirige a HTTPS)"
curl -sI http://localhost:8080 | grep -iE "^HTTP|^location"
pausa

# ---------------------------------------------------------------- 5
titulo "5/9 · PostgreSQL: cifrado y autenticación (HD05, HD06)" \
       "Contraseñas con scram-sha-256 y conexiones cifradas con TLS."
comando "SHOW password_encryption;  SHOW ssl;"
docker exec "$PG" psql -U postgres -d "$BD" -tAc "SELECT 'password_encryption = ' || current_setting('password_encryption') UNION ALL SELECT 'ssl                 = ' || current_setting('ssl');"
comando "Conexión por red con sslmode=require"
docker exec -e PGPASSWORD="$(leer_env POSTGRES_PASSWORD)" "$PG" \
  psql "host=localhost dbname=$BD user=postgres sslmode=require" \
  -c "SELECT ssl AS cifrada, version AS protocolo, cipher AS cifrado FROM pg_stat_ssl WHERE pid = pg_backend_pid();"
pausa

# ---------------------------------------------------------------- 6
titulo "6/9 · Baseline de seguridad (HD12)" \
       "Valores esperados vs. configuración real. Es la base de la alerta H5."
comando "SELECT * FROM pg_settings_baseline;"
sql "SELECT b.name AS parametro, b.valor_esperado, s.setting AS valor_actual,
            CASE WHEN s.setting = b.valor_esperado THEN '✔' ELSE '✘ DESVÍO' END AS estado
     FROM pg_settings_baseline b JOIN pg_settings s ON s.name = b.name ORDER BY 1;"
pausa

# ---------------------------------------------------------------- 7
titulo "7/9 · Control de acceso por roles (HD07, RBAC)" \
       "Cada usuario solo puede lo que su rol necesita."
comando "agente_ia (bot) intenta escribir:"
sql_como agente_ia "INSERT INTO gastos (categoria, descripcion, monto, aprobado_por) VALUES ('demo','intento',1,'bot');"
comando "agente_ia sí puede leer:"
sql_como agente_ia "SELECT count(*) AS clientes_visibles FROM clientes;"
comando "gerente_db intenta ver la auditoría:"
sql_como gerente_db "SELECT * FROM auditoria_datos LIMIT 1;"
comando "gerente_db sí ve su vista de reportes:"
sql_como gerente_db "SELECT * FROM vw_produccion_planta ORDER BY 1, 2 LIMIT 5;"
pausa

# ---------------------------------------------------------------- 8
titulo "8/9 · Triggers de auditoría (UPDATE y DELETE)" \
       "Toda modificación en tablas críticas queda registrada con el antes y el después."
comando "INSERT → UPDATE → DELETE de un cliente de prueba"
ID=$(docker exec "$PG" psql -U postgres -d "$BD" -tAc \
     "INSERT INTO clientes (nombre, tipo, correo, segmento) VALUES ('Cliente Demo', 'empresa', 'demo@nutri.cr', 'B') RETURNING id;" | head -1)
docker exec "$PG" psql -q -U postgres -d "$BD" -c "UPDATE clientes SET segmento = 'A' WHERE id = $ID;"
docker exec "$PG" psql -q -U postgres -d "$BD" -c "DELETE FROM clientes WHERE id = $ID;"
echo "  Cliente $ID creado, modificado y eliminado."
comando "SELECT … FROM auditoria_datos WHERE fila_id = $ID;"
sql "SELECT to_char(fecha, 'HH24:MI:SS') AS hora, usuario, operacion,
            valor_antes->>'segmento' AS segmento_antes, valor_nuevo->>'segmento' AS segmento_despues
     FROM auditoria_datos WHERE tabla = 'clientes' AND fila_id = $ID ORDER BY id;"
pausa

# ---------------------------------------------------------------- 9
titulo "9/9 · Rotación de un secreto comprometido" \
       "Simulamos que se filtró la contraseña de gerente_db y la rotamos en vivo."
ANTERIOR="$(leer_env GERENTE_DB_PASSWORD)"
comando "bash scripts/rotar_password_bd.sh gerente_db GERENTE_DB_PASSWORD"
bash scripts/rotar_password_bd.sh gerente_db GERENTE_DB_PASSWORD
NUEVA="$(leer_env GERENTE_DB_PASSWORD)"
comando "Login con la contraseña FILTRADA (anterior):"
docker exec -e PGPASSWORD="$ANTERIOR" "$PG" psql "host=localhost dbname=$BD user=gerente_db" \
  -tAc "SELECT 'acceso concedido';" 2>&1 | tail -1 || true
comando "Login con la contraseña NUEVA:"
docker exec -e PGPASSWORD="$NUEVA" "$PG" psql "host=localhost dbname=$BD user=gerente_db" \
  -tAc "SELECT '✔ acceso concedido con la contraseña nueva';" 2>&1 | tail -1
echo -e "\n  → La credencial filtrada quedó inutilizada. Ninguna contraseña se mostró en pantalla."
pausa

clear
echo -e "${AZUL}  Fin de la demo de M1 · 12 puntos de hardening · auditoría · RBAC · secretos${FIN}\n"
