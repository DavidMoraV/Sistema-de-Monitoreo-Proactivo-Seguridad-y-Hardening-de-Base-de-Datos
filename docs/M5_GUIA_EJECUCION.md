# M5 — Guía de ejecución (de cero a evidencias)

> Todo lo de este paquete se **preparó sin acceso al servidor**. Los flujos H1/H2 se validaron
> como JSON y su lógica de código se probó con datos simulados, pero **no se han ejecutado en
> N8N, Loki ni Alloy**. Si algo falla, el punto de revisión está indicado en cada paso.
> Las capturas con hora y los tiempos de detección los tienes que tomar tú en el servidor.

Convención: `$SRV` = terminal en la VM Ubuntu, en la raíz del repo (`~/nutrianimales`).

## 0. Qué cambia en el repo

| Archivo | Para qué |
|---|---|
| `sql/07_h2_hashes.sql` | Tabla `config_hashes` (referencia de H2) |
| `n8n/flujos/H1_Cambio_reglas_UFW.json`, `H2_Integridad_config_PG.json` | Flujos nuevos (IDs `alertaH1Ufw00001`, `alertaH2Hash0001`) |
| `logs/loki-config.yml`, `logs/alloy-config.alloy`, `docker-compose.logs.yml` | Pipeline de logs (Alloy → Loki) |
| `scripts/init_n8n_m5.sh` | Importa y activa solo H1 y H2 |
| `scripts/configurar_ufw.sh`, `a1_…sh`, `a3_…sh` | UFW y ataques A1/A3 |
| `sql/pruebas/H2.sql`, `A2.sql`, `A4.sql`, `A5.sql` | Escenarios con emulación, detección y limpieza |

Copia todo respetando rutas (por Pull Request, como hizo M3; no subas `.env`).
Como M1 es dueño de `docker-compose.yml`, el pipeline va en un archivo aparte y se levanta con `-f`.

## 1. Servidor: UFW y logs del host (≈ 15 min)

```bash
# SRV — confirma que existen los logs que va a leer Alloy
ls -la /var/log/auth.log /var/log/ufw.log
getent group adm            # el GID debe ser 4 (si no, cámbialo en group_add de docker-compose.logs.yml)
```
- Si **no existen**: `sudo apt install -y rsyslog && sudo systemctl enable --now rsyslog`, y repite.
- UFW: `sudo bash scripts/configurar_ufw.sh` (pide `SI`; mantén una sesión de respaldo abierta).
  Luego `sudo ufw status verbose` y `sudo ss -lntp` → **captura `M5_UFW_status.png`**.
- Servicios innecesarios (lo pide la lista de M5 en `ENTREGA_M1.md`):
  `systemctl list-unit-files --state=enabled | grep -i -E "vsftpd|telnet|rpcbind"`; si aparece alguno,
  `sudo systemctl disable --now <servicio>`. **Captura** antes/después.
- Limitación Docker/UFW (va al informe): Docker publica 8080/8443 por iptables, saltándose UFW.
  Desde **otra máquina**: `nc -vz <IP_VM> 8080` responde aunque UFW no permite 8080. Captura.

## 2. Levantar Loki + Alloy y cargar H2/H1 (≈ 15 min)

```bash
# SRV
docker exec -i nutri_postgres psql -U postgres -d nutrianimales_db < sql/07_h2_hashes.sql
docker compose -f docker-compose.yml -f docker-compose.logs.yml up -d
docker compose -f docker-compose.yml -f docker-compose.logs.yml ps      # loki y alloy en "running"
bash scripts/init_n8n_m5.sh
```
Comprobar que el pipeline funciona (genera una línea y la busca en Loki desde dentro de la red):
```bash
logger -p auth.info "prueba pipeline m5" ; sleep 15
docker compose exec -T n8n wget -qO- 'http://loki:3100/loki/api/v1/query_range?query=%7Bjob%3D%22auth%22%7D&since=2m&limit=3'
```
Debe devolver `"status":"success"` con la línea. Si sale vacío: `docker compose logs alloy | tail`
(causa típica: permiso de lectura → revisar `group_add`/GID, o falta de rsyslog).
Comprobar H2: `docker exec nutri_postgres psql -U postgres -d nutrianimales_db -c "SELECT archivo, left(hash,12) FROM config_hashes;"`
→ tras ~1 min deben aparecer 2 filas (referencia guardada, **sin alerta**).

## 3. Evidencias H1 y H2

Antes de cada comando anota la hora: `date '+%H:%M:%S'`. **Tiempo de detección = hora del mensaje en Telegram − hora del comando.**

