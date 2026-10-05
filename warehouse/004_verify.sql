-- Run after 001_bootstrap.sql, 002_transform.sql, and 003_marts.sql on warehouse_db_test.
-- The transaction rolls all fixture data back.
BEGIN;

DO $$
BEGIN
  IF current_database() <> 'warehouse_db_test' THEN
    RAISE EXCEPTION '004_verify.sql may run only against warehouse_db_test';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('11111111-1111-1111-1111-111111111111', 'db_oltp', '2026-07-01 00:00+00', '2026-07-04 00:00+07');

INSERT INTO stg.sales_channels (batch_id, source_id, code, name, source_updated_at)
VALUES
  ('11111111-1111-1111-1111-111111111111', 1, 'POS', 'Point of Sale', '2026-07-01 00:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2, 'TT', 'TikTok Shop', '2026-07-01 00:00+00'),
  ('11111111-1111-1111-1111-111111111111', 3, 'Facebook', 'Facebook', '2026-07-01 00:00+00');

INSERT INTO stg.skus (
  batch_id, source_id, sku_code, product_source_id, product_name, category_source_id,
  category_name, unit_cost, selling_price, on_hand_quantity, reserved_quantity,
  min_stock_level, source_updated_at, as_of_at
)
VALUES (
  '11111111-1111-1111-1111-111111111111', 101, 'SILK-RED', 10, 'Red Silk', 20,
  'Silk', 50, 100, 10, 2, 3, '2026-07-01 12:00+00', '2026-07-01 12:00+00'
), (
  '11111111-1111-1111-1111-111111111111', 102, 'SILK-UNKNOWN', 11, 'Unknown Category Silk', NULL,
  NULL, 40, 80, 5, 0, 1, '2026-07-01 12:00+00', '2026-07-01 12:00+00'
);

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  buyer_source_id, buyer_name, province_name, postal_code,
  return_received_at, subtotal_amount, total_amount, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 1001, 'ORD-1001', '2026-07-01 01:00+00', 'completed', 1, 501, 'Buyer A', 'Bangkok', '10110', NULL, 215, 215, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1002, 'ORD-1002', '2026-07-01 02:00+00', 'cancelled', 1, 501, 'Buyer A Updated', 'Chiang Mai', '50000', NULL, 100, 100, '2026-07-01 04:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1003, 'ORD-1003', '2026-07-01 05:00+00', 'pending', 1, NULL, 'Guest', 'Bangkok', '10110', NULL, 50, 50, '2026-07-01 05:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1004, 'ORD-1004', '2026-07-01 06:00+00', 'completed', 1, NULL, 'Walk-in', NULL, NULL, NULL, 75, 75, '2026-07-01 06:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1005, 'ORD-1005', '2026-07-01 07:00+00', 'refunded', 1, NULL, 'Walk-in', NULL, NULL, '2026-07-03 08:00+00', 125, 125, '2026-07-03 08:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1006, 'ORD-1006', '2026-07-01 09:00+00', 'completed', 2, NULL, 'Online', NULL, NULL, NULL, 300, 300, '2026-07-01 10:00+00'),
  ('11111111-1111-1111-1111-111111111111', 1007, 'FB-1007', '2026-07-01 09:00+07', 'PAID', 3, NULL, 'CF on time', NULL, NULL, NULL, 100, 100, '2026-07-01 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1008, 'FB-1008', '2026-07-01 08:00+07', 'CANCELLED', 3, NULL, 'Partial payment', NULL, NULL, NULL, 100, 100, '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1009, 'FB-1009', '2026-07-01 07:00+07', 'CANCELLED', 3, NULL, 'Paid late', NULL, NULL, NULL, 100, 100, '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1010, 'FB-1010', '2026-07-01 11:00+07', 'DELIVERED', 3, NULL, 'COD current status changed', NULL, NULL, NULL, 80, 80, '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1011, 'FB-1011', '2026-07-01 12:00+07', 'pending', 3, NULL, 'Invalid legacy deadline', NULL, NULL, NULL, 100, 100, '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1012, 'FB-1012', '2026-07-01 05:00+07', 'PAID', 3, NULL, 'Missing payment evidence', NULL, NULL, NULL, 100, 100, '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 1013, 'FB-1013', '2026-07-01 06:00+07', 'CANCELLED', 3, NULL, 'Known unpaid', NULL, NULL, NULL, 100, 100, '2026-07-03 09:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status,
  channel_source_id, total_amount, deleted_at, source_updated_at
)
VALUES (
  '11111111-1111-1111-1111-111111111111', 1014, 'ORD-1014-DELETED',
  '2026-07-01 13:00+07', 'COMPLETED', 1, 999,
  '2026-07-02 00:00+07', '2026-07-02 00:00+07'
), (
  '11111111-1111-1111-1111-111111111111', 1015, 'FB-1015-REFUND-PROOF',
  '2026-07-01 10:00+07', 'CANCELLED', 3, 100,
  NULL, '2026-07-03 09:00+07'
), (
  '11111111-1111-1111-1111-111111111111', 1016, 'FB-1016-SHORT-DEADLINE',
  '2026-07-01 14:00+07', 'PENDING', 3, 50,
  NULL, '2026-07-03 09:00+07'
);

