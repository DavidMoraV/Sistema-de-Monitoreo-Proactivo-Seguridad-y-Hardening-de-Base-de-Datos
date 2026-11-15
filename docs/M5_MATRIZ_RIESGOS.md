# M5 — Matriz de riesgos (versión 2)

**Método:** Riesgo = P × I (1–5 cada una). **Bajo** 1–4 · **Medio** 5–9 · **Alto** 10–16 · **Crítico** 17–25.
> **Verificar antes de entregar:** la sección 2.2 del enunciado define los 5 riesgos y la escala oficial; no la tengo.
> Los cinco riesgos de abajo siguen la lógica de los cinco ataques A1–A5 (uno por ataque). Si el enunciado
> usa otros nombres o rangos, cámbialos tal cual y deja las columnas de control.
> Cambio respecto a la versión 1: se reemplazó "alteración de configuración" por **inyección SQL vía el bot**,
> porque A2 no estaba cubierto por ningún riesgo. La alteración de configuración queda como control extra (H2) de RSK-02.

| ID | Riesgo | Escenario | P | I | P×I | Nivel | Mitigación implementada (hardening) | Detección | Ataque que lo prueba |
|---|---|---|---:|---:|---:|---|---|---|---|
| RSK-01 | Fuerza bruta sobre SSH | Intentos masivos de contraseña contra el servidor | 4 | 4 | 16 | Alto | UFW (solo 22 y 8443) | R4 (auth.log vía Loki) | A1 |
| RSK-02 | Exposición del puerto 5432 | Regla de firewall o publicación de puerto que expone PostgreSQL | 3 | 5 | 15 | Alto | HD04 (sin `ports:`), HD03 (red aislada), HD06 (SSL), HD12 (baseline) | H1, H4, H2 (integridad de `pg_hba.conf`) | A3 |
| RSK-03 | Exfiltración de datos | Lectura masiva de clientes/ventas | 3 | 5 | 15 | Alto | HD07 (`agente_ia` solo lectura), RBAC por roles | D7 | A5 |
| RSK-04 | Escalada de privilegios | `agente_ia` recibe INSERT/UPDATE/DELETE | 2 | 5 | 10 | Alto | HD07, mínimo privilegio, triggers de auditoría | H3 | A4 |
| RSK-05 | Inyección SQL vía bot | Texto malicioso en Telegram convertido en SQL por el LLM | 4 | 5 | 20 | Crítico | Filtro de entrada, validación de una sola sentencia SELECT, `LIMIT 50`, `agente_ia` solo lectura (3 barreras) | Registro `BLOQUEO` en `auditoria_datos` | A2 |

**Justificación de P e I** (propuesta, a ratificar por el grupo): P alta en RSK-01 y RSK-05 porque SSH y el bot reciben entrada
externa continuamente; I = 5 cuando se compromete la base de datos o su confidencialidad; RSK-04 tiene P baja porque requiere ya contar con una cuenta administradora.

## Riesgo residual (completar con evidencia, no antes)
| ID | Control probado | P res. | I res. | P×I | Nivel | Evidencia |
|---|---|---:|---:|---:|---|---|
| RSK-01 | [PENDIENTE: A1, R4 + bloqueo de IP] | | | | | A1_* |
| RSK-02 | [PENDIENTE: A3, H1; 5432 sigue cerrado desde fuera] | | | | | A3_*, H1_* |
| RSK-03 | [PENDIENTE: A5, D7, rotación] | | | | | A5_* |
| RSK-04 | [PENDIENTE: A4, H3, REVOKE] | | | | | A4_* |
| RSK-05 | [PENDIENTE: A2, bloqueo registrado] | | | | | A2_* |

Regla para el residual: bajar P solo si la prueba demostró que el control detecta o bloquea; I normalmente no cambia.
