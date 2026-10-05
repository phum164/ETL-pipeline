-- Dashboard contracts. Read only from mart.*; do not join fact headers to lines for revenue totals.
CREATE OR REPLACE VIEW mart.v_sales_daily AS
WITH metrics AS (
  SELECT
    order_date_key AS date_key,
    channel_key,
    COUNT(*) FILTER (WHERE NOT is_cancelled AND NOT is_deleted)::BIGINT AS booked_order_count,
    COALESCE(SUM(total_amount) FILTER (WHERE NOT is_cancelled AND NOT is_deleted), 0)::NUMERIC(18, 2) AS booked_sales_amount,
    COUNT(*) FILTER (WHERE is_cancelled AND NOT is_deleted)::BIGINT AS cancelled_order_count,
    COALESCE(SUM(total_amount) FILTER (WHERE is_cancelled AND NOT is_deleted), 0)::NUMERIC(18, 2) AS cancelled_sales_amount,
    0::BIGINT AS delivered_order_count,
    0::NUMERIC(18, 2) AS delivered_sales_amount,
    0::BIGINT AS delivered_estimated_timestamp_count,
    0::BIGINT AS returned_order_count
  FROM dw.fact_order
  GROUP BY order_date_key, channel_key

  UNION ALL

  SELECT
    delivered_date_key,
    channel_key,
    0::BIGINT,
    0::NUMERIC(18, 2),
    0::BIGINT,
    0::NUMERIC(18, 2),
    COUNT(*) FILTER (WHERE NOT is_deleted)::BIGINT,
    COALESCE(SUM(total_amount) FILTER (WHERE NOT is_deleted), 0)::NUMERIC(18, 2),
    COUNT(*) FILTER (
      WHERE NOT is_deleted AND delivery_timestamp_source = 'ORDER_UPDATED_AT_ESTIMATE'
    )::BIGINT,
    COUNT(*) FILTER (
      WHERE NOT is_deleted AND return_received_at IS NOT NULL
    )::BIGINT
  FROM dw.fact_order
  WHERE delivered_date_key IS NOT NULL
  GROUP BY delivered_date_key, channel_key
)
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  SUM(booked_order_count)::BIGINT AS booked_order_count,
  SUM(booked_sales_amount)::NUMERIC(18, 2) AS booked_sales_amount,
  SUM(cancelled_order_count)::BIGINT AS cancelled_order_count,
  SUM(cancelled_sales_amount)::NUMERIC(18, 2) AS cancelled_sales_amount,
  SUM(delivered_order_count)::BIGINT AS delivered_order_count,
  SUM(delivered_sales_amount)::NUMERIC(18, 2) AS delivered_sales_amount,
  SUM(delivered_estimated_timestamp_count)::BIGINT AS delivered_estimated_timestamp_count,
  'Delivered Sales includes completed POS sales and is gross before returns.'::TEXT AS delivered_sales_note,
  SUM(returned_order_count)::BIGINT AS returned_order_count
FROM metrics AS m
JOIN dw.dim_date AS d ON d.date_key = m.date_key
JOIN dw.dim_channel AS c ON c.channel_key = m.channel_key
GROUP BY d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name;

CREATE OR REPLACE VIEW mart.v_sales_sku_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  s.sku_key,
  s.product_source_id,
  s.sku_code,
  s.product_name,
  s.category_name,
  SUM(l.quantity)::BIGINT AS units_sold,
  SUM(l.quantity * l.unit_price)::NUMERIC(18, 2) AS gross_line_sales_amount,
  SUM(l.line_discount_amount)::NUMERIC(18, 2) AS line_discount_amount,
  SUM(l.line_subtotal_amount)::NUMERIC(18, 2) AS line_subtotal_amount
FROM dw.fact_order_line AS l
JOIN dw.fact_order AS o ON o.order_key = l.order_key
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
WHERE NOT o.is_cancelled AND NOT o.is_deleted AND NOT l.is_deleted
GROUP BY
  d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name,
  s.sku_key, s.product_source_id, s.sku_code, s.product_name, s.category_name;

