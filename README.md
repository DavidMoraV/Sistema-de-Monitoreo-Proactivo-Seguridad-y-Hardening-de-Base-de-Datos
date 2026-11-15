# Sistema de Monitoreo Proactivo, Seguridad y Hardening de Base de Datos

**NutriAnimales S.A.** · Proyecto de Investigación Aplicada · BCD 9220 Seguridad de Sistemas Digitales · Lead University · III Cuatrimestre 2026

Servidor PostgreSQL endurecido, auditado y vigilado en tiempo real: **17 alertas automáticas** llegan a Telegram cuando algo amenaza el rendimiento, la configuración de seguridad o los datos, y un **bot con IA** responde consultas de negocio sin poder modificar nada.

Stack: Docker Compose · PostgreSQL 16 · N8N 2.45.5 · Nginx (HTTPS) · Grafana Loki + Alloy · Telegram · Groq

---

## Contenido

1. [El problema y la solución](#1-el-problema-y-la-solución)
2. [Equipo](#2-equipo)
3. [Arquitectura](#3-arquitectura)
4. [Estado del proyecto](#4-estado-del-proyecto)
5. [Instalación desde cero](#5-instalación-desde-cero)
6. [Verificación rápida](#6-verificación-rápida)
7. [Hardening: los 12 puntos](#7-hardening-los-12-puntos)
8. [Base de datos, roles y auditoría](#8-base-de-datos-roles-y-auditoría)
9. [Las 17 alertas](#9-las-17-alertas)
10. [Bot de Telegram con IA](#10-bot-de-telegram-con-ia)
11. [Pipeline de logs del servidor](#11-pipeline-de-logs-del-servidor)
12. [Ataques simulados A1–A5](#12-ataques-simulados-a1a5)
13. [Gestión de secretos](#13-gestión-de-secretos)
14. [Matriz de riesgos](#14-matriz-de-riesgos)
15. [Demos y evidencias](#15-demos-y-evidencias)
16. [Operación diaria](#16-operación-diaria)
17. [Decisiones técnicas y correcciones al enunciado](#17-decisiones-técnicas-y-correcciones-al-enunciado)
18. [Limitaciones conocidas](#18-limitaciones-conocidas)
19. [Estructura del repositorio](#19-estructura-del-repositorio)
20. [Documentación detallada](#20-documentación-detallada)

---

## 1. El problema y la solución

NutriAnimales S.A. produce y vende alimento balanceado para aves, cerdos, ganado y peces en tres plantas. Su base de datos concentra producción, ventas, clientes y costos. Los riesgos principales son que alguien la exponga a Internet, que un usuario abuse de sus permisos, que se borren o extraigan datos de forma masiva, o que se debilite su configuración sin que nadie lo note.

El sistema responde con **cuatro capas**:

| Capa | Qué hace | Cómo |
|---|---|---|
| **Prevenir** | Reducir la superficie de ataque | 12 puntos de hardening: red aislada, sin puertos de BD, TLS, mínimo privilegio, secretos protegidos, firewall |
| **Registrar** | Que ningún cambio pase sin rastro | Triggers de auditoría con valor antes y después; logs de PostgreSQL y del sistema |
| **Detectar** | Avisar en minutos, no en días | 17 flujos de N8N que revisan cada minuto y alertan a Telegram |
| **Responder** | Corregir rápido y demostrarlo | Procedimientos de respuesta por ataque y rotación de secretos con script |

---

## 2. Equipo

| Rol | Responsable | Aporte principal |
|---|---|---|
| **M1** · Infraestructura / DevOps | David Mora | Stack Docker, red, Nginx HTTPS, hardening 1–12, esquema y RBAC base, secretos y rotación, servidor de integración, demo de infraestructura |
| **M2** · DBA | Jean Rabbat | Ajuste de parámetros vía `ALTER SYSTEM` (H5 demostrable), corrección de R5, respaldos, pgbench, pgBadger, evidencias de BD |
| **M3** · N8N + alertas R y H | Luis Rojas | N8N, bot de Telegram con Groq, subflujo `Enviar_Alerta`, alertas R1–R5 y H3–H5 |
| **M4** · Alertas de datos | Jorge Chaves | Alertas D1–D7 con detección de un solo evento, escenarios y script de demo |
| **M5** · Seguridad ofensiva + host | M5 | Pipeline Alloy + Loki, alertas H1 y H2, firewall, matriz de riesgos, ataques A1–A5, consolidación del informe |

---

## 3. Arquitectura

```
                    Internet / red de administración (192.168.56.0/24)
                                         │
              ┌──────────────────────────┼──────────────────────────────┐
              │ Servidor Ubuntu 24.04    │  UFW: deny entrante,          │
              │                          │  solo SSH desde 192.168.56.0/24│
              │                  :8080 → 301 ─┐                          │
              │                  :8443 (TLS)  ▼                          │
              │  ┌──────────────── nutrianimales-net (bridge, 172.18.0.0/16) ───────────┐
              │  │                                                                       │
              │  │  Nginx ──► N8N (uid 1000) ──► PostgreSQL 16 (sin puertos, TLS 1.3)   │
              │  │  headers      │   19 flujos      ▲  scram-sha-256, auditoría, RBAC    │
              │  │  de seguridad │                  │                                    │
              │  │               ├──► Loki ◄── Alloy ◄── /var/log/auth.log, ufw.log (ro)│
              │  │               │                                                       │
              │  └───────────────┼───────────────────────────────────────────────────────┘
              └──────────────────┼──────────────────────────────────────────────┘
                                 ▼  (salida HTTPS)
                      Telegram (alertas y bot)  ·  Groq (LLM del bot)
```

| Componente | Imagen | Puertos al host | Función |
|---|---|---|---|
| `nutri_nginx` | `nginx:1.27-alpine` | **8080, 8443** (únicos) | Proxy inverso HTTPS con headers de seguridad |
| `nutri_n8n` | `n8nio/n8n:2.45.5` | — | Motor de alertas y bot |
| `nutri_postgres` | `postgres:16` | — | Base de datos endurecida |
| `nutri_loki` | `grafana/loki:3.4.2` | — | Almacén de logs del host |
| `nutri_alloy` | `grafana/alloy:v1.8.2` | — | Agente que envía `auth.log` y `ufw.log` a Loki |

Los tres primeros se definen en `docker-compose.yml`. Loki y Alloy van en `docker-compose.logs.yml`, que se agrega con `-f`.

---

## 4. Estado del proyecto

Checklist de evaluación (sección 13 del enunciado):

| # | Ítem | Estado | Evidencia |
|---|---|---|---|
| 1.1 | 12 puntos de hardening | ✅ | [sección 7](#7-hardening-los-12-puntos), `docs/capturas/HD*` |
| 1.2–1.3 | Stack arriba; PostgreSQL sin puerto expuesto | ✅ | `docker compose ps` |
| 1.4 | `pg_settings_baseline` | ✅ | `HD12_baseline.png` |
| 2.1 | Matriz de 5 riesgos | ✅ | [`docs/M5_MATRIZ_RIESGOS.md`](docs/M5_MATRIZ_RIESGOS.md) |
| 2.2–2.3 | RBAC; gerente sin acceso a la auditoría | ✅ | `C2_2_roles_rbac.png`, `C2_3_gerente_denied.png` |
| 2.4 | Inventario de secretos y rotación | ✅ | [`docs/SECRETOS.md`](docs/SECRETOS.md) |
| 3.1–3.4 | Auditoría y triggers | ✅ | `C3_1` … `C3_4` |
| 4.1 | R1–R5 | ✅ Activas | `R1_alerta.png` … `R5_alerta.png` |
| 4.2 | H1–H5 | ✅ Activas | `H3`–`H5_alerta.png`; H1 y H2 con evidencia pendiente |
| 4.3–4.5 | D1–D7 | ✅ Activas | Capturas pendientes (`demo_m4.sh`) |
| 5.1–5.5 | Ataques A1–A5 | 🟡 Preparados | Ejecución con evidencia pendiente ([guía](docs/M5_GUIA_EJECUCION.md)) |
| 6.1 | Demo de rotación de la API key de Groq | 🟡 Preparada | Credencial con `$env.GROQ_API_KEY` |
| 6.2–6.3 | `.env` con 600 y en `.gitignore` | ✅ | `ls -la .env`, `git check-ignore -v .env` |
| 7.1–7.2 | ZIP y README reproducible | ✅ | Este documento, [sección 5](#5-instalación-desde-cero) |

**Servidor de integración** (15 nov 2026): 5 contenedores arriba, **19 flujos activos** en N8N (17 alertas + `Enviar_Alerta` + bot), baseline 6/6, pipeline de logs operativo y H2 con su referencia guardada.

---

## 5. Instalación desde cero

Tiempo estimado: **10 minutos** (la primera vez descarga ~1.5 GB de imágenes).

### 5.1 Requisitos

| Requisito | Detalle |
|---|---|
| Sistema | **Ubuntu 22.04/24.04** (VM o servidor). Los permisos del hardening no funcionan en carpetas de Windows |
| Usuario | **UID 1000** (`id`) con `sudo` |
| Recursos | 4 GB de RAM, 20 GB de disco |
| Software | Docker Engine + plugin `docker compose`, `git`, `openssl` |
| Logs del host | `rsyslog` activo (`/var/log/auth.log`) y grupo `adm` con GID 4 (`getent group adm`) |
| Cuentas externas | Bot de Telegram (@BotFather), grupo con su `chat_id`, API key de Groq |

### 5.2 Pasos

📍 Todo en la terminal de Ubuntu.

```bash
# 1. Código
git clone https://github.com/DavidMoraV/Sistema-de-Monitoreo-Proactivo-Seguridad-y-Hardening-de-Base-de-Datos.git nutrianimales
cd nutrianimales

# 2. Entorno: .env con contraseñas aleatorias (chmod 600), volúmenes (chmod 700) y certificados TLS
bash scripts/preparar_entorno.sh

# 3. Completar las 3 claves externas (reemplazar __cambiar__, sin espacios ni comillas)
nano .env          # TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID (con el "-" de los grupos), GROQ_API_KEY

# 4. Firewall y logs del host
sudo ufw default deny incoming && sudo ufw default allow outgoing
sudo ufw allow from 192.168.56.0/24 to any port 22 proto tcp comment 'SSH desde red de administracion'
sudo ufw logging medium && sudo ufw --force enable

# 5. Stack completo (base + pipeline de logs)
docker compose -f docker-compose.yml -f docker-compose.logs.yml up -d
docker compose -f docker-compose.yml -f docker-compose.logs.yml ps     # 5 servicios Up, postgres (healthy)

# 6. N8N: 4 credenciales + 19 flujos importados y activados
bash scripts/init_n8n_m3.sh
```

7. Abrir **`https://<IP_DEL_SERVIDOR>:8443`**, aceptar el certificado autofirmado y crear la cuenta dueña de N8N. Guardar esa contraseña en `N8N_PASSWORD` del `.env` (solo como registro: N8N no la lee).
8. En Telegram: @BotFather → `/setprivacy` → *Disable* para el bot, y luego sacarlo y volver a agregarlo al grupo. Con el modo privacidad activo, el bot solo recibe comandos que empiezan con `/`.

**Opcional:** para no escribir `-f` en cada comando, agregar al `.env`:
```
COMPOSE_FILE=docker-compose.yml:docker-compose.logs.yml
```

### 5.3 Qué hace la inicialización automática

Al crear el volumen por primera vez, PostgreSQL ejecuta `sql/` en orden:

| Script | Contenido |
|---|---|
| `00_extensiones.sql` | `pg_stat_statements` |
| `01_esquema.sql` | 12 tablas del enunciado + 2 auxiliares (`pg_settings_snapshot`, `snapshot_tablas`) |
| `02_semilla.sql` | Datos reproducibles: 1,500 clientes, 1,500 ventas, 500 lotes, 300 controles, 200 gastos, 100 materias primas, 50 productos, 3 plantas |
| `03_auditoria.sql` | `auditoria_datos`, `fn_auditoria()` y triggers (después de la semilla, para no auditar la carga inicial) |
| `04_baseline.sql` | Parámetros de seguridad vía `ALTER SYSTEM` + `pg_settings_baseline` + vista `vw_settings_servidor` |
| `05_rbac.sh` | Roles, vistas del gerente y usuarios, con contraseñas leídas del `.env` |
| `06_snapshot_inicial.sql` | Fotos iniciales para R5 y D2 |
| `07_h2_hashes.sql` | Tabla `config_hashes` para H2 (idempotente; también se puede aplicar a una BD existente) |

### 5.4 Reiniciar la base de datos desde cero

```bash
docker compose -f docker-compose.yml -f docker-compose.logs.yml down
sudo rm -rf volumes/pgdata
bash scripts/preparar_entorno.sh
docker compose -f docker-compose.yml -f docker-compose.logs.yml up -d
```
La cuenta y los flujos de N8N se conservan (viven en `volumes/n8n`).

---

## 6. Verificación rápida

```bash
alias psqln='docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db'

psqln -c "SHOW ssl;" -c "SHOW password_encryption;"                  # on · scram-sha-256
psqln -c "SELECT b.name, b.valor_esperado, s.setting FROM pg_settings_baseline b JOIN pg_settings s USING(name);"
docker exec nutri_n8n n8n list:workflow 2>/dev/null | grep -vc license  # 19
psqln -c "SELECT archivo, left(hash,12) FROM config_hashes;"            # 2 filas (H2)
psqln -c "SELECT alerta, severidad, fecha FROM alertas_auditoria ORDER BY id DESC LIMIT 10;"
sudo ufw status verbose                                                # solo 22 desde 192.168.56.0/24
curl -skI https://localhost:8443 | grep -iE "strict|x-frame|x-content|content-security"
```

Prueba de punta a punta (alerta R1):
```bash
psqln -c "SELECT pg_sleep(2);"          # en ≤ 1 min: mensaje en Telegram + fila R1 en alertas_auditoria
```

---

## 7. Hardening: los 12 puntos

| # | Medida | Implementación | Verificación |
|---|---|---|---|
| HD01 | Contenedores sin root | `user: "1000:1000"` en N8N | `docker exec nutri_n8n id` → `uid=1000(node)` |
| HD02 | Secretos en `.env` protegido | `chmod 600`, en `.gitignore`, contraseñas aleatorias con `openssl rand` | `ls -la .env` → `-rw-------` |
| HD03 | Red aislada | Red bridge `nutrianimales-net` con nombre fijo | `docker network inspect nutrianimales-net` |
| HD04 | PostgreSQL sin puerto expuesto | Sin `ports:` en `postgres`; solo Nginx publica | `ss -tln` sin 5432; desde Windows `Test-NetConnection <IP> -Port 5432` → `False` |
| HD05 | scram-sha-256 | `POSTGRES_INITDB_ARGS` + `ALTER SYSTEM` | `SHOW password_encryption;` |
| HD06 | TLS en PostgreSQL | Certificado propio + `ssl=on` vía `ALTER SYSTEM` | `pg_stat_ssl` → TLSv1.3, AES-256-GCM |
| HD07 | `agente_ia` solo lectura | `GRANT SELECT` únicamente | `INSERT` → `permission denied` |
| HD08 | Headers de seguridad | X-Frame-Options DENY, nosniff, HSTS, CSP, `server_tokens off` | `curl -skI https://localhost:8443` |
| HD09 | HTTPS | Certificado autofirmado, TLS 1.2/1.3, HTTP/2, redirección 301 desde 8080 | Navegador con HTTPS |
| HD10 | Volúmenes privados | `chmod 700`, dueño UID del servicio | `ls -ld volumes/*` → `drwx------` |
| HD11 | Registro de consultas lentas | `log_min_duration_statement = 1000` + `pg_stat_statements` | `SELECT pg_sleep(2)` aparece en el log y en `pg_stat_statements` |
| HD12 | Baseline de seguridad | `pg_settings_baseline` con 6 parámetros, vigilada por H5 | `SELECT * FROM pg_settings_baseline;` |

**Medidas adicionales:** firewall UFW con política *deny* (solo SSH desde la red de administración), servicios innecesarios deshabilitados (vsftpd), N8N sin acceso a `POSTGRES_PASSWORD`, imágenes con versión fija y `REVOKE CONNECT ... FROM PUBLIC` en la base.

---

## 8. Base de datos, roles y auditoría

### 8.1 Usuarios y permisos

| Usuario | Rol | Puede | Uso |
|---|---|---|---|
| `postgres` | Superusuario | Todo | Administración |
| `agente_ia` | — | `SELECT` en todas las tablas | Bot de Telegram |
| `monitor_n8n` | `rol_ti` + `pg_monitor` + `pg_read_server_files` | Leer estadísticas, logs y archivos de configuración; escribir snapshots, alertas y `config_hashes` | Los 17 flujos de alerta |
| `gerente_db` | `rol_gerente` | Solo `vw_ventas_resumen` y `vw_produccion_planta` | Reportes |
| `ti_db` | `rol_ti` | Lectura total + `INSERT` en `backups` y `alertas_auditoria` | Administración TI |
| `auditor_db` | `rol_auditor` | `auditoria_datos`, `backups`, `alertas_auditoria` + `pg_read_all_stats` | Auditoría |

### 8.2 Auditoría

- Tabla `auditoria_datos`: tabla, operación, usuario, fecha, IP del cliente, id de fila, **valor antes** y **valor después** en JSONB.
- `fn_auditoria()` es `SECURITY DEFINER` y registra `session_user`. Así audita los cambios de cualquier rol sin darle acceso a la tabla de auditoría.
- Triggers `AFTER INSERT OR UPDATE OR DELETE` en las 4 tablas críticas: `lotes_produccion`, `ventas`, `clientes` y `productos`.
- El bot registra ahí cada intento de inyección bloqueado (operación `BLOQUEO`).

### 8.3 Rendimiento (M2)

pgbench con 15 clientes durante 120 s: **2,531 transacciones/s**, latencia media **5.89 ms**, 0 fallos. Reporte completo en [`docs/pgbadger/reporte.html`](docs/pgbadger/reporte.html) y [`docs/pgbench_resultado.txt`](docs/pgbench_resultado.txt).

---

## 9. Las 17 alertas

Cada flujo se ejecuta **cada minuto** con el usuario `monitor_n8n` y termina en el subflujo común **`Enviar_Alerta`**, que envía el mensaje con el formato oficial a Telegram y lo registra en `alertas_auditoria`. Además descarta la misma alerta si ya se envió en los últimos 10 minutos.

### Rendimiento (M3)

| Código | Detecta | Condición | Fuente |
|---|---|---|---|
| R1 | Consulta lenta | > 1 s | Log de PostgreSQL |
| R2 | Exceso de conexiones | > 10 conexiones de cliente | `pg_stat_activity` |
| R3 | Conexión fuera de horario | Entre 23:00 y 06:00 | `pg_stat_activity` |
| R4 | Autenticaciones fallidas | > 5 en 10 min | Log de PostgreSQL + `auth.log` vía Loki |
| R5 | Cambio de parámetros | Cualquier cambio | `vw_settings_servidor` vs. `pg_settings_snapshot` |

### Hardening (M3 y M5)

| Código | Detecta | Condición | Fuente |
|---|---|---|---|
| H1 | Cambio en reglas del firewall | `sudo ufw allow/insert/disable/reset` → CRÍTICA; `delete/deny` → ADVERTENCIA | `auth.log` vía Loki |
| H2 | Integridad de configuración | Cambia el hash de `pg_hba.conf` o `postgresql.conf` | `md5(pg_read_file())` vs. `config_hashes` |
| H3 | Escalada de privilegios | `agente_ia` con INSERT, UPDATE, DELETE o TRUNCATE | `has_table_privilege()` |
| H4 | Conexión externa | IP fuera de 172.16.0.0/12 | `pg_stat_activity` |
| H5 | Desvío del baseline | Un parámetro difiere de `pg_settings_baseline` | `pg_settings` |

### Datos (M4)

| Código | Detecta | Umbral | Severidad |
|---|---|---|---|
| D1 | `DELETE` sin `WHERE` | > 100 filas por ejecución | CRÍTICA |
| D2 | Crecimiento anormal de una tabla | > 20 % en 30 min | ADVERTENCIA |
| D3 | Sin respaldo exitoso | > 24 h | CRÍTICA |
| D4 | Duplicados en tablas críticas | > 5 | ADVERTENCIA |
| D5 | Transacción bloqueada | > 30 s | ADVERTENCIA |
| D6 | `UPDATE` sin `WHERE` | > 50 filas por ejecución | CRÍTICA |
| D7 | Posible exfiltración (`clientes`/`ventas`) | > 1,000 filas por consulta | CRÍTICA |

**Una alerta por evento:** D1, D6 y D7 usan `rows / calls` y reinician la entrada de `pg_stat_statements` por `queryid` al detectar; D2 reinicia su ventana; D3–D5 marcan el evento en `alertas_auditoria`; R5 y H2 actualizan su referencia tras alertar. Sin esto, la misma condición alertaría cada minuto.

Cada alerta tiene su escenario en `sql/pruebas/<código>.sql`, con tres secciones: emulación, detección y limpieza.

---

## 10. Bot de Telegram con IA

Flujo: mensaje en el grupo → **filtro de entrada** → Groq (`openai/gpt-oss-120b`) genera SQL → **validación del SQL** → ejecución con **`agente_ia`** → Groq redacta la respuesta.

| Barrera | Qué bloquea |
|---|---|
| 1. Filtro de entrada | `;`, `--`, `/*`, `DROP`, `DELETE`, `UPDATE`, `INSERT`, `ALTER`, `GRANT`, `UNION`… El intento se registra en `auditoria_datos` |
| 2. Validación del SQL generado | Solo una sentencia `SELECT`/`WITH`, sin palabras de escritura, con `LIMIT 50` forzado |
| 3. Usuario de solo lectura | Aunque las dos anteriores fallaran, `agente_ia` no puede escribir |

El bot funciona por **sondeo** (`getUpdates` cada 10 s), no por webhook: Telegram no acepta el certificado autofirmado y el servidor no es público. Solo atiende el chat configurado en `TELEGRAM_CHAT_ID`.

---

## 11. Pipeline de logs del servidor

```
/var/log/auth.log ─┐                                    ┌─► H1 (cambios de UFW)
                   ├─► Alloy (solo lectura) ─► Loki ─► N8N ┤
/var/log/ufw.log  ─┘     job="auth" / "ufw"              └─► R4 (SSH fallido, A1)
```

- **Alloy en lugar de Filebeat:** Filebeat no tiene salida nativa hacia Loki (requeriría Logstash). Alloy es el agente oficial de Loki.
- Se lee `auth.log` además de `ufw.log` porque los **cambios de reglas** UFW quedan en la línea de `sudo` de `auth.log`; `ufw.log` solo registra tráfico.
- `tail_from_end`: al arrancar se leen solo líneas nuevas, para no alertar con el historial.
- Ni Loki ni Alloy publican puertos.

Prueba del pipeline:
```bash
logger -p auth.info "prueba pipeline"; sleep 15
docker compose exec -T n8n wget -qO- 'http://loki:3100/loki/api/v1/query_range?query=%7Bjob%3D%22auth%22%7D&since=2m&limit=3'
```

---

## 12. Ataques simulados A1–A5

| Ataque | Simulación | Detecta | Respuesta |
|---|---|---|---|
| **A1** Fuerza bruta SSH | 20 intentos fallidos (`scripts/a1_fuerza_bruta_ssh.sh`) | R4 | `sudo ufw deny from <IP_ORIGEN>` |
| **A2** Inyección SQL vía bot | `Lista datos; DROP TABLE clientes; --` | Filtro anti-SQLi (bloqueo, sin alerta) | Rechazo; `clientes` intacta; registro `BLOQUEO` |
| **A3** Apertura del puerto 5432 | `sudo ufw allow 5432/tcp` (`scripts/a3_apertura_puerto_5432.sh`) | H1 | `sudo ufw delete allow 5432/tcp` |
| **A4** Escalada de privilegios | `GRANT INSERT ON ALL TABLES IN SCHEMA public TO agente_ia` | H3 | `REVOKE` + verificación |
| **A5** Exfiltración | `SELECT * FROM clientes` como `agente_ia` | D7 | `bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD` + actualizar la credencial en N8N |

Cada ataque se documenta con cuatro evidencias: comando, alerta en Telegram con hora, registro en la base y acción de respuesta. Procedimiento completo en [`docs/M5_GUIA_EJECUCION.md`](docs/M5_GUIA_EJECUCION.md).

**Defensa en profundidad en A3:** aunque UFW permita el 5432, el puerto sigue cerrado desde fuera, porque `postgres` no publica puertos (HD04). La alerta H1 detecta la intención, y la arquitectura impide el daño.

---

## 13. Gestión de secretos

Inventario completo, procedimientos y calendario en [`docs/SECRETOS.md`](docs/SECRETOS.md).

- **10 secretos** inventariados: contraseñas de PostgreSQL (5 usuarios + superusuario), token de Telegram, key de Groq, contraseña y llave de cifrado de N8N, llaves TLS.
- Todos viven solo en el `.env` del servidor (600, fuera de Git). El repositorio tiene `.env.example` con valores de relleno.
- N8N guarda las credenciales cifradas; la de Groq lee `$env.GROQ_API_KEY`, para que la rotación sea editar el `.env` y recrear el contenedor.
- **Rotación de contraseñas de BD** sin mostrarlas en pantalla: `bash scripts/rotar_password_bd.sh <usuario> <VARIABLE>`.
- **Demo obligatoria 6.1:** borrar la key en Groq → el bot falla → key nueva → `.env` → `docker compose up -d --force-recreate n8n` → el bot responde.

Verificación:
```bash
git check-ignore -v .env                                                    # .gitignore:2:.env
git log --all --oneline -- .env | wc -l                                     # 0
git log -p --all | grep -cE "gsk_[A-Za-z0-9]{20,}|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}"   # 0
```

---

## 14. Matriz de riesgos

Riesgo = Probabilidad × Impacto (1–5). Detalle y riesgo residual en [`docs/M5_MATRIZ_RIESGOS.md`](docs/M5_MATRIZ_RIESGOS.md).

| ID | Riesgo | P×I | Nivel | Mitigación | Detección | Ataque |
|---|---|---:|---|---|---|---|
| RSK-01 | Fuerza bruta sobre SSH | 16 | Alto | UFW, SSH solo desde la red de administración | R4 | A1 |
| RSK-02 | Exposición del puerto 5432 | 15 | Alto | HD03, HD04, HD06, HD12 | H1, H2, H4 | A3 |
| RSK-03 | Exfiltración de datos | 15 | Alto | HD07, RBAC | D7 | A5 |
| RSK-04 | Escalada de privilegios | 10 | Alto | HD07, mínimo privilegio, auditoría | H3 | A4 |
| RSK-05 | Inyección SQL vía bot | 20 | Crítico | 3 barreras del bot | Registro `BLOQUEO` | A2 |

---

## 15. Demos y evidencias

| Script | Responsable | Qué muestra |
|---|---|---|
| `bash scripts/demo_m1.sh` | M1 | 9 pasos con Enter: arquitectura, red, mínimo privilegio, HTTPS, TLS, baseline, RBAC, triggers y rotación de un secreto. Material: [`docs/Demo_M1_NutriAnimales_David.pdf`](docs/Demo_M1_NutriAnimales_David.pdf) |
| `./scripts/evidencias_m2.sh <código>` | M2 | Cada evidencia de BD con su hora (`HD05`, `2.3`, `3.4`…) |
| `docs/ENTREGA_M3.md` §7 | M3 | Pregunta al bot + `ALTER SYSTEM` → H5 y R5 |
| `./scripts/demo_m4.sh D1…D7 [limpiar]` | M4 | Emula cada alerta de datos y deja todo como estaba |
| `docs/M5_GUIA_EJECUCION.md` | M5 | H1, H2 y ataques A1–A5 |

Capturas en `docs/capturas/` con el formato `<código>_<descripción>.png`, mostrando la **hora** en las alertas.

---

## 16. Operación diaria

| Tarea | Comando |
|---|---|
| Estado del stack | `docker compose -f docker-compose.yml -f docker-compose.logs.yml ps` |
| Últimas alertas | `psqln -c "SELECT alerta, severidad, fecha FROM alertas_auditoria ORDER BY id DESC LIMIT 10;"` |
| Respaldo (registra en `backups`, evita D3) | `./scripts/backup.sh` |
| Rotar una contraseña de BD | `bash scripts/rotar_password_bd.sh <usuario> <VARIABLE>` |
| Recargar flujos tras cambiarlos | `bash scripts/init_n8n_m3.sh` |
| Prueba de rendimiento | `./scripts/rendimiento.sh` |
| Ejecuciones de N8N | `https://<IP>:8443` → Overview → Executions |
| Logs de un servicio | `docker compose logs <servicio> --tail 50` |
| Empaquetar la entrega | `git archive --format=zip --prefix=nutrianimales/ -o NutriAnimales_BCD9220.zip HEAD` |

El ZIP se arma con `git archive`, así que **nunca** incluye `.env`, `volumes/` ni llaves: no están versionados.

---

## 17. Decisiones técnicas y correcciones al enunciado

| # | Tema | Decisión | Motivo |
|---|---|---|---|
| 1 | Query D7 | Paréntesis en el filtro de tablas y `pg_roles.rolname` | El original aplicaba el umbral solo a `ventas`, y `usename` no existe en `pg_roles` |
| 2 | Ataque A4 | `GRANT ... ON ALL TABLES IN SCHEMA public` | La sintaxis del enunciado es inválida |
| 3 | `rol_gerente` | Solo vistas de reportes | El SQL del enunciado daba acceso directo a tablas |
| 4 | `rol_auditor` | `+ pg_read_all_stats` | Sin eso no puede leer `pg_stat_statements` ni `pg_stat_activity` |
| 5 | Volumen de datos | 1,500 clientes y ventas | Con los mínimos (200) nunca se supera el umbral de D7 (> 1,000) |
| 6 | `pg_stat_statements` | `rows / calls` + reset por `queryid` | Es acumulativo: sin esto, D1, D6 y D7 alertarían en cada ciclo |
| 7 | Parámetros de seguridad | `ALTER SYSTEM` en lugar de `-c` en el compose | Un `-c` tiene prioridad y la prueba de H5 nunca habría funcionado |
| 8 | `fn_auditoria()` | `SECURITY DEFINER` + `session_user` | Auditar cambios de cualquier rol sin darle acceso a la auditoría |
| 9 | Filebeat | Grafana Alloy | Filebeat no envía directo a Loki |
| 10 | H1 | Leer `auth.log`, no solo `ufw.log` | Los cambios de reglas no aparecen en `ufw.log` |
| 11 | Bot | Sondeo `getUpdates` | El webhook exige un certificado válido y una URL pública |
| 12 | Rotación de Groq | Credencial con `$env.GROQ_API_KEY` | Si la key quedara fija en la credencial, editar el `.env` no tendría efecto |
| 13 | R5 | Comparar contra `vw_settings_servidor` | `pg_settings` incluye valores de sesión que saltaban al conectarse N8N |
| 14 | Contraseñas | Generadas y leídas del `.env` | El enunciado las escribía en el SQL |
| 15 | Rotación de BD | `ALTER USER` siempre | El `.env` solo se lee al crear la base; editarlo no cambia la contraseña real |
| 16 | Mensajes de Telegram | HTML con escape | En Markdown, un `_` suelto hace que Telegram rechace el mensaje |
| 17 | Modelo de Groq | `openai/gpt-oss-120b` | Groq retiró `llama-3.3-70b-versatile` en agosto de 2026 |

---

## 18. Limitaciones conocidas

- **Docker y UFW:** Docker publica 8080/8443 escribiendo directamente en iptables, antes de UFW. La protección del 5432 no depende de UFW sino de que el contenedor no publique el puerto (HD04).
- **Certificados autofirmados:** el navegador muestra una advertencia la primera vez. En producción se usaría Let's Encrypt con un dominio público.
- **Sockets locales en *trust*:** la imagen oficial de PostgreSQL permite conexiones locales dentro del contenedor sin contraseña. Por red se exige scram-sha-256.
- **H1** solo ve comandos ejecutados con `sudo` directo; un `sudo -i` o `sudo bash` registra el shell, no cada comando.
- **Filtro anti-SQLi** de entrada: puede bloquear mensajes legítimos que contengan `;` o palabras como "update". Por eso existen las otras dos barreras.
- **Rotar `agente_ia` o `monitor_n8n`** exige actualizar también su credencial en N8N (o volver a correr `init_n8n_m3.sh`).
- **`init_n8n_m3.sh`** pasa las contraseñas a `docker exec -e`, visibles en la lista de procesos durante un segundo. Aceptable en un servidor de un solo administrador.

---

## 19. Estructura del repositorio

```
├── docker-compose.yml          postgres, n8n, nginx (red nutrianimales-net)
├── docker-compose.logs.yml     loki, alloy (pipeline de logs)
├── .env.example                plantilla sin secretos
├── sql/
│   ├── 00 … 07                 inicialización de la base (orden de ejecución)
│   └── pruebas/                escenarios de R1–R5, H2–H5, D1–D7, A2, A4, A5
├── n8n/flujos/                 19 flujos: Enviar_Alerta, bot, R1–R5, H1–H5, D1–D7
├── nginx/nginx.conf            HTTPS + headers de seguridad
├── logs/                       configuración de Alloy y Loki
├── scripts/
│   ├── preparar_entorno.sh     .env, volúmenes y certificados
│   ├── init_n8n_m3.sh          credenciales y los 19 flujos
│   ├── init_n8n_m5.sh          solo H1 y H2
│   ├── rotar_password_bd.sh    rotación de contraseñas de BD
│   ├── backup.sh · rendimiento.sh · configurar_ufw.sh
│   ├── demo_m1.sh · evidencias_m2.sh · demo_m4.sh
│   └── a1_fuerza_bruta_ssh.sh · a3_apertura_puerto_5432.sh
├── docs/                       entregas, informes, secretos, matriz, guía, PDF de demo, capturas
├── certs/postgres/ · nginx/certs/   certificados (se generan, no se versionan)
└── backups/                    respaldos (no se versionan)
```

---

## 20. Documentación detallada

| Documento | Contenido |
|---|---|
| [`docs/ENTREGA_M1.md`](docs/ENTREGA_M1.md) | Infraestructura, hardening y traspaso al grupo |
| [`docs/ENTREGA_M2.md`](docs/ENTREGA_M2.md) | Base de datos, correcciones de H5 y R5, rendimiento |
| [`docs/ENTREGA_M3.md`](docs/ENTREGA_M3.md) · [`INFORME_M3.md`](docs/INFORME_M3.md) | N8N, bot, `Enviar_Alerta`, R y H |
| [`docs/ENTREGA_M4.md`](docs/ENTREGA_M4.md) · [`INFORME_M4.md`](docs/INFORME_M4.md) | Alertas D1–D7 y su lógica de un evento |
| [`docs/INFORME_M5.md`](docs/INFORME_M5.md) · [`M5_GUIA_EJECUCION.md`](docs/M5_GUIA_EJECUCION.md) | Host, logs, H1, H2 y ataques |
| [`docs/M5_MATRIZ_RIESGOS.md`](docs/M5_MATRIZ_RIESGOS.md) | Matriz de riesgos y riesgo residual |
| [`docs/SECRETOS.md`](docs/SECRETOS.md) | Inventario de secretos y política de rotación |
| [`docs/Demo_M1_NutriAnimales_David.pdf`](docs/Demo_M1_NutriAnimales_David.pdf) | Guía visual de la demo de infraestructura |
