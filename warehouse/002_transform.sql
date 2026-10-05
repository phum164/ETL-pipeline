-- Apply a staged db_oltp extract. The caller reads etl.load_batch.status after this function returns.
CREATE OR REPLACE FUNCTION etl.apply_sales_stock_batch(p_batch_id UUID)
RETURNS TABLE (result_batch_id UUID, result_status TEXT, rejected_count BIGINT, result_error_message TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
  v_batch etl.load_batch%ROWTYPE;
  v_rejected_count BIGINT := 0;
  v_error TEXT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('warehouse_db:apply_sales_stock_batch'));

  SELECT * INTO v_batch
  FROM etl.load_batch
  WHERE load_batch.batch_id = p_batch_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown ETL batch %', p_batch_id;
  END IF;

  IF v_batch.status IN ('SUCCEEDED', 'SUCCEEDED_WITH_REJECTS') THEN
    SELECT COUNT(*) INTO v_rejected_count FROM etl.rejected_row WHERE rejected_row.batch_id = p_batch_id;
    RETURN QUERY SELECT p_batch_id, v_batch.status, v_rejected_count, v_batch.error_message;
    RETURN;
  END IF;

  UPDATE etl.load_batch
  SET status = 'RUNNING', started_at = COALESCE(started_at, CURRENT_TIMESTAMP), error_message = NULL
  WHERE load_batch.batch_id = p_batch_id;

  BEGIN
    IF EXISTS (
      SELECT 1 FROM stg.sales_channels
      WHERE stg.sales_channels.batch_id = p_batch_id
        AND COALESCE(BTRIM(code), '') = ''
    ) THEN
      RAISE EXCEPTION 'sales_channels contains a blank code';
    END IF;

    PERFORM etl.ensure_dates(ARRAY(
      SELECT etl.business_date(source_at)
      FROM (
        SELECT order_at AS source_at FROM stg.orders WHERE stg.orders.batch_id = p_batch_id
        UNION ALL SELECT occurred_at FROM stg.order_status_history WHERE stg.order_status_history.batch_id = p_batch_id
        UNION ALL SELECT movement_at FROM stg.inventory_movements WHERE stg.inventory_movements.batch_id = p_batch_id
        UNION ALL SELECT as_of_at FROM stg.skus WHERE stg.skus.batch_id = p_batch_id
        UNION ALL SELECT as_of_at FROM stg.sku_on_channel WHERE stg.sku_on_channel.batch_id = p_batch_id
      ) AS source_dates
    ));

    INSERT INTO dw.dim_channel (
      source_system, channel_source_id, channel_code, channel_name,
      is_active, is_deleted, source_updated_at, last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, source_id, code, name, is_active, deleted_at IS NOT NULL,
      source_updated_at, p_batch_id
    FROM stg.sales_channels
    WHERE stg.sales_channels.batch_id = p_batch_id
    ON CONFLICT (source_system, channel_source_id) DO UPDATE SET
      channel_code = EXCLUDED.channel_code,
      channel_name = EXCLUDED.channel_name,
      is_active = EXCLUDED.is_active,
      is_deleted = EXCLUDED.is_deleted,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.dim_channel.source_updated_at;

    INSERT INTO dw.dim_sku (
      source_system, sku_source_id, sku_code, product_source_id, product_name,
      category_source_id, category_name, attribute_value, size_value, unit_cost,
      selling_price, min_stock_level, is_active, is_deleted, source_updated_at,
      last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, source_id, sku_code, product_source_id, product_name,
      category_source_id, category_name, attribute_value, size_value, unit_cost,
      selling_price, min_stock_level, is_active, deleted_at IS NOT NULL,
      source_updated_at, p_batch_id
    FROM stg.skus
    WHERE stg.skus.batch_id = p_batch_id
    ON CONFLICT (source_system, sku_source_id) DO UPDATE SET
      sku_code = EXCLUDED.sku_code,
      product_source_id = EXCLUDED.product_source_id,
      product_name = EXCLUDED.product_name,
      category_source_id = EXCLUDED.category_source_id,
      category_name = EXCLUDED.category_name,
      attribute_value = EXCLUDED.attribute_value,
      size_value = EXCLUDED.size_value,
      unit_cost = EXCLUDED.unit_cost,
      selling_price = EXCLUDED.selling_price,
      min_stock_level = EXCLUDED.min_stock_level,
      is_active = EXCLUDED.is_active,
      is_deleted = EXCLUDED.is_deleted,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.dim_sku.source_updated_at;

    INSERT INTO dw.dim_customer (
      source_system, customer_source_id, customer_name, latest_province_name,
      latest_postal_code, source_updated_at, last_loaded_batch_id
    )
    SELECT DISTINCT ON (o.buyer_source_id)
      v_batch.source_system, o.buyer_source_id, o.buyer_name, o.province_name,
      o.postal_code, o.source_updated_at, p_batch_id
    FROM stg.orders AS o
    WHERE o.batch_id = p_batch_id
      AND o.buyer_source_id IS NOT NULL
    ORDER BY o.buyer_source_id, o.source_updated_at DESC, o.source_id DESC
    ON CONFLICT (source_system, customer_source_id) DO UPDATE SET
      customer_name = EXCLUDED.customer_name,
      latest_province_name = EXCLUDED.latest_province_name,
      latest_postal_code = EXCLUDED.latest_postal_code,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.dim_customer.source_updated_at;

    INSERT INTO dw.fact_order (
      source_system, order_source_id, order_number, order_at, order_date_key, channel_key,
      customer_key, buyer_source_id, buyer_name, province_name, postal_code,
      current_status, is_cancelled, is_deleted, delivered_at, delivered_date_key,
      delivery_timestamp_source, return_received_at, subtotal_amount, discount_amount, shipping_fee_amount,
      tax_amount, total_amount, source_updated_at, last_loaded_batch_id
    )
    WITH delivered_history AS (
      SELECT history.order_source_id, MIN(history.occurred_at) AS delivered_at
      FROM stg.order_status_history AS history
      JOIN stg.orders AS staged_order
        ON staged_order.batch_id = p_batch_id
       AND staged_order.source_id = history.order_source_id
      LEFT JOIN dw.dim_channel AS history_channel
        ON history_channel.source_system = v_batch.source_system
       AND history_channel.channel_source_id = staged_order.channel_source_id
      WHERE history.batch_id = p_batch_id
        AND (
          LOWER(BTRIM(history.new_status)) = 'delivered'
          OR (
            UPPER(BTRIM(history_channel.channel_code)) = 'POS'
            AND LOWER(BTRIM(history.new_status)) = 'completed'
          )
        )
      GROUP BY history.order_source_id
    )
    SELECT
      v_batch.source_system, o.source_id, o.order_number, o.order_at, etl.date_key(o.order_at),
      COALESCE(channel.channel_key, 0), COALESCE(customer.customer_key, 0),
      o.buyer_source_id, o.buyer_name, o.province_name, o.postal_code,
      o.current_status,
      LOWER(BTRIM(o.current_status)) = 'cancelled', o.deleted_at IS NOT NULL,
      COALESCE(h.delivered_at, CASE
        WHEN LOWER(BTRIM(o.current_status)) = 'delivered' THEN o.source_updated_at
        WHEN UPPER(BTRIM(channel.channel_code)) = 'POS'
          AND LOWER(BTRIM(o.current_status)) = 'completed' THEN o.order_at
      END),
      etl.date_key(COALESCE(h.delivered_at, CASE
        WHEN LOWER(BTRIM(o.current_status)) = 'delivered' THEN o.source_updated_at
        WHEN UPPER(BTRIM(channel.channel_code)) = 'POS'
          AND LOWER(BTRIM(o.current_status)) = 'completed' THEN o.order_at
      END)),
      CASE
        WHEN h.delivered_at IS NOT NULL THEN 'HISTORY'
        WHEN LOWER(BTRIM(o.current_status)) = 'delivered' THEN 'ORDER_UPDATED_AT_ESTIMATE'
        WHEN UPPER(BTRIM(channel.channel_code)) = 'POS'
          AND LOWER(BTRIM(o.current_status)) = 'completed' THEN 'ORDER_UPDATED_AT_ESTIMATE'
      END,
      o.return_received_at,
      o.subtotal_amount, o.discount_amount, o.shipping_fee_amount, o.tax_amount,
      o.total_amount, o.source_updated_at, p_batch_id
    FROM stg.orders AS o
    LEFT JOIN delivered_history AS h ON h.order_source_id = o.source_id
    LEFT JOIN dw.dim_channel AS channel
      ON channel.source_system = v_batch.source_system AND channel.channel_source_id = o.channel_source_id
    LEFT JOIN dw.dim_customer AS customer
      ON customer.source_system = v_batch.source_system AND customer.customer_source_id = o.buyer_source_id
    WHERE o.batch_id = p_batch_id
    ON CONFLICT (source_system, order_source_id) DO UPDATE SET
      order_number = EXCLUDED.order_number,
      order_at = EXCLUDED.order_at,
      order_date_key = EXCLUDED.order_date_key,
      channel_key = EXCLUDED.channel_key,
      customer_key = EXCLUDED.customer_key,
      buyer_source_id = EXCLUDED.buyer_source_id,
      buyer_name = EXCLUDED.buyer_name,
      province_name = EXCLUDED.province_name,
      postal_code = EXCLUDED.postal_code,
      current_status = EXCLUDED.current_status,
      is_cancelled = EXCLUDED.is_cancelled,
      is_deleted = EXCLUDED.is_deleted,
      delivered_at = CASE
        WHEN dw.fact_order.delivered_at IS NULL THEN EXCLUDED.delivered_at
        WHEN EXCLUDED.delivered_at IS NULL THEN dw.fact_order.delivered_at
        ELSE LEAST(dw.fact_order.delivered_at, EXCLUDED.delivered_at)
      END,
      delivered_date_key = CASE
        WHEN dw.fact_order.delivered_at IS NULL THEN EXCLUDED.delivered_date_key
        WHEN EXCLUDED.delivered_at IS NULL THEN dw.fact_order.delivered_date_key
        WHEN EXCLUDED.delivered_at < dw.fact_order.delivered_at THEN EXCLUDED.delivered_date_key
        ELSE dw.fact_order.delivered_date_key
      END,
      delivery_timestamp_source = CASE
        WHEN EXCLUDED.delivery_timestamp_source = 'HISTORY' THEN 'HISTORY'
        WHEN dw.fact_order.delivery_timestamp_source IS NULL THEN EXCLUDED.delivery_timestamp_source
        ELSE dw.fact_order.delivery_timestamp_source
      END,
      return_received_at = CASE
        WHEN dw.fact_order.return_received_at IS NULL THEN EXCLUDED.return_received_at
        WHEN EXCLUDED.return_received_at IS NULL THEN dw.fact_order.return_received_at
        ELSE LEAST(dw.fact_order.return_received_at, EXCLUDED.return_received_at)
      END,
      subtotal_amount = EXCLUDED.subtotal_amount,
      discount_amount = EXCLUDED.discount_amount,
      shipping_fee_amount = EXCLUDED.shipping_fee_amount,
      tax_amount = EXCLUDED.tax_amount,
      total_amount = EXCLUDED.total_amount,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.fact_order.source_updated_at;

    -- Delivery can arrive after the order row. POS completion is immediate handover.
    WITH delivered_history AS (
      SELECT history.order_source_id, MIN(history.occurred_at) AS delivered_at
      FROM stg.order_status_history AS history
      JOIN dw.fact_order AS existing_order
        ON existing_order.source_system = v_batch.source_system
       AND existing_order.order_source_id = history.order_source_id
      JOIN dw.dim_channel AS history_channel
        ON history_channel.channel_key = existing_order.channel_key
      WHERE history.batch_id = p_batch_id
        AND (
          LOWER(BTRIM(history.new_status)) = 'delivered'
          OR (
            UPPER(BTRIM(history_channel.channel_code)) = 'POS'
            AND LOWER(BTRIM(history.new_status)) = 'completed'
          )
        )
      GROUP BY history.order_source_id
    )
    UPDATE dw.fact_order AS f
    SET delivered_at = CASE
          WHEN f.delivered_at IS NULL THEN h.delivered_at
          ELSE LEAST(f.delivered_at, h.delivered_at)
        END,
        delivered_date_key = etl.date_key(CASE
          WHEN f.delivered_at IS NULL THEN h.delivered_at
          ELSE LEAST(f.delivered_at, h.delivered_at)
        END),
        delivery_timestamp_source = 'HISTORY',
        last_loaded_batch_id = p_batch_id
    FROM delivered_history AS h
    WHERE f.source_system = v_batch.source_system
      AND f.order_source_id = h.order_source_id;

    INSERT INTO dw.fact_facebook_reserve (
      source_system, reserve_source_id, order_source_id, created_at, reserved_until,
      status, is_deleted, source_updated_at, last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, source_id, order_source_id, created_at, reserved_until,
      status, deleted_at IS NOT NULL, source_updated_at, p_batch_id
    FROM stg.facebook_reserves
    WHERE stg.facebook_reserves.batch_id = p_batch_id
    ON CONFLICT (source_system, reserve_source_id) DO UPDATE SET
      order_source_id = EXCLUDED.order_source_id,
      created_at = EXCLUDED.created_at,
      reserved_until = EXCLUDED.reserved_until,
      status = EXCLUDED.status,
      is_deleted = EXCLUDED.is_deleted,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.fact_facebook_reserve.source_updated_at;

    INSERT INTO dw.fact_payment_transaction (
      source_system, payment_source_id, order_source_id, amount, current_status,
      payment_at, verified_at, is_deleted, source_updated_at, last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, source_id, order_source_id, amount, current_status,
      payment_at, verified_at, deleted_at IS NOT NULL, source_updated_at, p_batch_id
    FROM stg.payment_transactions
    WHERE stg.payment_transactions.batch_id = p_batch_id
    ON CONFLICT (source_system, payment_source_id) DO UPDATE SET
      order_source_id = EXCLUDED.order_source_id,
      amount = EXCLUDED.amount,
      current_status = EXCLUDED.current_status,
      payment_at = EXCLUDED.payment_at,
      verified_at = EXCLUDED.verified_at,
      is_deleted = EXCLUDED.is_deleted,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.fact_payment_transaction.source_updated_at;

    INSERT INTO dw.fact_order_status_event (
      source_system, event_source_id, order_source_id, new_status, action,
      occurred_at, source_updated_at, last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, source_id, order_source_id, new_status, action,
      occurred_at, source_updated_at, p_batch_id
    FROM stg.order_status_history
    WHERE stg.order_status_history.batch_id = p_batch_id
    ON CONFLICT (source_system, event_source_id) DO UPDATE SET
      order_source_id = EXCLUDED.order_source_id,
      new_status = EXCLUDED.new_status,
      action = EXCLUDED.action,
      occurred_at = EXCLUDED.occurred_at,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.fact_order_status_event.source_updated_at;

    INSERT INTO etl.rejected_row (batch_id, entity_name, source_id, reason, payload)
    SELECT
      p_batch_id, 'order_lines', l.source_id, 'Missing parent order or SKU dimension',
      jsonb_build_object('order_source_id', l.order_source_id, 'sku_source_id', l.sku_source_id)
    FROM stg.order_lines AS l
    LEFT JOIN dw.fact_order AS o
      ON o.source_system = v_batch.source_system AND o.order_source_id = l.order_source_id
    LEFT JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = l.sku_source_id
    WHERE l.batch_id = p_batch_id AND (o.order_key IS NULL OR s.sku_key IS NULL)
    ON CONFLICT (batch_id, entity_name, source_id, reason) DO NOTHING;

    INSERT INTO dw.fact_order_line (
      source_system, order_line_source_id, order_key, sku_key, quantity, unit_price,
      line_discount_amount, line_subtotal_amount, is_deleted, source_updated_at,
      last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, l.source_id, o.order_key, s.sku_key, l.quantity, l.unit_price,
      l.line_discount_amount, l.line_subtotal_amount, l.deleted_at IS NOT NULL,
      l.source_updated_at, p_batch_id
    FROM stg.order_lines AS l
    JOIN dw.fact_order AS o
      ON o.source_system = v_batch.source_system AND o.order_source_id = l.order_source_id
    JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = l.sku_source_id
    WHERE l.batch_id = p_batch_id
    ON CONFLICT (source_system, order_line_source_id) DO UPDATE SET
      order_key = EXCLUDED.order_key,
      sku_key = EXCLUDED.sku_key,
      quantity = EXCLUDED.quantity,
      unit_price = EXCLUDED.unit_price,
      line_discount_amount = EXCLUDED.line_discount_amount,
      line_subtotal_amount = EXCLUDED.line_subtotal_amount,
      is_deleted = EXCLUDED.is_deleted,
      source_updated_at = EXCLUDED.source_updated_at,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.source_updated_at >= dw.fact_order_line.source_updated_at;

    INSERT INTO etl.rejected_row (batch_id, entity_name, source_id, reason, payload)
    SELECT
      p_batch_id, 'inventory_movements', m.source_id, 'Missing SKU dimension',
      jsonb_build_object('sku_source_id', m.sku_source_id)
    FROM stg.inventory_movements AS m
    LEFT JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = m.sku_source_id
    WHERE m.batch_id = p_batch_id AND s.sku_key IS NULL
    ON CONFLICT (batch_id, entity_name, source_id, reason) DO NOTHING;

    INSERT INTO dw.fact_inventory_movement (
      source_system, movement_source_id, sku_key, movement_at, movement_date_key,
      on_hand_delta, reserved_delta, on_hand_before, on_hand_after, reserved_before,
      reserved_after, inventory_version, operation, reason, source_name, reference_type,
      reference_id, last_loaded_batch_id
    )
    SELECT
      v_batch.source_system, m.source_id, s.sku_key, m.movement_at, etl.date_key(m.movement_at),
      m.on_hand_delta, m.reserved_delta, m.on_hand_before, m.on_hand_after,
      m.reserved_before, m.reserved_after, m.inventory_version, m.operation, m.reason,
      m.source_name, m.reference_type, m.reference_id, p_batch_id
    FROM stg.inventory_movements AS m
    JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = m.sku_source_id
    WHERE m.batch_id = p_batch_id
    ON CONFLICT (source_system, movement_source_id) DO NOTHING;

    INSERT INTO dw.fact_inventory_daily_snapshot (
      snapshot_date_key, sku_key, captured_at, on_hand_quantity, reserved_quantity,
      available_quantity, min_stock_level, is_low_stock, last_loaded_batch_id
    )
    SELECT
      etl.date_key(s.as_of_at), d.sku_key, s.as_of_at, s.on_hand_quantity, s.reserved_quantity,
      GREATEST(s.on_hand_quantity - s.reserved_quantity, 0), s.min_stock_level,
      GREATEST(s.on_hand_quantity - s.reserved_quantity, 0) <= s.min_stock_level,
      p_batch_id
    FROM stg.skus AS s
    JOIN dw.dim_sku AS d
      ON d.source_system = v_batch.source_system AND d.sku_source_id = s.source_id
    WHERE s.batch_id = p_batch_id
    ON CONFLICT (snapshot_date_key, sku_key) DO UPDATE SET
      captured_at = EXCLUDED.captured_at,
      on_hand_quantity = EXCLUDED.on_hand_quantity,
      reserved_quantity = EXCLUDED.reserved_quantity,
      available_quantity = EXCLUDED.available_quantity,
      min_stock_level = EXCLUDED.min_stock_level,
      is_low_stock = EXCLUDED.is_low_stock,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.captured_at >= dw.fact_inventory_daily_snapshot.captured_at;

    INSERT INTO etl.rejected_row (batch_id, entity_name, source_id, reason, payload)
    SELECT
      p_batch_id, 'sku_on_channel', sc.sku_source_id,
      'Missing SKU or channel dimension',
      jsonb_build_object('sku_source_id', sc.sku_source_id, 'channel_source_id', sc.channel_source_id)
    FROM stg.sku_on_channel AS sc
    LEFT JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = sc.sku_source_id
    LEFT JOIN dw.dim_channel AS c
      ON c.source_system = v_batch.source_system AND c.channel_source_id = sc.channel_source_id
    WHERE sc.batch_id = p_batch_id AND (s.sku_key IS NULL OR c.channel_key IS NULL)
    ON CONFLICT (batch_id, entity_name, source_id, reason) DO NOTHING;

    INSERT INTO dw.fact_channel_inventory_daily_snapshot (
      snapshot_date_key, sku_key, channel_key, captured_at, allocated_quantity,
      allocated_reserved_quantity, safety_stock_quantity, target_quantity, remote_quantity,
      available_quantity, inventory_dirty, is_active, last_loaded_batch_id
    )
    SELECT
      etl.date_key(sc.as_of_at), s.sku_key, c.channel_key, sc.as_of_at,
      sc.allocated_quantity, sc.allocated_reserved_quantity, sc.safety_stock_quantity,
      sc.target_quantity, sc.remote_quantity, sc.available_quantity, sc.inventory_dirty,
      sc.is_active AND sc.deleted_at IS NULL, p_batch_id
    FROM stg.sku_on_channel AS sc
    JOIN dw.dim_sku AS s
      ON s.source_system = v_batch.source_system AND s.sku_source_id = sc.sku_source_id
    JOIN dw.dim_channel AS c
      ON c.source_system = v_batch.source_system AND c.channel_source_id = sc.channel_source_id
    WHERE sc.batch_id = p_batch_id
    ON CONFLICT (snapshot_date_key, sku_key, channel_key) DO UPDATE SET
      captured_at = EXCLUDED.captured_at,
      allocated_quantity = EXCLUDED.allocated_quantity,
      allocated_reserved_quantity = EXCLUDED.allocated_reserved_quantity,
      safety_stock_quantity = EXCLUDED.safety_stock_quantity,
      target_quantity = EXCLUDED.target_quantity,
      remote_quantity = EXCLUDED.remote_quantity,
      available_quantity = EXCLUDED.available_quantity,
      inventory_dirty = EXCLUDED.inventory_dirty,
      is_active = EXCLUDED.is_active,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id
    WHERE EXCLUDED.captured_at >= dw.fact_channel_inventory_daily_snapshot.captured_at;

    -- The immutable reserve deadline is the source of the 24-hour cohort.
    -- Invalid or missing deadlines remain as undated, incomplete facts.
    WITH reserve_summary AS (
      SELECT
        source_system,
        order_source_id,
        MIN(created_at) AS first_reserve_at,
        MIN(reserved_until) AS earliest_due_at,
        MAX(reserved_until) AS latest_due_at,
        COUNT(*) FILTER (WHERE reserved_until IS NULL) AS missing_due_count,
        COUNT(*) AS linked_reserve_count
      FROM dw.fact_facebook_reserve
      WHERE source_system = v_batch.source_system
        AND order_source_id IS NOT NULL
      GROUP BY source_system, order_source_id
    ), payment_totals AS (
      SELECT
        source_system,
        order_source_id,
        COALESCE(SUM(amount) FILTER (
          WHERE LOWER(BTRIM(current_status)) = 'completed'
            AND NOT is_deleted
            AND amount > 0
        ), 0)::NUMERIC(18, 2) AS confirmed_paid_amount,
        COALESCE(BOOL_OR(
          LOWER(BTRIM(current_status)) = 'completed'
          AND NOT is_deleted
          AND amount > 0
          AND verified_at IS NULL
        ), FALSE) AS has_untimed_completed_payment,
        COALESCE(BOOL_OR(
          LOWER(BTRIM(current_status)) = 'refunded'
          AND verified_at IS NOT NULL
        ), FALSE) AS has_refund_evidence
      FROM dw.fact_payment_transaction
      WHERE source_system = v_batch.source_system
      GROUP BY source_system, order_source_id
    ), paid_steps AS (
      SELECT
        payment.source_system,
        payment.order_source_id,
        payment.verified_at,
        orders.total_amount AS required_amount,
        SUM(payment.amount) OVER (
          PARTITION BY payment.source_system, payment.order_source_id
          ORDER BY payment.verified_at, payment.payment_source_id
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_paid_amount
      FROM dw.fact_payment_transaction AS payment
      JOIN dw.fact_order AS orders
        ON orders.source_system = payment.source_system
       AND orders.order_source_id = payment.order_source_id
      WHERE payment.source_system = v_batch.source_system
        AND LOWER(BTRIM(payment.current_status)) = 'completed'
        AND NOT payment.is_deleted
        AND payment.amount > 0
        AND payment.verified_at IS NOT NULL
    ), paid_in_full AS (
      SELECT
        source_system,
        order_source_id,
        MIN(verified_at) FILTER (
          WHERE cumulative_paid_amount >= required_amount
        ) AS paid_in_full_at
      FROM paid_steps
      GROUP BY source_system, order_source_id
    ), order_status_signals AS (
      SELECT
        source_system,
        order_source_id,
        BOOL_OR(LOWER(BTRIM(new_status)) = 'cod') AS has_cod_history,
        BOOL_OR(LOWER(BTRIM(new_status)) = 'paid') AS has_paid_history
      FROM dw.fact_order_status_event
      WHERE source_system = v_batch.source_system
      GROUP BY source_system, order_source_id
    ), social_orders AS (
      SELECT
        orders.source_system,
        orders.order_source_id,
        CASE
          WHEN reserves.missing_due_count = 0
            AND reserves.linked_reserve_count > 0
            AND reserves.earliest_due_at = reserves.latest_due_at
            AND reserves.earliest_due_at >= reserves.first_reserve_at + INTERVAL '24 hours'
          THEN reserves.earliest_due_at - INTERVAL '24 hours'
        END AS cf_at,
        CASE
          WHEN reserves.missing_due_count = 0
            AND reserves.linked_reserve_count > 0
            AND reserves.earliest_due_at = reserves.latest_due_at
            AND reserves.earliest_due_at >= reserves.first_reserve_at + INTERVAL '24 hours'
          THEN reserves.earliest_due_at
        END AS payment_due_at,
        orders.total_amount AS required_amount,
        COALESCE(payments.confirmed_paid_amount, 0)::NUMERIC(18, 2) AS confirmed_paid_amount,
        paid.paid_in_full_at,
        COALESCE(signals.has_cod_history, FALSE)
          OR LOWER(BTRIM(orders.current_status)) = 'cod' AS is_cod,
        orders.is_cancelled,
        orders.is_deleted,
        (
          reserves.missing_due_count = 0
          AND reserves.linked_reserve_count > 0
          AND reserves.earliest_due_at = reserves.latest_due_at
          AND reserves.earliest_due_at >= reserves.first_reserve_at + INTERVAL '24 hours'
          AND orders.total_amount > 0
          AND NOT COALESCE(payments.has_untimed_completed_payment, FALSE)
          AND NOT (
            COALESCE(payments.has_refund_evidence, FALSE)
            AND paid.paid_in_full_at IS NULL
          )
          AND NOT (
            (COALESCE(signals.has_paid_history, FALSE)
              OR LOWER(BTRIM(orders.current_status)) = 'paid')
            AND (
              COALESCE(payments.confirmed_paid_amount, 0) < orders.total_amount
              OR paid.paid_in_full_at IS NULL
            )
          )
        ) AS is_data_complete
      FROM dw.fact_order AS orders
      JOIN dw.dim_channel AS channel ON channel.channel_key = orders.channel_key
      JOIN reserve_summary AS reserves
        ON reserves.source_system = orders.source_system
       AND reserves.order_source_id = orders.order_source_id
      LEFT JOIN payment_totals AS payments
        ON payments.source_system = orders.source_system
       AND payments.order_source_id = orders.order_source_id
      LEFT JOIN paid_in_full AS paid
        ON paid.source_system = orders.source_system
       AND paid.order_source_id = orders.order_source_id
      LEFT JOIN order_status_signals AS signals
        ON signals.source_system = orders.source_system
       AND signals.order_source_id = orders.order_source_id
      WHERE orders.source_system = v_batch.source_system
        AND UPPER(BTRIM(channel.channel_code)) IN ('FACEBOOK', 'FB', '1111')
    )
    INSERT INTO dw.fact_social_order (
      source_system, order_source_id, cf_at, payment_due_at, required_amount,
      confirmed_paid_amount, paid_in_full_at, is_cod, is_cancelled, is_deleted,
      is_data_complete, snapshot_as_of, last_loaded_batch_id
    )
    SELECT
      source_system, order_source_id, cf_at, payment_due_at, required_amount,
      confirmed_paid_amount, paid_in_full_at, is_cod, is_cancelled, is_deleted,
      is_data_complete, v_batch.source_window_ended_at, p_batch_id
    FROM social_orders
    ON CONFLICT (source_system, order_source_id) DO UPDATE SET
      cf_at = EXCLUDED.cf_at,
      payment_due_at = EXCLUDED.payment_due_at,
      required_amount = EXCLUDED.required_amount,
      confirmed_paid_amount = EXCLUDED.confirmed_paid_amount,
      paid_in_full_at = EXCLUDED.paid_in_full_at,
      is_cod = EXCLUDED.is_cod,
      is_cancelled = EXCLUDED.is_cancelled,
      is_deleted = EXCLUDED.is_deleted,
      is_data_complete = EXCLUDED.is_data_complete,
      snapshot_as_of = EXCLUDED.snapshot_as_of,
      last_loaded_batch_id = EXCLUDED.last_loaded_batch_id;

    -- A rejected row keeps its entity watermark at the previous position. The
    -- next incremental run must replay that entity after its parent/dimension
    -- is repaired; advancing here would permanently skip the rejected row.
    WITH candidate_watermarks AS (
      SELECT 'sales_channels'::TEXT AS entity_name, source_updated_at AS changed_at, source_id
      FROM stg.sales_channels WHERE stg.sales_channels.batch_id = p_batch_id
      UNION ALL SELECT 'skus', source_updated_at, source_id FROM stg.skus WHERE stg.skus.batch_id = p_batch_id
      UNION ALL SELECT 'orders', source_updated_at, source_id FROM stg.orders WHERE stg.orders.batch_id = p_batch_id
      UNION ALL SELECT 'order_status_history', source_updated_at, source_id FROM stg.order_status_history WHERE stg.order_status_history.batch_id = p_batch_id
      UNION ALL SELECT 'order_lines', source_updated_at, source_id FROM stg.order_lines WHERE stg.order_lines.batch_id = p_batch_id
      UNION ALL SELECT 'facebook_reserves', source_updated_at, source_id FROM stg.facebook_reserves WHERE stg.facebook_reserves.batch_id = p_batch_id
      UNION ALL SELECT 'payment_transactions', source_updated_at, source_id FROM stg.payment_transactions WHERE stg.payment_transactions.batch_id = p_batch_id
      UNION ALL SELECT 'inventory_movements', movement_at, source_id FROM stg.inventory_movements WHERE stg.inventory_movements.batch_id = p_batch_id
      UNION ALL SELECT 'sku_on_channel', source_updated_at, sku_source_id FROM stg.sku_on_channel WHERE stg.sku_on_channel.batch_id = p_batch_id
    ), ranked_watermarks AS (
      SELECT DISTINCT ON (entity_name) entity_name, changed_at, source_id
      FROM candidate_watermarks
      ORDER BY entity_name, changed_at DESC, source_id DESC
    )
    INSERT INTO etl.watermark (
      source_system, entity_name, last_changed_at, last_source_id, last_successful_batch_id
    )
    SELECT v_batch.source_system, entity_name, changed_at, source_id, p_batch_id
    FROM ranked_watermarks
    WHERE NOT EXISTS (
      SELECT 1
      FROM etl.rejected_row AS rejected
      WHERE rejected.batch_id = p_batch_id
        AND rejected.entity_name = ranked_watermarks.entity_name
    )
    ON CONFLICT (source_system, entity_name) DO UPDATE SET
      last_changed_at = EXCLUDED.last_changed_at,
      last_source_id = EXCLUDED.last_source_id,
      last_successful_batch_id = EXCLUDED.last_successful_batch_id,
      updated_at = CURRENT_TIMESTAMP
    WHERE EXCLUDED.last_changed_at > etl.watermark.last_changed_at
       OR (EXCLUDED.last_changed_at = etl.watermark.last_changed_at
           AND EXCLUDED.last_source_id > etl.watermark.last_source_id);

  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
    UPDATE etl.load_batch
    SET status = 'FAILED', completed_at = CURRENT_TIMESTAMP, error_message = v_error
    WHERE load_batch.batch_id = p_batch_id;
    RETURN QUERY SELECT p_batch_id, 'FAILED'::TEXT, 0::BIGINT, v_error;
    RETURN;
  END;

  SELECT COUNT(*) INTO v_rejected_count
  FROM etl.rejected_row
  WHERE rejected_row.batch_id = p_batch_id;

  UPDATE etl.load_batch
  SET status = CASE WHEN v_rejected_count > 0 THEN 'SUCCEEDED_WITH_REJECTS' ELSE 'SUCCEEDED' END,
      completed_at = CURRENT_TIMESTAMP,
      row_counts = jsonb_build_object(
        'sales_channels', (SELECT COUNT(*) FROM stg.sales_channels WHERE stg.sales_channels.batch_id = p_batch_id),
        'skus', (SELECT COUNT(*) FROM stg.skus WHERE stg.skus.batch_id = p_batch_id),
        'orders', (SELECT COUNT(*) FROM stg.orders WHERE stg.orders.batch_id = p_batch_id),
        'order_status_history', (SELECT COUNT(*) FROM stg.order_status_history WHERE stg.order_status_history.batch_id = p_batch_id),
        'order_lines', (SELECT COUNT(*) FROM stg.order_lines WHERE stg.order_lines.batch_id = p_batch_id),
        'facebook_reserves', (SELECT COUNT(*) FROM stg.facebook_reserves WHERE stg.facebook_reserves.batch_id = p_batch_id),
        'payment_transactions', (SELECT COUNT(*) FROM stg.payment_transactions WHERE stg.payment_transactions.batch_id = p_batch_id),
        'inventory_movements', (SELECT COUNT(*) FROM stg.inventory_movements WHERE stg.inventory_movements.batch_id = p_batch_id),
        'sku_on_channel', (SELECT COUNT(*) FROM stg.sku_on_channel WHERE stg.sku_on_channel.batch_id = p_batch_id),
        'rejected_rows', v_rejected_count
      )
  WHERE load_batch.batch_id = p_batch_id;

  RETURN QUERY SELECT
    p_batch_id,
    CASE WHEN v_rejected_count > 0 THEN 'SUCCEEDED_WITH_REJECTS' ELSE 'SUCCEEDED' END,
    v_rejected_count,
    NULL::TEXT;
END;
$$;
