# Gestión de Secretos y Política de Rotación

**NutriAnimales S.A.** · Sección 9 del informe · Checklist 2.4 · Responsable: M1

Todos los secretos viven en un único archivo `.env` en el servidor, con permisos `600` (solo el dueño lee/escribe), excluido de Git por `.gitignore`. El repositorio solo contiene `.env.example`, con valores de relleno (`__cambiar__`). Las contraseñas se generan aleatoriamente con `openssl rand` al preparar el entorno (`scripts/preparar_entorno.sh`); ningún integrante las elige ni las comparte.

---

## 9.1 Inventario de secretos

| # | Secreto | Dónde vive | Quién lo usa | Rotación | Impacto si se filtra |
|---|---|---|---|---|---|
| 1 | `GROQ_API_KEY` | `.env` → variable de entorno de N8N → credencial que la lee con `$env` | Bot conversacional | 90 días o inmediata si se filtra | Consumo de la cuota de Groq a nombre de la empresa |
| 2 | `TELEGRAM_BOT_TOKEN` | `.env` → credencial Telegram de N8N | Envío de las 17 alertas y bot | Inmediata si se compromete | Un atacante lee o envía mensajes como el bot (alertas falsas) |
| 3 | `TELEGRAM_CHAT_ID` | `.env` | Destino de las alertas | No es secreto crítico; cambia si cambia el grupo | Bajo: solo identifica el grupo |
| 4 | `POSTGRES_PASSWORD` | `.env` + catálogo de PostgreSQL | Administración (superusuario) | 180 días | **Crítico:** control total de la BD |
| 5 | `AGENTE_IA_PASSWORD` | `.env` + catálogo de PostgreSQL + credencial Postgres de N8N | Bot (solo lectura) | 180 días | Lectura de todos los datos (exfiltración, ver A5) |
| 6 | `MONITOR_N8N_PASSWORD` | `.env` + catálogo de PostgreSQL + credencial Postgres de N8N | Flujos de alertas | 180 días | Lectura de estadísticas, logs y `pg_hba.conf` |
| 7 | `GERENTE_DB_PASSWORD` · `TI_DB_PASSWORD` · `AUDITOR_DB_PASSWORD` | `.env` + catálogo de PostgreSQL | Usuarios humanos por rol | 90 días | Acceso según el rol (RBAC limita el daño) |
| 8 | `N8N_PASSWORD` | Base interna de N8N (`volumes/n8n`); copia de registro en `.env` | Cuenta dueña del editor N8N | 90 días | Modificar o desactivar flujos de alertas |
| 9 | `N8N_ENCRYPTION_KEY` | `.env` → N8N | Cifra las credenciales guardadas en N8N | No se rota (rotarla invalida todas las credenciales) | **Crítico:** descifrar todas las credenciales de N8N si además se roba `volumes/n8n` |
| 10 | Llaves privadas TLS (`nginx.key`, `server.key`) | `nginx/certs/`, `certs/postgres/` (permisos `600`, fuera de Git) | Nginx y PostgreSQL | 365 días (vencimiento del certificado) | Suplantar el servidor / descifrar tráfico capturado |

---

## 9.2 Procedimientos de revocación y rotación

> **Corrección al enunciado:** `POSTGRES_PASSWORD` y las contraseñas de usuarios solo se leen del `.env` **la primera vez** que se crea la BD. Editar el `.env` y reiniciar **no cambia** la contraseña real: siempre hay que ejecutar `ALTER USER` primero. Además, N8N guarda su propia copia de la contraseña dentro de sus credenciales, que también hay que actualizar.

### A. Contraseñas de PostgreSQL (#4–#7)

Script automatizado (genera una contraseña nueva, la aplica en PostgreSQL y la actualiza en el `.env`):

```bash
bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD
```

Equivalente manual:

```bash
NUEVA=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db \
  -c "ALTER USER agente_ia WITH PASSWORD '$NUEVA';"
sed -i "s|^AGENTE_IA_PASSWORD=.*|AGENTE_IA_PASSWORD=$NUEVA|" .env
```

Después, solo para `agente_ia` y `monitor_n8n`: **N8N → Credentials → (credencial Postgres) → actualizar contraseña → Save**, y ejecutar un flujo de prueba.

