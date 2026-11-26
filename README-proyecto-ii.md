# Proyecto II · GLPI para ITSM, CMDB y cumplimiento ISO/IEC 27001

**NutriAnimales S.A.** · BCD 9220 Seguridad de Sistemas Digitales · Lead University · III Cuatrimestre 2026
Integrantes: David Mora · Jean Rabbat · Luis Rojas · Jorge Chaves · Cristian Vargas

Continuación del Proyecto I. Sobre el mismo stack (Docker, PostgreSQL, N8N, Nginx y Telegram) se agrega **GLPI** como herramienta central de gestión de servicios de TI. El flujo completo es:

1. **Detecta:** `scripts/hash_sshd.sh` calcula el SHA-256 de `sshd_config` y lo envía al webhook de N8N.
2. **Decide:** N8N compara el hash con la línea base y consulta en GLPI si existe un Change aprobado.
3. **Gestiona:** N8N crea el incidente en GLPI con SLA crítico de 1 hora y lo cierra cuando el hash vuelve a la línea base.
4. **Notifica:** N8N envía las alertas C1, C2 y C3 a Telegram.

---

## 1. Qué se agregó al repositorio

| Archivo | Para qué sirve |
|---|---|
| `docker-compose.glpi.yml` | GLPI 10.0 y su base de datos MariaDB. Es un archivo aparte para no modificar el compose del Proyecto I. |
| `.env.example` | Variables nuevas de GLPI y del script de hash (al final del archivo). |
| `scripts/hash_sshd.sh` | Script que calcula el hash de `sshd_config` y lo envía a N8N. |

GLPI queda en `http://<IP_DEL_SERVIDOR>:8090`. Su base de datos no publica puertos: solo GLPI la alcanza por la red interna `nutrianimales-net`.

---

## 2. Requisitos

- El stack del Proyecto I instalado y funcionando (sección 5 del `README.md` principal).
- Puerto **8090** libre en el servidor.

---

## 3. Instalación paso a paso

### 3.1 Actualizar el repositorio

```bash
cd ~/Sistema-de-Monitoreo-Proactivo-Seguridad-y-Hardening-de-Base-de-Datos
git pull
```

### 3.2 Agregar las variables nuevas al `.env`

El `.env` del servidor ya existe, así que hay que copiarle a mano el bloque nuevo que está al final de `.env.example` (desde `# --- Proyecto II: compose combinado`).

```bash
# Ver el bloque nuevo
tail -n 17 .env.example

# Abrir el .env y pegarlo al final
nano .env
```

Luego completar:

- `GLPI_DB_PASSWORD`: generar una con `openssl rand -base64 18`.
- `N8N_WEBHOOK_URL`: cambiar la IP por la del servidor (la misma de `SERVIDOR_IP`).
- `GLPI_APP_TOKEN` y `GLPI_USER_TOKEN` se dejan en `__cambiar__` por ahora; se completan en el paso 3.5.

La línea `COMPOSE_FILE` hace que `docker compose` use los tres archivos (base, logs y GLPI) sin escribir `-f`.

### 3.3 Levantar el stack completo

```bash
docker compose up -d
docker compose ps        # 7 servicios: postgres, n8n, nginx, loki, alloy, glpi_db y glpi
```

La primera vez, GLPI instala su base de datos solo. Puede tardar uno o dos minutos; se puede seguir con `docker logs -f nutri_glpi`.

### 3.4 Primer ingreso a GLPI

1. Abrir `http://<IP_DEL_SERVIDOR>:8090`.
2. Entrar con el usuario por defecto `glpi` / contraseña `glpi`.
3. Cambiar de inmediato las contraseñas de las cuentas por defecto (`glpi`, `tech`, `normal` y `post-only`); GLPI muestra un aviso con los enlaces.

### 3.5 Activar la API REST y generar los tokens

1. **Configuración → General → pestaña API**
   - Activar **Habilitar API REST**.
   - Activar **Habilitar inicio de sesión con token externo**.
   - Guardar.
