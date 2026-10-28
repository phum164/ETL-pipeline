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

-- ---------------------------------------------------------------------
-- Dashboard v2 marts: fixture + assertions. Own batches (55555555-..., replay
-- 66666666-...) and own source ids (orders 3001-3014, lines 4001-4018, history
-- 5101+, reserves 8101+, payments 9101, customers 601-604, SKUs 103-104, product
-- 12) so the assertions above are unaffected. Reuses channels 1/2/3, SKUs 101/102.
-- Business dates are Asia/Bangkok. Scenario map (order -> what it proves):
--   3001 TT   cust 601  delivered 08-02 (order 08-01)   new customer, order/delivery date differ
--   3002 TT   cust 601  carrier_picked_up               IN_TRANSIT + shipped_at
--   3003 FB   cust 602  delivered; 2 SKUs of product 12 once-per-order pair + order_count
--   3004 POS  cust 602  completed THEN cancelled (2 cancel events)  gross vs net delivered
--   3005 POS  walk-in   completed                        customer_key 0 kept in sums
--   3006 FB   cust 603  delivered 2026-05                lapsed customer
--   3007 TT   cust 602  delivered, return received       repeat customer + returned_order_count
--   3008 TT   cust 601  DELETED order                    excluded everywhere
--   3009 TT   walk-in   ready_to_ship                    AWAITING_SHIPMENT
--   3010 TT   walk-in   legacy upper-case IN_TRANSIT     IN_TRANSIT via legacy value
--   3011 TT   walk-in   delivered then return_requested  RETURN
--   3012 FB   cust 604  pending CF, unpaid               CF raw facts, eligible
--   3013 FB   walk-in   cod                              CF not eligible
--   3014 FB   walk-in   paid late                        CF paid after deadline
--   line 4012 = DELETED line on live order 3001          excluded from line marts
-- ---------------------------------------------------------------------
INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('55555555-5555-5555-5555-555555555555', 'db_oltp', '2026-08-01 00:00+07', '2026-08-06 00:00+07');

