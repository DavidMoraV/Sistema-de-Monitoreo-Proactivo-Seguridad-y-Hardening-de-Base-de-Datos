# Sistema de Monitoreo Proactivo, Seguridad y Hardening de Base de Datos

**NutriAnimales S.A.** · BCD 9220 Seguridad de Sistemas Digitales · Lead University · III Cuatrimestre 2026

Stack: Docker Compose · PostgreSQL 16 · N8N 2.45.5 · Nginx (HTTPS) · Telegram · Groq

> Estado actual y tareas por integrante: [`docs/ENTREGA_M1.md`](docs/ENTREGA_M1.md)

---

## Requisitos

- **Linux** (Ubuntu 22.04/24.04, en VM o servidor). Los permisos `chmod`/`chown` del hardening no funcionan en carpetas de Windows.
- Docker Engine + plugin `docker compose`, `git`, `openssl`
- Usuario con **UID 1000** (`id` para verificar) y permisos de `sudo`
- 4 GB de RAM y 20 GB de disco libres

## Puesta en marcha (≈ 5 minutos)

📍 Todo en la terminal de Ubuntu.

```bash
git clone https://github.com/DavidMoraV/Sistema-de-Monitoreo-Proactivo-Seguridad-y-Hardening-de-Base-de-Datos.git nutrianimales
cd nutrianimales
bash scripts/preparar_entorno.sh      # crea .env (contraseñas aleatorias), volúmenes y certificados
docker compose up -d
docker compose ps                     # 3 servicios "Up", postgres "(healthy)"
```

1. Abrir `https://<IP_DEL_SERVIDOR>:8443` y aceptar el certificado autofirmado.
2. Crear la cuenta de dueño de N8N. Guardar esa contraseña en `N8N_PASSWORD` del `.env`.
3. Para ver las contraseñas generadas: `cat .env` (solo en tu terminal; **nunca** en capturas ni en el chat del grupo).

### Reiniciar la base de datos desde cero

Los scripts de `sql/` solo se ejecutan cuando el volumen está vacío:

```bash
docker compose down
sudo rm -rf volumes/pgdata
bash scripts/preparar_entorno.sh
docker compose up -d
```

## Acceso a PostgreSQL

PostgreSQL **no publica puertos** (HD04). Se accede desde dentro de la red Docker:

```bash
# Consola como administrador
docker exec -it nutri_postgres psql -U postgres -d nutrianimales_db

# Como otro usuario (prueba de permisos)
docker exec -it nutri_postgres psql -U agente_ia -d nutrianimales_db
```

Conexión desde **N8N** (nodo / credencial *Postgres*):

| Campo | Valor |
|---|---|
| Host | `nutri_postgres` |
| Puerto | `5432` |
| Base de datos | `nutrianimales_db` |
| Usuario | `monitor_n8n` (alertas) o `agente_ia` (bot) |
| Contraseña | `MONITOR_N8N_PASSWORD` / `AGENTE_IA_PASSWORD` del `.env` |
| SSL | `require` + *Ignore SSL issues* (certificado autofirmado) |

## Usuarios de la base de datos

| Usuario | Rol | Puede | Uso |
|---|---|---|---|
| `postgres` | superusuario | todo | administración |
| `agente_ia` | — | SELECT en todas las tablas | bot de Telegram (HD07) |
| `monitor_n8n` | `rol_ti` + `pg_monitor` + `pg_read_server_files` | leer estadísticas, logs, `pg_hba.conf`; escribir snapshots y alertas | flujos de alertas R/H/D |
| `gerente_db` | `rol_gerente` | SELECT solo en `vw_ventas_resumen` y `vw_produccion_planta` | reportes |
| `ti_db` | `rol_ti` | SELECT en todo + INSERT en `backups` y `alertas_auditoria` | administración TI |
| `auditor_db` | `rol_auditor` | `auditoria_datos`, `backups`, `alertas_auditoria` + estadísticas | auditoría |

## Estructura

| Ruta | Contenido |
|---|---|
| `docker-compose.yml` | postgres, n8n, nginx en la red `nutrianimales-net` |
| `sql/00…05` | Extensiones, esquema (14 tablas), datos, auditoría, baseline, RBAC |
| `sql/pruebas/` | Escenarios de emulación de alertas y ataques (`R1.sql`, `D6.sql`, `A4.sql`…) |
| `nginx/` | Proxy HTTPS con headers de seguridad |
| `n8n/flujos/` | Flujos exportados en JSON (uno por alerta) |
| `logs/` | Configuración de recolección de logs (Filebeat/Loki) |
| `scripts/` | `preparar_entorno.sh`, backups |
| `docs/capturas/` | Evidencias: `<código>_<descripción>.png` |

## Seguridad

- `.env` tiene los secretos reales, permisos `600`, y **nunca** se sube (está en `.gitignore`). Cada integrante genera el suyo.
- Solo Nginx es accesible desde el host (8080 → 8443).
- No subir `volumes/`, llaves privadas ni respaldos.
