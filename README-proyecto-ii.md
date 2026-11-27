# Proyecto II · GLPI para ITSM, CMDB y cumplimiento ISO/IEC 27001

**NutriAnimales S.A.** · BCD 9220 Seguridad de Sistemas Digitales · Lead University · III Cuatrimestre 2026
Integrantes: David Mora · Jean Rabbat · Luis Rojas · Jorge Chaves · Cristian Vargas

Continuación del Proyecto I. Sobre el mismo stack (Docker, PostgreSQL, N8N, Nginx y Telegram) se agrega **GLPI** como herramienta central de gestión de servicios de TI. El flujo completo es:

1. **Detecta:** `scripts/hash_sshd.sh` calcula el SHA-256 de `sshd_config` y lo envía al webhook de N8N.
2. **Decide:** N8N compara el hash con la línea base guardada en PostgreSQL y consulta en GLPI si existe un Change aprobado.
3. **Gestiona:** N8N crea el incidente en GLPI con SLA crítico de 1 hora y lo cierra cuando el hash vuelve a la línea base.
4. **Notifica:** N8N envía las alertas C1, C2 y C3 a Telegram con el subflujo `Enviar_Alerta` del Proyecto I.

---

## 1. Qué se agregó al repositorio

| Archivo | Para qué sirve |
|---|---|
| `docker-compose.glpi.yml` | GLPI 10.0 y MariaDB, sin puertos publicados. Amplía Nginx (puerto 8444) y N8N (variables). Archivo aparte para no modificar el compose del Proyecto I. |
| `nginx/glpi.conf` | Sitio HTTPS de GLPI en Nginx (8444), con los headers de seguridad. |
| `sql/08_itsm_glpi.sql` | Tablas de estado del flujo: `sshd_baseline` (línea base) y `glpi_incidentes` (incidentes abiertos por N8N, marca de C3), más la vista `vw_tiempos_incidentes`. |
| `n8n/flujos/C1C2_Cambio_sshd_config.json` | Flujo de detección: webhook, comparación, GLPI y alertas C1 y C2. |
| `n8n/flujos/C3_SLA_vencido.json` | Flujo programado: alerta C3 cuando un incidente crítico supera el SLA. |
| `n8n_workflow.json` | Export de los dos flujos en un solo archivo (entregable del ZIP). |
| `scripts/hash_sshd.sh` | Calcula el hash de `sshd_config` y lo envía a N8N con un secreto compartido. |
| `scripts/cargar_cmdb_glpi.py` | Carga en la CMDB los 7 contenedores y su relación de impacto con el servidor (idempotente). |
| `.env.example` | Variables nuevas del Proyecto II (al final del archivo). |

### Decisiones de seguridad (coherentes con el Proyecto I)

| Decisión | Motivo |
|---|---|
| GLPI y MariaDB **sin `ports:`**; GLPI sale solo por Nginx en `https://<IP>:8444` | Docker publica puertos por encima de UFW: un `ports:` en GLPI quedaría abierto a toda la red y sin cifrar. Igual que HD04, Nginx es el único punto de entrada. |
| El webhook exige el header `X-Hash-Token` | Sin él, cualquiera en la red podría enviar un hash falso, o el de la línea base para cerrar el incidente solo. |
| Línea base y estado de los incidentes en **PostgreSQL** | En N8N 2.x la memoria de un flujo publicado no se conserva entre ejecuciones (mismo caso que H2). Además, las horas salen de un solo reloj y no dependen de la zona horaria de GLPI. |
| El script lee **solo sus variables** del `.env` | Un `source` del `.env` completo falla con contraseñas que tienen `$`, `\|` o espacios, y carga secretos que no usa. |
| El script **valida el certificado** de Nginx (`--cacert`) | No se desactiva TLS; `N8N_TLS_INSECURE=true` queda solo como último recurso. |

---

## 2. Requisitos

- El stack del Proyecto I instalado y funcionando (sección 5 del `README.md` principal).
- Al menos **2 GB de RAM libres** en la VM para GLPI y MariaDB.

---

## 3. Instalación paso a paso

> Todos los comandos son en el servidor (📍 Ubuntu/SSH), dentro de la carpeta del repositorio: `cd ~/nutrianimales`

### 3.1 Actualizar el repositorio y el `.env`

```bash
git pull
bash scripts/preparar_entorno.sh
```

