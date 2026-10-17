-- Dashboard contracts. Read only from mart.*; do not join fact headers to lines for revenue totals.
CREATE OR REPLACE VIEW mart.v_channel_catalog AS
SELECT DISTINCT ON (channel_code)
  channel_code,
  channel_name
FROM dw.dim_channel
WHERE is_active
  AND NOT is_deleted
  AND NULLIF(BTRIM(channel_code), '') IS NOT NULL
ORDER BY channel_code, source_updated_at DESC, channel_key DESC;

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

-- =====================================================================
-- Dashboard v2 marts (business overview + drill-downs). Read only from mart.*.
-- Definitions shared by the views below:
--   booked        = NOT is_cancelled AND NOT is_deleted, dated by order date
--   delivered     = delivered_date_key IS NOT NULL (HISTORY or the
--                   ORDER_UPDATED_AT_ESTIMATE fallback; POS 'completed' counts)
--   net delivered = delivered AND NOT is_cancelled AND NOT is_deleted
--   v_order_cohort_daily / v_delivered_net_daily delivered_* and returned_* are NET
--   OF CANCELLATION, so they differ from v_sales_daily / v_sales_buyer_daily /
--   v_sales_province_daily delivered_* (gross, later-cancelled orders retained);
--   only booked_* reconciles one-to-one across marts.
--   product revenue = line_subtotal_amount (after line discounts, before
--   order-level fee/tax); shares need a line-sales denominator to reconcile.
--   customer_key = 0 (unknown / walk-in) is kept in sums so marts reconcile;
--   filter customer_key <> 0 for people counts. Only mart.v_customer_profile
--   exposes a customer name among these views; mask it in the API and exports.
-- =====================================================================

-- A1. Order-date cohort. One consistent population for cancel / delivered /
-- return rates. Grain: order date x channel.
-- Reconciles: booked_* == mart.v_sales_daily.booked_* for the same date/channel.
CREATE OR REPLACE VIEW mart.v_order_cohort_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  COUNT(*)::BIGINT AS order_count_all,
  COUNT(*) FILTER (WHERE NOT o.is_cancelled)::BIGINT AS booked_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE NOT o.is_cancelled), 0)::NUMERIC(18, 2) AS booked_sales_amount,
  COUNT(*) FILTER (WHERE o.is_cancelled)::BIGINT AS cancelled_order_count,
  COALESCE(SUM(o.total_amount) FILTER (WHERE o.is_cancelled), 0)::NUMERIC(18, 2) AS cancelled_sales_amount,
  COUNT(*) FILTER (
    WHERE NOT o.is_cancelled AND o.delivered_date_key IS NOT NULL
  )::BIGINT AS delivered_order_count,
  COALESCE(SUM(o.total_amount) FILTER (
    WHERE NOT o.is_cancelled AND o.delivered_date_key IS NOT NULL
  ), 0)::NUMERIC(18, 2) AS delivered_sales_amount,
  COUNT(*) FILTER (
    WHERE NOT o.is_cancelled AND o.delivered_date_key IS NULL
  )::BIGINT AS undelivered_order_count,
  COUNT(*) FILTER (
    WHERE NOT o.is_cancelled
      AND o.delivered_date_key IS NOT NULL
      AND o.return_received_at IS NOT NULL
  )::BIGINT AS returned_order_count
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
WHERE NOT o.is_deleted
GROUP BY d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name;


-- A2. Net delivered sales by delivery date ("delivered, excluding cancelled").
-- Grain: delivered date x channel.
-- Unlike mart.v_sales_daily.delivered_*, later-cancelled orders are excluded.
CREATE OR REPLACE VIEW mart.v_delivered_net_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  COUNT(*)::BIGINT AS delivered_order_count,
  COALESCE(SUM(o.total_amount), 0)::NUMERIC(18, 2) AS delivered_sales_amount,
  COUNT(*) FILTER (
    WHERE o.delivery_timestamp_source = 'ORDER_UPDATED_AT_ESTIMATE'
  )::BIGINT AS delivered_estimated_timestamp_count
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.delivered_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
WHERE o.delivered_date_key IS NOT NULL
  AND NOT o.is_cancelled
  AND NOT o.is_deleted
GROUP BY d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name;


