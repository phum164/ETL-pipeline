-- Run after 001_bootstrap.sql, 002_transform.sql, and 003_marts.sql on rm_dw_test.
-- The transaction rolls all fixture data back.
BEGIN;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'rm_oltp', '2026-07-01 00:00+00', '2026-07-02 00:00+00');

INSERT INTO stg.sales_channels (batch_id, source_id, code, name, source_updated_at)
VALUES ('11111111-1111-1111-1111-111111111111', 1, 'POS', 'Point of Sale', '2026-07-01 00:00+00');

INSERT INTO stg.skus (
  batch_id, source_id, sku_code, product_source_id, product_name, category_source_id,
  category_name, unit_cost, selling_price, on_hand_quantity, reserved_quantity,
  min_stock_level, source_updated_at, as_of_at
)
VALUES (
  '11111111-1111-1111-1111-111111111111', 101, 'SILK-RED', 10, 'Red Silk', 20,
  'Silk', 50, 100, 10, 2, 3, '2026-07-01 12:00+00', '2026-07-01 12:00+00'
);

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  buyer_source_id, buyer_name, province_name, postal_code,
  subtotal_amount, total_amount, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 1001, 'ORD-1001', '2026-07-01 01:00+00', 'delivered', 1, 501, 'Buyer A', 'Bangkok', '10110', 200, 200, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1002, 'ORD-1002', '2026-07-01 02:00+00', 'cancelled', 1, 502, 'Buyer B', 'Chiang Mai', NULL, 100, 100, '2026-07-01 04:00+00');

INSERT INTO stg.order_status_history (batch_id, source_id, order_source_id, new_status, occurred_at)
VALUES ('11111111-1111-1111-1111-111111111111', 5001, 1001, 'delivered', '2026-07-01 03:00+00');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 2001, 1001, 101, 2, 100, 0, 200, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2002, 1002, 101, 1, 100, 0, 100, '2026-07-01 04:00+00');

INSERT INTO stg.inventory_movements (
  batch_id, source_id, sku_source_id, movement_at, on_hand_delta, on_hand_before,
  on_hand_after, reserved_before, reserved_after, inventory_version, operation,
  reason, source_name
)
VALUES ('11111111-1111-1111-1111-111111111111', 3001, 101, '2026-07-01 12:00+00', 10, 0, 10, 0, 2, 1, 'RECEIVE', 'opening stock', 'MANUAL');

INSERT INTO stg.sku_on_channel (
  batch_id, sku_source_id, channel_source_id, allocated_quantity,
  allocated_reserved_quantity, safety_stock_quantity, target_quantity,
  remote_quantity, available_quantity, source_updated_at, as_of_at
)
VALUES ('11111111-1111-1111-1111-111111111111', 101, 1, 8, 2, 1, 8, 8, 8, '2026-07-01 12:00+00', '2026-07-01 12:00+00');

SELECT * FROM etl.apply_sales_stock_batch('11111111-1111-1111-1111-111111111111');
SELECT * FROM etl.apply_sales_stock_batch('11111111-1111-1111-1111-111111111111');

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'rm_oltp') <> 2 THEN
    RAISE EXCEPTION 'Expected two idempotent order facts';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'rm_oltp') <> 2 THEN
    RAISE EXCEPTION 'Expected two idempotent order-line facts';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 200 THEN
    RAISE EXCEPTION 'Booked revenue duplicated or incorrect';
  END IF;
  IF (SELECT line_subtotal_amount FROM mart.v_sales_product_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS' AND product_source_id = 10) <> 200 THEN
    RAISE EXCEPTION 'Product revenue or product key incorrect';
  END IF;
  IF (SELECT cancelled_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 100 THEN
    RAISE EXCEPTION 'Cancelled revenue incorrect';
  END IF;
  IF (SELECT delivered_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 200 THEN
    RAISE EXCEPTION 'Delivered revenue incorrect';
  END IF;
  IF (SELECT buyer_name FROM dw.fact_order WHERE source_system = 'rm_oltp' AND order_source_id = 1001) <> 'Buyer A' THEN
    RAISE EXCEPTION 'Buyer snapshot incorrect';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_buyer_daily WHERE business_date = DATE '2026-07-01' AND buyer_name = 'Buyer A') <> 200 THEN
    RAISE EXCEPTION 'Buyer mart incorrect';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_province_daily WHERE business_date = DATE '2026-07-01' AND province_name = 'Bangkok') <> 200 THEN
    RAISE EXCEPTION 'Province mart incorrect';
  END IF;
  IF (SELECT available_quantity FROM mart.v_inventory_daily WHERE business_date = DATE '2026-07-01' AND sku_code = 'SILK-RED') <> 8 THEN
    RAISE EXCEPTION 'Inventory available quantity incorrect';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system)
VALUES ('33333333-3333-3333-3333-333333333333', 'rm_oltp');
INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_subtotal_amount, source_updated_at
)
VALUES ('33333333-3333-3333-3333-333333333333', 2999, 1001, 999, 1, 100, 100, '2026-07-02 00:00+00');

SELECT * FROM etl.apply_sales_stock_batch('33333333-3333-3333-3333-333333333333');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '33333333-3333-3333-3333-333333333333') <> 'SUCCEEDED_WITH_REJECTS' THEN
    RAISE EXCEPTION 'Missing SKU should create a successful batch with rejects';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.rejected_row
    WHERE batch_id = '33333333-3333-3333-3333-333333333333'
      AND entity_name = 'order_lines' AND source_id = 2999
  ) THEN
    RAISE EXCEPTION 'Rejected row audit trail missing';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM etl.watermark
    WHERE source_system = 'rm_oltp'
      AND entity_name = 'order_lines'
      AND last_source_id = 2002
      AND last_successful_batch_id = '11111111-1111-1111-1111-111111111111'::UUID
  ) THEN
    RAISE EXCEPTION 'Rejected order-line entity advanced its watermark';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system)
VALUES ('22222222-2222-2222-2222-222222222222', 'rm_oltp');
INSERT INTO stg.sales_channels (batch_id, source_id, code, name, source_updated_at)
VALUES ('22222222-2222-2222-2222-222222222222', 2, ' ', 'Invalid channel', '2026-07-02 00:00+00');

SELECT * FROM etl.apply_sales_stock_batch('22222222-2222-2222-2222-222222222222');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '22222222-2222-2222-2222-222222222222') <> 'FAILED' THEN
    RAISE EXCEPTION 'Invalid batch should fail';
  END IF;
  IF (SELECT last_successful_batch_id FROM etl.watermark WHERE source_system = 'rm_oltp' AND entity_name = 'sales_channels') <> '11111111-1111-1111-1111-111111111111'::UUID THEN
    RAISE EXCEPTION 'Failed batch advanced watermark';
  END IF;
END;
$$;

ROLLBACK;