INSERT INTO stg.skus (
  batch_id, source_id, sku_code, product_source_id, product_name, category_source_id,
  category_name, unit_cost, selling_price, on_hand_quantity, reserved_quantity,
  min_stock_level, source_updated_at, as_of_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 103, 'COTTON-A', 12, 'Cotton', 21, 'Cotton', 30, 100, 20, 5, 3, '2026-08-05 12:00+07', '2026-08-05 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 104, 'COTTON-B', 12, 'Cotton', 21, 'Cotton', 30, 100, 0, 0, 1, '2026-08-04 12:00+07', '2026-08-04 12:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  buyer_source_id, buyer_name, province_name, postal_code, return_received_at,
  subtotal_amount, total_amount, source_updated_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 3001, 'ORD-3001', '2026-08-01 10:00+07', 'delivered', 2, 601, 'Cust New', 'Chiang Mai', NULL, NULL, 300, 300, '2026-08-02 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3002, 'ORD-3002', '2026-08-02 11:00+07', 'carrier_picked_up', 2, 601, 'Cust New', 'Chiang Mai', NULL, NULL, 150, 150, '2026-08-02 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3003, 'FB-3003', '2026-08-02 09:00+07', 'delivered', 3, 602, 'Cust Repeat', 'Bangkok', NULL, NULL, 250, 250, '2026-08-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3004, 'ORD-3004', '2026-08-03 14:00+07', 'cancelled', 1, 602, 'Cust Repeat', 'Bangkok', NULL, NULL, 500, 500, '2026-08-03 16:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3005, 'ORD-3005', '2026-08-03 12:00+07', 'completed', 1, NULL, 'Walk-in', NULL, NULL, NULL, 100, 100, '2026-08-03 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3006, 'FB-3006', '2026-05-01 10:00+07', 'delivered', 3, 603, 'Cust Lapsed', 'Khon Kaen', NULL, NULL, 400, 400, '2026-05-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3007, 'ORD-3007', '2026-07-10 10:00+07', 'delivered', 2, 602, 'Cust Repeat', 'Bangkok', NULL, '2026-07-20 10:00+07', 200, 200, '2026-07-20 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3009, 'ORD-3009', '2026-08-03 08:00+07', 'ready_to_ship', 2, NULL, 'Walk-in', NULL, NULL, NULL, 80, 80, '2026-08-03 08:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3010, 'ORD-3010', '2026-08-03 08:30+07', 'IN_TRANSIT', 2, NULL, 'Walk-in', NULL, NULL, NULL, 60, 60, '2026-08-03 09:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3011, 'ORD-3011', '2026-08-01 11:00+07', 'return_requested', 2, NULL, 'Walk-in', NULL, NULL, NULL, 70, 70, '2026-08-02 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3012, 'FB-3012', '2026-08-01 08:00+07', 'pending', 3, 604, 'Cust CF', 'Phuket', NULL, NULL, 300, 300, '2026-08-01 08:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3013, 'FB-3013', '2026-08-01 09:00+07', 'cod', 3, NULL, 'Walk-in', NULL, NULL, NULL, 90, 90, '2026-08-01 09:00+07'),
  ('55555555-5555-5555-5555-555555555555', 3014, 'FB-3014', '2026-08-01 10:00+07', 'paid', 3, NULL, 'Walk-in', NULL, NULL, NULL, 100, 100, '2026-08-02 11:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  buyer_source_id, buyer_name, province_name, total_amount, deleted_at, source_updated_at
)
VALUES (
  '55555555-5555-5555-5555-555555555555', 3008, 'ORD-3008-DELETED', '2026-08-01 13:00+07',
  'delivered', 2, 601, 'Cust New', 'Chiang Mai', 999, '2026-08-02 00:00+07', '2026-08-02 00:00+07'
);

INSERT INTO stg.order_status_history (
  batch_id, source_id, order_source_id, new_status, action, reason, occurred_at, source_updated_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 5101, 3001, 'delivered', NULL, NULL, '2026-08-02 10:00+07', '2026-08-02 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5102, 3002, 'carrier_picked_up', NULL, NULL, '2026-08-02 12:00+07', '2026-08-02 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5103, 3003, 'delivered', NULL, NULL, '2026-08-03 10:00+07', '2026-08-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5104, 3004, 'completed', NULL, NULL, '2026-08-03 14:05+07', '2026-08-03 14:05+07'),
  ('55555555-5555-5555-5555-555555555555', 5105, 3004, 'cancelled', 'customer_request', 'Customer requested cancellation', '2026-08-03 15:00+07', '2026-08-03 15:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5106, 3004, 'cancelled', 'void', 'Duplicate order', '2026-08-03 16:00+07', '2026-08-03 16:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5107, 3005, 'completed', NULL, NULL, '2026-08-03 12:00+07', '2026-08-03 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5108, 3006, 'delivered', NULL, NULL, '2026-05-03 10:00+07', '2026-05-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5109, 3007, 'delivered', NULL, NULL, '2026-07-12 10:00+07', '2026-07-12 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5110, 3010, 'IN_TRANSIT', NULL, NULL, '2026-08-03 09:00+07', '2026-08-03 09:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5111, 3011, 'delivered', NULL, NULL, '2026-08-01 12:00+07', '2026-08-01 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 5112, 3011, 'return_requested', NULL, NULL, '2026-08-02 12:00+07', '2026-08-02 12:00+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, source_updated_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 4001, 3001, 103, 2, 100, 0, 200, '2026-08-02 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4002, 3001, 101, 1, 100, 0, 100, '2026-08-02 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4003, 3002, 103, 1, 150, 0, 150, '2026-08-02 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4004, 3003, 101, 1, 150, 0, 150, '2026-08-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4005, 3003, 103, 1, 50, 0, 50, '2026-08-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4006, 3003, 104, 1, 50, 0, 50, '2026-08-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4007, 3004, 101, 1, 500, 0, 500, '2026-08-03 16:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4008, 3005, 102, 1, 100, 0, 100, '2026-08-03 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4009, 3006, 101, 1, 400, 0, 400, '2026-05-03 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4010, 3007, 101, 1, 200, 0, 200, '2026-07-20 10:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4011, 3008, 101, 1, 999, 0, 999, '2026-08-02 00:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4013, 3009, 103, 1, 80, 0, 80, '2026-08-03 08:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4014, 3010, 102, 1, 60, 0, 60, '2026-08-03 09:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4015, 3011, 102, 1, 70, 0, 70, '2026-08-02 12:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4016, 3012, 103, 1, 300, 0, 300, '2026-08-01 08:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4017, 3013, 102, 1, 90, 0, 90, '2026-08-01 09:00+07'),
  ('55555555-5555-5555-5555-555555555555', 4018, 3014, 104, 1, 100, 0, 100, '2026-08-02 11:00+07');

-- Soft-deleted line on a live order (order 3001).
INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_subtotal_amount, deleted_at, source_updated_at
)
VALUES (
  '55555555-5555-5555-5555-555555555555', 4012, 3001, 101, 1, 1000,
  1000, '2026-08-02 00:00+07', '2026-08-02 00:00+07'
);

INSERT INTO stg.facebook_reserves (
  batch_id, source_id, order_source_id, keyword, sku_source_id, quantity,
  created_at, reserved_until, status, deleted_at, source_updated_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 8101, 3012, 'CF-KEY-12', 103, 1, '2026-08-01 08:00+07', '2026-08-02 08:00+07', 'converted', NULL, '2026-08-01 08:01+07'),
  ('55555555-5555-5555-5555-555555555555', 8102, 3013, 'COD-KEY-13', 999999, 2, '2026-08-01 09:00+07', '2026-08-02 09:00+07', 'converted', NULL, '2026-08-01 09:01+07'),
  ('55555555-5555-5555-5555-555555555555', 8103, 3014, NULL, 104, 1, '2026-08-01 10:00+07', '2026-08-02 10:00+07', 'converted', NULL, '2026-08-01 10:01+07');

INSERT INTO stg.payment_transactions (
  batch_id, source_id, order_source_id, amount, current_status, payment_method_source_id,
  payment_method_name, payment_at, verified_at, deleted_at, source_updated_at
)
VALUES
  ('55555555-5555-5555-5555-555555555555', 9101, 3014, 100, 'COMPLETED', 41, 'PromptPay', '2026-08-02 10:55+07', '2026-08-02 11:00+07', NULL, '2026-08-02 11:00+07'),
  ('55555555-5555-5555-5555-555555555555', 9102, 3001, 40, 'COMPLETED', 42, 'Bank transfer', '2026-08-02 09:00+07', '2026-08-02 09:05+07', NULL, '2026-08-02 09:05+07'),
  ('55555555-5555-5555-5555-555555555555', 9103, 3001, 60, 'completed', 42, 'Bank transfer', '2026-08-02 09:30+07', '2026-08-02 09:35+07', NULL, '2026-08-02 09:35+07'),
  ('55555555-5555-5555-5555-555555555555', 9104, 3001, 20, 'pending', 42, 'Bank transfer', '2026-08-02 09:40+07', '2026-08-02 09:00+07', NULL, '2026-08-02 09:40+07'),
  ('55555555-5555-5555-5555-555555555555', 9105, 3001, 0, 'completed', 42, 'Bank transfer', '2026-08-02 09:45+07', '2026-08-02 09:01+07', NULL, '2026-08-02 09:45+07'),
  ('55555555-5555-5555-5555-555555555555', 9106, 3001, 25, 'completed', 42, 'Bank transfer', '2026-08-02 09:50+07', '2026-08-02 09:02+07', '2026-08-02 09:51+07', '2026-08-02 09:51+07');

SELECT * FROM etl.apply_sales_stock_batch('55555555-5555-5555-5555-555555555555');

-- ---------------------------------------------------------------------
-- Assertions: one assertion per view behaviour (A1..A10), then cross-mart
-- reconciliation, privacy and a full-replay idempotency check.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '55555555-5555-5555-5555-555555555555') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Dashboard fixture batch must succeed without rejects';
  END IF;

  -- A1 v_order_cohort_daily ------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_cohort_daily
    WHERE business_date = DATE '2026-08-01' AND channel_code = 'TT'
      AND order_count_all = 2 AND booked_order_count = 2 AND booked_sales_amount = 370
      AND cancelled_order_count = 0 AND delivered_order_count = 2 AND delivered_sales_amount = 370
      AND undelivered_order_count = 0 AND returned_order_count = 0
  ) THEN
    RAISE EXCEPTION 'A1: TikTok 2026-08-01 cohort wrong (deleted order must be excluded; order-date cohort counts later delivery)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_cohort_daily
    WHERE business_date = DATE '2026-08-01' AND channel_code = 'Facebook'
      AND order_count_all = 3 AND booked_order_count = 3 AND booked_sales_amount = 490
      AND delivered_order_count = 0 AND undelivered_order_count = 3
  ) THEN
    RAISE EXCEPTION 'A1: Facebook 2026-08-01 cohort wrong';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_cohort_daily
    WHERE business_date = DATE '2026-08-03' AND channel_code = 'POS'
      AND order_count_all = 2 AND booked_order_count = 1 AND booked_sales_amount = 100
      AND cancelled_order_count = 1 AND cancelled_sales_amount = 500
      AND delivered_order_count = 1 AND delivered_sales_amount = 100 AND undelivered_order_count = 0
  ) THEN
    RAISE EXCEPTION 'A1: POS 2026-08-03 cohort must be net of the later-cancelled delivered order';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_cohort_daily
    WHERE business_date = DATE '2026-07-10' AND channel_code = 'TT'
      AND booked_order_count = 1 AND delivered_order_count = 1 AND returned_order_count = 1
  ) THEN
    RAISE EXCEPTION 'A1: returned order was not counted in its order-date delivered cohort';
  END IF;
  -- documents the divergence: the legacy daily mart keeps cancelled-after-delivery gross
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_daily
    WHERE business_date = DATE '2026-08-03' AND channel_code = 'POS'
      AND delivered_order_count = 2 AND delivered_sales_amount = 600
  ) THEN
    RAISE EXCEPTION 'A1/A2: legacy v_sales_daily delivered_* is expected to retain the cancelled-after-delivery order (gross)';
  END IF;

  -- A2 v_delivered_net_daily -----------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_delivered_net_daily
    WHERE business_date = DATE '2026-08-03' AND channel_code = 'POS'
      AND delivered_order_count = 1 AND delivered_sales_amount = 100
  ) THEN
    RAISE EXCEPTION 'A2: cancelled-after-delivery POS order must be excluded from net delivered sales';
  END IF;
  IF (
    SELECT COUNT(*) FROM (VALUES
      (DATE '2026-08-01', 'TT', 1::BIGINT, 70::NUMERIC),
      (DATE '2026-08-02', 'TT', 1, 300),
      (DATE '2026-08-03', 'Facebook', 1, 250),
      (DATE '2026-07-12', 'TT', 1, 200),
      (DATE '2026-05-03', 'Facebook', 1, 400)
    ) AS expected(business_date, channel_code, n, amount)
    JOIN mart.v_delivered_net_daily AS v
      ON v.business_date = expected.business_date AND v.channel_code = expected.channel_code
     AND v.delivered_order_count = expected.n AND v.delivered_sales_amount = expected.amount
  ) <> 5 THEN
    RAISE EXCEPTION 'A2: net delivered rows must be dated by DELIVERY date, not order date';
  END IF;

  -- A3 v_customer_profile --------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_customer_profile
    WHERE buyer_source_id = 601 AND lifetime_order_count = 2 AND lifetime_sales_amount = 450
      AND first_order_date = DATE '2026-08-01' AND last_order_date = DATE '2026-08-02'
      AND first_channel_code = 'TT' AND channel_codes = ARRAY['TT']::TEXT[]
  ) THEN
    RAISE EXCEPTION 'A3: new customer 601 profile wrong (deleted order must not count)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_customer_profile
    WHERE buyer_source_id = 602 AND lifetime_order_count = 2 AND lifetime_sales_amount = 450
      AND first_order_date = DATE '2026-07-10' AND last_order_date = DATE '2026-08-02'
      AND first_channel_code = 'TT' AND channel_codes = ARRAY['Facebook', 'TT']::TEXT[]
  ) THEN
    RAISE EXCEPTION 'A3: repeat customer 602 profile wrong (cancelled order must not count)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_customer_profile
    WHERE buyer_source_id = 603 AND lifetime_order_count = 1 AND lifetime_sales_amount = 400
      AND first_order_date = DATE '2026-05-01' AND last_order_date = DATE '2026-05-01'
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_customer_profile
    WHERE buyer_source_id = 604 AND lifetime_order_count = 1 AND lifetime_sales_amount = 300
  ) THEN
    RAISE EXCEPTION 'A3: lapsed/CF customer profile wrong';
  END IF;
  IF EXISTS (SELECT 1 FROM mart.v_customer_profile WHERE customer_key = 0)
     OR EXISTS (SELECT 1 FROM mart.v_customer_profile GROUP BY customer_key HAVING COUNT(*) > 1) THEN
    RAISE EXCEPTION 'A3: unknown customer leaked into the profile or a customer has several rows';
  END IF;

  -- A4 v_customer_purchase_line --------------------------------------------
  IF (SELECT COUNT(*) FROM mart.v_customer_purchase_line WHERE order_source_id BETWEEN 3001 AND 3014) <> 16 THEN
    RAISE EXCEPTION 'A4: expected 16 retained lines (deleted order and deleted line excluded)';
  END IF;
  IF EXISTS (
    SELECT 1 FROM mart.v_customer_purchase_line
    WHERE order_source_id = 3008 OR line_subtotal_amount IN (999, 1000)
  ) THEN
    RAISE EXCEPTION 'A4: deleted order/line leaked into purchase lines';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_customer_purchase_line
    WHERE order_source_id = 3004 AND is_cancelled AND is_delivered
  ) THEN
    RAISE EXCEPTION 'A4: cancelled order lines must be kept and flagged';
  END IF;

  -- A5 v_product_customer_daily --------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_customer_daily
    WHERE business_date = DATE '2026-08-02' AND channel_code = 'Facebook'
      AND product_source_id = 12 AND buyer_source_id = 602 AND province_name = 'Bangkok'
      AND order_count = 1 AND units_sold = 2 AND line_subtotal_amount = 100
  ) THEN
    RAISE EXCEPTION 'A5: two SKUs of one product in one order must give order_count 1, units 2';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_customer_daily
    WHERE business_date = DATE '2026-08-03' AND channel_code = 'POS'
      AND product_source_id = 11 AND customer_key = 0 AND line_subtotal_amount = 100
  ) THEN
    RAISE EXCEPTION 'A5: walk-in (customer_key 0) must stay in sums so the mart reconciles';
  END IF;
  IF EXISTS (
    SELECT 1 FROM mart.v_product_customer_daily
    WHERE (business_date = DATE '2026-08-03' AND channel_code = 'POS' AND product_source_id = 10)
       OR line_subtotal_amount IN (999, 1000)
  ) THEN
    RAISE EXCEPTION 'A5: cancelled/deleted lines leaked into customer-product mart';
  END IF;

  -- A6 v_product_pair_daily ------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_pair_daily
    WHERE business_date = DATE '2026-08-01' AND channel_code = 'TT'
      AND product_a_source_id = 10 AND product_b_source_id = 12 AND order_count = 1
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_product_pair_daily
    WHERE business_date = DATE '2026-08-02' AND channel_code = 'Facebook'
      AND product_a_source_id = 10 AND product_b_source_id = 12 AND order_count = 1
  ) THEN
    RAISE EXCEPTION 'A6: a pair must be counted once per order even with two SKUs of the same product';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_pair_daily
    WHERE business_date = DATE '2026-07-01' AND channel_code = 'POS'
      AND product_a_source_id = 10 AND product_b_source_id = 11 AND order_count = 1
  ) THEN
    RAISE EXCEPTION 'A6: earlier fixture order 1001 should yield pair (10, 11)';
  END IF;
  IF EXISTS (SELECT 1 FROM mart.v_product_pair_daily WHERE product_a_source_id >= product_b_source_id) THEN
    RAISE EXCEPTION 'A6: pairs must be unordered with a < b';
  END IF;

  -- A7 v_product_stock_latest ----------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_stock_latest
    WHERE product_source_id = 12 AND sku_count = 2 AND out_of_stock_sku_count = 1
      AND on_hand_quantity = 20 AND reserved_quantity = 5 AND available_quantity = 15
      AND snapshot_date_key = 20260805 AND oldest_snapshot_date_key = 20260804
      AND stale_sku_count = 1
  ) THEN
    RAISE EXCEPTION 'A7: product stock must expose mixed snapshot ages and stale SKU count';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_product_stock_latest
    WHERE product_source_id = 11 AND sku_count = 1 AND available_quantity = 5
      AND snapshot_date_key = 20260701 AND stale_sku_count = 1
  ) THEN
    RAISE EXCEPTION 'A7: older single-SKU product must be flagged stale against the newest snapshot';
  END IF;

  -- A8 v_order_operational_detail ------------------------------------------
  IF (
    SELECT COUNT(*) FROM (VALUES
      (3001, 'DELIVERED'), (3002, 'IN_TRANSIT'), (3003, 'DELIVERED'), (3004, 'CANCELLED'),
      (3005, 'DELIVERED'), (3006, 'DELIVERED'), (3007, 'DELIVERED'), (3009, 'AWAITING_SHIPMENT'),
      (3010, 'IN_TRANSIT'), (3011, 'RETURN'), (3012, 'OPEN'), (3013, 'OPEN'), (3014, 'OPEN')
    ) AS expected(order_source_id, stage)
    JOIN mart.v_order_operational_detail AS v
      ON v.order_source_id = expected.order_source_id AND v.fulfillment_stage = expected.stage
  ) <> 13 THEN
    RAISE EXCEPTION 'A8: fulfillment_stage mapping wrong (check carrier_picked_up / legacy IN_TRANSIT / ready_to_ship)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_operational_detail
    WHERE order_source_id = 3002 AND shipped_at = '2026-08-02 12:00+07'::TIMESTAMPTZ
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_order_operational_detail
    WHERE order_source_id = 3010 AND shipped_at = '2026-08-03 09:00+07'::TIMESTAMPTZ
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_order_operational_detail
    WHERE order_source_id = 3004 AND cancelled_at = '2026-08-03 16:00+07'::TIMESTAMPTZ
  ) THEN
    RAISE EXCEPTION 'A8: shipped_at / cancelled_at derived from status events incorrectly';
  END IF;
  IF EXISTS (SELECT 1 FROM mart.v_order_operational_detail WHERE order_source_id = 3008)
     OR (SELECT COUNT(*) FROM mart.v_order_operational_detail WHERE order_source_id BETWEEN 3001 AND 3014) <> 13 THEN
    RAISE EXCEPTION 'A8: deleted order leaked or order multiplied';
  END IF;

  -- A9 v_order_cancellation ------------------------------------------------
  IF (SELECT COUNT(*) FROM mart.v_order_cancellation WHERE order_source_id BETWEEN 3001 AND 3014) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM mart.v_order_cancellation
       WHERE order_source_id = 3004 AND total_amount = 500
         AND cancelled_at = '2026-08-03 16:00+07'::TIMESTAMPTZ AND cancel_action = 'void'
     ) THEN
    RAISE EXCEPTION 'A9: one row per cancelled order using the LATEST cancel event';
  END IF;

  -- A10 v_social_order_action ----------------------------------------------
  IF (SELECT COUNT(*) FROM mart.v_social_order_action WHERE order_source_id BETWEEN 3001 AND 3014) <> 3
     OR EXISTS (SELECT 1 FROM mart.v_social_order_action WHERE order_source_id IN (3003, 3006)) THEN
    RAISE EXCEPTION 'A10: only Facebook orders with CF reserve evidence belong in the CF action view';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_action
    WHERE order_source_id = 3012 AND buyer_source_id = 604 AND channel_code = 'Facebook'
      AND payment_due_at = '2026-08-02 08:00+07'::TIMESTAMPTZ
      AND required_amount = 300 AND confirmed_paid_amount = 0 AND outstanding_amount = 300
      AND paid_in_full_at IS NULL AND is_eligible AND NOT is_cod AND is_data_complete
      AND primary_product_source_id = 12 AND line_count = 1
  ) THEN
    RAISE EXCEPTION 'A10: unpaid CF order facts wrong';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_action
    WHERE order_source_id = 3013 AND is_cod AND NOT is_eligible
  ) THEN
    RAISE EXCEPTION 'A10: COD CF order must be marked not eligible';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_action
    WHERE order_source_id = 3014 AND is_eligible AND outstanding_amount = 0
      AND payment_due_at = '2026-08-02 10:00+07'::TIMESTAMPTZ
      AND paid_in_full_at = '2026-08-02 11:00+07'::TIMESTAMPTZ
      AND paid_in_full_at > payment_due_at
  ) THEN
    RAISE EXCEPTION 'A10: paid-late CF order must expose raw paid_in_full_at after payment_due_at';
  END IF;
  -- the view must stay cutoff-free so the API assesses with its own cutoff
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'mart' AND table_name = 'v_social_order_action'
      AND column_name IN ('snapshot_as_of', 'is_overdue_unpaid', 'days_overdue')
  ) THEN
    RAISE EXCEPTION 'A10: cutoff-dependent columns must not be baked into the view';
  END IF;

  -- B1 cancellation reason is selected from the latest cancel event --------
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_order_cancellation
    WHERE order_source_id = 3004 AND cancel_reason = 'Duplicate order'
  ) THEN
    RAISE EXCEPTION 'B1: cancellation view must return the latest event reason';
  END IF;

  -- B2 payment method grain and confirmed-payment predicate ----------------
  IF (SELECT COUNT(*) FROM mart.v_order_payment_method WHERE order_source_id IN (3001, 3014)) <> 2
     OR EXISTS (
       SELECT source_system, order_source_id, payment_method_source_id
       FROM mart.v_order_payment_method
       WHERE order_source_id IN (3001, 3014)
       GROUP BY source_system, order_source_id, payment_method_source_id
       HAVING COUNT(*) > 1
     )
     OR NOT EXISTS (
       SELECT 1 FROM mart.v_order_payment_method
       WHERE order_source_id = 3001 AND payment_method_source_id = 42
         AND payment_method_name = 'Bank transfer'
         AND confirmed_transaction_count = 2 AND confirmed_paid_amount = 100
         AND first_verified_at = '2026-08-02 09:05+07'::TIMESTAMPTZ
     ) THEN
    RAISE EXCEPTION 'B2: payment method grain or confirmed payment values are wrong';
  END IF;

  -- B3 reserve grain, nullable SKU lookup, and optional keyword -------------
  IF (SELECT COUNT(*) FROM mart.v_social_order_reserve WHERE reserve_source_id BETWEEN 8101 AND 8103) <> 3
     OR EXISTS (
       SELECT reserve_source_id FROM mart.v_social_order_reserve
       WHERE reserve_source_id BETWEEN 8101 AND 8103
       GROUP BY reserve_source_id HAVING COUNT(*) <> 1
     ) THEN
    RAISE EXCEPTION 'B3: social reserve view must keep exactly one row per reserve';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_reserve
    WHERE reserve_source_id = 8101 AND keyword = 'CF-KEY-12' AND quantity = 1
      AND reserve_status = 'converted'
      AND created_at = '2026-08-01 08:00+07'::TIMESTAMPTZ
      AND reserved_until = '2026-08-02 08:00+07'::TIMESTAMPTZ
      AND sku_code = 'COTTON-A' AND product_source_id = 12 AND product_name = 'Cotton'
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_reserve
    WHERE reserve_source_id = 8102 AND keyword = 'COD-KEY-13' AND quantity = 2
      AND sku_key IS NULL AND sku_code IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_social_order_reserve
    WHERE reserve_source_id = 8103 AND keyword IS NULL AND quantity = 1
      AND sku_code = 'COTTON-B' AND product_source_id = 12
  ) THEN
    RAISE EXCEPTION 'B3: reserve keyword, quantity, status, timestamps, or nullable SKU values are wrong';
  END IF;

  -- Privacy: buyer_name / customer_name only in the profile view -----------
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name IN (
        'v_order_cohort_daily', 'v_delivered_net_daily', 'v_customer_purchase_line',
        'v_product_customer_daily', 'v_product_pair_daily', 'v_product_stock_latest',
        'v_order_operational_detail', 'v_order_cancellation', 'v_social_order_action',
        'v_order_payment_method', 'v_social_order_reserve', 'v_promotion',
        'v_sales_promotion_daily'
      )
      AND column_name IN ('buyer_name', 'customer_name', 'code')
  ) THEN
    RAISE EXCEPTION 'Privacy: promotion and non-profile marts must not expose restricted names or promotion codes';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Cross-mart reconciliation (each condition must find ZERO mismatches).
