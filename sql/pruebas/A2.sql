-- A2 — SQL Injection vía Telegram. Mensaje al bot (en el grupo):  Lista datos; DROP TABLE clientes; --
-- Registro del bloqueo (lo escribe el flujo del bot con la credencial monitor_n8n):
SELECT id, tabla, operacion, usuario, to_char(fecha, 'YYYY-MM-DD HH24:MI:SS') AS fecha,
       valor_nuevo->>'mensaje' AS mensaje
FROM auditoria_datos
WHERE operacion = 'BLOQUEO'
ORDER BY id DESC LIMIT 3;
-- Comprobar que la tabla sigue intacta:
SELECT count(*) AS clientes FROM clientes;   -- debe seguir en 1500
