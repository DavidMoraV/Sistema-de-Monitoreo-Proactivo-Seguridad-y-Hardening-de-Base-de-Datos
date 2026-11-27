#!/usr/bin/env python3
"""Carga en la CMDB de GLPI los 7 contenedores del stack y su relación de impacto con el servidor.
Idempotente: si un elemento ya existe, no lo duplica. Uso: python3 scripts/cargar_cmdb_glpi.py
Pide el token de API de un usuario administrador (no se guarda); el App-Token se lee del .env."""
import getpass, json, ssl, sys, urllib.request
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
API = "https://localhost:8444/apirest.php"
SERVIDOR = "nutrianimales-srv01"
GRUPO = "Equipo TI NutriAnimales"
TIPO = "Contenedor Docker"
ESTADO = "En producción"
CONTENEDORES = [
    ("nutri_postgres", "postgres:16 · Base de datos transaccional (clientes, ventas, inventario) · sin puertos publicados"),
    ("nutri_n8n",      "n8nio/n8n:2.45.5 · Automatización: alertas, webhook del hash y API de GLPI · sin puertos publicados"),
    ("nutri_nginx",    "nginx:1.27-alpine · Proxy HTTPS, único punto de entrada · 8080, 8443 y 8444"),
    ("nutri_loki",     "grafana/loki:3.4.2 · Almacenamiento de logs del host · sin puertos publicados"),
    ("nutri_alloy",    "grafana/alloy:v1.8.2 · Recolección de auth.log y ufw.log · sin puertos publicados"),
    ("nutri_glpi",     "glpi/glpi:10.0.28 · ITSM y CMDB · sale solo por Nginx (8444)"),
    ("nutri_glpi_db",  "mariadb:10.11 · Base de datos de GLPI · sin puertos publicados"),
]


def leer_env(clave):
    """Devuelve el valor de una variable del .env sin cargar el resto."""
    for linea in (RAIZ / ".env").read_text().splitlines():
        if linea.startswith(clave + "="):
            return linea.split("=", 1)[1].strip().strip('"')
    sys.exit(f"Falta {clave} en el .env")


# TLS validado contra el certificado propio de Nginx (emitido para nutrianimales.local; se llama por localhost)
ctx = ssl.create_default_context(cafile=str(RAIZ / "nginx/certs/nginx.crt"))
ctx.check_hostname = False
cab = {"Content-Type": "application/json", "App-Token": leer_env("GLPI_APP_TOKEN")}


def api(metodo, ruta, cuerpo=None, extra=None):
    """Llamada a la API REST de GLPI; corta el script con el mensaje de error si falla."""
    datos = json.dumps(cuerpo).encode() if cuerpo is not None else None
    req = urllib.request.Request(API + ruta, data=datos, method=metodo, headers={**cab, **(extra or {})})
    try:
        with urllib.request.urlopen(req, context=ctx) as r:
            texto = r.read().decode()
            return json.loads(texto) if texto else None
    except urllib.request.HTTPError as e:
        sys.exit(f"{metodo} {ruta} → HTTP {e.code}: {e.read().decode()[:300]}")


def lista(tipo):
    r = api("GET", f"/{tipo}?range=0-999")
    return r if isinstance(r, list) else []


def obtener_o_crear(tipo, nombre, campos=None):
    """Busca un elemento por nombre exacto; si no existe, lo crea. Devuelve (id, creado)."""
    for x in lista(tipo):
        if x.get("name") == nombre:
            return x["id"], False
    return api("POST", f"/{tipo}", {"input": {"name": nombre, **(campos or {})}})["id"], True


token = getpass.getpass("Token de API del usuario administrador de GLPI: ").strip()
cab["Session-Token"] = api("GET", "/initSession", extra={"Authorization": "user_token " + token})["session_token"]
try:
    servidor = next((c["id"] for c in lista("Computer") if c["name"] == SERVIDOR), None)
    if not servidor:
        sys.exit(f"No existe la computadora {SERVIDOR} en GLPI")
    grupo = next((g["id"] for g in lista("Group") if g["name"] == GRUPO), 0)
    tipo, _ = obtener_o_crear("ComputerType", TIPO, {"comment": "Contenedor del stack Docker de NutriAnimales"})
    estado, _ = obtener_o_crear("State", ESTADO)
    relaciones = {(r["items_id_source"], r["items_id_impacted"]) for r in lista("ImpactRelation")
                  if r.get("itemtype_source") == "Computer" and r.get("itemtype_impacted") == "Computer"}
    for nombre, comentario in CONTENEDORES:
        cid, nuevo = obtener_o_crear("Computer", nombre, {
            "computertypes_id": tipo, "states_id": estado, "groups_id_tech": grupo,
            "entities_id": 0, "comment": f"{comentario}\nCorre en {SERVIDOR}."})
        if (servidor, cid) not in relaciones:
            api("POST", "/ImpactRelation", {"input": {
                "itemtype_source": "Computer", "items_id_source": servidor,
                "itemtype_impacted": "Computer", "items_id_impacted": cid}})
            rel = "relación creada"
        else:
            rel = "relación ya existía"
        print(f"  {nombre:<15} id {cid:<3} {'creado' if nuevo else 'ya existía':<11} · {rel}")
    print(f"Listo: {SERVIDOR} (id {servidor}) impacta a {len(CONTENEDORES)} contenedores.")
finally:
    api("GET", "/killSession")