-- Both sides are aggregated to the same grain and FULL-joined so rows that
-- exist on one side only are caught. Includes ALL earlier fixture data.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM mart.v_order_cohort_daily AS c
    FULL JOIN (
      SELECT date_key, channel_key,
             SUM(booked_order_count) AS booked_order_count,
             SUM(booked_sales_amount) AS booked_sales_amount
      FROM mart.v_sales_daily
      GROUP BY date_key, channel_key
    ) AS s ON s.date_key = c.date_key AND s.channel_key = c.channel_key
    WHERE COALESCE(c.booked_order_count, 0) <> COALESCE(s.booked_order_count, 0)
       OR COALESCE(c.booked_sales_amount, 0) <> COALESCE(s.booked_sales_amount, 0)
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_order_cohort_daily booked_* differs from v_sales_daily';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      SELECT date_key, channel_key, product_source_id,
             SUM(units_sold) AS units, SUM(line_subtotal_amount) AS amount
      FROM mart.v_product_customer_daily GROUP BY date_key, channel_key, product_source_id
    ) AS m
    FULL JOIN (
      SELECT date_key, channel_key, product_source_id,
             SUM(units_sold) AS units, SUM(line_subtotal_amount) AS amount
      FROM mart.v_sales_product_daily GROUP BY date_key, channel_key, product_source_id
    ) AS p USING (date_key, channel_key, product_source_id)
    WHERE m.units IS DISTINCT FROM p.units OR m.amount IS DISTINCT FROM p.amount
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_product_customer_daily differs from v_sales_product_daily';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      SELECT date_key, channel_key, sku_key,
             SUM(quantity) AS units, SUM(line_subtotal_amount) AS amount
      FROM mart.v_customer_purchase_line WHERE NOT is_cancelled
      GROUP BY date_key, channel_key, sku_key
    ) AS l
    FULL JOIN (
      SELECT date_key, channel_key, sku_key,
             SUM(units_sold) AS units, SUM(line_subtotal_amount) AS amount
      FROM mart.v_sales_sku_daily GROUP BY date_key, channel_key, sku_key
    ) AS s USING (date_key, channel_key, sku_key)
    WHERE l.units IS DISTINCT FROM s.units OR l.amount IS DISTINCT FROM s.amount
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_customer_purchase_line differs from v_sales_sku_daily';
  END IF;

  -- net delivered == legacy gross delivered minus cancelled-after-delivery
  IF EXISTS (
    SELECT 1
    FROM (
      SELECT g.date_key, g.channel_key, g.gross - COALESCE(x.cancelled_amount, 0) AS expected
      FROM (
        SELECT date_key, channel_key, SUM(delivered_sales_amount) AS gross
        FROM mart.v_sales_daily GROUP BY date_key, channel_key
      ) AS g
      LEFT JOIN (
        SELECT o.delivered_date_key AS date_key, o.channel_key, SUM(o.total_amount) AS cancelled_amount
        FROM dw.fact_order AS o
        WHERE o.delivered_date_key IS NOT NULL AND o.is_cancelled AND NOT o.is_deleted
        GROUP BY o.delivered_date_key, o.channel_key
      ) AS x USING (date_key, channel_key)
    ) AS e
    FULL JOIN mart.v_delivered_net_daily AS n USING (date_key, channel_key)
    WHERE COALESCE(e.expected, 0) <> COALESCE(n.delivered_sales_amount, 0)
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_delivered_net_daily != v_sales_daily delivered minus cancelled-after-delivery';
  END IF;

  -- exact key sets, both directions
  IF EXISTS (
    (SELECT order_key FROM dw.fact_order WHERE NOT is_deleted
     EXCEPT SELECT order_key FROM mart.v_order_operational_detail)
    UNION ALL
    (SELECT order_key FROM mart.v_order_operational_detail
     EXCEPT SELECT order_key FROM dw.fact_order WHERE NOT is_deleted)
  ) OR EXISTS (
    SELECT order_key FROM mart.v_order_operational_detail GROUP BY order_key HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_order_operational_detail must hold exactly one row per non-deleted order';
  END IF;
  IF EXISTS (
    (SELECT order_key FROM dw.fact_order WHERE is_cancelled AND NOT is_deleted
     EXCEPT SELECT order_key FROM mart.v_order_cancellation)
    UNION ALL
    (SELECT order_key FROM mart.v_order_cancellation
     EXCEPT SELECT order_key FROM dw.fact_order WHERE is_cancelled AND NOT is_deleted)
  ) OR EXISTS (
    SELECT order_key FROM mart.v_order_cancellation GROUP BY order_key HAVING COUNT(*) > 1
  ) THEN
    RAISE EXCEPTION 'Reconcile: v_order_cancellation must hold exactly one row per cancelled non-deleted order';
  END IF;

  -- CF facts: one row per social order that has a parent order
  IF (SELECT COUNT(*) FROM mart.v_social_order_action)
     <> (SELECT COUNT(*)
         FROM dw.fact_social_order AS f
         JOIN dw.fact_order AS o
           ON o.source_system = f.source_system AND o.order_source_id = f.order_source_id
         WHERE NOT f.is_deleted AND NOT o.is_deleted) THEN
    RAISE EXCEPTION 'Reconcile: v_social_order_action row count differs from CF facts with a parent order';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Full replay of the same source identities. Phase B source fields include a
-- reason correction, reserve correction, and payment-method rename to exercise
-- their fact upserts as well as the unchanged-row idempotency path.
-- ---------------------------------------------------------------------
INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('66666666-6666-6666-6666-666666666666', 'db_oltp', '2026-08-06 00:00+07', '2026-08-07 00:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  buyer_source_id, buyer_name, province_name, postal_code, return_received_at,
  subtotal_amount, discount_amount, shipping_fee_amount, tax_amount, total_amount,
  deleted_at, source_updated_at
)
SELECT
  '66666666-6666-6666-6666-666666666666', source_id, order_number, order_at, current_status,
  channel_source_id, buyer_source_id, buyer_name, province_name, postal_code,
  return_received_at, subtotal_amount, discount_amount, shipping_fee_amount, tax_amount,
  total_amount, deleted_at, source_updated_at
FROM stg.orders WHERE batch_id = '55555555-5555-5555-5555-555555555555';

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at
)
SELECT
  '66666666-6666-6666-6666-666666666666', source_id, order_source_id, sku_source_id, quantity,
  unit_price, line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at
FROM stg.order_lines WHERE batch_id = '55555555-5555-5555-5555-555555555555';

INSERT INTO stg.order_status_history (
  batch_id, source_id, order_source_id, new_status, action, reason, occurred_at, source_updated_at
)
SELECT
  '66666666-6666-6666-6666-666666666666', source_id, order_source_id, new_status, action,
  CASE WHEN source_id = 5106 THEN 'Corrected cancellation reason' ELSE reason END,
  occurred_at,
  CASE WHEN source_id = 5106 THEN source_updated_at + INTERVAL '1 minute' ELSE source_updated_at END
FROM stg.order_status_history WHERE batch_id = '55555555-5555-5555-5555-555555555555';

INSERT INTO stg.facebook_reserves (
  batch_id, source_id, order_source_id, keyword, sku_source_id, quantity,
  created_at, reserved_until, status, deleted_at, source_updated_at
)
SELECT
  '66666666-6666-6666-6666-666666666666', source_id, order_source_id,
  CASE WHEN source_id = 8101 THEN 'CF-KEY-12-UPDATED' ELSE keyword END,
  CASE WHEN source_id = 8101 THEN 101 ELSE sku_source_id END,
  CASE WHEN source_id = 8101 THEN 2 ELSE quantity END,
  created_at, reserved_until, status, deleted_at,
  CASE WHEN source_id = 8101 THEN source_updated_at + INTERVAL '1 minute' ELSE source_updated_at END
FROM stg.facebook_reserves WHERE batch_id = '55555555-5555-5555-5555-555555555555';

INSERT INTO stg.payment_transactions (
  batch_id, source_id, order_source_id, amount, current_status, payment_method_source_id,
  payment_method_name, payment_at, verified_at, deleted_at, source_updated_at
)
SELECT
  '66666666-6666-6666-6666-666666666666', source_id, order_source_id, amount, current_status,
  payment_method_source_id,
  -- The rename does not reach payment 9103, so one (order, method id) holds two
  -- labels at once. The mart must still return ONE row for it (grouped by method
  -- id, label picked deterministically), not one row per label.
  CASE WHEN payment_method_source_id = 42 AND source_id <> 9103 THEN 'Bank transfer renamed' ELSE payment_method_name END,
  payment_at, verified_at, deleted_at,
  CASE WHEN payment_method_source_id = 42 AND source_id <> 9103 THEN source_updated_at + INTERVAL '1 minute' ELSE source_updated_at END
FROM stg.payment_transactions WHERE batch_id = '55555555-5555-5555-5555-555555555555';

SELECT * FROM etl.apply_sales_stock_batch('66666666-6666-6666-6666-666666666666');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '66666666-6666-6666-6666-666666666666') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Replay: dashboard fixture replay must succeed';
  END IF;
  IF (SELECT COUNT(*) FROM mart.v_customer_purchase_line WHERE order_source_id BETWEEN 3001 AND 3014) <> 16
     OR (SELECT COUNT(*) FROM mart.v_order_operational_detail WHERE order_source_id BETWEEN 3001 AND 3014) <> 13
     OR (SELECT COUNT(*) FROM mart.v_order_cancellation WHERE order_source_id BETWEEN 3001 AND 3014) <> 1
     OR (SELECT COUNT(*) FROM mart.v_social_order_action WHERE order_source_id BETWEEN 3001 AND 3014) <> 3 THEN
    RAISE EXCEPTION 'Replay: row-grain marts duplicated or dropped rows';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_customer_profile
    WHERE buyer_source_id = 601 AND lifetime_order_count = 2 AND lifetime_sales_amount = 450
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_product_customer_daily
    WHERE business_date = DATE '2026-08-02' AND channel_code = 'Facebook'
      AND product_source_id = 12 AND buyer_source_id = 602
      AND order_count = 1 AND units_sold = 2 AND line_subtotal_amount = 100
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_product_pair_daily
    WHERE business_date = DATE '2026-08-02' AND channel_code = 'Facebook'
      AND product_a_source_id = 10 AND product_b_source_id = 12 AND order_count = 1
  ) THEN
    RAISE EXCEPTION 'Replay: customer/product aggregates duplicated on replay';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_delivered_net_daily
    WHERE business_date = DATE '2026-08-03' AND channel_code = 'POS'
      AND delivered_order_count = 1 AND delivered_sales_amount = 100
  ) THEN
    RAISE EXCEPTION 'Replay: net delivered sales duplicated on replay';
  END IF;
  IF (SELECT COUNT(*) FROM mart.v_order_cancellation WHERE order_source_id = 3004) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM mart.v_order_cancellation
       WHERE order_source_id = 3004 AND cancel_reason = 'Corrected cancellation reason'
     ) THEN
    RAISE EXCEPTION 'Replay: cancellation reason correction was not upserted';
  END IF;
  IF (SELECT COUNT(*) FROM mart.v_order_payment_method WHERE order_source_id IN (3001, 3014)) <> 2
     OR EXISTS (
       SELECT source_system, order_source_id, payment_method_source_id
       FROM mart.v_order_payment_method
       WHERE order_source_id IN (3001, 3014)
       GROUP BY source_system, order_source_id, payment_method_source_id
       HAVING COUNT(*) > 1
     )
     OR NOT EXISTS (
       SELECT 1 FROM mart.v_order_payment_method
       WHERE order_source_id = 3001 AND payment_method_source_id = 42
         AND payment_method_name = 'Bank transfer renamed'
         AND confirmed_transaction_count = 2 AND confirmed_paid_amount = 100
         AND first_verified_at = '2026-08-02 09:05+07'::TIMESTAMPTZ
     ) THEN
    RAISE EXCEPTION 'Replay: payment-method rename duplicated or lost the confirmed totals';
  END IF;
  IF (SELECT COUNT(*) FROM mart.v_social_order_reserve WHERE reserve_source_id BETWEEN 8101 AND 8103) <> 3
     OR EXISTS (
       SELECT reserve_source_id FROM mart.v_social_order_reserve
       WHERE reserve_source_id BETWEEN 8101 AND 8103
       GROUP BY reserve_source_id HAVING COUNT(*) <> 1
     ) OR NOT EXISTS (
       SELECT 1 FROM mart.v_social_order_reserve
       WHERE reserve_source_id = 8101 AND keyword = 'CF-KEY-12-UPDATED'
         AND quantity = 2 AND sku_code = 'SILK-RED' AND product_source_id = 10
     ) OR NOT EXISTS (
       SELECT 1 FROM mart.v_social_order_reserve
       WHERE reserve_source_id = 8102 AND sku_key IS NULL
     ) OR NOT EXISTS (
       SELECT 1 FROM mart.v_social_order_reserve
       WHERE reserve_source_id = 8103 AND keyword IS NULL
     ) THEN
    RAISE EXCEPTION 'Replay: reserve corrections duplicated or lost reserve evidence';
  END IF;
