# Informe — secciones de M5 (borrador)

> Texto base con lo que ya está decidido en el repo. Los campos `[PENDIENTE]` se completan con resultados reales
> y capturas del servidor; no se presentan resultados esperados como obtenidos.

## 6. Matriz de riesgos
Se identificaron cinco riesgos, uno por cada ataque simulado (A1–A5), valorados con P × I en escala 1–5
(Bajo 1–4, Medio 5–9, Alto 10–16, Crítico 17–25). [Insertar tabla de `M5_MATRIZ_RIESGOS.md`.]
La inyección SQL a través del bot resultó el único riesgo Crítico antes de aplicar controles, porque el bot recibe texto libre y
lo convierte en SQL mediante un modelo de lenguaje. Tras las pruebas, el riesgo residual es: [PENDIENTE].

## 7. Seguridad del host y firewall
El servidor de integración (Ubuntu, VM) usa UFW con política `deny incoming` / `allow outgoing`, y solo permite SSH (22/tcp) y HTTPS (8443/tcp),
con registro en nivel medio. [PENDIENTE: salida de `ufw status verbose`, `M5_UFW_status.png`.]
**Limitación conocida:** Docker publica los puertos de los contenedores escribiendo directamente en iptables, antes de que el tráfico
llegue a las reglas de UFW. Por eso 8080 y 8443 responden aunque UFW no los permita explícitamente. [PENDIENTE: captura de `nc -vz <IP> 8080`.]
La protección real del puerto 5432 no depende de UFW sino de HD04: el servicio `postgres` no declara `ports:`, por lo que
aun con una regla `ufw allow 5432/tcp` el puerto sigue cerrado desde fuera. [PENDIENTE: captura de `nc -vz <IP> 5432`.]
Servicios innecesarios deshabilitados: [PENDIENTE].

## 8. Pipeline de logs, H1 y H2
**Arquitectura real:** Filebeat no tiene salida nativa hacia Loki. Se usó **Grafana Alloy**, el agente nativo de Loki (alternativa b del plan),
que lee `/var/log/auth.log` y `/var/log/ufw.log` del host en modo solo lectura y los envía a Loki con las etiquetas `job="auth"` y `job="ufw"`.
Ni Loki ni Alloy publican puertos; N8N consulta a Loki por la red interna `nutrianimales-net`. [Confirmar con el profesor que Alloy es aceptable.]
Se leen ambos archivos porque los cambios de reglas UFW quedan en `auth.log` (línea de `sudo`) y no en `ufw.log`, que solo registra tráfico.
Para no alertar con el historial al arrancar, Alloy lee solo líneas nuevas (`tail_from_end`).

**H1 — Cambio en reglas UFW.** Cada minuto N8N consulta a Loki las líneas de los últimos 3 minutos con `COMMAND=/usr/sbin/ufw`, descarta los
comandos que no modifican reglas (`status`, `show`), y envía la alerta por `Enviar_Alerta`: CRÍTICA si el comando abre o debilita el firewall
(`allow`, `insert`, `disable`, `reset`), ADVERTENCIA para los demás (`delete`, `deny`). Limitación: solo detecta comandos ejecutados con `sudo` directo;
un `sudo bash` o `sudo -i` registra el shell y no cada comando interno. [PENDIENTE: resultados y tiempo de detección.]

**H2 — Integridad de configuración.** Cada minuto se calcula `md5(pg_read_file(...))` de `pg_hba.conf` y `postgresql.conf` con la credencial `monitor_n8n`
(rol `pg_read_server_files`) y se compara con el hash guardado en la tabla `config_hashes`. La primera ejecución guarda la referencia sin alertar;
si cambia, alerta CRÍTICA y guarda el nuevo hash (una alerta por cambio). Se persiste en la base de datos porque en N8N 2.x la memoria de un flujo
publicado no se conserva entre ejecuciones. `ALTER SYSTEM` modifica `postgresql.auto.conf`, que ya cubren H5 y R5, por lo que no dispara H2.
[PENDIENTE: resultados y tiempo de detección.]

## 9. Filtro anti-SQLi (con M3)
El filtro está en el flujo del bot antes de Groq: bloquea mensajes con `;`, `--`, `/*` o palabras como `DROP`, `DELETE`, `UPDATE`, `UNION`, registra el
intento en `auditoria_datos` (operación `BLOQUEO`, con la credencial `monitor_n8n`) y responde "Consulta rechazada por política de seguridad".
Segunda barrera: el SQL generado por Groq solo se ejecuta si es una única sentencia `SELECT`/`WITH` sin palabras de escritura, con `LIMIT 50`; la tercera,
el usuario `agente_ia`, es de solo lectura. Es un filtro de entrada básico: puede bloquear mensajes legítimos que contengan `;` o términos como "update"
y no sustituye al mínimo privilegio. [PENDIENTE: capturas A2.]

## 10. Pruebas de ataque A1–A5
[Una subsección por ataque con: objetivo, comando, alerta con hora, registro, respuesta, tiempo de detección. Tabla resumen:]

| Ataque | Detecta | Ejecutado | Hora comando | Hora alerta | Tiempo (s) | Registro | Respuesta verificada |
|---|---|---|---|---|---:|---|---|
| A1 SSH | R4 | [PENDIENTE] | | | | | |
| A2 SQLi | Filtro | [PENDIENTE] | | | | | |
| A3 Puerto 5432 | H1 | [PENDIENTE] | | | | | |
| A4 Escalada | H3 | [PENDIENTE] | | | | | |
| A5 Exfiltración | D7 | [PENDIENTE: depende de M4] | | | | | |

## 11. Limitaciones y decisiones técnicas
- Docker evita UFW para puertos publicados (sección 7); la exposición real se valida con `nc` desde otra máquina.
- Alloy sustituye a Filebeat por falta de salida nativa a Loki.
- H1 depende de `sudo` directo y de que `rsyslog` escriba `auth.log`.
- El filtro anti-SQLi es una barrera básica con falsos positivos posibles.
- Rotar `agente_ia` deja al bot sin servicio hasta actualizar su credencial en N8N.