INSERT INTO stg.order_status_history (
  batch_id, source_id, order_source_id, new_status, action, occurred_at, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 5001, 1001, 'completed', NULL, '2026-07-01 03:00+00', '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 5002, 1005, 'completed', NULL, '2026-07-01 07:00+00', '2026-07-01 07:00+00'),
  ('11111111-1111-1111-1111-111111111111', 5003, 1005, 'completed', NULL, '2026-07-01 07:30+00', '2026-07-01 07:30+00'),
  ('11111111-1111-1111-1111-111111111111', 5004, 1006, 'completed', NULL, '2026-07-01 10:00+00', '2026-07-01 10:00+00'),
  ('11111111-1111-1111-1111-111111111111', 5005, 1010, 'cod', 'choose_cod', '2026-07-01 12:00+07', '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 5006, 1009, 'paid', 'slip_verified', '2026-07-02 08:00+07', '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 5007, 1012, 'paid', 'manual_confirm', '2026-07-01 06:00+07', '2026-07-03 09:00+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 2001, 1001, 101, 2, 100, 0, 200, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2002, 1002, 101, 1, 100, 0, 100, '2026-07-01 04:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2003, 1004, 101, 1, 75, 0, 75, '2026-07-01 06:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2004, 1005, 101, 1, 125, 0, 125, '2026-07-03 08:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2005, 1001, 102, 1, 20, 5, 15, '2026-07-01 03:00+00'),
  ('11111111-1111-1111-1111-111111111111', 2006, 1014, 101, 1, 999, 0, 999, '2026-07-02 00:00+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_subtotal_amount, deleted_at, source_updated_at
)
VALUES (
  '11111111-1111-1111-1111-111111111111', 2007, 1001, 101, 1, 1000,
  1000, '2026-07-02 00:00+07', '2026-07-02 00:00+07'
);

INSERT INTO stg.facebook_reserves (
  batch_id, source_id, order_source_id, created_at, reserved_until, status, deleted_at, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 8001, 1007, '2026-07-01 09:00+07', '2026-07-02 09:00+07', 'converted', NULL, '2026-07-01 09:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8002, 1007, '2026-07-01 18:00+07', '2026-07-02 09:00+07', 'converted', '2026-07-03 09:00+07', '2026-07-03 09:00+07'),
  ('11111111-1111-1111-1111-111111111111', 8003, 1008, '2026-07-01 08:00+07', '2026-07-02 08:00+07', 'converted', NULL, '2026-07-01 08:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8004, 1009, '2026-07-01 07:00+07', '2026-07-02 07:00+07', 'converted', NULL, '2026-07-01 07:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8005, 1010, '2026-07-01 11:00+07', '2026-07-02 11:00+07', 'converted', NULL, '2026-07-01 11:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8006, 1011, '2026-07-01 12:00+07', '2026-07-01 12:00+07', 'converted', NULL, '2026-07-01 12:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8007, 1012, '2026-07-01 05:00+07', '2026-07-02 05:00+07', 'converted', NULL, '2026-07-01 05:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8008, 1013, '2026-07-01 06:00+07', '2026-07-02 06:00+07', 'converted', NULL, '2026-07-01 06:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8009, 1015, '2026-07-01 10:00+07', '2026-07-02 10:00+07', 'converted', NULL, '2026-07-01 10:01+07'),
  ('11111111-1111-1111-1111-111111111111', 8010, 1016, '2026-07-01 14:00+07', '2026-07-01 15:00+07', 'converted', NULL, '2026-07-01 14:01+07');

INSERT INTO stg.payment_transactions (
  batch_id, source_id, order_source_id, amount, current_status, payment_at, verified_at, deleted_at, source_updated_at
)
VALUES
  ('11111111-1111-1111-1111-111111111111', 9001, 1007, 40, 'COMPLETED', '2026-07-01 12:00+07', '2026-07-01 12:05+07', NULL, '2026-07-01 12:05+07'),
  ('11111111-1111-1111-1111-111111111111', 9002, 1007, 60, 'COMPLETED', '2026-07-02 10:00+07', '2026-07-02 08:00+07', NULL, '2026-07-02 08:00+07'),
  ('11111111-1111-1111-1111-111111111111', 9003, 1008, 60, 'COMPLETED', '2026-07-01 10:00+07', '2026-07-01 10:05+07', NULL, '2026-07-01 10:05+07'),
  ('11111111-1111-1111-1111-111111111111', 9004, 1009, 100, 'COMPLETED', '2026-07-02 06:00+07', '2026-07-02 08:00+07', NULL, '2026-07-02 08:00+07'),
  ('11111111-1111-1111-1111-111111111111', 9005, 1015, 100, 'REFUNDED', '2026-07-01 10:30+07', '2026-07-01 10:35+07', NULL, '2026-07-01 10:35+07');

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
  IF (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp') <> 16 THEN
    RAISE EXCEPTION 'Expected sixteen idempotent order facts';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp') <> 7 THEN
    RAISE EXCEPTION 'Expected seven idempotent order-line facts';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 465 THEN
    RAISE EXCEPTION 'Booked revenue duplicated or incorrect';
  END IF;
  IF (SELECT line_subtotal_amount FROM mart.v_sales_product_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS' AND product_source_id = 10) <> 400 THEN
    RAISE EXCEPTION 'Product revenue or product key incorrect';
  END IF;
  IF (SELECT cancelled_sales_amount FROM mart.v_sales_daily WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS') <> 100 THEN
    RAISE EXCEPTION 'Cancelled revenue incorrect';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
      AND delivered_order_count = 3 AND delivered_sales_amount = 415
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
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_delivered_product_category_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
      AND category_source_id = 20 AND category_name = 'Silk'
      AND product_source_id = 10 AND units_sold = 4 AND line_subtotal_amount = 400
  ) THEN
    RAISE EXCEPTION 'Delivered category/product mart omitted delivered POS or later refunded lines';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_delivered_product_category_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
      AND category_source_id IS NULL AND category_name = 'ไม่ระบุหมวดหมู่'
      AND product_source_id = 11 AND units_sold = 1 AND line_subtotal_amount = 15
  ) THEN
    RAISE EXCEPTION 'Unknown category bucket was omitted';
  END IF;
  IF (
    SELECT COALESCE(SUM(line_subtotal_amount), 0)
    FROM mart.v_delivered_product_category_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
  ) <> 415 OR (
    SELECT COALESCE(SUM(line_subtotal_amount), 0)
    FROM mart.v_sales_product_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
  ) <> 415 THEN
    RAISE EXCEPTION 'Delivered category revenue must exactly reconcile to discounted product line revenue';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_social_order WHERE source_system = 'db_oltp') <> 9 THEN
    RAISE EXCEPTION 'Social order fact should contain one row per linked Facebook CF order';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1007
      AND cf_at = '2026-07-01 09:00+07'::TIMESTAMPTZ
      AND payment_due_at = '2026-07-02 09:00+07'::TIMESTAMPTZ
      AND confirmed_paid_amount = 100
      AND paid_in_full_at = '2026-07-02 08:00+07'::TIMESTAMPTZ
      AND is_data_complete AND NOT is_cod AND NOT is_cancelled
      AND snapshot_as_of = '2026-07-04 00:00+07'::TIMESTAMPTZ
  ) THEN
    RAISE EXCEPTION '24-hour due, partial-payment completion, or UTC/Bangkok cutoff handling is incorrect';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_facebook_reserve WHERE source_system = 'db_oltp' AND order_source_id = 1007) <> 2 THEN
    RAISE EXCEPTION 'Soft-deleted linked CF evidence was not retained';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1008 AND is_cancelled AND is_data_complete
      AND confirmed_paid_amount = 60 AND paid_in_full_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Partial verified payments should remain complete but unpaid-in-full';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1009 AND payment_due_at = '2026-07-02 07:00+07'::TIMESTAMPTZ
      AND paid_in_full_at = '2026-07-02 08:00+07'::TIMESTAMPTZ AND is_cancelled AND is_data_complete
  ) THEN
    RAISE EXCEPTION 'Late payment should retain the verified completion timestamp';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1010 AND is_cod AND is_data_complete
      AND LOWER(BTRIM((SELECT current_status FROM dw.fact_order WHERE order_source_id = 1010))) = 'delivered'
  ) THEN
    RAISE EXCEPTION 'COD classification must persist from status history after current status changes';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1011 AND payment_due_at IS NULL
      AND cf_at IS NULL AND NOT is_data_complete
  ) THEN
    RAISE EXCEPTION 'Invalid legacy deadline should retain a fallback cohort as incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1012 AND NOT is_data_complete
      AND paid_in_full_at IS NULL AND confirmed_paid_amount = 0
  ) THEN
    RAISE EXCEPTION 'Paid history without verified transaction evidence should be incomplete';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1013 AND payment_due_at IS NOT NULL
      AND confirmed_paid_amount = 0 AND is_data_complete AND is_cancelled
  ) THEN
    RAISE EXCEPTION 'A valid matured order with no completed payments should be known unpaid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1015 AND confirmed_paid_amount = 0
      AND paid_in_full_at IS NULL AND NOT is_data_complete
  ) THEN
    RAISE EXCEPTION 'A refunded transaction with verification evidence must not be classified as known unpaid';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_status
    WHERE order_source_id = 1016 AND payment_due_at IS NULL
      AND cf_at IS NULL AND NOT is_data_complete
  ) THEN
    RAISE EXCEPTION 'A deadline less than 24 hours after the first CF event must remain unknown';
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
  IF (SELECT booked_sales_amount FROM mart.v_sales_buyer_daily WHERE business_date = DATE '2026-07-01' AND buyer_name = 'Buyer A') <> 215 THEN
    RAISE EXCEPTION 'Buyer mart incorrect';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_buyer_daily
    WHERE business_date = DATE '2026-07-01' AND buyer_name = 'Buyer A'
      AND customer_name = 'Buyer A Updated' AND latest_province_name = 'Chiang Mai'
  ) THEN
    RAISE EXCEPTION 'Buyer mart customer dimension columns incorrect';
  END IF;
  IF (SELECT booked_sales_amount FROM mart.v_sales_province_daily WHERE business_date = DATE '2026-07-01' AND province_name = 'Bangkok') <> 265 THEN
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