END;
$$;

-- ---------------------------------------------------------------------
-- Phase C promotion history, order-line resolution, and membership state.
-- Separate IDs/batches keep this fixture independent from phases A and B.
-- ---------------------------------------------------------------------
INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('77777777-7777-7777-7777-777777777777', 'db_oltp', '2026-09-03 00:00+07', '2026-09-03 10:00+07');

INSERT INTO stg.promotions (
  batch_id, promotion_source_id, promotion_name, code, discount_type, discount_value,
  min_purchase_amount, max_discount_amount, usage_limit, usage_count, start_at, end_at,
  is_active, created_at, deleted_at, source_updated_at, as_of_at
)
VALUES (
  '77777777-7777-7777-7777-777777777777', 9201, 'Phase C promotion', 'PRIVATE-9201',
  'percentage', 10, 100, 50, 100, 2, '2026-09-03 00:00+07', '2026-09-30 23:59+07',
  TRUE, '2026-08-01 10:00+07', NULL, '2026-09-03 09:00+07', '2026-09-03 10:00+07'
);

INSERT INTO stg.promotion_categories (
  batch_id, promotion_source_id, category_source_id, use_count
)
VALUES ('77777777-7777-7777-7777-777777777777', 9201, 9301, 4);

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  subtotal_amount, discount_amount, total_amount, source_updated_at
)
VALUES
  ('77777777-7777-7777-7777-777777777777', 3015, 'PROMO-3015', '2026-09-03 09:00+07', 'completed', 1, 290, 0, 290, '2026-09-03 09:01+07'),
  ('77777777-7777-7777-7777-777777777777', 3016, 'PROMO-3016', '2026-09-03 09:30+07', 'completed', 1, 60, 0, 60, '2026-09-03 09:31+07'),
  ('77777777-7777-7777-7777-777777777777', 3017, 'PROMO-3017', '2026-09-03 09:45+07', 'cancelled', 1, 30, 0, 30, '2026-09-03 09:46+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at,
  promotion_source_id, promotion_category_source_id
)
VALUES
  ('77777777-7777-7777-7777-777777777777', 4101, 3015, 101, 2, 100, 0, 200, NULL, '2026-09-03 09:01+07', 9201, 9301),
  ('77777777-7777-7777-7777-777777777777', 4102, 3015, 101, 1, 50, 10, 40, NULL, '2026-09-03 09:01+07', 9202, NULL),
  ('77777777-7777-7777-7777-777777777777', 4103, 3016, 101, 1, 60, 0, 60, NULL, '2026-09-03 09:31+07', NULL, NULL),
  ('77777777-7777-7777-7777-777777777777', 4104, 3017, 101, 1, 30, 0, 30, NULL, '2026-09-03 09:46+07', 9201, 9301),
  ('77777777-7777-7777-7777-777777777777', 4105, 3015, 101, 10, 10, 0, 100, '2026-09-03 09:02+07', '2026-09-03 09:02+07', 9201, 9301),
  ('77777777-7777-7777-7777-777777777777', 4106, 3015, 101, 1, 50, 0, 50, NULL, '2026-09-03 09:01+07', 9201, 9301);