-- Grain: one row per business date, channel and source product. Revenue uses
-- line subtotal after line-level discounts; order-level fees/tax are excluded.
CREATE OR REPLACE VIEW mart.v_sales_product_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  s.product_source_id,
  s.product_name,
  SUM(l.quantity)::BIGINT AS units_sold,
  COALESCE(SUM(l.line_subtotal_amount), 0)::NUMERIC(18, 2) AS line_subtotal_amount
FROM dw.fact_order_line AS l
JOIN dw.fact_order AS o ON o.order_key = l.order_key
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
WHERE NOT o.is_cancelled AND NOT o.is_deleted AND NOT l.is_deleted
GROUP BY
  d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name,
  s.product_source_id, s.product_name;

-- Grain: one row per business date, channel, buyer and shipping geography.
-- Buyer fields are order-time snapshots; postal_code may be NULL when OLTP has none.
CREATE OR REPLACE VIEW mart.v_sales_buyer_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  o.buyer_source_id,
  o.buyer_name,
  o.province_name,
  o.postal_code,
  COUNT(*) FILTER (WHERE NOT o.is_cancelled AND NOT o.is_deleted)::BIGINT AS booked_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE NOT o.is_cancelled AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS booked_sales_amount,
  COUNT(*) FILTER (WHERE o.is_cancelled AND NOT o.is_deleted)::BIGINT AS cancelled_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE o.is_cancelled AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS cancelled_sales_amount,
  COUNT(*) FILTER (WHERE o.delivered_date_key IS NOT NULL AND NOT o.is_deleted)::BIGINT AS delivered_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE o.delivered_date_key IS NOT NULL AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS delivered_sales_amount,
  o.customer_key,
  customer.customer_name,
  customer.latest_province_name,
  customer.latest_postal_code
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_customer AS customer ON customer.customer_key = o.customer_key
GROUP BY
  d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name,
  o.buyer_source_id, o.buyer_name, o.province_name, o.postal_code,
  o.customer_key, customer.customer_name, customer.latest_province_name,
  customer.latest_postal_code;

-- Grain: one row per business date and province, suitable for ranking provinces.
CREATE OR REPLACE VIEW mart.v_sales_province_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  o.province_name,
  COUNT(DISTINCT o.buyer_source_id) FILTER (WHERE o.buyer_source_id IS NOT NULL)::BIGINT AS distinct_buyer_count,
  COUNT(*) FILTER (WHERE NOT o.is_cancelled AND NOT o.is_deleted)::BIGINT AS booked_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE NOT o.is_cancelled AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS booked_sales_amount,
  COUNT(*) FILTER (WHERE o.is_cancelled AND NOT o.is_deleted)::BIGINT AS cancelled_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE o.is_cancelled AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS cancelled_sales_amount,
  COUNT(*) FILTER (WHERE o.delivered_date_key IS NOT NULL AND NOT o.is_deleted)::BIGINT AS delivered_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE o.delivered_date_key IS NOT NULL AND NOT o.is_deleted), 0)::NUMERIC(18, 2) AS delivered_sales_amount
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
WHERE o.province_name IS NOT NULL
GROUP BY d.date_key, d.calendar_date, o.province_name;

CREATE OR REPLACE VIEW mart.v_inventory_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  s.sku_key,
  s.sku_code,
  s.product_name,
  s.category_name,
  i.captured_at,
  i.on_hand_quantity,
  i.reserved_quantity,
  i.available_quantity,
  i.min_stock_level,
  i.is_low_stock
FROM dw.fact_inventory_daily_snapshot AS i
JOIN dw.dim_date AS d ON d.date_key = i.snapshot_date_key
JOIN dw.dim_sku AS s ON s.sku_key = i.sku_key;

