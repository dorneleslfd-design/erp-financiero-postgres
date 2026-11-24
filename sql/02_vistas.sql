-- =====================================================================
-- ERP financiero — vistas para reportes y Power BI
-- La fecha de referencia es CURRENT_DATE; en los datos de ejemplo
-- se usa erp.fn_hoy() para que los resultados sean reproducibles.
-- =====================================================================

SET search_path TO erp;

-- Fecha de referencia. En producción devuelve CURRENT_DATE;
-- los datos de ejemplo la fijan con: SET erp.hoy = '2026-10-31';
CREATE FUNCTION fn_hoy() RETURNS date
LANGUAGE sql STABLE AS $$
    SELECT COALESCE(NULLIF(current_setting('erp.hoy', true), '')::date, CURRENT_DATE)
$$;

-- Movimientos con nombres y estado calculado.
CREATE VIEW v_movimientos AS
SELECT
    m.id_movimiento,
    m.tipo,
    c.nombre                                   AS categoria,
    c.grupo,
    COALESCE(cl.nombre, pr.nombre)             AS contraparte,
    cc.codigo                                  AS centro_costo,
    cb.alias                                   AS cuenta,
    m.documento,
    m.fecha_emision,
    m.fecha_venc,
    m.monto,
    m.fecha_pago,
    m.monto_pagado,
    CASE
        WHEN m.fecha_pago IS NOT NULL      THEN 'PAGADO'
        WHEN m.fecha_venc <  fn_hoy()      THEN 'VENCIDO'
        WHEN m.fecha_venc =  fn_hoy()      THEN 'VENCE HOY'
        ELSE 'POR VENCER'
    END                                        AS estado,
    CASE WHEN m.fecha_pago IS NULL AND m.fecha_venc < fn_hoy()
         THEN fn_hoy() - m.fecha_venc END      AS dias_atraso
FROM f_movimiento m
JOIN d_categoria         c  ON c.id_categoria     = m.id_categoria
JOIN d_cuenta_bancaria   cb ON cb.id_cuenta       = m.id_cuenta
LEFT JOIN d_cliente      cl ON cl.id_cliente      = m.id_cliente
LEFT JOIN d_proveedor    pr ON pr.id_proveedor    = m.id_proveedor
LEFT JOIN d_centro_costo cc ON cc.id_centro_costo = m.id_centro_costo;

-- Flujo de caja mensual (lo efectivamente pagado y cobrado), con saldo acumulado.
CREATE VIEW v_flujo_caja_mensual AS
WITH mensual AS (
    SELECT
        date_trunc('month', fecha_pago)::date                                   AS mes,
        SUM(monto_pagado) FILTER (WHERE tipo = 'INGRESO')                       AS ingresos,
        SUM(monto_pagado) FILTER (WHERE tipo = 'EGRESO')                        AS egresos
    FROM f_movimiento
    WHERE fecha_pago IS NOT NULL
    GROUP BY 1
)
SELECT
    mes,
    COALESCE(ingresos, 0)                                   AS ingresos,
    COALESCE(egresos, 0)                                    AS egresos,
    COALESCE(ingresos, 0) - COALESCE(egresos, 0)            AS neto,
    (SELECT SUM(saldo_inicial) FROM d_cuenta_bancaria)
      + SUM(COALESCE(ingresos, 0) - COALESCE(egresos, 0)) OVER (ORDER BY mes) AS saldo_acumulado
FROM mensual
ORDER BY mes;

-- Cuentas por cobrar abiertas, por antigüedad.
CREATE VIEW v_cuentas_por_cobrar AS
SELECT
    contraparte                                                          AS cliente,
    COUNT(*)                                                             AS documentos,
    SUM(monto) FILTER (WHERE estado IN ('POR VENCER', 'VENCE HOY'))      AS a_vencer,
    SUM(monto) FILTER (WHERE dias_atraso BETWEEN 1 AND 30)               AS vencido_1_30,
    SUM(monto) FILTER (WHERE dias_atraso BETWEEN 31 AND 60)              AS vencido_31_60,
    SUM(monto) FILTER (WHERE dias_atraso BETWEEN 61 AND 90)              AS vencido_61_90,
    SUM(monto) FILTER (WHERE dias_atraso > 90)                           AS vencido_mas_90,
    SUM(monto)                                                           AS total_abierto
FROM v_movimientos
WHERE tipo = 'INGRESO' AND estado <> 'PAGADO'
GROUP BY contraparte;

-- Alertas: lo que vence hoy o mañana (base de los avisos automáticos por correo).
CREATE VIEW v_alertas_vencimiento AS
SELECT tipo, contraparte, documento, fecha_venc, monto, centro_costo,
       CASE WHEN fecha_venc = fn_hoy() THEN 'HOY' ELSE 'MAÑANA' END AS cuando
FROM v_movimientos
WHERE estado <> 'PAGADO'
  AND fecha_venc BETWEEN fn_hoy() AND fn_hoy() + 1;

-- Resultado mensual por grupo (criterio de emisión / devengado).
CREATE VIEW v_resultado_mensual AS
SELECT
    date_trunc('month', m.fecha_emision)::date                         AS mes,
    c.grupo,
    SUM(CASE WHEN m.tipo = 'INGRESO' THEN m.monto ELSE -m.monto END)   AS resultado
FROM f_movimiento m
JOIN d_categoria c ON c.id_categoria = m.id_categoria
GROUP BY 1, 2;

-- Margen por centro de costo (obra).
CREATE VIEW v_margen_centro_costo AS
SELECT
    cc.codigo,
    cc.nombre,
    SUM(m.monto) FILTER (WHERE m.tipo = 'INGRESO')                      AS ingresos,
    SUM(m.monto) FILTER (WHERE m.tipo = 'EGRESO')                       AS egresos,
    COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'INGRESO'), 0)
      - COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'EGRESO'), 0)      AS margen,
    ROUND(100 * (COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'INGRESO'), 0)
      - COALESCE(SUM(m.monto) FILTER (WHERE m.tipo = 'EGRESO'), 0))
      / NULLIF(SUM(m.monto) FILTER (WHERE m.tipo = 'INGRESO'), 0), 1)  AS margen_pct
FROM d_centro_costo cc
LEFT JOIN f_movimiento m ON m.id_centro_costo = cc.id_centro_costo
GROUP BY cc.codigo, cc.nombre;
