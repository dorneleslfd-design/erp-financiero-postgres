-- =====================================================================
-- ERP financiero — esquema
-- Modelo dimensional simple: tablas d_ (dimensiones) y f_ (hechos).
-- IDs numéricos, poco texto en la tabla de hechos, reglas en la base.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS erp;
SET search_path TO erp;

-- ---------- Dimensiones ----------

CREATE TABLE d_cliente (
    id_cliente      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          varchar(120) NOT NULL,
    ruc             varchar(20)  UNIQUE,
    ciudad          varchar(60),
    activo          boolean      NOT NULL DEFAULT true
);

CREATE TABLE d_proveedor (
    id_proveedor    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          varchar(120) NOT NULL,
    ruc             varchar(20)  UNIQUE,
    activo          boolean      NOT NULL DEFAULT true
);

-- Plan de cuentas simplificado. "grupo" alimenta el estado de resultados.
CREATE TABLE d_categoria (
    id_categoria    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre          varchar(80)  NOT NULL UNIQUE,
    tipo            varchar(7)   NOT NULL CHECK (tipo IN ('INGRESO', 'EGRESO')),
    grupo           varchar(40)  NOT NULL
);

CREATE TABLE d_cuenta_bancaria (
    id_cuenta       integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    banco           varchar(60)   NOT NULL,
    alias           varchar(60)   NOT NULL UNIQUE,
    saldo_inicial   numeric(14,2) NOT NULL DEFAULT 0,
    fecha_saldo     date          NOT NULL
);

-- Centro de costo = obra o proyecto al que se imputa el movimiento.
CREATE TABLE d_centro_costo (
    id_centro_costo integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo          varchar(10)  NOT NULL UNIQUE,
    nombre          varchar(120) NOT NULL
);

-- ---------- Hechos ----------

-- Un movimiento = una cuenta a cobrar (INGRESO) o a pagar (EGRESO).
-- Mientras fecha_pago es NULL, el movimiento está abierto.
CREATE TABLE f_movimiento (
    id_movimiento   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo            varchar(7)    NOT NULL CHECK (tipo IN ('INGRESO', 'EGRESO')),
    id_categoria    integer       NOT NULL REFERENCES d_categoria,
    id_cliente      integer       REFERENCES d_cliente,
    id_proveedor    integer       REFERENCES d_proveedor,
    id_centro_costo integer       REFERENCES d_centro_costo,
    id_cuenta       integer       NOT NULL REFERENCES d_cuenta_bancaria,
    documento       varchar(30),
    fecha_emision   date          NOT NULL,
    fecha_venc      date          NOT NULL,
    monto           numeric(14,2) NOT NULL CHECK (monto > 0),
    fecha_pago      date,
    monto_pagado    numeric(14,2),

    -- Un ingreso tiene cliente; un egreso tiene proveedor.
    CONSTRAINT ck_contraparte CHECK (
        (tipo = 'INGRESO' AND id_cliente IS NOT NULL AND id_proveedor IS NULL) OR
        (tipo = 'EGRESO'  AND id_proveedor IS NOT NULL AND id_cliente IS NULL)
    ),
    CONSTRAINT ck_fechas CHECK (fecha_venc >= fecha_emision),
    -- Pago completo o nada: fecha y monto van juntos.
    CONSTRAINT ck_pago CHECK (
        (fecha_pago IS NULL AND monto_pagado IS NULL) OR
        (fecha_pago IS NOT NULL AND monto_pagado IS NOT NULL AND monto_pagado > 0
         AND fecha_pago >= fecha_emision)
    )
);

-- El tipo del movimiento debe coincidir con el tipo de su categoría.
CREATE FUNCTION fn_validar_tipo_categoria() RETURNS trigger
LANGUAGE plpgsql SET search_path = erp AS $$
BEGIN
    IF NEW.tipo <> (SELECT tipo FROM d_categoria WHERE id_categoria = NEW.id_categoria) THEN
        RAISE EXCEPTION 'La categoría % no corresponde a un %', NEW.id_categoria, NEW.tipo;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER tg_validar_tipo_categoria
    BEFORE INSERT OR UPDATE OF tipo, id_categoria ON f_movimiento
    FOR EACH ROW EXECUTE FUNCTION fn_validar_tipo_categoria();

-- Índices para las consultas más frecuentes: vencimientos abiertos y flujo de caja.
CREATE INDEX ix_mov_abiertos_venc ON f_movimiento (fecha_venc) WHERE fecha_pago IS NULL;
CREATE INDEX ix_mov_fecha_pago    ON f_movimiento (fecha_pago) WHERE fecha_pago IS NOT NULL;
CREATE INDEX ix_mov_emision       ON f_movimiento (fecha_emision);
CREATE INDEX ix_mov_cliente       ON f_movimiento (id_cliente)      WHERE id_cliente IS NOT NULL;
CREATE INDEX ix_mov_proveedor     ON f_movimiento (id_proveedor)    WHERE id_proveedor IS NOT NULL;
CREATE INDEX ix_mov_centro        ON f_movimiento (id_centro_costo) WHERE id_centro_costo IS NOT NULL;

-- ---------- Procedimiento: registrar pago (baja) ----------

CREATE PROCEDURE sp_registrar_pago(
    p_id_movimiento bigint,
    p_fecha_pago    date,
    p_monto_pagado  numeric
)
LANGUAGE plpgsql SET search_path = erp AS $$
DECLARE
    v_mov f_movimiento%ROWTYPE;
BEGIN
    SELECT * INTO v_mov FROM f_movimiento WHERE id_movimiento = p_id_movimiento FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Movimiento % no existe', p_id_movimiento;
    END IF;
    IF v_mov.fecha_pago IS NOT NULL THEN
        RAISE EXCEPTION 'Movimiento % ya fue pagado el %', p_id_movimiento, v_mov.fecha_pago;
    END IF;
    IF p_monto_pagado IS NULL OR p_monto_pagado <= 0 THEN
        RAISE EXCEPTION 'Monto pagado inválido';
    END IF;

    UPDATE f_movimiento
       SET fecha_pago = p_fecha_pago,
           monto_pagado = p_monto_pagado
     WHERE id_movimiento = p_id_movimiento;
END $$;