`preparar_entorno.sh` no toca lo que ya existe: solo **agrega** al `.env` las variables nuevas del Proyecto II, con `GLPI_DB_PASSWORD` y `HASH_WEBHOOK_TOKEN` generados al azar. `GLPI_APP_TOKEN` y `GLPI_USER_TOKEN` quedan en `__cambiar__` hasta el paso 3.5. También crea `volumes/glpi` con dueño `www-data` (uid 33): si la crea Docker queda de root y GLPI no arranca.

Si `git config core.fileMode` es `false` en el clon, Git no aplica el bit de ejecución: `chmod +x scripts/*.sh scripts/*.py`.

La línea `COMPOSE_FILE` hace que `docker compose` use los tres archivos (base, logs y GLPI) sin escribir `-f`.

### 3.2 Crear las tablas del flujo en PostgreSQL

En una instalación nueva se crean solas. En el servidor que ya tiene la base de datos del Proyecto I:

```bash
docker exec -i nutri_postgres psql -U postgres -d nutrianimales_db < sql/08_itsm_glpi.sql
```

### 3.3 Levantar el stack completo

```bash
docker compose up -d
docker compose ps        # 7 servicios: postgres, n8n, nginx, loki, alloy, glpi_db y glpi
```

`nutri_nginx` debe mostrar `8080`, `8443` y `8444`; `nutri_glpi` y `nutri_glpi_db` **no** muestran puertos. La primera vez, GLPI instala su base de datos solo; puede tardar uno o dos minutos (`docker logs -f nutri_glpi`).

### 3.4 Primer ingreso a GLPI

1. Abrir `https://<IP_DEL_SERVIDOR>:8444` (el navegador avisa del certificado autofirmado, igual que con N8N).
2. Entrar con `glpi` / `glpi`.
3. Cambiar de inmediato las contraseñas de las cuentas por defecto (`glpi`, `tech`, `normal` y `post-only`); GLPI muestra un aviso con los enlaces.
4. **Configuración → General → Configuración general → URL de la aplicación:** `https://<IP_DEL_SERVIDOR>:8444`.

### 3.5 Activar la API REST y generar los tokens

1. **Configuración → General → pestaña API**
   - Activar **Habilitar API REST** y **Habilitar inicio de sesión con token externo**. Guardar.
   - **Cliente API:** GLPI trae uno llamado *full access from localhost* que solo acepta `127.0.0.1`. Abrirlo (o añadir uno nuevo) y dejarlo así: nombre `n8n`, activo, **IPv4 de `172.18.0.1` a `172.18.255.255`** (la red `nutrianimales-net`: N8N y Nginx llegan desde ahí), IPv6 vacía, marcar **Regenerar** y guardar. Copiar el **Token de aplicación** → `GLPI_APP_TOKEN`.
2. **Administración → Usuarios → Añadir:** usuario `n8n` (cuenta de servicio, perfil *Technician*, entidad raíz).
   - Sin contraseña: solo entra por la API.
   - En **Claves de acceso remoto**, marcar **Regenerar** junto a **Token de API**, guardar y, **ya recargada la página**, copiar el token → `GLPI_USER_TOKEN`.
   - Son dos tokens distintos: `GLPI_APP_TOKEN` (cliente API) y `GLPI_USER_TOKEN` (usuario `n8n`). Si se pega el mismo en las dos líneas, la API responde `user_token seems invalid`.
3. Guardar ambos tokens en el `.env` y recrear N8N para que los tome:

```bash
nano .env
docker compose up -d n8n
```

> Tras recrear N8N, los flujos tardan unos 3 minutos en volver a alertar. No hacerlo justo antes de una demo.

> Idioma: **Mi configuración → Personalización → Idioma: Español** y desactivar el traductor del navegador para este sitio. Con la traducción automática, los desplegables buscan por el texto original y las capturas salen con errores ("Estibador" en vez de "Docker").

### 3.6 Probar la API

```bash
APP=$(grep ^GLPI_APP_TOKEN= .env | cut -d= -f2-); USR=$(grep ^GLPI_USER_TOKEN= .env | cut -d= -f2-)
curl -sk -H "App-Token: $APP" -H "Authorization: user_token $USR" https://localhost:8444/apirest.php/initSession
```

Debe responder `{"session_token":"..."}`. Dentro de N8N, la API se usa por la red interna (`http://glpi/apirest.php`).

### 3.7 Cargar los flujos de N8N

```bash
bash scripts/init_n8n_m3.sh
```