-- A3. Customer profile: ONE row per known customer; the only mart exposing the
-- customer name. First/last purchase + lifetime totals over ALL retained
-- history (booked orders). The API derives new / repeat / lapsed per window:
--   new    : first_order_date within the window
--   repeat : first_order_date < window start AND bought in the window
--   lapsed : last_order_date < (as-of date - 60 days)
-- Customer identity = local OLTP customer id (not a verified unique person).
CREATE OR REPLACE VIEW mart.v_customer_profile AS
WITH booked AS (
  SELECT o.customer_key, o.order_key, o.order_at, o.order_date_key, o.channel_key, o.total_amount
  FROM dw.fact_order AS o
  WHERE o.customer_key <> 0
    AND NOT o.is_cancelled
    AND NOT o.is_deleted
), totals AS (
  SELECT
    customer_key,
    MIN(order_date_key) AS first_order_date_key,
    MAX(order_date_key) AS last_order_date_key,
    COUNT(*)::BIGINT AS lifetime_order_count,
    COALESCE(SUM(total_amount), 0)::NUMERIC(18, 2) AS lifetime_sales_amount
  FROM booked
  GROUP BY customer_key
), first_channel AS (
  SELECT DISTINCT ON (customer_key) customer_key, channel_key
  FROM booked
  ORDER BY customer_key, order_at, order_key
), used_channels AS (
  SELECT b.customer_key, ARRAY_AGG(DISTINCT c.channel_code ORDER BY c.channel_code) AS channel_codes
  FROM booked AS b
  JOIN dw.dim_channel AS c ON c.channel_key = b.channel_key
  WHERE c.channel_code IS NOT NULL
  GROUP BY b.customer_key
)
SELECT
  cust.customer_key,
  cust.source_system,
  cust.customer_source_id AS buyer_source_id,
  cust.customer_name,
  cust.latest_province_name,
  cust.latest_postal_code,
  d_first.calendar_date AS first_order_date,
  d_last.calendar_date AS last_order_date,
  t.lifetime_order_count,
  t.lifetime_sales_amount,
  first_ch.channel_code AS first_channel_code,
  used.channel_codes
FROM totals AS t
JOIN dw.dim_customer AS cust ON cust.customer_key = t.customer_key
JOIN dw.dim_date AS d_first ON d_first.date_key = t.first_order_date_key
JOIN dw.dim_date AS d_last ON d_last.date_key = t.last_order_date_key
LEFT JOIN first_channel AS fc ON fc.customer_key = t.customer_key
LEFT JOIN dw.dim_channel AS first_ch ON first_ch.channel_key = fc.channel_key
LEFT JOIN used_channels AS used ON used.customer_key = t.customer_key;


-- A4. Purchase lines with order + customer context (order items, orders of a
-- product, purchase history). Grain: order line.
-- Cancelled orders are KEPT with is_cancelled so callers choose; deleted
-- orders/lines are excluded. No customer name (join mart.v_customer_profile).
CREATE OR REPLACE VIEW mart.v_customer_purchase_line AS
SELECT
  l.order_line_key,
  o.order_key,
  o.source_system,
  o.order_source_id,
  o.order_number,
  o.order_at,
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  o.customer_key,
  o.buyer_source_id,
  o.province_name,
  s.sku_key,
  s.sku_source_id,
  s.sku_code,
  s.product_source_id,
  s.product_name,
  s.category_source_id,
  s.category_name,
  s.attribute_value,
  s.size_value,
  l.quantity,
  l.unit_price,
  l.line_discount_amount,
  l.line_subtotal_amount,
  o.is_cancelled,
  o.delivered_date_key,
  (o.delivered_date_key IS NOT NULL) AS is_delivered
FROM dw.fact_order_line AS l
JOIN dw.fact_order AS o ON o.order_key = l.order_key
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
WHERE NOT o.is_deleted
  AND NOT l.is_deleted;


