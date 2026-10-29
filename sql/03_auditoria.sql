-- =====================================================================
--  03_auditoria.sql — Triggers de auditoría (sección 6 del enunciado)
--
--  Ajuste respecto al enunciado: la función es SECURITY DEFINER para que cualquier
--  rol que modifique una tabla auditada pueda escribir en auditoria_datos sin tener
--  permiso directo sobre ella. Por eso el usuario se registra con session_user
--  (quien inició sesión), no con current_user (que sería el dueño de la función).
-- =====================================================================

-- 6.1 Tabla de auditoría centralizada
CREATE TABLE auditoria_datos (
    id           SERIAL PRIMARY KEY,
    tabla        VARCHAR(100) NOT NULL,
    operacion    VARCHAR(10)  NOT NULL,              -- INSERT, UPDATE, DELETE, BLOQUEO
    usuario      VARCHAR(100) DEFAULT session_user,
    fecha        TIMESTAMP    DEFAULT NOW(),
    ip_cliente   INET         DEFAULT inet_client_addr(),
    fila_id      INTEGER,
    valor_antes  JSONB,
    valor_nuevo  JSONB
);

CREATE INDEX idx_audit_tabla   ON auditoria_datos(tabla);
CREATE INDEX idx_audit_usuario ON auditoria_datos(usuario);
CREATE INDEX idx_audit_fecha   ON auditoria_datos(fecha);

-- 6.2 Función genérica del trigger
CREATE OR REPLACE FUNCTION fn_auditoria()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO auditoria_datos (tabla, operacion, usuario, fila_id, valor_antes, valor_nuevo)
        VALUES (TG_TABLE_NAME, 'DELETE', session_user, OLD.id, row_to_json(OLD)::jsonb, NULL);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO auditoria_datos (tabla, operacion, usuario, fila_id, valor_antes, valor_nuevo)
        VALUES (TG_TABLE_NAME, 'UPDATE', session_user, NEW.id, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO auditoria_datos (tabla, operacion, usuario, fila_id, valor_antes, valor_nuevo)
        VALUES (TG_TABLE_NAME, 'INSERT', session_user, NEW.id, NULL, row_to_json(NEW)::jsonb);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

-- Nadie fuera del dueño puede ejecutarla directamente (solo vía trigger)
REVOKE ALL ON FUNCTION fn_auditoria() FROM PUBLIC;

-- 6.3 Triggers en las 4 tablas críticas
CREATE TRIGGER trg_auditoria_lotes
    AFTER INSERT OR UPDATE OR DELETE ON lotes_produccion
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_ventas
    AFTER INSERT OR UPDATE OR DELETE ON ventas
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_clientes
    AFTER INSERT OR UPDATE OR DELETE ON clientes
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria();

CREATE TRIGGER trg_auditoria_formulas
    AFTER INSERT OR UPDATE OR DELETE ON productos
    FOR EACH ROW EXECUTE FUNCTION fn_auditoria();