SELECT * FROM etl.apply_sales_stock_batch('77777777-7777-7777-7777-777777777777');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '77777777-7777-7777-7777-777777777777') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Phase C: initial promotion fixture batch must succeed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE order_line_source_id = 4101 AND promotion_source_id = 9201
      AND promotion_category_source_id = 9301 AND promotion_key IS NOT NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE order_line_source_id = 4102 AND promotion_source_id = 9202
      AND promotion_category_source_id IS NULL AND promotion_key IS NULL
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE order_line_source_id = 4103 AND promotion_source_id IS NULL
      AND promotion_category_source_id IS NULL AND promotion_key IS NULL
  ) THEN
    RAISE EXCEPTION 'Phase C: resolved, unresolved, and no-promotion lines were not retained correctly';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
      AND promotion_source_id = 9202 AND promotion_name IS NULL
      AND booked_order_count = 1 AND units_sold = 1
      AND line_discount_amount = 10 AND line_subtotal_amount = 40
  ) THEN
    RAISE EXCEPTION 'Phase C: unresolved promotion line must remain visible with a NULL name';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
      AND promotion_source_id = 9201 AND booked_order_count = 1
      AND units_sold = 3 AND line_discount_amount = 0 AND line_subtotal_amount = 250
  ) OR EXISTS (
    SELECT 1 FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
      AND promotion_source_id = 9201
      AND (booked_order_count <> 1 OR units_sold <> 3
        OR line_discount_amount <> 0 OR line_subtotal_amount <> 250)
  ) OR EXISTS (
    SELECT 1 FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
      AND promotion_source_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Phase C: cancelled/deleted lines leaked or the no-promotion line was exposed';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('88888888-8888-8888-8888-888888888888', 'db_oltp', '2026-09-03 10:00+07', '2026-09-04 15:00+07');

INSERT INTO stg.promotions (
  batch_id, promotion_source_id, promotion_name, code, discount_type, discount_value,
  min_purchase_amount, max_discount_amount, usage_limit, usage_count, start_at, end_at,
  is_active, created_at, deleted_at, source_updated_at, as_of_at
)
VALUES
  ('88888888-8888-8888-8888-888888888888', 9201, 'Phase C promotion updated', 'PRIVATE-9201',
   'percentage', 15, 120, 60, 100, 9, '2026-09-04 00:00+07', '2026-10-01 23:59+07',
   FALSE, '2026-08-01 10:00+07', NULL, '2026-09-04 14:00+07', '2026-09-04 15:00+07'),
  ('88888888-8888-8888-8888-888888888888', 9202, 'Late promotion', 'PRIVATE-9202',
   'fixed', 5, NULL, 25, NULL, 1, '2026-09-04 00:00+07', '2026-10-01 23:59+07',
   TRUE, '2026-09-04 12:00+07', NULL, '2026-09-04 14:30+07', '2026-09-04 15:00+07');

INSERT INTO stg.promotion_categories (
  batch_id, promotion_source_id, category_source_id, use_count
)
VALUES ('88888888-8888-8888-8888-888888888888', 9202, 9302, 1);

SELECT * FROM etl.apply_sales_stock_batch('88888888-8888-8888-8888-888888888888');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line AS line
    JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = line.promotion_key
    WHERE line.order_line_source_id = 4102 AND promotion.promotion_source_id = 9202
  ) OR NOT EXISTS (
    SELECT 1 FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND promotion_source_id = 9202
      AND promotion_name = 'Late promotion'
  ) THEN
    RAISE EXCEPTION 'Phase C: a later promotion extract must resolve the stored line key';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9201 AND category_source_id = 9301
      AND use_count = 4 AND NOT is_current
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9202 AND category_source_id = 9302
      AND use_count = 1 AND is_current
  ) THEN
    RAISE EXCEPTION 'Phase C: disappeared category pairs must be retained as not current';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_promotion_daily_snapshot AS snapshot
    JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = snapshot.promotion_key
    WHERE promotion.promotion_source_id = 9201 AND snapshot.snapshot_date_key = 20260903
      AND snapshot.usage_count = 2 AND snapshot.discount_value = 10
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.fact_promotion_daily_snapshot AS snapshot
    JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = snapshot.promotion_key
    WHERE promotion.promotion_source_id = 9201 AND snapshot.snapshot_date_key = 20260904
      AND snapshot.usage_count = 9 AND snapshot.discount_value = 15
  ) THEN
    RAISE EXCEPTION 'Phase C: changed promotion terms/counters must retain both daily snapshots';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM mart.v_promotion
    WHERE promotion_source_id = 9201 AND usage_count = 9 AND discount_value = 15
      AND NOT is_active AND first_snapshot_date = DATE '2026-09-03'
      AND last_snapshot_date = DATE '2026-09-04'
  ) THEN
    RAISE EXCEPTION 'Phase C: promotion mart must expose latest terms and available snapshot dates';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('99999999-9999-9999-9999-999999999999', 'db_oltp', '2026-09-04 00:00+07', '2026-09-04 10:00+07');

