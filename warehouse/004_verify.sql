-- Run after 001_bootstrap.sql, 002_transform.sql, and 003_marts.sql on warehouse_db_test.
-- The transaction rolls all fixture data back.
BEGIN;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'db_oltp', '2026-07-01 00:00+00', '2026-07-02 00:00+00');

INSERT INTO stg.sales_channels (batch_id, source_id, code, name, source_updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 1, 'POS', 'Point of Sale', '2026-07-01 00:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2, 'TT', 'TikTok Shop', '2026-07-01 00:00+00');

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
  return_received_at, subtotal_amount, total_amount, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 1001, 'ORD-1001', '2026-07-01 01:00+00', 'completed', 1, 501, 'Buyer A', 'Bangkok', '10110', NULL, 200, 200, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1002, 'ORD-1002', '2026-07-01 02:00+00', 'cancelled', 1, 501, 'Buyer A Updated', 'Chiang Mai', '50000', NULL, 100, 100, '2026-07-01 04:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1003, 'ORD-1003', '2026-07-01 05:00+00', 'pending', 1, NULL, 'Guest', 'Bangkok', '10110', NULL, 50, 50, '2026-07-01 05:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1004, 'ORD-1004', '2026-07-01 06:00+00', 'completed', 1, NULL, 'Walk-in', NULL, NULL, NULL, 75, 75, '2026-07-01 06:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1005, 'ORD-1005', '2026-07-01 07:00+00', 'refunded', 1, NULL, 'Walk-in', NULL, NULL, '2026-07-03 08:00+00', 125, 125, '2026-07-03 08:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1006, 'ORD-1006', '2026-07-01 09:00+00', 'completed', 2, NULL, 'Online', NULL, NULL, NULL, 300, 300, '2026-07-01 10:00+00');