-- A5. Who bought which product (province x product matrix, per-product repeat %,
-- distinct buyers). Grain: order date x channel x product x customer x
-- order-time province. Same filters as mart.v_sales_product_daily, so
--   SUM(units_sold)/SUM(line_subtotal_amount) reconcile with it exactly.
-- Consumers: distinct buyers = COUNT(DISTINCT customer_key) WHERE customer_key <> 0
-- over the whole period (never sum daily distinct counts).
-- Repeat buyer of a product = SUM(order_count) >= 2 in window, or bought it before.
-- Grain is guaranteed by STABLE keys only (source_system + product_source_id,
-- customer_key); display names/ids are deterministic MAX() attributes.
-- product_source_id is only unique within product_source_system.
CREATE OR REPLACE VIEW mart.v_product_customer_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  s.source_system AS product_source_system,
  s.product_source_id,
  MAX(s.product_name) AS product_name,
  o.customer_key,
  MAX(o.buyer_source_id) AS buyer_source_id,
  o.province_name,
  COUNT(DISTINCT o.order_key)::BIGINT AS order_count,
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
  s.source_system, s.product_source_id,
  o.customer_key, o.province_name;


-- A6. Co-purchase ("มักซื้อคู่กับ"). Grain: order date x channel x unordered
-- product pair (a < b). Each pair counted once per order. Booked orders only.
-- NOTE: self-join per order; candidate for materialization if volume grows.
CREATE OR REPLACE VIEW mart.v_product_pair_daily AS
WITH order_products AS (
  SELECT
    o.order_key,
    o.order_date_key,
    o.channel_key,
    s.source_system,
    s.product_source_id,
    MAX(s.product_name) AS product_name
  FROM dw.fact_order_line AS l
  JOIN dw.fact_order AS o ON o.order_key = l.order_key
  JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
  WHERE NOT o.is_cancelled AND NOT o.is_deleted AND NOT l.is_deleted
    AND s.product_source_id IS NOT NULL
  GROUP BY o.order_key, o.order_date_key, o.channel_key, s.source_system, s.product_source_id
)
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  a.source_system AS product_source_system,
  a.product_source_id AS product_a_source_id,
  MAX(a.product_name) AS product_a_name,
  b.product_source_id AS product_b_source_id,
  MAX(b.product_name) AS product_b_name,
  COUNT(*)::BIGINT AS order_count
FROM order_products AS a
JOIN order_products AS b
  ON b.order_key = a.order_key
 AND b.source_system = a.source_system
 AND a.product_source_id < b.product_source_id
JOIN dw.dim_date AS d ON d.date_key = a.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = a.channel_key
GROUP BY
  d.date_key, d.calendar_date, c.channel_key, c.channel_code, c.channel_name,
  a.source_system, a.product_source_id, b.product_source_id;


-- A7. Latest captured stock per product (stock / days-of-cover).
-- Snapshots are capture-time state (not live, not back-filled). Days of cover is
-- computed by the API: available_quantity / (units_sold in window / window_days)
-- using mart.v_sales_product_daily; guard zero sales.
-- Each SKU contributes ITS OWN latest snapshot, so a product can mix ages:
-- oldest_snapshot_date_key / stale_sku_count expose that (stale = SKU whose
-- latest snapshot is older than the newest snapshot of any SKU). Show the stock
-- figure as "latest captured", and flag when stale_sku_count > 0.
CREATE OR REPLACE VIEW mart.v_product_stock_latest AS
WITH latest AS (
  SELECT DISTINCT ON (i.sku_key)
    i.sku_key, i.snapshot_date_key, i.captured_at,
    i.on_hand_quantity, i.reserved_quantity, i.available_quantity
  FROM dw.fact_inventory_daily_snapshot AS i
  ORDER BY i.sku_key, i.snapshot_date_key DESC
), latest_with_global AS (
  SELECT l.*, MAX(l.snapshot_date_key) OVER () AS global_latest_date_key
  FROM latest AS l
)
SELECT
  s.source_system,
  s.product_source_id,
  MAX(s.product_name) AS product_name,
  COUNT(*)::BIGINT AS sku_count,
  COUNT(*) FILTER (WHERE g.available_quantity = 0)::BIGINT AS out_of_stock_sku_count,
  COUNT(*) FILTER (WHERE g.snapshot_date_key < g.global_latest_date_key)::BIGINT AS stale_sku_count,
  SUM(g.on_hand_quantity)::BIGINT AS on_hand_quantity,
  SUM(g.reserved_quantity)::BIGINT AS reserved_quantity,
  SUM(g.available_quantity)::BIGINT AS available_quantity,
  MIN(g.snapshot_date_key) AS oldest_snapshot_date_key,
  MAX(g.snapshot_date_key) AS snapshot_date_key,
  MIN(g.captured_at) AS oldest_captured_at,
  MAX(g.captured_at) AS captured_at
