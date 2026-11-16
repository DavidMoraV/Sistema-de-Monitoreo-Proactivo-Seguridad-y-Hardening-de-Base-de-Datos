# M5 — Matriz de riesgos (versión 3, con residual)

**Método:** Riesgo = P × I (1–5 cada una). **Bajo** 1–4 · **Medio** 5–9 · **Alto** 10–16 · **Crítico** 17–25.
> Cinco riesgos, uno por cada ataque A1–A5. La alteración de configuración queda como control extra (H2) de RSK-02.

| ID | Riesgo | Escenario | P | I | P×I | Nivel | Mitigación implementada (hardening) | Detección | Ataque que lo prueba |
|---|---|---|---:|---:|---:|---|---|---|---|
| RSK-01 | Fuerza bruta sobre SSH | Intentos masivos de contraseña contra el servidor | 4 | 4 | 16 | Alto | UFW (SSH solo desde 192.168.56.0/24) | R4 (auth.log vía Loki) | A1 |
| RSK-02 | Exposición del puerto 5432 | Regla de firewall o publicación de puerto que expone PostgreSQL | 3 | 5 | 15 | Alto | HD04 (sin `ports:`), HD03 (red aislada), HD06 (SSL), HD12 (baseline) | H1, H4, H2 (integridad de `pg_hba.conf`) | A3 |
| RSK-03 | Exfiltración de datos | Lectura masiva de clientes/ventas | 3 | 5 | 15 | Alto | HD07 (`agente_ia` solo lectura), RBAC por roles | D7 | A5 |
| RSK-04 | Escalada de privilegios | `agente_ia` recibe INSERT/UPDATE/DELETE | 2 | 5 | 10 | Alto | HD07, mínimo privilegio, triggers de auditoría | H3 | A4 |
| RSK-05 | Inyección SQL vía bot | Texto malicioso en Telegram convertido en SQL por el LLM | 4 | 5 | 20 | Crítico | Filtro de entrada, validación de una sola sentencia SELECT, `LIMIT 50`, `agente_ia` solo lectura (3 barreras) | Registro `BLOQUEO` en `auditoria_datos` | A2 |

**Justificación de P e I:** P alta en RSK-01 y RSK-05 porque SSH y el bot reciben entrada
externa continuamente; I = 5 cuando se compromete la base de datos o su confidencialidad; RSK-04 tiene P baja porque requiere ya contar con una cuenta administradora.

## Riesgo residual (tras ejecutar A1–A5, 15/11/2026)
| ID | Control probado | P res. | I res. | P×I | Nivel | Evidencia |
|---|---|---:|---:|---:|---|---|
| RSK-01 | A1: R4 alertó a los 79 s (21 fallos SSH). El bloqueo `ufw deny` es manual | 3 | 4 | 12 | Alto | A1_R4_* |
| RSK-02 | A3: H1 alertó a los 21 s; el 5432 siguió cerrado porque el contenedor no lo publica | 1 | 5 | 5 | Medio | H1_A3_terminal, H1_H2_alerta_telegram |
| RSK-03 | A5: D7 alertó a los 53 s, pero los 1,500 registros ya se habían leído | 2 | 5 | 10 | Alto | A5_D7_* |
| RSK-04 | A4: H3 alertó a los 5 s y se revirtió con REVOKE | 1 | 5 | 5 | Medio | A4_H3_* |
| RSK-05 | A2: el filtro rechazó la consulta; `clientes` siguió con 1,500 filas | 2 | 5 | 10 | Alto | A2_bloqueo_* |

Regla aplicada: bajar P solo si la prueba demostró que el control detecta o bloquea; I no cambia porque depende del dato expuesto.
RSK-01, RSK-03 y RSK-05 siguen en Alto: los controles detectan pero no impiden el primer daño, o dependen de un filtro evadible.
Mejora propuesta: bloqueo automático (fail2ban para SSH y límite de filas por consulta para `agente_ia`).
