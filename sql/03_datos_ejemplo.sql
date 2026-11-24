-- =====================================================================
-- ERP financiero — datos de ejemplo (ficticios)
-- Ene–oct 2026, montos en guaraníes. Generación reproducible.
-- =====================================================================

SET search_path TO erp;
SELECT setseed(0.42);

INSERT INTO d_cliente (nombre, ruc, ciudad) VALUES
    ('CONSTRUCTORA DEL ESTE S.A.',      '80012345-1', 'Asunción'),
    ('INMOBILIARIA LAS PALMAS S.R.L.',  '80023456-2', 'Asunción'),
    ('LOGÍSTICA RUTA 2 S.A.',           '80034567-3', 'Luque'),
    ('MUNICIPALIDAD DE SAN LORENZO',    '80045678-4', 'San Lorenzo'),
    ('DESARROLLOS URBANOS E.A.S.',      '80056789-5', 'Lambaré');

INSERT INTO d_proveedor (nombre, ruc) VALUES
    ('HORMIGONES CENTRAL S.A.',         '80111111-1'),
    ('FERRETERÍA INDUSTRIAL S.R.L.',    '80122222-2'),
    ('COMBUSTIBLES DEL PARAGUAY S.A.',  '80133333-3'),
    ('ALQUILER DE MAQUINARIAS S.A.',    '80144444-4'),
    ('ESTUDIO CONTABLE GÓMEZ',          '80155555-5'),
    ('INMUEBLES OFICINA CENTRO',        '80166666-6');

INSERT INTO d_categoria (nombre, tipo, grupo) VALUES
    ('SERVICIOS DE PERFORACIÓN', 'INGRESO', 'INGRESOS OPERATIVOS'),
    ('ENSAYOS Y SONDEOS',        'INGRESO', 'INGRESOS OPERATIVOS'),
    ('MATERIALES',               'EGRESO',  'COSTOS DE OBRA'),
    ('COMBUSTIBLE',              'EGRESO',  'COSTOS DE OBRA'),
    ('ALQUILER DE EQUIPOS',      'EGRESO',  'COSTOS DE OBRA'),
    ('HONORARIOS CONTABLES',     'EGRESO',  'GASTOS ADMINISTRATIVOS'),
    ('ALQUILER DE OFICINA',      'EGRESO',  'GASTOS ADMINISTRATIVOS');

INSERT INTO d_cuenta_bancaria (banco, alias, saldo_inicial, fecha_saldo) VALUES
    ('BANCO A', 'CUENTA OPERATIVA', 150000000, '2025-12-31'),
    ('BANCO B', 'CUENTA RESERVA',    80000000, '2025-12-31');

INSERT INTO d_centro_costo (codigo, nombre) VALUES
    ('OB-101', 'EDIFICIO RESIDENCIAL LAS PALMAS'),
    ('OB-102', 'CENTRO LOGÍSTICO RUTA 2'),
    ('OB-103', 'PUENTE ARROYO SECO'),
    ('ADM',    'ADMINISTRACIÓN CENTRAL');

-- Ingresos: ~12 facturas por mes, cobro a 30 días; parte se cobra tarde y parte queda abierta.
INSERT INTO f_movimiento (tipo, id_categoria, id_cliente, id_centro_costo, id_cuenta,
                          documento, fecha_emision, fecha_venc, monto, fecha_pago, monto_pagado)
SELECT
    'INGRESO',
    1 + (random() < 0.35)::int,
    1 + floor(random() * 5)::int,
    1 + floor(random() * 3)::int,
    1,
    'FAC-' || lpad(n::text, 5, '0'),
    emision,
    emision + 30,
    monto,
    CASE WHEN emision + 30 + atraso <= DATE '2026-10-31' AND cobra THEN emision + 30 + atraso END,
    CASE WHEN emision + 30 + atraso <= DATE '2026-10-31' AND cobra THEN monto END
FROM (
    SELECT n,
           DATE '2026-01-02' + floor(random() * 302)::int                      AS emision,
           round((8 + random() * 37)::numeric * 1000000, -3)                   AS monto,
           (CASE WHEN random() < 0.7 THEN floor(random() * 6) ELSE floor(random() * 45) END)::int AS atraso,
           random() > 0.06                                                     AS cobra
    FROM generate_series(1, 120) AS n
) x;

-- Egresos variables de obra: ~25 por mes, pago al vencimiento.
INSERT INTO f_movimiento (tipo, id_categoria, id_proveedor, id_centro_costo, id_cuenta,
                          documento, fecha_emision, fecha_venc, monto, fecha_pago, monto_pagado)
SELECT
    'EGRESO',
    cat,
    CASE cat WHEN 3 THEN 1 + (random() < 0.5)::int WHEN 4 THEN 3 ELSE 4 END,
    1 + floor(random() * 3)::int,
    1,
    'CMP-' || lpad(n::text, 5, '0'),
    emision,
    emision + 15,
    monto,
    CASE WHEN emision + 15 <= DATE '2026-10-31' THEN emision + 15 END,
    CASE WHEN emision + 15 <= DATE '2026-10-31' THEN monto END
FROM (
    SELECT n,
           3 + floor(random() * 3)::int                                        AS cat,
           DATE '2026-01-02' + floor(random() * 302)::int                      AS emision,
           round((2 + random() * 14)::numeric * 1000000, -3)                   AS monto
    FROM generate_series(1, 250) AS n
) x;

-- Gastos fijos mensuales: contador y alquiler de oficina, vencen el día 10.
INSERT INTO f_movimiento (tipo, id_categoria, id_proveedor, id_centro_costo, id_cuenta,
                          documento, fecha_emision, fecha_venc, monto, fecha_pago, monto_pagado)
SELECT 'EGRESO', g.cat, g.prov, 4, 2,
       g.pref || to_char(mes, 'YYYYMM'),
       mes, mes + 9, g.monto,
       CASE WHEN mes + 9 <= DATE '2026-10-31' THEN mes + 9 END,
       CASE WHEN mes + 9 <= DATE '2026-10-31' THEN g.monto END
FROM (SELECT d::date AS mes
      FROM generate_series(DATE '2026-01-01', DATE '2026-11-01', interval '1 month') AS d) AS meses,
     (VALUES (6, 5, 4500000::numeric, 'HON-'), (7, 6, 7000000::numeric, 'ALQ-')) AS g(cat, prov, monto, pref);

-- Algunos vencimientos abiertos para hoy y mañana (para ver las alertas).
INSERT INTO f_movimiento (tipo, id_categoria, id_cliente, id_proveedor, id_centro_costo, id_cuenta,
                          documento, fecha_emision, fecha_venc, monto)
VALUES
    ('INGRESO', 1, 2, NULL, 1, 1, 'FAC-09001', DATE '2026-10-01', DATE '2026-10-31', 32500000),
    ('INGRESO', 2, 4, NULL, 3, 1, 'FAC-09002', DATE '2026-10-02', DATE '2026-11-01', 18700000),
    ('EGRESO',  3, NULL, 1, 1, 1, 'CMP-09003', DATE '2026-10-17', DATE '2026-10-31',  9800000),
    ('EGRESO',  5, NULL, 4, 2, 1, 'CMP-09004', DATE '2026-10-18', DATE '2026-11-01', 12400000);