-- A later successful full replay upserts the same source evidence instead of
-- duplicating social-order, payment, category, or reserve values.
INSERT INTO etl.load_batch (
  batch_id, source_system, source_window_started_at, source_window_ended_at
)
VALUES (
  '44444444-4444-4444-4444-444444444444', 'db_oltp',
  '2026-07-04 00:00+07', '2026-07-05 00:00+07'
);

INSERT INTO stg.facebook_reserves (
  batch_id, source_id, order_source_id, created_at, reserved_until, status, deleted_at, source_updated_at
)
SELECT
  '44444444-4444-4444-4444-444444444444', source_id, order_source_id, created_at,
  reserved_until, status, deleted_at, source_updated_at
FROM stg.facebook_reserves
WHERE batch_id = '11111111-1111-1111-1111-111111111111';

INSERT INTO stg.payment_transactions (
  batch_id, source_id, order_source_id, amount, current_status,
  payment_at, verified_at, deleted_at, source_updated_at
)
SELECT
  '44444444-4444-4444-4444-444444444444', source_id, order_source_id, amount,
  current_status, payment_at, verified_at, deleted_at, source_updated_at
FROM stg.payment_transactions
WHERE batch_id = '11111111-1111-1111-1111-111111111111';

SELECT * FROM etl.apply_sales_stock_batch('44444444-4444-4444-4444-444444444444');

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM dw.fact_facebook_reserve WHERE source_system = 'db_oltp') <> 10
    OR (SELECT COUNT(*) FROM dw.fact_payment_transaction WHERE source_system = 'db_oltp') <> 5
    OR (SELECT COUNT(*) FROM dw.fact_social_order WHERE source_system = 'db_oltp') <> 9 THEN
    RAISE EXCEPTION 'A later full replay duplicated retained social evidence';
  END IF;
  IF (SELECT confirmed_paid_amount FROM mart.v_social_order_status WHERE order_source_id = 1007) <> 100 THEN
    RAISE EXCEPTION 'A later full replay duplicated confirmed payment value';
  END IF;
  IF (
    SELECT COALESCE(SUM(line_subtotal_amount), 0)
    FROM mart.v_delivered_product_category_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
  ) <> 415 THEN
    RAISE EXCEPTION 'A later full replay duplicated delivered category revenue';
  END IF;
  IF (
    SELECT COALESCE(SUM(line_subtotal_amount), 0)
    FROM mart.v_delivered_sku_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
  ) <> 415 OR (
    SELECT COALESCE(SUM(units_sold), 0)
    FROM mart.v_delivered_sku_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
  ) <> 5 THEN
    RAISE EXCEPTION 'SKU delivery view duplicated or omitted delivered lines on replay';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (
  batch_id, source_system, source_window_started_at, source_window_ended_at
)
VALUES (
  '33333333-3333-3333-3333-333333333333', 'db_oltp',
  '2026-07-05 00:00+07', '2026-07-06 00:00+07'
);
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
      AND last_source_id = 2004
      AND last_successful_batch_id = '11111111-1111-1111-1111-111111111111'::UUID
  ) THEN
    RAISE EXCEPTION 'Rejected order-line entity advanced its watermark';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (
  batch_id, source_system, source_window_started_at, source_window_ended_at
)
VALUES (
  '22222222-2222-2222-2222-222222222222', 'db_oltp',
  '2026-07-06 00:00+07', '2026-07-07 00:00+07'
);
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
