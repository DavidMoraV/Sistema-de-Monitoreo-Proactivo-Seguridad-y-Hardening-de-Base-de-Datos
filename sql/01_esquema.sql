-- =====================================================================
--  01_esquema.sql — Modelo de datos de NutriAnimales S.A. (sección 11 del enunciado)
--  Todas las tablas auditadas tienen "id" como PK: fn_auditoria() usa OLD.id / NEW.id
-- =====================================================================

-- ---------------------------------------------------------------- Catálogos
CREATE TABLE plantas (
    id                    SERIAL PRIMARY KEY,
    nombre                VARCHAR(100) NOT NULL,
    ubicacion             VARCHAR(150) NOT NULL,
    capacidad_produccion  INTEGER      NOT NULL CHECK (capacidad_produccion > 0),   -- toneladas/mes
    estado                VARCHAR(20)  NOT NULL DEFAULT 'activa'
                          CHECK (estado IN ('activa', 'mantenimiento', 'inactiva'))
);

CREATE TABLE productos (
    id               SERIAL PRIMARY KEY,
    codigo           VARCHAR(20)   NOT NULL UNIQUE,
    nombre           VARCHAR(120)  NOT NULL,
    tipo             VARCHAR(20)   NOT NULL CHECK (tipo IN ('aves', 'cerdos', 'ganado', 'peces')),
    precio_unitario  NUMERIC(12,2) NOT NULL CHECK (precio_unitario > 0),          -- colones por saco
    activo           BOOLEAN       NOT NULL DEFAULT TRUE
);

CREATE TABLE materias_primas (
    id            SERIAL PRIMARY KEY,
    nombre        VARCHAR(120)  NOT NULL,
    categoria     VARCHAR(50)   NOT NULL,
    stock_actual  NUMERIC(12,2) NOT NULL CHECK (stock_actual >= 0),               -- kg
    stock_minimo  NUMERIC(12,2) NOT NULL CHECK (stock_minimo >= 0),
    proveedor     VARCHAR(120)  NOT NULL
);

CREATE TABLE clientes (
    id        SERIAL PRIMARY KEY,
    nombre    VARCHAR(150) NOT NULL,
    tipo      VARCHAR(20)  NOT NULL CHECK (tipo IN ('distribuidor', 'empresa', 'persona')),
    correo    VARCHAR(150) NOT NULL,          -- sin UNIQUE a propósito: la alerta D4 detecta duplicados
    segmento  VARCHAR(20)  NOT NULL
);

-- ---------------------------------------------------------------- Operación
CREATE TABLE lotes_produccion (
    id                  SERIAL PRIMARY KEY,
    codigo              VARCHAR(20)   NOT NULL UNIQUE,
    planta_id           INTEGER       NOT NULL REFERENCES plantas(id),
    producto_id         INTEGER       NOT NULL REFERENCES productos(id),
    cantidad_producida  NUMERIC(12,2) NOT NULL CHECK (cantidad_producida >= 0),   -- kg
    fecha_inicio        TIMESTAMP     NOT NULL DEFAULT NOW(),
    estado              VARCHAR(20)   NOT NULL DEFAULT 'planificado'
);

CREATE TABLE ventas (
    id            SERIAL PRIMARY KEY,
    cliente_id    INTEGER       NOT NULL REFERENCES clientes(id),
    producto_id   INTEGER       NOT NULL REFERENCES productos(id),
    cantidad      INTEGER       NOT NULL CHECK (cantidad > 0),
    precio_total  NUMERIC(14,2) NOT NULL CHECK (precio_total >= 0),
    fecha         TIMESTAMP     NOT NULL DEFAULT NOW(),
    estado        VARCHAR(20)   NOT NULL DEFAULT 'pendiente'
);

CREATE TABLE control_calidad (
    id              SERIAL PRIMARY KEY,
    lote_id         INTEGER       NOT NULL REFERENCES lotes_produccion(id),
    parametro       VARCHAR(60)   NOT NULL,
    valor_obtenido  NUMERIC(10,2) NOT NULL,
    valor_esperado  NUMERIC(10,2) NOT NULL,
    aprobado        BOOLEAN       NOT NULL
);

CREATE TABLE gastos (
    id            SERIAL PRIMARY KEY,
    categoria     VARCHAR(50)   NOT NULL,
    descripcion   VARCHAR(200)  NOT NULL,
    monto         NUMERIC(14,2) NOT NULL CHECK (monto >= 0),
    fecha         TIMESTAMP     NOT NULL DEFAULT NOW(),
    aprobado_por  VARCHAR(100)  NOT NULL
);

-- ---------------------------------------------------------------- Monitoreo
CREATE TABLE backups (                     -- alerta D3
    id      SERIAL PRIMARY KEY,
    fecha   TIMESTAMP    NOT NULL DEFAULT NOW(),
    estado  VARCHAR(20)  NOT NULL CHECK (estado IN ('ok', 'fallido')),
    ruta    VARCHAR(255) NOT NULL
);

CREATE TABLE alertas_auditoria (           -- historial de alertas enviadas por N8N
    id         SERIAL PRIMARY KEY,
    tipo       VARCHAR(20)  NOT NULL,      -- rendimiento / hardening / datos
    alerta     VARCHAR(10)  NOT NULL,      -- R1..R5, H1..H5, D1..D7
    mensaje    TEXT         NOT NULL,
    fecha      TIMESTAMP    NOT NULL DEFAULT NOW(),
    severidad  VARCHAR(20)  NOT NULL CHECK (severidad IN ('CRÍTICA', 'ADVERTENCIA'))
);

-- ---------------------------------------------------------------- Tablas auxiliares de alertas
CREATE TABLE pg_settings_snapshot (        -- R5: última foto de pg_settings
    name     TEXT PRIMARY KEY,
    setting  TEXT
);

CREATE TABLE snapshot_tablas (             -- D2: filas por tabla para medir crecimiento
    relname  TEXT      NOT NULL,
    filas    BIGINT    NOT NULL,
    fecha    TIMESTAMP NOT NULL DEFAULT NOW(),
    PRIMARY KEY (relname, fecha)
);

-- Índices de apoyo a consultas frecuentes
CREATE INDEX idx_ventas_fecha     ON ventas(fecha);
CREATE INDEX idx_ventas_cliente   ON ventas(cliente_id);
CREATE INDEX idx_lotes_planta     ON lotes_produccion(planta_id);
CREATE INDEX idx_clientes_correo  ON clientes(correo);
CREATE INDEX idx_backups_fecha    ON backups(fecha);