FROM latest_with_global AS g
JOIN dw.dim_sku AS s ON s.sku_key = g.sku_key
WHERE NOT s.is_deleted
  AND s.product_source_id IS NOT NULL
GROUP BY s.source_system, s.product_source_id;


-- A8. Order-level operational detail (day -> orders, in-transit list).
-- Grain: order. shipped_at / cancelled_at are derived from status events.
-- Vocabulary follows backend OrderWorkflowService.js ORDER_STATUS (lower_snake_case)
-- plus its LEGACY_STATUS aliases (IN_TRANSIT -> carrier_picked_up,
-- AWAITING_SHIPMENT -> ready_to_ship, AWAITING_COLLECTION -> awaiting_carrier_pickup,
-- CANCEL -> cancelled). Historical rows may still hold legacy upper-case values,
-- hence LOWER(BTRIM()). Before relying on fulfillment_stage, confirm no other value
-- carries volume:
--   SELECT LOWER(BTRIM(new_status)), COUNT(*) FROM dw.fact_order_status_event GROUP BY 1;
-- Stages (first match wins):
--   CANCELLED, RETURN, DELIVERED, IN_TRANSIT (carrier picked up),
--   AWAITING_SHIPMENT (preparing / ready / shipping requested / awaiting pickup),
--   OPEN (pending, paid, deposit, cod, procurement, on_hold, ...).
-- shipped_at = first carrier_picked_up (or legacy in_transit) event, kept even if the
-- order later moves to RETURN/DELIVERED. No customer name (see mart.v_customer_profile).
CREATE OR REPLACE VIEW mart.v_order_operational_detail AS
WITH status_events AS (
  SELECT
    source_system,
    order_source_id,
    MIN(occurred_at) FILTER (
      WHERE LOWER(BTRIM(new_status)) IN ('carrier_picked_up', 'in_transit')
    ) AS shipped_at,
    MAX(occurred_at) FILTER (
      WHERE LOWER(BTRIM(new_status)) IN ('cancelled', 'cancel')
    ) AS cancelled_at
  FROM dw.fact_order_status_event
  GROUP BY source_system, order_source_id
)
SELECT
  o.order_key,
  o.source_system,
  o.order_source_id,
  o.order_number,
  o.order_at,
  d.date_key,
  d.calendar_date AS business_date,
  c.channel_key,
  c.channel_code,
  c.channel_name,
  o.customer_key,
  o.buyer_source_id,
  o.province_name,
  o.current_status,
  o.is_cancelled,
  CASE
    WHEN o.is_cancelled THEN 'CANCELLED'
    WHEN LOWER(BTRIM(o.current_status)) IN (
      'return_requested', 'return_under_review', 'return_confirmed', 'returned'
    ) THEN 'RETURN'
    WHEN o.delivered_date_key IS NOT NULL THEN 'DELIVERED'
    WHEN LOWER(BTRIM(o.current_status)) IN ('carrier_picked_up', 'in_transit') THEN 'IN_TRANSIT'
    WHEN LOWER(BTRIM(o.current_status)) IN (
      'preparing_shipment', 'ready_to_ship', 'shipping_requested', 'awaiting_carrier_pickup',
      'awaiting_shipment', 'awaiting_collection'
    ) THEN 'AWAITING_SHIPMENT'
    ELSE 'OPEN'
  END AS fulfillment_stage,
  o.subtotal_amount,
  o.discount_amount,
  o.shipping_fee_amount,
  o.tax_amount,
  o.total_amount,
  e.shipped_at,
  o.delivered_at,
  o.delivered_date_key,
  o.delivery_timestamp_source,
  e.cancelled_at,
  o.return_received_at
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
LEFT JOIN status_events AS e
  ON e.source_system = o.source_system
 AND e.order_source_id = o.order_source_id
WHERE NOT o.is_deleted;


-- A9. Cancelled orders list. Grain: order. cancel_reason is the final column
-- to preserve the existing CREATE OR REPLACE VIEW column prefix.
CREATE OR REPLACE VIEW mart.v_order_cancellation AS
SELECT
  o.order_key,
  o.source_system,
  o.order_source_id,
  o.order_number,
  o.order_at,
  d.calendar_date AS business_date,
  c.channel_code,
  c.channel_name,
  o.customer_key,
  o.buyer_source_id,
  o.total_amount,
  ev.cancelled_at,
  ev.cancel_action,
  ev.cancel_reason