INSERT INTO stg.promotions (
  batch_id, promotion_source_id, promotion_name, code, discount_type, discount_value,
  min_purchase_amount, max_discount_amount, usage_limit, usage_count, start_at, end_at,
  is_active, created_at, deleted_at, source_updated_at, as_of_at
)
VALUES (
  '99999999-9999-9999-9999-999999999999', 9201, 'Older replay terms', 'PRIVATE-9201',
  'percentage', 3, 10, 20, 100, 99, '2026-09-01 00:00+07', '2026-09-15 23:59+07',
  TRUE, '2026-08-01 10:00+07', NULL, '2026-09-03 09:00+07', '2026-09-04 10:00+07'
);

INSERT INTO stg.promotion_categories (
  batch_id, promotion_source_id, category_source_id, use_count
)
VALUES ('99999999-9999-9999-9999-999999999999', 9201, 9301, 99);

SELECT * FROM etl.apply_sales_stock_batch('99999999-9999-9999-9999-999999999999');

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_promotion_daily_snapshot AS snapshot
    JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = snapshot.promotion_key
    WHERE promotion.promotion_source_id = 9201 AND snapshot.snapshot_date_key = 20260904
      AND snapshot.captured_at = '2026-09-04 15:00+07'::TIMESTAMPTZ
      AND snapshot.usage_count = 9 AND snapshot.discount_value = 15
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.dim_promotion
    WHERE promotion_source_id = 9201 AND usage_count = 9 AND discount_value = 15
      AND NOT is_active
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9201 AND category_source_id = 9301
      AND use_count = 4 AND NOT is_current
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9202 AND category_source_id = 9302
      AND use_count = 1 AND is_current
  ) THEN
    RAISE EXCEPTION 'Phase C: older snapshot replay overwrote newer terms, counters, or current category pairs';
  END IF;
END;
$$;

-- Reapply the latest snapshot under a new batch id to verify key-based idempotency.
INSERT INTO etl.load_batch (
  batch_id, source_system, source_window_started_at, source_window_ended_at, created_at
)
SELECT
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', source_system, source_window_started_at,
  source_window_ended_at, created_at + INTERVAL '1 minute'
FROM etl.load_batch
WHERE batch_id = '88888888-8888-8888-8888-888888888888';

INSERT INTO stg.promotions (
  batch_id, promotion_source_id, promotion_name, code, discount_type, discount_value,
  min_purchase_amount, max_discount_amount, usage_limit, usage_count, start_at, end_at,
  is_active, created_at, deleted_at, source_updated_at, as_of_at
)
SELECT
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', promotion_source_id, promotion_name, code,
  discount_type, discount_value, min_purchase_amount, max_discount_amount, usage_limit,
  usage_count, start_at, end_at, is_active, created_at, deleted_at, source_updated_at, as_of_at
FROM stg.promotions
WHERE batch_id = '88888888-8888-8888-8888-888888888888';

INSERT INTO stg.promotion_categories (
  batch_id, promotion_source_id, category_source_id, use_count
)
SELECT
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', promotion_source_id, category_source_id, use_count
FROM stg.promotion_categories
WHERE batch_id = '88888888-8888-8888-8888-888888888888';

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at,
  promotion_source_id, promotion_category_source_id
)
SELECT
  'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', source_id, order_source_id, sku_source_id,
  quantity, unit_price, line_discount_amount, line_subtotal_amount, deleted_at,
  source_updated_at, promotion_source_id, promotion_category_source_id
FROM stg.order_lines
WHERE batch_id = '77777777-7777-7777-7777-777777777777';

SELECT * FROM etl.apply_sales_stock_batch('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
SELECT * FROM etl.apply_sales_stock_batch('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');

DO $$
BEGIN
  IF (SELECT COUNT(*) FROM dw.fact_order_line WHERE order_line_source_id BETWEEN 4101 AND 4106) <> 6
     OR (SELECT COUNT(*) FROM dw.bridge_promotion_category WHERE promotion_source_id IN (9201, 9202)) <> 2
     OR (SELECT COUNT(*) FROM dw.fact_promotion_daily_snapshot AS snapshot
         JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = snapshot.promotion_key
         WHERE promotion.promotion_source_id IN (9201, 9202)) <> 3 THEN
    RAISE EXCEPTION 'Phase C: replay duplicated order lines, category pairs, or promotion snapshots';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_promotion_daily_snapshot AS snapshot
    JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = snapshot.promotion_key
    WHERE promotion.promotion_source_id = 9201 AND snapshot.snapshot_date_key = 20260904
      AND snapshot.captured_at = '2026-09-04 15:00+07'::TIMESTAMPTZ
      AND snapshot.usage_count = 9 AND snapshot.discount_value = 15
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.dim_promotion
    WHERE promotion_source_id = 9201 AND usage_count = 9 AND discount_value = 15
      AND NOT is_active
  ) THEN
    RAISE EXCEPTION 'Phase C: older same-day snapshot replay overwrote newer promotion state';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9201 AND category_source_id = 9301
      AND use_count = 4 AND NOT is_current
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9202 AND category_source_id = 9302
      AND use_count = 1 AND is_current
  ) THEN
    RAISE EXCEPTION 'Phase C: older snapshot replay resurrected or replaced category-pair state';
  END IF;
  IF (
    SELECT COALESCE(SUM(units_sold), 0) FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) + (
    SELECT COALESCE(SUM(line.quantity), 0)
    FROM dw.fact_order_line AS line
    JOIN dw.fact_order AS order_fact ON order_fact.order_key = line.order_key
    WHERE order_fact.order_source_id BETWEEN 3015 AND 3017
      AND line.promotion_source_id IS NULL
      AND NOT line.is_deleted AND NOT order_fact.is_cancelled AND NOT order_fact.is_deleted
  ) <> (
    SELECT COALESCE(SUM(units_sold), 0) FROM mart.v_sales_sku_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) OR (
    SELECT COALESCE(SUM(line_subtotal_amount), 0) FROM mart.v_sales_promotion_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) + (
    SELECT COALESCE(SUM(line.line_subtotal_amount), 0)
    FROM dw.fact_order_line AS line
    JOIN dw.fact_order AS order_fact ON order_fact.order_key = line.order_key
    WHERE order_fact.order_source_id BETWEEN 3015 AND 3017
      AND line.promotion_source_id IS NULL
      AND NOT line.is_deleted AND NOT order_fact.is_cancelled AND NOT order_fact.is_deleted
  ) <> (
    SELECT COALESCE(SUM(line_subtotal_amount), 0) FROM mart.v_sales_sku_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) THEN
    RAISE EXCEPTION 'Phase C: promotion and non-promotion lines do not reconcile to existing line sales totals';
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'mart'
      AND table_name IN ('v_promotion', 'v_sales_promotion_daily')
      AND column_name IN ('code', 'buyer_name', 'customer_name')
  ) THEN
    RAISE EXCEPTION 'Phase C: promotion marts expose restricted code or customer names';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'db_oltp', '2026-09-04 15:00+07', '2026-09-05 12:00+07');

