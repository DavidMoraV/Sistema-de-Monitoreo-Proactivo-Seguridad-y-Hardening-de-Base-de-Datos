-- A5 — Exfiltración (detecta D7, de M4). Conectar como agente_ia:
--   docker exec -it nutri_postgres psql -U agente_ia -d nutrianimales_db
-- 1. EMULACIÓN (1500 filas en una sola consulta, supera el umbral de 1000)
SELECT * FROM clientes;
-- 2. RESPUESTA (terminal del servidor, sin escribir la contraseña):
--    bash scripts/rotar_password_bd.sh agente_ia AGENTE_IA_PASSWORD
--    y actualizar la credencial "Postgres agente_ia" en N8N (el bot no responde hasta hacerlo)
-- 3. Registro de la alerta (como postgres):
-- SELECT alerta, severidad, to_char(fecha,'YYYY-MM-DD HH24:MI:SS') FROM alertas_auditoria WHERE alerta='D7' ORDER BY id DESC LIMIT 3;