INSERT INTO stg.order_status_history (batch_id, source_id, order_source_id, new_status, occurred_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 5001, 1001, 'completed', '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 5002, 1005, 'completed', '2026-07-01 07:00+00'),
  ('11111111-1111-1111-1111-111111111111', 5003, 1005, 'completed', '2026-07-01 07:30+00'),
  ('11111111-1111-1111-1111-111111111111', 5004, 1006, 'completed', '2026-07-01 10:00+00');

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

UPDATE dw.fact_order
SET customer_key = 0
WHERE source_system = 'db_oltp' AND buyer_source_id IS NOT NULL;
SELECT etl.backfill_customer_dimension();

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp') <> 6 THEN
    RAISE EXCEPTION 'Expected six idempotent order facts';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp') <> 2 THEN
    RAISE EXCEPTION 'Expected two idempotent order-line facts';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 450 THEN
    RAISE EXCEPTION 'Booked revenue duplicated or incorrect';
  END IF;
  IF (SELECT line_subtotal_amount FROM mart.v_sales_product_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS' AND product_source_id = 10) <> 200 THEN
    RAISE EXCEPTION 'Product revenue or product key incorrect';
  END IF;
  IF (SELECT cancelled_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 100 THEN
    RAISE EXCEPTION 'Cancelled revenue incorrect';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
      AND delivered_order_count = 3 AND delivered_sales_amount = 400
      AND returned_order_count = 1
  ) THEN
    RAISE EXCEPTION 'POS delivered or returned orders were not counted exactly once';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order
    WHERE source_system = 'db_oltp' AND order_source_id = 1004
      AND delivered_at = order_at AND delivery_timestamp_source = 'ORDER_UPDATED_AT_ESTIMATE'
  ) THEN
    RAISE EXCEPTION 'POS current-status fallback did not use order_at';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order
    WHERE source_system = 'db_oltp' AND order_source_id = 1005
      AND current_status = 'refunded'
      AND delivered_at = '2026-07-01 07:00+00'::TIMESTAMPTZ
      AND return_received_at = '2026-07-03 08:00+00'::TIMESTAMPTZ
      AND delivery_timestamp_source = 'HISTORY'
  ) THEN
    RAISE EXCEPTION 'Refunded POS order lost its delivery or physical return event';
  END IF;
  IF EXISTS (
    SELECT 1 FROM dw.fact_order
    WHERE source_system = 'db_oltp' AND order_source_id = 1006
      AND delivered_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'Non-POS completed order was treated as delivered';
  END IF;
  IF (SELECT buyer_name FROM dw.fact_order WHERE source_system = 'db_oltp' AND order_source_id = 1001) <> 'Buyer A' THEN
    RAISE EXCEPTION 'Buyer snapshot incorrect';
  END IF;
  IF (SELECT COUNT(*) FROM dw.dim_customer WHERE source_system = 'db_oltp') <> 1 THEN
    RAISE EXCEPTION 'Customer dimension upsert is not idempotent';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.dim_customer
    WHERE source_system = 'db_oltp' AND customer_source_id = 501
      AND customer_name = 'Buyer A Updated' AND latest_province_name = 'Chiang Mai'
      AND latest_postal_code = '50000'
  ) THEN
    RAISE EXCEPTION 'Latest customer snapshot was not applied';
  END IF;
  IF EXISTS (
    SELECT 1 FROM dw.fact_order
    WHERE source_system = 'db_oltp' AND buyer_source_id IS NOT NULL AND customer_key = 0
  ) THEN
    RAISE EXCEPTION 'Known customer fact uses unknown customer key';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'dw.fact_order'::regclass
      AND conname = 'fact_order_customer_key_fkey' AND contype = 'f'
  ) THEN
    RAISE EXCEPTION 'Customer fact foreign key is missing';
  END IF;
  IF (SELECT customer_key FROM dw.fact_order WHERE source_system = 'db_oltp' AND order_source_id = 1003) <> 0 THEN
    RAISE EXCEPTION 'Guest order should use unknown customer key';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_buyer_daily WHERE business_date = DATE '2026-07-01' AND buyer_name = 'Buyer A') <> 200 THEN
    RAISE EXCEPTION 'Buyer mart incorrect';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_buyer_daily
    WHERE business_date = DATE '2026-07-01' AND buyer_name = 'Buyer A'
      AND customer_name = 'Buyer A Updated' AND latest_province_name = 'Chiang Mai'
  ) THEN
    RAISE EXCEPTION 'Buyer mart customer dimension columns incorrect';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_province_daily WHERE business_date = DATE '2026-07-01' AND province_name = 'Bangkok') <> 250 THEN
    RAISE EXCEPTION 'Province mart incorrect';
  END IF;
  IF (
    SELECT COUNT(DISTINCT buyer_source_id)
    FROM mart.v_sales_buyer_daily
    WHERE business_date = DATE '2026-07-01' AND province_name = 'Bangkok'
      AND booked_order_count > 0
  ) <> 1 THEN
    RAISE EXCEPTION 'Province customer count included guest or double-counted customer';
  END IF;
  IF (SELECT available_quantity FROM mart.v_inventory_daily WHERE business_date = DATE '2026-07-01' AND sku_code = 'SILK-RED') <> 8 THEN
    RAISE EXCEPTION 'Inventory available quantity incorrect';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system)
VALUES ('33333333-3333-3333-3333-333333333333', 'db_oltp');
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
    WHERE source_system = 'db_oltp'
      AND entity_name = 'order_lines'
      AND last_source_id = 2002
      AND last_successful_batch_id = '11111111-1111-1111-1111-111111111111'::UUID
  ) THEN
    RAISE EXCEPTION 'Rejected order-line entity advanced its watermark';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system)
VALUES ('22222222-2222-2222-2222-222222222222', 'db_oltp');
INSERT INTO stg.sales_channels (batch_id, source_id, code, name, source_updated_at)
VALUES ('22222222-2222-2222-2222-222222222222', 2, ' ', 'Invalid channel', '2026-07-02 00:00+00');

SELECT * FROM etl.apply_sales_stock_batch('22222222-2222-2222-2222-222222222222');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '22222222-2222-2222-2222-222222222222') <> 'FAILED' THEN
    RAISE EXCEPTION 'Invalid batch should fail';
  END IF;
  IF (SELECT last_successful_batch_id FROM etl.watermark WHERE source_system = 'db_oltp' AND entity_name = 'sales_channels') <> '11111111-1111-1111-1111-111111111111'::UUID THEN
    RAISE EXCEPTION 'Failed batch advanced watermark';
  END IF;
END;
$$;

ROLLBACK;