-- An empty full snapshot still advances membership state and clears all current pairs.
SELECT * FROM etl.apply_sales_stock_batch('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id IN (9201, 9202) AND is_current
  ) OR NOT EXISTS (
    SELECT 1 FROM dw.bridge_promotion_category
    WHERE promotion_source_id = 9202 AND category_source_id = 9302 AND NOT is_current
  ) OR NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'promotion_categories'
      AND snapshot_at = '2026-09-05 12:00+07'::TIMESTAMPTZ
      AND last_successful_batch_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
  ) THEN
    RAISE EXCEPTION 'Phase C: an empty full snapshot must retain pairs as not current and advance its marker';
  END IF;
END;
$$;

-- Hard-deleted source lines: a line missing from the full id snapshot is
-- marked deleted, an older replay cannot resurrect it, and a batch without a
-- snapshot changes nothing.
CREATE TEMP TABLE line_delete_before AS
SELECT
  (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp' AND is_deleted) AS deleted_lines,
  (SELECT COALESCE(SUM(units_sold), 0) FROM mart.v_sales_sku_daily
   WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS') AS units_sold,
  (SELECT COALESCE(SUM(line_subtotal_amount), 0) FROM mart.v_sales_sku_daily
   WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS') AS line_sales;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE source_system = 'db_oltp' AND order_line_source_id = 4103 AND NOT is_deleted
  ) THEN
    RAISE EXCEPTION 'Hard delete: fixture line 4103 must be live before the id snapshot';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'db_oltp', '2026-09-05 12:00+07', '2026-09-06 12:00+07');

INSERT INTO stg.order_line_ids (batch_id, source_id, order_source_id)
SELECT 'cccccccc-cccc-cccc-cccc-cccccccccccc', line.order_line_source_id, order_fact.order_source_id
FROM dw.fact_order_line AS line
JOIN dw.fact_order AS order_fact ON order_fact.order_key = line.order_key
WHERE line.source_system = 'db_oltp' AND line.order_line_source_id <> 4103;

SELECT * FROM etl.apply_sales_stock_batch('cccccccc-cccc-cccc-cccc-cccccccccccc');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Hard delete: id snapshot batch must succeed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE source_system = 'db_oltp' AND order_line_source_id = 4103 AND is_deleted
      AND last_loaded_batch_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  ) OR (
    SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp' AND is_deleted
  ) <> (SELECT deleted_lines + 1 FROM line_delete_before) THEN
    RAISE EXCEPTION 'Hard delete: only the line missing from the id snapshot may be marked deleted';
  END IF;
  IF (
    SELECT COALESCE(SUM(units_sold), 0) FROM mart.v_sales_sku_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) <> (SELECT units_sold - 1 FROM line_delete_before) OR (
    SELECT COALESCE(SUM(line_subtotal_amount), 0) FROM mart.v_sales_sku_daily
    WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS'
  ) <> (SELECT line_sales - 60 FROM line_delete_before) THEN
    RAISE EXCEPTION 'Hard delete: line marts must drop the deleted line (1 unit, 60)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_line_ids'
      AND snapshot_at = '2026-09-06 12:00+07'::TIMESTAMPTZ
      AND last_successful_batch_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  ) THEN
    RAISE EXCEPTION 'Hard delete: the line-id snapshot marker must advance to the applied batch';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'db_oltp', '2026-09-03 00:00+07', '2026-09-04 10:00+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at,
  promotion_source_id, promotion_category_source_id
)
VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd', 4103, 3016, 101, 1, 60, 0, 60, NULL, '2026-09-03 09:31+07', NULL, NULL);

INSERT INTO stg.order_line_ids (batch_id, source_id, order_source_id)
SELECT 'dddddddd-dddd-dddd-dddd-dddddddddddd', line.order_line_source_id, order_fact.order_source_id
FROM dw.fact_order_line AS line
JOIN dw.fact_order AS order_fact ON order_fact.order_key = line.order_key
WHERE line.source_system = 'db_oltp';

SELECT * FROM etl.apply_sales_stock_batch('dddddddd-dddd-dddd-dddd-dddddddddddd');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = 'dddddddd-dddd-dddd-dddd-dddddddddddd') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Hard delete: older replay batch must succeed';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM dw.fact_order_line
    WHERE source_system = 'db_oltp' AND order_line_source_id = 4103 AND is_deleted
  ) THEN
    RAISE EXCEPTION 'Hard delete: an older replay resurrected a line deleted by a newer id snapshot';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_line_ids'
      AND snapshot_at = '2026-09-06 12:00+07'::TIMESTAMPTZ
      AND last_successful_batch_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  ) THEN
    RAISE EXCEPTION 'Hard delete: an older id snapshot moved the snapshot marker back';
  END IF;
END;
$$;

CREATE TEMP TABLE line_state_before_empty AS
SELECT order_line_source_id, is_deleted
FROM dw.fact_order_line
WHERE source_system = 'db_oltp';

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'db_oltp', '2026-09-06 12:00+07', '2026-09-07 12:00+07');

-- No ids staged: the snapshot is skipped instead of deleting every line.
SELECT * FROM etl.apply_sales_stock_batch('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Hard delete: batch without an id snapshot must succeed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM dw.fact_order_line AS line
    JOIN line_state_before_empty AS before
      ON before.order_line_source_id = line.order_line_source_id
    WHERE line.source_system = 'db_oltp' AND line.is_deleted <> before.is_deleted
  ) THEN
    RAISE EXCEPTION 'Hard delete: a batch without an id snapshot changed line deletion state';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_line_ids'
      AND snapshot_at = '2026-09-06 12:00+07'::TIMESTAMPTZ
      AND last_successful_batch_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
  ) THEN
    RAISE EXCEPTION 'Hard delete: a batch without an id snapshot moved the snapshot marker';
  END IF;
END;
$$;