FROM dw.fact_order AS o
JOIN dw.dim_date AS d ON d.date_key = o.order_date_key
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
LEFT JOIN LATERAL (
  SELECT e.occurred_at AS cancelled_at, e.action AS cancel_action, e.reason AS cancel_reason
  FROM dw.fact_order_status_event AS e
  WHERE e.source_system = o.source_system
    AND e.order_source_id = o.order_source_id
    AND LOWER(BTRIM(e.new_status)) IN ('cancelled', 'cancel')
  ORDER BY e.occurred_at DESC, e.event_source_id DESC
  LIMIT 1
) AS ev ON TRUE
WHERE o.is_cancelled
  AND NOT o.is_deleted;


-- A10. CF payment facts per Facebook order (overdue CF list). Grain: one row
-- per Facebook order that has a CF fact. RAW facts + eligibility only: the
-- overdue / paid-late / matured assessment must be done by the API with the SAME
-- cutoff parameter, source_system filter and Bangkok CF-date scope as its summary
-- (AnalyticsService.js socialAssessedCte/socialOutcomeColumns), so the list and the
-- rate can never disagree. Do NOT bake a cutoff into this view.
--   eligible    = is_eligible  (= NOT is_cod AND is_data_complete)
--   fully_paid  = paid_in_full_at IS NOT NULL AND paid_in_full_at <= cutoff
--   matured     = eligible AND payment_due_at <= cutoff
--   overdue_unpaid = matured AND NOT fully_paid          (includes cancelled orders)
--   paid_late   = matured AND fully_paid AND paid_in_full_at > payment_due_at
--   missed_deadline = overdue_unpaid OR paid_late        (numerator of nonPaymentRate)
-- The CF key and reserved product are exposed separately in
-- mart.v_social_order_reserve at reserve grain.
CREATE OR REPLACE VIEW mart.v_social_order_action AS
SELECT
  f.source_system,
  f.order_source_id,
  o.order_key,
  o.order_number,
  o.customer_key,
  o.buyer_source_id,
  c.channel_code,
  f.cf_at,
  f.payment_due_at,
  f.required_amount,
  f.confirmed_paid_amount,
  GREATEST(f.required_amount - f.confirmed_paid_amount, 0)::NUMERIC(18, 2) AS outstanding_amount,
  f.paid_in_full_at,
  f.is_cod,
  f.is_cancelled,
  f.is_data_complete,
  (NOT f.is_cod AND f.is_data_complete) AS is_eligible,
  prim.product_source_id AS primary_product_source_id,
  prim.product_name AS primary_product_name,
  prim.line_count
FROM dw.fact_social_order AS f
JOIN dw.fact_order AS o
  ON o.source_system = f.source_system
 AND o.order_source_id = f.order_source_id
JOIN dw.dim_channel AS c ON c.channel_key = o.channel_key
LEFT JOIN LATERAL (
  SELECT
    s.product_source_id,
    s.product_name,
    (COUNT(*) OVER ())::BIGINT AS line_count
  FROM dw.fact_order_line AS l
  JOIN dw.dim_sku AS s ON s.sku_key = l.sku_key
  WHERE l.order_key = o.order_key
    AND NOT l.is_deleted
  ORDER BY l.line_subtotal_amount DESC, l.order_line_key
  LIMIT 1
) AS prim ON TRUE
WHERE NOT f.is_deleted
  AND NOT o.is_deleted;


-- B2. Confirmed payment totals by order and payment-method id. Grouping by the
-- stable method id keeps renamed labels in one row; MAX() chooses one label
-- deterministically within that group.
CREATE OR REPLACE VIEW mart.v_order_payment_method AS
SELECT
  o.order_key,
  o.source_system,
  o.order_source_id,
  o.customer_key,
  p.payment_method_source_id,
  COALESCE(MAX(p.payment_method_name), 'ไม่ระบุ') AS payment_method_name,
  COUNT(*) FILTER (WHERE p.confirmed)::BIGINT AS confirmed_transaction_count,
  COALESCE(SUM(p.amount) FILTER (WHERE p.confirmed), 0)::NUMERIC(18, 2) AS confirmed_paid_amount,
  MIN(p.verified_at) FILTER (WHERE p.confirmed) AS first_verified_at