Importa y activa los 21 flujos (los 19 del Proyecto I más C1/C2 y C3). El flujo C1/C2 usa el subflujo `Enviar_Alerta`, así que las alertas del Proyecto II quedan también en `alertas_auditoria`.

### 3.8 Script de hash y línea base

```bash
./scripts/hash_sshd.sh --dry-run     # muestra el JSON sin enviarlo
./scripts/hash_sshd.sh               # primer envío: N8N lo guarda como línea base
```

El primer envío de cada servidor queda como **línea base** (tabla `sshd_baseline`) y llega un aviso a Telegram. Para que corra solo cada 5 minutos (`crontab -e`, con el usuario dueño del repositorio):

```
*/5 * * * * /home/<usuario>/nutrianimales/scripts/hash_sshd.sh >> /home/<usuario>/nutrianimales/logs/hash_sshd.log 2>&1
```

El JSON que envía tiene el formato del enunciado:

```json
{ "hash_sshd": "<sha256>", "timestamp": "2026-12-10T10:00:00Z", "host": "nutrianimales-srv01" }
```

---

## 4. Configuración funcional en GLPI

Orden recomendado (cada paso depende del anterior). Los nombres coinciden con la *Guía de configuración de GLPI* del Drive.

| # | Elemento | Dónde | Qué configurar | Control |
|---|---|---|---|---|
| 1 | Grupo y usuarios | Administración → Grupos / Usuarios | Grupo `Equipo TI NutriAnimales`; usuario `aprobador` (perfil *Supervisor*); `n8n`, `aprobador` y el administrador dentro del grupo | A.8.32 |
| 2 | Categorías | Configuración → Desplegables → Asistencia → Categorías ITIL | `Seguridad > Cambio de configuración` (su ID va en `GLPI_CATEGORIA_ID`) y `Auditoría > No conformidad ISO` | A.5.26 |
| 3 | Calendario | Configuración → Desplegables → Calendarios | `24/7 NutriAnimales`, de lunes a domingo de 00:00 a 24:00 | A.5.26 |
| 4 | SLA | Configuración → Niveles de servicio | `SLM NutriAnimales` con el calendario anterior y 4 SLA de **tiempo de resolución**: `SLA Crítico · Resolución 1 h` (su ID va en `GLPI_SLA_CRITICO_ID`), Alto 4 h, Medio 8 h y Bajo 24 h | A.5.26 |
| 5 | Regla del SLA | Administración → Reglas → **Reglas de negocio para tickets** (no la de activos) | `SLA crítico para cambios de configuración`, al agregar: si categoría = *Cambio de configuración* y tipo = *Incidente* → SLA crítico, prioridad muy alta y grupo técnico | A.5.26 |
| 6 | Servidor | Activos → Computadoras | `nutrianimales-srv01` en minúscula (igual que `HOST_NAME`), tipo *Servidor*, estado *En producción* | A.5.9 |
| 7 | Contenedores | Pestaña **Virtualización** del servidor y `python3 scripts/cargar_cmdb_glpi.py` | Los 7 contenedores como máquinas virtuales del servidor y como computadoras tipo *Contenedor Docker* relacionadas en **Análisis de impacto**. El script pide el token de API del administrador (Mi configuración → Claves de acceso remoto) y no lo guarda | A.5.9 |
| 8 | Cambios | Asistencia → Cambios | Change vinculado al servidor, aprobado por `aprobador`, con plan de reversión y estado *Aplicado* al terminar | A.8.32 |
| 9 | Problemas | Asistencia → Problemas | Problema vinculado al incidente y al Change, con causa raíz | ITIL |

Para revisar la configuración sin depender del navegador:

```bash
docker exec nutri_glpi_db sh -c 'mariadb -u"$MARIADB_USER" -p"$MARIADB_PASSWORD" "$MARIADB_DATABASE" -e "
SELECT id, completename FROM glpi_itilcategories; SELECT id, name, type FROM glpi_slas;
SELECT a.field, a.value FROM glpi_ruleactions a JOIN glpi_rules r ON r.id = a.rules_id WHERE r.name LIKE \"SLA%\";"'
```

En `glpi_slas`, `type = 0` es tiempo de resolución (1 es tiempo de asignación, que no aplica aquí).

### Roles del grupo y usuarios en GLPI

| Rol del proyecto | Integrante | Usuario y perfil en GLPI |
|---|---|---|
| Infraestructura (GLPI, CMDB, API) | David Mora | Administrador `glpi` · Super-Admin |
| Aprobador de cambios | Por definir | `aprobador` · *Supervisor* (valida Changes) |
| Automatización (N8N y script) | Por definir | Cuenta de servicio `n8n` · *Technician* (solo API) |
| Auditor (auditoría interna) | Cristian Vargas | Perfil *Observer* (solo lectura) |

