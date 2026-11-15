-- =====================================================================
--  H2 — Integridad de pg_hba.conf / postgresql.conf   Flujo: n8n/flujos/H2_Integridad_config_PG.json
-- =====================================================================
-- 0. Estado: el flujo guarda la referencia en su primera ejecución (sin alerta).
SELECT archivo, left(hash, 12) AS hash, actualizado FROM config_hashes;

-- 1. EMULACIÓN (en la terminal del servidor, NO en psql). Antes, respaldo:
--    docker exec nutri_postgres bash -c 'cp $PGDATA/pg_hba.conf $PGDATA/pg_hba.conf.bak'
--    docker exec nutri_postgres bash -c 'echo "# prueba H2" >> $PGDATA/pg_hba.conf'
--    (un comentario no cambia la política de acceso; no hace falta reiniciar)

-- 2. DETECCIÓN (usuario monitor_n8n) → hash_actual <> hash_guardado = alerta CRÍTICA
SELECT 'pg_hba.conf' AS archivo, md5(pg_read_file('pg_hba.conf')) AS hash_actual,
       (SELECT hash FROM config_hashes WHERE archivo = 'pg_hba.conf') AS hash_guardado
UNION ALL
SELECT 'postgresql.conf', md5(pg_read_file('postgresql.conf')),
       (SELECT hash FROM config_hashes WHERE archivo = 'postgresql.conf');

-- 3. LIMPIEZA (terminal): restaurar el archivo. Eso cambia el hash otra vez y genera
--    una segunda alerta H2 (la evidencia H2_restauracion):
--    docker exec nutri_postgres bash -c 'cp $PGDATA/pg_hba.conf.bak $PGDATA/pg_hba.conf && rm $PGDATA/pg_hba.conf.bak'

-- 4. Si algo queda desincronizado, reiniciar la referencia (el flujo la vuelve a guardar sin alertar):
-- DELETE FROM config_hashes;

-- Nota: ALTER SYSTEM escribe en postgresql.auto.conf, no en postgresql.conf, por eso
-- la demo de H5/R5 (ALTER SYSTEM) NO dispara H2. Si el grupo quiere vigilar también
-- postgresql.auto.conf, agregar un tercer SELECT igual a los de arriba en el flujo H2;
-- dispararía una alerta extra durante la demo de M3.