FROM (
  SELECT
    t.*,
    (
      LOWER(BTRIM(t.current_status)) = 'completed'
      AND NOT t.is_deleted
      AND t.amount > 0
    ) AS confirmed
  FROM dw.fact_payment_transaction AS t
) AS p
JOIN dw.fact_order AS o
  ON o.source_system = p.source_system
 AND o.order_source_id = p.order_source_id
WHERE NOT p.is_deleted
  AND NOT o.is_deleted
GROUP BY
  o.order_key, o.source_system, o.order_source_id, o.customer_key,
  p.payment_method_source_id;


-- B3. Facebook CF reserve detail. Grain: reserve. Keep the
-- reserve row even when its source SKU is unknown; the ETL stores sku_key NULL.
-- Keyword is restricted free text and customer identity is intentionally absent.
CREATE OR REPLACE VIEW mart.v_social_order_reserve AS
SELECT
  r.source_system,
  r.reserve_source_id,
  r.order_source_id,
  r.keyword,
  r.quantity,
  r.status AS reserve_status,
  r.created_at,
  r.reserved_until,
  s.sku_key,
  s.sku_code,
  s.product_source_id,
  s.product_name
FROM dw.fact_facebook_reserve AS r
LEFT JOIN dw.dim_sku AS s ON s.sku_key = r.sku_key
WHERE NOT r.is_deleted;


-- Promotion code is restricted to stg/dw. This view exposes current terms and
-- the first/last dates for which an actual daily snapshot is available.
CREATE OR REPLACE VIEW mart.v_promotion AS
WITH snapshot_dates AS (
  SELECT
    promotion_key,
    MIN(snapshot_date_key) AS first_snapshot_date_key,
    MAX(snapshot_date_key) AS last_snapshot_date_key
  FROM dw.fact_promotion_daily_snapshot
  GROUP BY promotion_key
)
SELECT
  promotion.promotion_key,
  promotion.source_system,
  promotion.promotion_source_id,
  promotion.promotion_name,
  promotion.discount_type,
  promotion.discount_value,
  promotion.min_purchase_amount,
  promotion.max_discount_amount,
  promotion.usage_limit,
  promotion.usage_count,
  promotion.start_at,
  promotion.end_at,
  promotion.is_active,
  promotion.is_deleted,
  promotion.source_updated_at,
  first_date.calendar_date AS first_snapshot_date,
  last_date.calendar_date AS last_snapshot_date
FROM dw.dim_promotion AS promotion
LEFT JOIN snapshot_dates AS snapshots ON snapshots.promotion_key = promotion.promotion_key
LEFT JOIN dw.dim_date AS first_date ON first_date.date_key = snapshots.first_snapshot_date_key
LEFT JOIN dw.dim_date AS last_date ON last_date.date_key = snapshots.last_snapshot_date_key;

-- Grain: order business date, channel, and source promotion id. Unresolved
-- promotion ids remain visible with a NULL promotion_name.
CREATE OR REPLACE VIEW mart.v_sales_promotion_daily AS
SELECT
  d.date_key,
  d.calendar_date AS business_date,
  channel.channel_key,
  channel.channel_code,
  channel.channel_name,
  line.promotion_source_id,
  promotion.promotion_name,
  COUNT(DISTINCT order_fact.order_key)::BIGINT AS booked_order_count,
  SUM(line.quantity)::BIGINT AS units_sold,
  COALESCE(SUM(line.line_discount_amount), 0)::NUMERIC(18, 2) AS line_discount_amount,
  COALESCE(SUM(line.line_subtotal_amount), 0)::NUMERIC(18, 2) AS line_subtotal_amount
FROM dw.fact_order_line AS line
JOIN dw.fact_order AS order_fact ON order_fact.order_key = line.order_key
JOIN dw.dim_date AS d ON d.date_key = order_fact.order_date_key
JOIN dw.dim_channel AS channel ON channel.channel_key = order_fact.channel_key
LEFT JOIN dw.dim_promotion AS promotion ON promotion.promotion_key = line.promotion_key
WHERE line.promotion_source_id IS NOT NULL
  AND NOT line.is_deleted
  AND NOT order_fact.is_cancelled
  AND NOT order_fact.is_deleted
GROUP BY
  d.date_key, d.calendar_date, channel.channel_key, channel.channel_code,
  channel.channel_name, line.promotion_source_id, promotion.promotion_name;