---

## 5. Comportamiento del flujo

| Situación | Qué hace N8N | Telegram |
|---|---|---|
| Primer hash del servidor | Lo guarda como línea base | Aviso informativo |
| Hash igual a la línea base, sin incidente | Nada | — |
| Hash distinto, **sin** Change aprobado | Crea el incidente (urgencia e impacto 5, SLA crítico, vinculado al servidor) | **C1** y **C2** con el número de ticket |
| Hash distinto con el incidente ya abierto | Nada (no repite alertas en cada ejecución del cron) | — |
| Hash distinto **con** un Change aprobado y no aplicado vinculado al servidor | El hash nuevo pasa a ser la línea base y se anota en el Change | **C1** informativa (ADVERTENCIA) |
| El hash vuelve a la línea base con un incidente abierto | Seguimiento y **cierre automático** del incidente | Aviso de cierre |
| Incidente abierto más de `C3_UMBRAL_MINUTOS` | Marca la alerta como enviada (una sola vez por incidente) | **C3** |
| Se envía un JSON sin `X-Hash-Token` válido | Se descarta | — |

### Tiempos del estudio de caso

```bash
docker exec nutri_postgres psql -U postgres -d nutrianimales_db -c "SELECT * FROM vw_tiempos_incidentes;"
```

Muestra la apertura y el cierre de cada incidente, los minutos abierto y si se cerró dentro del SLA de 1 hora.

### Demostrar C3 sin esperar una hora

Poner `C3_UMBRAL_MINUTOS=2` en el `.env` y `docker compose up -d n8n` (esperar unos 3 minutos). Volver a `60` al terminar. El estudio de caso principal debe cerrarse **dentro** de la hora; C3 se demuestra con un segundo incidente.

---

## 6. Reiniciar GLPI desde cero

Borra solo los datos de GLPI; no toca PostgreSQL ni N8N.

```bash
docker compose stop glpi glpi_db
docker compose rm -f glpi glpi_db
sudo rm -rf volumes/glpi volumes/glpi_db
docker exec nutri_postgres psql -U postgres -d nutrianimales_db -c "TRUNCATE glpi_incidentes;"
docker compose up -d
```

---

## 7. Problemas comunes

| Síntoma | Causa probable | Solución |
|---|---|---|
| `glpi` no arranca y queda esperando | `glpi_db` todavía no está lista | Esperar; `docker compose ps` debe mostrar `glpi_db (healthy)` |
| `https://<IP>:8444` no carga | El stack se levantó sin `docker-compose.glpi.yml` | Revisar `COMPOSE_FILE` en el `.env` y repetir `docker compose up -d` |
| La API responde `ERROR_APP_TOKEN_PARAMETERS_MISSING` o similar | Falta el app_token o la API está desactivada | Revisar el paso 3.5 |
| `ERROR_NOT_ALLOWED_IP` (172.18.0.x) | El cliente API solo acepta 127.0.0.1 | Rango IPv4 `172.18.0.1`–`172.18.255.255` en el cliente API (paso 3.5) |
| `user_token seems invalid` | Token del usuario mal copiado o igual al app_token | Copiar el token del usuario `n8n` después de guardar (paso 3.5) |
| `mkdir: cannot create directory '/var/glpi/config'` | `volumes/glpi` quedó de root | `bash scripts/preparar_entorno.sh` o `sudo chown 33:33 volumes/glpi` y `docker compose up -d glpi` |
| `Permiso denegado` al correr un script | `core.fileMode=false` en el clon | `chmod +x scripts/*.sh scripts/*.py` |
| El script da `Falta HASH_WEBHOOK_TOKEN` | Variable no agregada al `.env` | `bash scripts/preparar_entorno.sh` |
| El script da `no se pudo enviar el hash` | Flujo inactivo o certificado rechazado | Activar el flujo; revisar que `N8N_WEBHOOK_URL` use `nutrianimales.local` |
| Llega el JSON pero no pasa nada | Token distinto entre el script y N8N | Tras cambiar `HASH_WEBHOOK_TOKEN`, `docker compose up -d n8n` |
| Aviso *Found orphan containers* | Normal: Loki y Alloy están en otro archivo | **No** usar `--remove-orphans` |
