# Sistema de Monitoreo Proactivo, Seguridad y Hardening de Base de Datos

**NutriAnimales S.A.** · BCD 9220 Seguridad de Sistemas Digitales · Lead University · III Cuatrimestre 2026

Stack: Docker Compose · PostgreSQL 16 · N8N · Nginx (HTTPS) · Telegram · Groq

> README en construcción. La versión final debe permitir levantar el sistema en menos de 5 minutos (checklist 7.2).

## Requisitos

- Ubuntu 22.04/24.04 con Docker Engine y el plugin `docker compose`
- `git`, `openssl`
- Usuario con UID 1000 y permisos de `sudo`

## Puesta en marcha

```bash
git clone https://github.com/DavidMoraV/Sistema-de-Monitoreo-Proactivo-Seguridad-y-Hardening-de-Base-de-Datos.git nutrianimales
cd nutrianimales
bash scripts/preparar_entorno.sh      # .env, volúmenes y certificados
docker compose up -d
docker compose ps
```

Abrir `https://<IP_DEL_SERVIDOR>:8443` (aceptar el certificado autofirmado) y crear la cuenta de N8N con el valor de `N8N_PASSWORD` del `.env`.

## Estructura

| Carpeta | Contenido |
|---|---|
| `sql/` | Scripts que PostgreSQL ejecuta en orden al crear la BD |
| `sql/pruebas/` | Escenarios de emulación de alertas y ataques |
| `nginx/` | Proxy inverso HTTPS con headers de seguridad |
| `certs/postgres/` | Certificado TLS de PostgreSQL (se genera, no se versiona) |
| `n8n/flujos/` | Flujos de N8N exportados en JSON |
| `logs/` | Configuración de recolección de logs |
| `scripts/` | Preparación del entorno, backups |
| `docs/capturas/` | Evidencias para el informe |

## Seguridad

- El archivo `.env` contiene los secretos reales, tiene permisos `600` y **nunca** se sube al repositorio.
- PostgreSQL no publica puertos; solo Nginx es accesible desde el host (8080 → 8443).
