# Entrega de M3 (N8N + bot + alertas R y H) al grupo

**Fecha:** 12 de noviembre de 2026 · **Responsable:** Luis Rojas (M3)

N8N, el bot de Telegram con Groq, el subflujo `Enviar_Alerta` y las alertas R1–R5 y H3–H5 están listos. Los flujos se probaron en **n8n 2.45.5** (la versión del compose) contra una base creada con `sql/00`–`06` de este repo: SSL activo, RBAC de M2 y 1,500 clientes.

---

## 1. Qué está terminado

| Bloque | Detalle | Checklist |
|---|---|---|
| `Enviar_Alerta` | Subflujo común: mensaje con el formato oficial a Telegram + `INSERT` en `alertas_auditoria` | 4.1–4.3 |
| R1–R5 | Consulta lenta, exceso de conexiones, fuera de horario, autenticaciones fallidas y cambio de parámetros | 4.1 |
| H3–H5 | Escritura en `agente_ia`, conexión fuera de la red Docker y desvío del baseline | 4.2 |
| Bot conversacional | Telegram → Groq genera SQL → se ejecuta con `agente_ia` → Groq redacta la respuesta | 5.x |
| Filtro anti-SQLi | Código de M5 ya integrado en el bot. Registra el bloqueo en `auditoria_datos` | A2 |
| Credenciales | 4 credenciales de N8N creadas por script desde el `.env`. Groq usa `Bearer {{ $env.GROQ_API_KEY }}` | 6.1 |

## 2. Dónde está cada cosa

| Archivo | Qué hace |
|---|---|
| `n8n/flujos/00_Enviar_Alerta.json` | Subflujo común (ID fijo `enviarAlertaNA01`) |
| `n8n/flujos/01_Bot_Telegram.json` | Bot conversacional |
| `n8n/flujos/R1_…json` … `R5_…json`, `H3_…json` … `H5_…json` | Una alerta por archivo |
| `scripts/init_n8n_m3.sh` | Crea credenciales, importa los flujos, los activa y reinicia N8N |
| `sql/pruebas/R1.sql` … `R4.sql`, `H3.sql`, `H4.sql` | Emulación, detección y limpieza (R5 y H5 ya los había escrito M2) |

## 3. Cómo cargarlo (cualquier copia del stack)

```bash
# 1. Completar TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID y GROQ_API_KEY en el .env
# 2. Levantar el stack y cargar N8N
docker compose up -d
bash scripts/init_n8n_m3.sh
```

Se puede volver a correr cuando cambie un flujo: primero desactiva los flujos y luego los reimporta.

**Bot en el grupo de Telegram:** desactivar el modo privacidad del bot (BotFather → `/setprivacy` → *Disable*) y luego sacarlo y volver a agregarlo al grupo. Con el modo privacidad activo, Telegram solo le entrega al bot los comandos que empiezan con `/`, no las preguntas normales.

## 4. Para M4 y M5: cómo usar `Enviar_Alerta`

Al final de cada flujo de alerta, agregar un nodo **Execute Workflow** → *Source: Database* → *Workflow: By ID* → `enviarAlertaNA01`.
El nodo anterior debe entregar **un ítem** con el contrato:

```json
{ "codigo": "D6", "severidad": "CRÍTICA", "tipo": "UPDATE masivo sin WHERE detectado",
  "tabla": "lotes_produccion", "detalle": "Filas modificadas: 200 (umbral: 50)",
  "query": "UPDATE ...", "usuario": "postgres", "accion": "Verificar intención. Consultar auditoria_datos." }
```

- Si no hay alerta, el nodo anterior devuelve **0 ítems** y no se envía nada.
- `severidad`: `CRÍTICA` o `ADVERTENCIA`, porque la tabla tiene un `CHECK`.
- `alertas_auditoria` se llena así: `alerta` = código (D6) y `tipo` = categoría, que sale de la letra del código (R→rendimiento, H→hardening, D→datos, A→seguridad).
- **Plantilla:** copien cualquier flujo R/H (*Duplicate*). Solo cambian la consulta SQL y el nodo Code.
- **El subflujo tiene que estar activo** para que lo puedan llamar; en n8n 2.x es obligatorio. El script lo activa.

## 5. Decisiones de diseño (para el informe)

1. **Bot por sondeo (`getUpdates` cada 10 s), no webhook.** Telegram no acepta el certificado autofirmado de Nginx y el servidor no es público (sección 10, punto 10). El bot solo atiende el chat de `TELEGRAM_CHAT_ID`.
2. **Tres barreras en el bot:** el filtro de entrada (M5), la validación del SQL de Groq (solo una sentencia `SELECT`/`WITH`, sin palabras peligrosas y con `LIMIT 50` forzado) y el usuario `agente_ia` de solo lectura.
3. **Modelo de Groq `openai/gpt-oss-120b`.** Groq apagó `llama-3.3-70b-versatile` el 16 de agosto de 2026.
4. **R1 lee el log de PostgreSQL** (`log_min_duration_statement` = 1000 ms del baseline): solo cuenta las sentencias lentas del último minuto, sin depender de memoria entre ejecuciones.
5. **R4 con dos fuentes:** el log de PostgreSQL (`pg_read_file`) y `auth.log` vía Loki para A1 por SSH (sección 10, punto 9). Si Loki no existe, ese nodo se ignora sin romper el flujo.
6. **R5** usa `vw_settings_servidor` (de M2) y refresca `pg_settings_snapshot` en cada ciclo, así cada cambio se alerta una sola vez.
7. **Sin spam:** `Enviar_Alerta` consulta `alertas_auditoria` y descarta una alerta con el mismo código y detalle enviada en los últimos 10 minutos. Aplica también a las alertas de M4 y M5.
8. **Ningún secreto en los flujos:** todo sale de credenciales de N8N o del `.env`.
9. **Mensajes de Telegram en modo HTML:** el nodo de Telegram usa Markdown por defecto, y un `_` suelto (como en `password_encryption`) hace que Telegram rechace el mensaje con *Bad request*. Por eso los mensajes van en HTML, con `<`, `>` y `&` escapados.

## 6. Capturas pendientes (en el servidor de la demo)

`R1_alerta.png` … `R5_alerta.png`, `H3_alerta.png` … `H5_alerta.png`, `BOT_pregunta.png`. Cada una muestra la hora del mensaje en Telegram.

## 7. Demo en vivo (4:30–7:00)

```bash
# Pregunta al bot en el grupo:  @<bot> ¿cuáles son los 5 productos más vendidos?
docker compose exec -T postgres psql -U postgres -d nutrianimales_db \
  -c "ALTER SYSTEM SET password_encryption = 'md5';" -c "SELECT pg_reload_conf();"
# En < 1 min llegan H5 (CRÍTICA) y R5. Mostrar:
docker compose exec -T postgres psql -U postgres -d nutrianimales_db \
  -c "SELECT alerta, severidad, fecha FROM alertas_auditoria ORDER BY id DESC LIMIT 3;"
# Revertir:
docker compose exec -T postgres psql -U postgres -d nutrianimales_db \
  -c "ALTER SYSTEM SET password_encryption = 'scram-sha-256';" -c "SELECT pg_reload_conf();"
```

`ALTER SYSTEM` y `pg_reload_conf()` van en **dos `-c` separados**: en un solo `-c` PostgreSQL da *"cannot run inside a transaction block"*.