-- Whole orders deleted directly in the source: an order missing from the
-- order id snapshot is marked deleted with its lines and social fact, drops
-- out of the marts, and stays deleted through an older replay.
CREATE TEMP TABLE order_delete_before AS
SELECT
  (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp' AND is_deleted) AS deleted_orders,
  (SELECT COALESCE(SUM(booked_order_count), 0) FROM mart.v_sales_daily
   WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS') AS pos_orders,
  (SELECT COALESCE(SUM(booked_sales_amount), 0) FROM mart.v_sales_daily
   WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS') AS pos_sales,
  (SELECT COALESCE(SUM(booked_sales_amount), 0) FROM mart.v_sales_daily
   WHERE business_date = DATE '2026-08-01' AND channel_code = 'Facebook') AS fb_sales;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM dw.fact_order WHERE order_source_id = 3015 AND NOT is_deleted)
     OR NOT EXISTS (SELECT 1 FROM dw.fact_order WHERE order_source_id = 3012 AND NOT is_deleted)
     OR NOT EXISTS (SELECT 1 FROM dw.fact_social_order WHERE order_source_id = 3012 AND NOT is_deleted)
     OR NOT EXISTS (SELECT 1 FROM mart.v_social_order_action WHERE order_source_id = 3012) THEN
    RAISE EXCEPTION 'Order delete: fixture orders 3015 and 3012 must be live before the order snapshot';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('12121212-1212-1212-1212-121212121212', 'db_oltp', '2026-09-07 12:00+07', '2026-09-08 12:00+07');

INSERT INTO stg.order_ids (batch_id, source_id)
SELECT '12121212-1212-1212-1212-121212121212', order_source_id
FROM dw.fact_order
WHERE source_system = 'db_oltp' AND order_source_id NOT IN (3012, 3015);

SELECT * FROM etl.apply_sales_stock_batch('12121212-1212-1212-1212-121212121212');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '12121212-1212-1212-1212-121212121212') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Order delete: order snapshot batch must succeed';
  END IF;
  IF (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp' AND is_deleted)
       <> (SELECT deleted_orders + 2 FROM order_delete_before)
     OR EXISTS (
       SELECT 1 FROM dw.fact_order
       WHERE order_source_id IN (3012, 3015)
         AND (NOT is_deleted OR source_updated_at < '2026-09-08 12:00+07'::TIMESTAMPTZ)
     ) THEN
    RAISE EXCEPTION 'Order delete: exactly the orders missing from the snapshot must be marked deleted and pinned';
  END IF;
  IF EXISTS (
    SELECT 1 FROM dw.fact_order_line AS line
    JOIN dw.fact_order AS o ON o.order_key = line.order_key
    WHERE o.order_source_id IN (3012, 3015) AND NOT line.is_deleted
  ) THEN
    RAISE EXCEPTION 'Order delete: lines of a deleted order must be marked deleted';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM dw.fact_social_order WHERE order_source_id = 3012 AND is_deleted)
     OR EXISTS (SELECT 1 FROM mart.v_social_order_action WHERE order_source_id = 3012)
     OR EXISTS (SELECT 1 FROM mart.v_social_order_status WHERE order_source_id = 3012 AND NOT is_deleted) THEN
    RAISE EXCEPTION 'Order delete: a deleted Facebook order must leave the social marts';
  END IF;
  IF (SELECT COALESCE(SUM(booked_order_count), 0) FROM mart.v_sales_daily
      WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS')
       <> (SELECT pos_orders - 1 FROM order_delete_before)
     OR (SELECT COALESCE(SUM(booked_sales_amount), 0) FROM mart.v_sales_daily
         WHERE business_date = DATE '2026-09-03' AND channel_code = 'POS')
       <> (SELECT pos_sales - 290 FROM order_delete_before)
     OR (SELECT COALESCE(SUM(booked_sales_amount), 0) FROM mart.v_sales_daily
         WHERE business_date = DATE '2026-08-01' AND channel_code = 'Facebook')
       <> (SELECT fb_sales - 300 FROM order_delete_before) THEN
    RAISE EXCEPTION 'Order delete: booked sales must drop by the deleted orders (POS 290, Facebook 300)';
  END IF;
  IF EXISTS (SELECT 1 FROM mart.v_order_operational_detail WHERE order_source_id IN (3012, 3015))
     OR EXISTS (SELECT 1 FROM mart.v_customer_purchase_line WHERE order_source_id IN (3012, 3015)) THEN
    RAISE EXCEPTION 'Order delete: a deleted order leaked into order or purchase-line marts';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_ids'
      AND snapshot_at = '2026-09-08 12:00+07'::TIMESTAMPTZ
      AND last_successful_batch_id = '12121212-1212-1212-1212-121212121212'
  ) THEN
    RAISE EXCEPTION 'Order delete: the order snapshot marker must advance to the applied batch';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('13131313-1313-1313-1313-131313131313', 'db_oltp', '2026-09-03 00:00+07', '2026-09-04 10:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  subtotal_amount, discount_amount, total_amount, source_updated_at
)
VALUES ('13131313-1313-1313-1313-131313131313', 3015, 'PROMO-3015', '2026-09-03 09:00+07', 'completed', 1, 290, 0, 290, '2026-09-03 09:01+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at,
  promotion_source_id, promotion_category_source_id
)
VALUES ('13131313-1313-1313-1313-131313131313', 4101, 3015, 101, 2, 100, 0, 200, NULL, '2026-09-03 09:01+07', 9201, 9301);

INSERT INTO stg.order_ids (batch_id, source_id)
SELECT '13131313-1313-1313-1313-131313131313', order_source_id
FROM dw.fact_order
WHERE source_system = 'db_oltp';

SELECT * FROM etl.apply_sales_stock_batch('13131313-1313-1313-1313-131313131313');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '13131313-1313-1313-1313-131313131313') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Order delete: older replay batch must succeed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM dw.fact_order WHERE order_source_id = 3015 AND is_deleted)
     OR NOT EXISTS (SELECT 1 FROM dw.fact_order WHERE order_source_id = 3012 AND is_deleted)
     OR NOT EXISTS (SELECT 1 FROM dw.fact_order_line WHERE order_line_source_id = 4101 AND is_deleted)
     OR NOT EXISTS (SELECT 1 FROM dw.fact_social_order WHERE order_source_id = 3012 AND is_deleted) THEN
    RAISE EXCEPTION 'Order delete: an older replay resurrected a deleted order, line, or social fact';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_ids'
      AND last_successful_batch_id = '12121212-1212-1212-1212-121212121212'
  ) THEN
    RAISE EXCEPTION 'Order delete: an older order snapshot moved the marker back';
  END IF;
END;
$$;

CREATE TEMP TABLE order_state_before_empty AS
SELECT order_source_id, is_deleted FROM dw.fact_order WHERE source_system = 'db_oltp';

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('14141414-1414-1414-1414-141414141414', 'db_oltp', '2026-09-08 12:00+07', '2026-09-09 12:00+07');

-- No order ids staged: the order snapshot is skipped instead of deleting every order.
SELECT * FROM etl.apply_sales_stock_batch('14141414-1414-1414-1414-141414141414');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '14141414-1414-1414-1414-141414141414') <> 'SUCCEEDED' THEN
    RAISE EXCEPTION 'Order delete: batch without an order snapshot must succeed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM dw.fact_order AS o
    JOIN order_state_before_empty AS before ON before.order_source_id = o.order_source_id
    WHERE o.source_system = 'db_oltp' AND o.is_deleted <> before.is_deleted
  ) OR NOT EXISTS (
    SELECT 1 FROM etl.snapshot_state
    WHERE source_system = 'db_oltp' AND entity_name = 'order_ids'
      AND last_successful_batch_id = '12121212-1212-1212-1212-121212121212'
  ) THEN
    RAISE EXCEPTION 'Order delete: a batch without an order snapshot changed order state or its marker';
  END IF;
END;
$$;

-- Reused source ids (OLTP reset): a staged order whose id is already in the
-- warehouse under another order_number fails the whole batch untouched; the
-- same order_number is an ordinary update.
CREATE TEMP TABLE reused_id_before AS
SELECT
  (SELECT fact_order::TEXT FROM dw.fact_order WHERE source_system = 'db_oltp' AND order_source_id = 3016) AS order_row,
  (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp') AS line_count,
  (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp') AS order_count;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('15151515-1515-1515-1515-151515151515', 'db_oltp', '2026-09-09 12:00+07', '2026-10-12 12:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  subtotal_amount, discount_amount, total_amount, source_updated_at
)
VALUES
  ('15151515-1515-1515-1515-151515151515', 3016, 'ORD-AFTER-RESET', '2026-10-11 10:00+07', 'pending', 1, 700, 0, 700, '2026-10-11 10:01+07'),
  ('15151515-1515-1515-1515-151515151515', 3999, 'ORD-NEW-3999', '2026-10-11 11:00+07', 'pending', 1, 100, 0, 100, '2026-10-11 11:01+07');

INSERT INTO stg.order_lines (
  batch_id, source_id, order_source_id, sku_source_id, quantity, unit_price,
  line_discount_amount, line_subtotal_amount, deleted_at, source_updated_at,
  promotion_source_id, promotion_category_source_id
)
VALUES ('15151515-1515-1515-1515-151515151515', 4999, 3999, 101, 1, 100, 0, 100, NULL, '2026-10-11 11:01+07', NULL, NULL);

SELECT * FROM etl.apply_sales_stock_batch('15151515-1515-1515-1515-151515151515');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '15151515-1515-1515-1515-151515151515') <> 'FAILED'
     OR (SELECT error_message FROM etl.load_batch WHERE batch_id = '15151515-1515-1515-1515-151515151515')
          NOT LIKE 'Source order ids were reused: 1 staged order(s)%' THEN
    RAISE EXCEPTION 'Reused id: a staged order id with another order_number must fail the batch with a counts-only message';
  END IF;
  IF (SELECT fact_order::TEXT FROM dw.fact_order WHERE source_system = 'db_oltp' AND order_source_id = 3016)
       IS DISTINCT FROM (SELECT order_row FROM reused_id_before)
     OR EXISTS (SELECT 1 FROM dw.fact_order WHERE order_source_id = 3999)
     OR (SELECT COUNT(*) FROM dw.fact_order WHERE source_system = 'db_oltp') <> (SELECT order_count FROM reused_id_before)
     OR (SELECT COUNT(*) FROM dw.fact_order_line WHERE source_system = 'db_oltp') <> (SELECT line_count FROM reused_id_before) THEN
    RAISE EXCEPTION 'Reused id: a failed batch must leave every warehouse order and line unchanged';
  END IF;
  IF EXISTS (
    SELECT 1 FROM etl.watermark
    WHERE source_system = 'db_oltp' AND last_successful_batch_id = '15151515-1515-1515-1515-151515151515'
  ) THEN
    RAISE EXCEPTION 'Reused id: a failed batch must not advance watermarks';
  END IF;
END;
$$;

INSERT INTO etl.load_batch (batch_id, source_system, source_window_started_at, source_window_ended_at)
VALUES ('16161616-1616-1616-1616-161616161616', 'db_oltp', '2026-09-09 12:00+07', '2026-09-10 12:00+07');

INSERT INTO stg.orders (
  batch_id, source_id, order_number, order_at, current_status, channel_source_id,
  subtotal_amount, discount_amount, total_amount, source_updated_at
)
VALUES ('16161616-1616-1616-1616-161616161616', 3016, 'PROMO-3016', '2026-09-03 09:30+07', 'cancelled', 1, 60, 0, 60, '2026-09-10 09:00+07');

SELECT * FROM etl.apply_sales_stock_batch('16161616-1616-1616-1616-161616161616');

DO $$
BEGIN
  IF (SELECT status FROM etl.load_batch WHERE batch_id = '16161616-1616-1616-1616-161616161616') <> 'SUCCEEDED'
     OR NOT EXISTS (
       SELECT 1 FROM dw.fact_order
       WHERE source_system = 'db_oltp' AND order_source_id = 3016
         AND order_number = 'PROMO-3016' AND is_cancelled
         AND last_loaded_batch_id = '16161616-1616-1616-1616-161616161616'
     ) THEN
    RAISE EXCEPTION 'Reused id: the same order_number must update the existing order normally';
  END IF;
END;
$$;

ROLLBACK;