CREATE OR REPLACE VIEW mart.v_channel_inventory_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  s.sku_key,
  s.sku_code,
  s.product_name,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  i.captured_at,
  i.allocated_quantity,
  i.allocated_reserved_quantity,
  i.safety_stock_quantity,
  i.target_quantity,
  i.remote_quantity,
  i.available_quantity,
  CASE WHEN i.remote_quantity IS NULL THEN NULL ELSE i.remote_quantity - i.target_quantity END AS remote_target_variance,
  i.inventory_dirty,
  i.is_active
FROM dw.fact_channel_inventory_daily_snapshot AS i
JOIN dw.dim_date AS d ON d.date_key = i.snapshot_date_key
JOIN dw.dim_sku AS s ON s.sku_key = i.sku_key
JOIN dw.dim_channel AS c ON c.channel_key = i.channel_key;

-- Revenue by directly assigned product category and product. Historical sales
-- use the SKU's current category; delivery date is the cohort and the gross
-- delivered population is retained even when the order is later cancelled,
-- refunded, or returned. Line subtotals are after line-level discounts.
CREATE OR REPLACE VIEW mart.v_delivered_product_category_daily AS
SELECT
  d.calendar_date AS business_date,
  c.channel_code,
  s.category_source_id,
  COALESCE(s.category_name, 'ไม่ระบุหมวดหมู่'::TEXT) AS category_name,
  s.product_source_id,
  s.product_name,
  SUM(l.quantity)::BIGINT AS units_sold,
  COALESCE(SUM(l.line_subtotal_amount), 0)::NUMERIC(18, 2) AS line_subtotal_amount
FROM dw.fact_order_line AS l
JOIN dw.fact_order AS o ON o.order_key = l.order_key
JOIN dw.dim_date AS d ON d.date_key = o.delivered_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
WHERE o.delivered_date_key IS NOT NULL
  AND NOT o.is_deleted
  AND NOT l.is_deleted
GROUP BY
  d.calendar_date, c.channel_code, s.category_source_id, s.category_name,
  s.product_source_id, s.product_name;

-- Same delivered gross population as category revenue, at SKU grain. Keep
-- variants separate by stable SKU identity, not mutable codes/attributes.
CREATE OR REPLACE VIEW mart.v_delivered_sku_daily AS
SELECT
  d.calendar_date AS business_date,
  c.channel_code,
  s.product_source_id,
  s.product_name,
  s.sku_source_id,
  s.sku_code,
  s.attribute_value,
  s.size_value,
  SUM(l.quantity)::BIGINT AS units_sold,
  COALESCE(SUM(l.line_subtotal_amount), 0)::NUMERIC(18, 2) AS line_subtotal_amount
FROM dw.fact_order_line AS l
JOIN dw.fact_order AS o ON o.order_key = l.order_key
JOIN dw.dim_date AS d ON d.date_key = o.delivered_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
WHERE o.delivered_date_key IS NOT NULL
  AND NOT o.is_deleted
  AND NOT l.is_deleted
GROUP BY
  d.calendar_date, c.channel_code, s.product_source_id, s.product_name,
  s.sku_source_id, s.sku_code, s.attribute_value, s.size_value;

-- One current row per Facebook order with retained CF evidence. snapshot_as_of
-- is the source cutoff of the most recent successful ETL, not wall-clock time.
CREATE OR REPLACE VIEW mart.v_social_order_status AS
SELECT
  f.order_source_id,
  f.cf_at,
  f.payment_due_at,
  f.required_amount,
  f.confirmed_paid_amount,
  f.paid_in_full_at,
  f.is_cod,
  f.is_cancelled,
  f.is_data_complete,
  f.is_deleted,
  COALESCE(snapshot.source_window_ended_at, f.snapshot_as_of) AS snapshot_as_of
FROM dw.fact_social_order AS f
LEFT JOIN LATERAL (
  SELECT MAX(batch.source_window_ended_at) AS source_window_ended_at
  FROM etl.load_batch AS batch
  WHERE batch.source_system = f.source_system
    AND batch.status IN ('SUCCEEDED', 'SUCCEEDED_WITH_REJECTS')
) AS snapshot ON TRUE;