### B. `GROQ_API_KEY` (#1) — demostración obligatoria en la exposición

| Paso | Acción | Evidencia |
|---|---|---|
| 1 | El bot responde una pregunta con la key actual | Captura de Telegram |
| 2 | Simular filtración: console.groq.com → API Keys → **Delete** | Captura de la consola |
| 3 | El siguiente mensaje al bot falla: N8N registra error `401` | Captura de *Executions* en N8N |
| 4 | Crear key nueva en console.groq.com | Captura (key tapada) |
| 5 | `nano .env` → `GROQ_API_KEY=<nueva>` | Captura de `ls -la .env` (no del contenido) |
| 6 | `docker compose restart n8n` (la BD sigue arriba) | Captura del comando |
| 7 | El bot vuelve a responder | Captura de Telegram |

Requisito técnico: la credencial de Groq en N8N debe usar la expresión `Bearer {{ $env.GROQ_API_KEY }}`. Si la key se pega directamente en la credencial, el paso 6 no tendría efecto.

### C. `TELEGRAM_BOT_TOKEN` (#2)

1. Telegram → @BotFather → `/revoke` → elegir el bot → nuevo token.
2. Actualizar `TELEGRAM_BOT_TOKEN` en `.env` **y** en la credencial Telegram de N8N.
3. `docker compose restart n8n` → disparar una alerta de prueba.

### D. `N8N_PASSWORD` (#8)

> **Corrección al enunciado:** N8N 2.x no lee esta variable; la contraseña se cambia desde la interfaz.

1. N8N → *Settings → Personal → Change password*.
2. Actualizar la copia en `.env` (registro para el equipo).

### E. Llaves TLS (#10)

```bash
rm nginx/certs/nginx.*              # o certs/postgres/server.* para PostgreSQL
bash scripts/preparar_entorno.sh    # genera certificados nuevos
docker compose restart nginx        # o postgres
```

---

## 9.3 Reglas de seguridad y cómo se verifican

| Regla | Cómo se cumple | Verificación |
|---|---|---|
| El `.env` nunca se sube a Git | En `.gitignore`; nunca se hizo `git add` | `git check-ignore -v .env` y `git log --all --oneline -- .env` (vacío) |
| Permisos mínimos sobre el `.env` | `chmod 600` automático en `preparar_entorno.sh` | `ls -la .env` → `-rw-------` |
| Ningún secreto en el historial | Contraseñas generadas, no escritas en SQL ni en el compose | `git log -p --all \| grep -cE "gsk_[A-Za-z0-9]{20,}\|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}"` → `0` |
| N8N sin keys visibles en nodos | Todas las claves en *Credentials* o `$env` | Revisar los JSON exportados: `grep -rcE "gsk_[A-Za-z0-9]{20,}\|[0-9]{8,10}:AA[A-Za-z0-9_-]{30,}" n8n/flujos/` → `0` |
| Logs de N8N sin variables de entorno | `N8N_LOG_LEVEL=info`; no se registran variables | `docker logs nutri_n8n 2>&1 \| grep -cE "gsk_[A-Za-z0-9]{20,}"` → `0` |
| Mínimo privilegio en contenedores | N8N solo recibe los secretos que usa; **no** recibe `POSTGRES_PASSWORD` | `docker exec nutri_n8n env \| grep -c POSTGRES_PASSWORD` → `0` |
| Secreto filtrado = revocación inmediata | Aunque el commit se revierta, la key ya es pública | Procedimientos A–E |
| `.env.example` sin credenciales reales | Solo `__cambiar__` | `grep -v "__cambiar__" .env.example \| grep -E "PASSWORD\|KEY\|TOKEN"` (vacío) |

---

## Calendario de rotación

| Frecuencia | Secretos |
|---|---|
| Inmediata ante sospecha | Todos |
| 90 días | `GROQ_API_KEY`, `N8N_PASSWORD`, usuarios humanos (#7) |
| 180 días | `POSTGRES_PASSWORD`, `AGENTE_IA_PASSWORD`, `MONITOR_N8N_PASSWORD` |
| 365 días | Certificados TLS |
| Nunca (salvo compromiso total) | `N8N_ENCRYPTION_KEY` |
