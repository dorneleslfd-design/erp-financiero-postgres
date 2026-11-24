-- =====================================================================
-- ERP financiero — consultas de ejemplo
-- =====================================================================

SET search_path TO erp;
SET erp.hoy = '2026-10-31';   -- fecha de referencia de los datos de ejemplo

-- 1. Flujo de caja mensual con saldo acumulado
SELECT * FROM v_flujo_caja_mensual;

-- 2. Cuentas por cobrar por antigüedad
SELECT * FROM v_cuentas_por_cobrar ORDER BY total_abierto DESC;

-- 3. Lo que vence hoy o mañana (lo que enviaría el aviso automático por correo)
SELECT * FROM v_alertas_vencimiento ORDER BY fecha_venc, tipo;

-- 4. Margen por obra
SELECT * FROM v_margen_centro_costo ORDER BY margen DESC;

-- 5. Estado de resultados del año por grupo
SELECT grupo, SUM(resultado) AS resultado_anual
FROM v_resultado_mensual
GROUP BY grupo
ORDER BY resultado_anual DESC;

-- 6. Registrar un pago (el procedimiento valida que exista y que no esté pagado)
-- CALL sp_registrar_pago(10, DATE '2026-10-31', 25000000);