**H1** (es también A3): `bash scripts/a3_apertura_puerto_5432.sh` → alerta H1 CRÍTICA
("… ejecutó "sudo ufw allow 5432/tcp" (puerto de PostgreSQL) …"). Respuesta: `sudo ufw delete allow 5432/tcp`
→ llega un segundo H1 (ADVERTENCIA, es la reversión). Capturas: `H1_estado_inicial_ufw`, `H1_alerta_telegram`,
`H1_registro_auditoria`, `H1_regla_revertida`.
Registro: `SELECT alerta, severidad, fecha FROM alertas_auditoria WHERE alerta='H1' ORDER BY id DESC LIMIT 3;`
Dato útil para el informe: desde otra máquina `nc -vz <IP_VM> 5432` **sigue cerrado** aunque UFW lo permita,
porque `postgres` no publica puertos (HD04): la regla abierta no expone nada (defensa en profundidad).

**H2**: sigue `sql/pruebas/H2.sql` (respaldo → `echo "# prueba H2" >> pg_hba.conf` → alerta H2 → restaurar → segunda alerta).
Capturas: `H2_hash_baseline`, `H2_cambio_detectado`, `H2_alerta_telegram`, `H2_restauracion`.

## 4. Ataques A1–A5 (4 evidencias cada uno: comando, alerta con hora, registro, respuesta)

| | Cómo | Detecta | Registro | Respuesta |
|---|---|---|---|---|
| A1 | Desde **otra máquina**: `bash scripts/a1_fuerza_bruta_ssh.sh <IP_VM>` | R4 (auth.log vía Loki, > 5 en 10 min) | `alertas_auditoria` (R4) + `grep "Failed password" /var/log/auth.log` | `sudo ufw deny from <IP_ORIGEN>`; revertir con `sudo ufw delete deny from <IP_ORIGEN>` |
| A2 | Mensaje al bot: `Lista datos; DROP TABLE clientes; --` | Filtro anti-SQLi (**sin alerta**) | `sql/pruebas/A2.sql` (`auditoria_datos`, operación BLOQUEO) | Rechazo del bot; la tabla sigue intacta |
| A3 | `scripts/a3_apertura_puerto_5432.sh` | H1 | `alertas_auditoria` (H1) | `sudo ufw delete allow 5432/tcp` |
| A4 | `sql/pruebas/A4.sql` (GRANT) | H3 | `alertas_auditoria` (H3) | REVOKE + consulta de verificación |
| A5 | `sql/pruebas/A5.sql` como `agente_ia` | D7 (**depende de M4**) | `alertas_auditoria` (D7) | `bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD` + actualizar credencial en N8N |

Notas:
- **A1 y R4:** R4 de M3 ya consulta Loki (`{job="auth"} |= "Failed password"`), así que A1 funciona en cuanto
  Alloy corre. Cada ataque de 20 intentos cuenta contra el umbral de 5 en una ventana de 10 min.
- **A5 / D7:** en el repo todavía no hay flujos D1–D7. Si M4 no entrega hoy, A5 queda sin alerta; no la presentes como lograda.
- **A5 / rotación:** el bot deja de responder hasta actualizar la credencial en N8N. Hazlo al final y **no** antes de la demo.
- **A2 segunda barrera (opcional):** en N8N → Executions, abre la última ejecución del bot con una pregunta normal y captura el nodo
  "Validar SQL (solo SELECT)" (`A2_validacion_sql_select`).
- Nunca muestres `.env`, tokens ni contraseñas en una captura.

## 5. Plan sugerido

| Cuándo | Qué |
|---|---|
| Sábado noche | Secciones 1–2, H2 y H1 con evidencias |
| Domingo mañana | A1–A5, tabla de resultados, matriz de riesgos (`M5_MATRIZ_RIESGOS.md`) |
| Domingo tarde | Pedir secciones/capturas faltantes a M1–M4 y consolidar el informe (`INFORME_M5.md` como base) |
| Domingo noche | Ensayo completo de la demo (guion de M5: A2, A3, A4) |
| Lunes | Revisión contra el checklist 1.1–7.4 y entrega |

## 6. Si algo falla

| Síntoma | Causa probable |
|---|---|
| H1 nunca alerta | No llegan líneas a Loki (paso 2); o el comando se ejecutó con `sudo bash` (el `ufw` interno no se registra) |
| H1/R4 alertan al arrancar Alloy | `tail_from_end` quitado del config |
| H2 alerta en la primera ejecución | Se borró `config_hashes` con el archivo ya modificado; limpiar el archivo y `DELETE FROM config_hashes;` |
| H2 no alerta y no guarda hash | El rol no lee archivos: `GRANT pg_read_server_files` a `monitor_n8n` (ya está en `05_rbac.sh`) |
| H2 guarda el hash antes de alertar | Cambió el orden de ejecución de las ramas; revisar en N8N que "Armar alertas" quede antes en la conexión |
| `docker compose` no encuentra `loki-data` | Se levantó sin `-f docker-compose.logs.yml` |