2. En esa misma pestaña, **Añadir cliente API**:
   - Nombre: `n8n`
   - Activo: Sí
   - Rango de IP: dejar vacío para el laboratorio.
   - Guardar y copiar el **Token de aplicación (app_token)** → va en `GLPI_APP_TOKEN`.
3. **Administración → Usuarios → glpi** (o un usuario dedicado para N8N, recomendado):
   - En **Claves de acceso remoto**, marcar **Regenerar** junto a **Token de API** y guardar.
   - Copiar el token → va en `GLPI_USER_TOKEN`.
4. Guardar ambos tokens en el `.env` y recrear N8N para que los tome:

```bash
nano .env
docker compose up -d n8n
```

### 3.6 Probar la API desde el servidor

```bash
source .env
curl -s -H "App-Token: ${GLPI_APP_TOKEN}" \
     -H "Authorization: user_token ${GLPI_USER_TOKEN}" \
     http://localhost:8090/apirest.php/initSession
```

Debe responder algo como `{"session_token":"..."}`. Si responde un error, revisar el paso 3.5.

Dentro de N8N, la API se usa por la red interna con las variables `$env.GLPI_API_URL`, `$env.GLPI_APP_TOKEN` y `$env.GLPI_USER_TOKEN`.

### 3.7 Script de hash de `sshd_config`

```bash
chmod +x scripts/hash_sshd.sh

# Prueba sin enviar nada: muestra el JSON
sudo ./scripts/hash_sshd.sh --dry-run

# Envío real a N8N (requiere el flujo con el webhook "hash-sshd" activo)
sudo ./scripts/hash_sshd.sh
```

El JSON que envía tiene el formato del enunciado:

```json
{ "hash_sshd": "<sha256>", "timestamp": "2026-12-10T10:00:00Z", "host": "nutrianimales-srv01" }
```

Para que corra solo cada 5 minutos, agregar con `sudo crontab -e`:

```
*/5 * * * * /ruta/al/repo/scripts/hash_sshd.sh >> /var/log/hash_sshd.log 2>&1
```

Si `curl` rechaza el certificado autofirmado de Nginx, poner `N8N_TLS_INSECURE=true` en el `.env`.

---

## 4. Configuración funcional en GLPI (resumen)

| Elemento | Dónde | Qué configurar |
|---|---|---|
| CMDB | Activos → Computadoras | Servidor `nutrianimales-srv01` y los contenedores relacionados |
| SLA | Configuración → Niveles de servicio | SLA de tiempo de resolución de 1 hora para severidad crítica, con calendario 24/7 |
| Regla de SLA | Administración → Reglas → Reglas de negocio para tickets | Asignar el SLA crítico a los incidentes de la categoría de N8N |
| Cambios | Asistencia → Cambios | Change con aprobador, plan de reversión y estado ejecutado |
| Problemas | Asistencia → Problemas | Problema vinculado al incidente, con causa raíz |

El detalle de cada práctica está en el informe técnico (sección ITIL 4 en GLPI).

---

## 5. Reiniciar GLPI desde cero

Borra solo los datos de GLPI; no toca PostgreSQL ni N8N.

```bash
docker compose stop glpi glpi_db
docker compose rm -f glpi glpi_db
sudo rm -rf volumes/glpi volumes/glpi_db
docker compose up -d
```

---

## 6. Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `glpi` no arranca y queda esperando | `glpi_db` todavía no está lista | Esperar; `docker compose ps` debe mostrar `glpi_db (healthy)` |
| La página de GLPI no carga | Puerto 8090 bloqueado por UFW | `sudo ufw allow from 192.168.56.0/24 to any port 8090 proto tcp` |
| La API responde `ERROR_APP_TOKEN_PARAMETERS_MISSING` o similar | Falta el app_token o la API está desactivada | Revisar el paso 3.5 |
| El script da `[ERROR] Falta N8N_WEBHOOK_URL` | Variable no copiada al `.env` | Revisar el paso 3.2 |
| El script no conecta con N8N | Flujo inactivo o certificado rechazado | Activar el flujo en N8N o usar `N8N_TLS_INSECURE=true` |
