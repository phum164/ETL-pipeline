from __future__ import annotations

import os
import sys
import unittest
import uuid
from datetime import datetime, timezone
from decimal import Decimal
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pandas as pd

from etl.config import Settings, normalize_postgres_url
from etl.pipeline import DATASETS, SOURCE_CONTRACTS, WAREHOUSE_CONTRACTS, _assert_delivery_evidence, _assert_reconciled, _python_value, _without_hard_deleted_orders, exit_code_for_status, prepare_frame
from etl.__main__ import main


class ConfigTests(unittest.TestCase):
    def test_prisma_schema_parameter_is_removed(self) -> None:
        result = normalize_postgres_url("postgresql://user:pass@localhost:5432/omsdb?schema=public&sslmode=disable")
        self.assertNotIn("schema=", result)
        self.assertIn("sslmode=disable", result)

    def test_same_database_is_rejected(self) -> None:
        values = {
            "OLTP_DATABASE_URL": "postgresql://reader:one@localhost/omsdb",
            "WAREHOUSE_DATABASE_URL": "postgresql://writer:two@localhost/omsdb",
        }
        with patch.dict(os.environ, values, clear=True):
            with self.assertRaisesRegex(ValueError, "different PostgreSQL databases"):
                Settings.from_env()

    def test_cli_configuration_failure_returns_one(self) -> None:
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["etl", "check"]), patch(
            "sys.stderr", new_callable=StringIO
        ):
            self.assertEqual(main(), 1)


class PipelineTests(unittest.TestCase):
    def test_orders_extract_buyer_fields(self) -> None:
        spec = next(item for item in DATASETS if item.name == "orders")
        self.assertTrue({"buyer_source_id", "buyer_name", "province_name", "postal_code"}.issubset(spec.columns))
        self.assertIn('"Province"', spec.query)
        self.assertIn('"Subdistrict"', spec.query)

    def test_orders_extract_completed_physical_returns_once(self) -> None:
        spec = next(item for item in DATASETS if item.name == "orders")
        self.assertIn("return_received_at", spec.columns)
        self.assertIn("MIN(rr.received_at) AT TIME ZONE 'UTC'", spec.query)
        self.assertIn("ri.received_quantity > 0", spec.query)
        self.assertIn("return_requests", SOURCE_CONTRACTS)
        self.assertIn("return_items", SOURCE_CONTRACTS)

    def test_social_payment_extracts_keep_soft_deleted_cf_and_verified_time(self) -> None:
        reserves = next(item for item in DATASETS if item.name == "facebook_reserves")
        payments = next(item for item in DATASETS if item.name == "payment_transactions")
        history = next(item for item in DATASETS if item.name == "order_status_history")

        self.assertIn("deleted_at", reserves.columns)
        self.assertIn("deleted_at AT TIME ZONE 'UTC'", reserves.query)
        self.assertNotIn("deleted_at IS NULL", reserves.query)
        self.assertIn("updated_at AT TIME ZONE 'UTC'", reserves.query)
        self.assertIn("slip_checks", SOURCE_CONTRACTS)
        self.assertIn("LOWER(BTRIM(slip_check.status)) = 'complete'", payments.query)
        self.assertIn("slip_check.checked_at AT TIME ZONE 'UTC'", payments.query)
        self.assertIn("slip_check.updated_at AT TIME ZONE 'UTC'", payments.query)
        self.assertIn("payment.verified_at AT TIME ZONE 'UTC'", payments.query)
        self.assertIn("payment.updated_at AT TIME ZONE 'UTC'", payments.query)
        self.assertIn("orders.updated_at AT TIME ZONE 'UTC'", history.query)
        self.assertIn("source_updated_at", history.columns)

    def test_phase_b_extract_queries_include_requested_fields_and_rename_watermark(self) -> None:
        specs = {item.name: item for item in DATASETS}
        history = specs["order_status_history"]
        reserves = specs["facebook_reserves"]
        payments = specs["payment_transactions"]

        self.assertIn("reason", history.columns)
        self.assertIn("history.reason", history.query)
        for column in ("keyword", "sku_source_id", "quantity"):
            self.assertIn(column, reserves.columns)
        self.assertIn("skus_id::bigint AS sku_source_id", reserves.query)
        self.assertIn("keyword", reserves.query)
        self.assertIn("quantity", reserves.query)
        for column in ("payment_method_source_id", "payment_method_name"):
            self.assertIn(column, payments.columns)
        self.assertIn("payment_method.id::bigint AS payment_method_source_id", payments.query)
        self.assertIn("payment_method.name AS payment_method_name", payments.query)
        self.assertIn("LEFT JOIN payment_methods AS payment_method", payments.query)
        self.assertGreaterEqual(payments.query.count("payment_method.updated_at AT TIME ZONE 'UTC'"), 3)
        self.assertEqual(SOURCE_CONTRACTS["payment_methods"], ("id", "name", "updated_at"))
        self.assertIn("reason", SOURCE_CONTRACTS["order_status_history"])
        self.assertTrue({"keyword", "skus_id", "quantity"}.issubset(SOURCE_CONTRACTS["facebook_reserves"]))
        self.assertIn("payment_methods_id", SOURCE_CONTRACTS["payment_transactions"])

    def test_phase_b_extracts_do_not_select_restricted_source_fields(self) -> None:
        specs = {item.name: item for item in DATASETS}
        queries = (
            specs["order_status_history"].query.lower(),
            specs["facebook_reserves"].query.lower(),
            specs["payment_transactions"].query.lower(),
        )
        for field in (
            "notes", "metadata", "account_number", "account_name", "bank_name",
            "comment_text", "facebook_comment_id", "phone", "email", "address_line",
            "slip_image", "token",
        ):
            with self.subTest(field=field):
                self.assertTrue(all(field not in query for query in queries))

    def test_social_marts_are_checked_as_warehouse_contracts(self) -> None:
        self.assertIn("is_data_complete", WAREHOUSE_CONTRACTS[("dw", "fact_social_order")])
        self.assertIn("category_source_id", WAREHOUSE_CONTRACTS[("mart", "v_delivered_product_category_daily")])
        self.assertIn("snapshot_as_of", WAREHOUSE_CONTRACTS[("mart", "v_social_order_status")])

    def test_phase_b_and_phase_a_marts_are_checked_as_warehouse_contracts(self) -> None:
        phase_a_views = (
            "v_order_cohort_daily", "v_delivered_net_daily", "v_customer_profile",
            "v_customer_purchase_line", "v_product_customer_daily", "v_product_pair_daily",
            "v_product_stock_latest", "v_order_operational_detail", "v_order_cancellation",
            "v_social_order_action",
        )
        for view in phase_a_views:
            with self.subTest(view=view):
                self.assertIn(("mart", view), WAREHOUSE_CONTRACTS)

        self.assertEqual(WAREHOUSE_CONTRACTS[("mart", "v_order_cancellation")][-1], "cancel_reason")
        self.assertIn("payment_method_source_id", WAREHOUSE_CONTRACTS[("dw", "fact_payment_transaction")])
        self.assertIn("payment_method_name", WAREHOUSE_CONTRACTS[("dw", "fact_payment_transaction")])
        self.assertIn("reason", WAREHOUSE_CONTRACTS[("dw", "fact_order_status_event")])
        for column in ("keyword", "sku_key", "quantity"):
            self.assertIn(column, WAREHOUSE_CONTRACTS[("dw", "fact_facebook_reserve")])
        self.assertIn(("mart", "v_order_payment_method"), WAREHOUSE_CONTRACTS)
        self.assertIn(("mart", "v_social_order_reserve"), WAREHOUSE_CONTRACTS)

    def test_phase_c_promotion_extracts_use_full_snapshot_contracts_and_utc(self) -> None:
        specs = {item.name: item for item in DATASETS}
        promotions = specs["promotions"]
        memberships = specs["promotion_categories"]

        self.assertTrue(promotions.full_snapshot)
        self.assertEqual(promotions.key_columns, ("promotion_source_id",))
        self.assertIn("promotion_source_id", promotions.required_columns)
        self.assertIn("as_of_at", promotions.columns)
        promotion_selects = (
            ("id::bigint AS promotion_source_id", "promotion_source_id"),
            ("name AS promotion_name", "promotion_name"),
            ("code,", "code"),
            ("discount_type,", "discount_type"),
            ("discount_value,", "discount_value"),
            ("min_purchase AS min_purchase_amount", "min_purchase_amount"),
            ("max_discount AS max_discount_amount", "max_discount_amount"),
            ("usage_limit,", "usage_limit"),
            ("usage_count,", "usage_count"),
            ("start_date AT TIME ZONE 'UTC' AS start_at", "start_at"),
            ("end_date AT TIME ZONE 'UTC' AS end_at", "end_at"),
            ("is_active,", "is_active"),
            ("created_at AT TIME ZONE 'UTC' AS created_at", "created_at"),
            ("deleted_at AT TIME ZONE 'UTC' AS deleted_at", "deleted_at"),
            ("updated_at AT TIME ZONE 'UTC' AS source_updated_at", "source_updated_at"),
        )
        for expression, output_column in promotion_selects:
            with self.subTest(output_column=output_column):
                self.assertIn(expression, promotions.query)
                self.assertIn(output_column, promotions.columns)
        self.assertIn("FROM promotions", promotions.query)
        self.assertNotIn("description", promotions.query.lower())
        self.assertEqual(
            SOURCE_CONTRACTS["promotions"],
            (
                "id", "name", "code", "discount_type", "discount_value", "min_purchase",
                "max_discount", "usage_limit", "usage_count", "start_date", "end_date",
                "is_active", "created_at", "updated_at", "deleted_at",
            ),
        )
        self.assertTrue(
            {
                "promotion_source_id", "promotion_name", "code", "discount_type",
                "discount_value", "min_purchase_amount", "max_discount_amount",
                "usage_limit", "usage_count", "start_at", "end_at", "is_active",
                "created_at", "deleted_at", "source_updated_at", "as_of_at",
            }.issubset(promotions.columns)
        )

        self.assertTrue(memberships.full_snapshot)
        self.assertEqual(
            memberships.key_columns,
            ("promotion_source_id", "category_source_id"),
        )
        self.assertEqual(
            memberships.required_columns,
            ("promotion_source_id", "category_source_id"),
        )
        self.assertIn('"useCount" AS use_count', memberships.query)
        self.assertIn("FROM categories_has_promotions", memberships.query)
        self.assertTrue(
            {"promotion_source_id", "category_source_id", "use_count"}.issubset(memberships.columns)
        )
        for expression, output_column in (
            ("promotions_id::bigint AS promotion_source_id", "promotion_source_id"),
            ("category_id::bigint AS category_source_id", "category_source_id"),
            ('"useCount" AS use_count', "use_count"),
        ):
            with self.subTest(membership_output=output_column):
                self.assertIn(expression, memberships.query)
                self.assertIn(output_column, memberships.columns)
        self.assertEqual(
            SOURCE_CONTRACTS["categories_has_promotions"],
            ("category_id", "promotions_id", "useCount"),
        )

    def test_phase_c_order_line_promotion_ids_and_warehouse_contracts(self) -> None:
        line_spec = next(item for item in DATASETS if item.name == "order_lines")
        for field in ("categories_has_promotions_promotions_id", "categories_has_promotions_category_id"):
            self.assertIn(field, SOURCE_CONTRACTS["order_details"])
        for field, expression in (
            ("promotion_source_id", "categories_has_promotions_promotions_id::bigint AS promotion_source_id"),
            ("promotion_category_source_id", "categories_has_promotions_category_id::bigint AS promotion_category_source_id"),
        ):
            self.assertIn(field, line_spec.columns)
            self.assertIn(expression, line_spec.query)
        self.assertIn("WHERE (updated_at AT TIME ZONE 'UTC', id)", line_spec.query)

        line_contract = WAREHOUSE_CONTRACTS[("dw", "fact_order_line")]
        self.assertTrue(
            {"promotion_source_id", "promotion_category_source_id", "promotion_key"}.issubset(line_contract)
        )
        for contract, required in (
            (
                ("etl", "snapshot_state"),
                {"source_system", "entity_name", "snapshot_at", "snapshot_created_at", "last_successful_batch_id"},
            ),
            (
                ("dw", "dim_promotion"),
                {"promotion_key", "source_system", "promotion_source_id", "code", "source_updated_at"},
            ),
            (
                ("dw", "fact_promotion_daily_snapshot"),
                {"snapshot_date_key", "promotion_key", "captured_at", "discount_value", "usage_count"},
            ),
            (
                ("dw", "bridge_promotion_category"),
                {"source_system", "promotion_source_id", "category_source_id", "use_count", "promotion_key", "is_current"},
            ),
        ):
            with self.subTest(contract=contract):
                self.assertTrue(required.issubset(WAREHOUSE_CONTRACTS[contract]))
        self.assertTrue(
            {
                "promotion_key", "source_system", "promotion_source_id", "promotion_name",
                "discount_type", "discount_value", "first_snapshot_date", "last_snapshot_date",
            }.issubset(WAREHOUSE_CONTRACTS[("mart", "v_promotion")])
        )
        self.assertTrue(
            {
                "promotion_source_id", "promotion_name", "booked_order_count", "units_sold",
                "line_discount_amount", "line_subtotal_amount",
            }.issubset(WAREHOUSE_CONTRACTS[("mart", "v_sales_promotion_daily")])
        )
        for field in ("code", "buyer_name", "customer_name"):
            self.assertNotIn(field, WAREHOUSE_CONTRACTS[("mart", "v_promotion")])
            self.assertNotIn(field, WAREHOUSE_CONTRACTS[("mart", "v_sales_promotion_daily")])

    def test_hard_deleted_order_lines_use_full_id_snapshot(self) -> None:
        specs = {item.name: item for item in DATASETS}
        ids = specs["order_line_ids"]
        self.assertTrue(ids.full_snapshot)
        self.assertEqual(ids.columns, ("batch_id", "source_id", "order_source_id"))
        self.assertEqual(ids.key_columns, ("source_id",))
        self.assertEqual(ids.required_columns, ("source_id", "order_source_id"))
        self.assertIn("id::bigint AS source_id", ids.query)
        self.assertIn("orders_id::bigint AS order_source_id", ids.query)
        self.assertIn("FROM order_details", ids.query)
        # Soft-deleted lines still exist; only rows gone from the source count as deleted.
        self.assertNotIn("WHERE", ids.query)
        self.assertTrue({"is_deleted", "source_updated_at"}.issubset(WAREHOUSE_CONTRACTS[("dw", "fact_order_line")]))

        sql = (Path(__file__).parents[1] / "warehouse" / "002_transform.sql").read_text(encoding="utf-8")
        self.assertIn("SELECT 1 FROM stg.order_line_ids WHERE stg.order_line_ids.batch_id = p_batch_id", sql)
        self.assertIn("state.entity_name = 'order_line_ids'", sql)
        self.assertIn("IF v_apply_order_line_snapshot THEN", sql)
        self.assertIn("source_updated_at = GREATEST(line.source_updated_at, v_batch.source_window_ended_at)", sql)
        self.assertIn("AND staged.source_id = line.order_line_source_id", sql)
        self.assertLess(
            sql.index("INSERT INTO dw.fact_order_line"),
            sql.index("IF v_apply_order_line_snapshot THEN"),
        )

    def test_hard_deleted_orders_use_full_id_snapshot(self) -> None:
        ids = next(item for item in DATASETS if item.name == "order_ids")
        self.assertTrue(ids.full_snapshot)
        self.assertEqual(ids.columns, ("batch_id", "source_id"))
        self.assertEqual(ids.key_columns, ("source_id",))
        self.assertIn("SELECT id::bigint AS source_id", ids.query)
        self.assertIn("FROM orders", ids.query)
        # Soft-deleted orders still exist in the source and keep their own flag.
        self.assertNotIn("WHERE", ids.query)
        self.assertTrue({"is_deleted", "source_updated_at"}.issubset(WAREHOUSE_CONTRACTS[("dw", "fact_order")]))

        sql = (Path(__file__).parents[1] / "warehouse" / "002_transform.sql").read_text(encoding="utf-8")
        self.assertIn("SELECT 1 FROM stg.order_ids WHERE stg.order_ids.batch_id = p_batch_id", sql)
        self.assertIn("state.entity_name = 'order_ids'", sql)
        block = sql[sql.index("IF v_apply_order_snapshot THEN"):]
        block = block[:block.index("END IF;")]
        for statement in ("UPDATE dw.fact_order AS o", "UPDATE dw.fact_order_line AS line",
                          "UPDATE dw.fact_social_order AS social"):
            self.assertIn(statement, block)
        self.assertIn("source_updated_at = GREATEST(o.source_updated_at, v_batch.source_window_ended_at)", block)
        # Marked after both upserts and before the social fact is recomputed.
        self.assertLess(sql.index("INSERT INTO dw.fact_order_line"), sql.index("IF v_apply_order_snapshot THEN"))
        self.assertLess(sql.index("IF v_apply_order_snapshot THEN"), sql.index("INSERT INTO dw.fact_social_order"))

    def test_reused_order_ids_fail_the_batch_before_any_warehouse_write(self) -> None:
        sql = (Path(__file__).parents[1] / "warehouse" / "002_transform.sql").read_text(encoding="utf-8")
        guard = sql.index("SELECT COUNT(*) INTO v_reused_order_count")
        self.assertIn("staged.order_number IS DISTINCT FROM existing.order_number", sql)
        self.assertIn("RAISE EXCEPTION 'Source order ids were reused: %", sql)
        self.assertIn("warehouse-rebuild-after-oltp-reset.md", sql)
        # Inside the batch's exception block, ahead of the first dw write, so a
        # failure marks the batch FAILED and leaves the warehouse untouched.
        self.assertLess(sql.index("BEGIN\n    v_apply_promotion_category_snapshot"), guard)
        self.assertLess(guard, sql.index("INSERT INTO dw."))
        message = sql[sql.index("RAISE EXCEPTION 'Source order ids were reused"):]
        message = message[:message.index(";")]
        for restricted in ("buyer", "customer", "order_source_id"):
            self.assertNotIn(restricted, message)

    def test_customer_dimension_is_part_of_warehouse_contract(self) -> None:
        self.assertIn("customer_source_id", WAREHOUSE_CONTRACTS[("dw", "dim_customer")])
        self.assertIn("customer_key", WAREHOUSE_CONTRACTS[("dw", "fact_order")])
        self.assertIn("return_received_at", WAREHOUSE_CONTRACTS[("dw", "fact_order")])

    def test_delivered_sku_drilldown_is_checked_as_warehouse_contract(self) -> None:
        columns = WAREHOUSE_CONTRACTS[("mart", "v_delivered_sku_daily")]
        for column in ("business_date", "channel_code", "product_source_id", "sku_source_id",
                       "attribute_value", "size_value", "units_sold", "line_subtotal_amount"):
            self.assertIn(column, columns)

    def test_status_exit_codes(self) -> None:
        self.assertEqual(exit_code_for_status("SUCCEEDED"), 0)
        self.assertEqual(exit_code_for_status("SUCCEEDED_WITH_REJECTS"), 2)
        self.assertEqual(exit_code_for_status("FAILED"), 1)

    def test_nullable_integer_values_are_copy_safe(self) -> None:
        self.assertEqual(_python_value(69.0), 69)
        self.assertIsNone(_python_value(float("nan")))

    def test_copy_rejects_naive_timestamps_instead_of_using_session_timezone(self) -> None:
        with self.assertRaisesRegex(ValueError, 'timezone-naive'):
            _python_value(datetime(2026, 1, 31, 17))
        aware = datetime(2026, 1, 31, 17, tzinfo=timezone.utc)
        self.assertEqual(_python_value(pd.Timestamp(aware)), aware)

    def test_naive_source_event_and_watermark_fields_are_explicitly_utc(self) -> None:
        specs = {item.name: item for item in DATASETS}
        for name, expression in (
            ('orders', "o.order_date AT TIME ZONE 'UTC'"),
            ('orders', "MIN(rr.received_at) AT TIME ZONE 'UTC'"),
            ('order_lines', "WHERE (updated_at AT TIME ZONE 'UTC', id)"),
            ('inventory_movements', "created_at AT TIME ZONE 'UTC' AS movement_at"),
            ('inventory_movements', "WHERE (created_at AT TIME ZONE 'UTC', id)"),
        ):
            self.assertIn(expression, specs[name].query)

    def test_reconciliation_detects_same_totals_on_wrong_date_or_channel(self) -> None:
        correct = [(1, 'POS', '2026-02-01', 100), (2, 'TT', '2026-02-01', 200)]
        _assert_reconciled(correct, list(reversed(correct)))
        for wrong in (
            [(1, 'POS', '2026-01-31', 100), correct[1]],
            [(1, 'TT', '2026-02-01', 100), correct[1]],
            correct + [correct[0]],
            correct[1:],
        ):
            with self.assertRaisesRegex(RuntimeError, 'reconciliation failed'):
                _assert_reconciled(correct, wrong)

    def test_line_reconciliation_detects_line_left_after_source_hard_delete(self) -> None:
        source = [(38, 28, Decimal('350.00')), (39, 28, Decimal('350.00'))]
        _assert_reconciled(source, [(38, 28, Decimal('350')), (39, 28, Decimal('350'))], "Order line")
        for wrong in (
            source + [(37, 28, Decimal('700.00'))],
            [(38, 28, Decimal('350.00')), (39, 28, Decimal('300.00'))],
            source[:1],
        ):
            with self.assertRaisesRegex(RuntimeError, 'Order line reconciliation failed'):
                _assert_reconciled(source, wrong, "Order line")

    def test_order_reconciliation_skips_flagged_hard_deleted_orders_only(self) -> None:
        # (id, channel, order_at, delivered_at, received_at, is_cancelled, is_deleted, total)
        live = (1, 'POS', 'at', None, None, False, False, Decimal('700'))
        source = [live]
        flagged_gone = (2, 'Facebook', 'at', None, None, False, True, Decimal('1'))
        live_gone = (3, 'POS', 'at', None, None, False, False, Decimal('700'))

        kept = _without_hard_deleted_orders(source, [live, flagged_gone])
        self.assertEqual(kept, [live])
        _assert_reconciled(source, kept)

        kept = _without_hard_deleted_orders(source, [live, live_gone])
        with self.assertRaisesRegex(RuntimeError, 'reconciliation failed'):
            _assert_reconciled(source, kept)

        # A warehouse order flagged deleted while the source still has it live is a mismatch.
        wrongly_flagged = live[:6] + (True,) + live[7:]
        kept = _without_hard_deleted_orders(source, [wrongly_flagged])
        with self.assertRaisesRegex(RuntimeError, 'reconciliation failed'):
            _assert_reconciled(source, kept)

    def test_lost_checkout_history_is_reported_as_incomplete_not_a_timezone_bug(self) -> None:
        source = [(1, 'POS', 'order_at', None)]
        preserved = [(1, 'POS', 'order_at', 'checkout_at')]
        with self.assertRaisesRegex(RuntimeError, 'Delivery evidence is incomplete'):
            _assert_delivery_evidence(source, preserved, 0)
        with self.assertRaisesRegex(RuntimeError, 'non_pos_mutable_estimates=1'):
            _assert_delivery_evidence(preserved, preserved, 1)
        _assert_delivery_evidence(preserved, preserved, 0)

    def test_prepare_frame_adds_batch_and_snapshot_time(self) -> None:
        spec = next(item for item in DATASETS if item.name == "skus")
        frame = pd.DataFrame(
            [
                {
                    "source_id": 1,
                    "sku_code": "SKU-1",
                    "product_source_id": 10,
                    "product_name": "Silk",
                    "category_source_id": 20,
                    "category_name": "Fabric",
                    "attribute_value": None,
                    "size_value": None,
                    "unit_cost": 10,
                    "selling_price": 20,
                    "on_hand_quantity": 5,
                    "reserved_quantity": 2,
                    "min_stock_level": 1,
                    "is_active": True,
                    "deleted_at": None,
                    "source_updated_at": datetime(2026, 8, 1, tzinfo=timezone.utc),
                }
            ]
        )
        batch_id = uuid.UUID("11111111-1111-1111-1111-111111111111")
        as_of_at = datetime(2026, 8, 2, tzinfo=timezone.utc)

        result = prepare_frame(frame, spec, batch_id, as_of_at)

        self.assertEqual(result.loc[0, "batch_id"], str(batch_id))
        self.assertEqual(result.loc[0, "as_of_at"], as_of_at)
        self.assertEqual(list(result.columns), list(spec.columns))

    def test_prepare_frame_rejects_duplicate_source_keys(self) -> None:
        spec = next(item for item in DATASETS if item.name == "sales_channels")
        frame = pd.DataFrame(
            [
                {"source_id": 1, "code": "POS", "name": "POS", "is_active": True, "deleted_at": None, "source_updated_at": datetime.now(timezone.utc)},
                {"source_id": 1, "code": "POS", "name": "POS", "is_active": True, "deleted_at": None, "source_updated_at": datetime.now(timezone.utc)},
            ]
        )
        with self.assertRaisesRegex(ValueError, "duplicate source keys"):
            prepare_frame(frame, spec, uuid.uuid4(), datetime.now(timezone.utc))

    def test_rejected_entity_watermark_is_frozen_in_warehouse_sql(self) -> None:
        sql = (Path(__file__).parents[1] / "warehouse" / "002_transform.sql").read_text(encoding="utf-8")
        self.assertIn("rejected.entity_name = ranked_watermarks.entity_name", sql)
        self.assertIn("rejected.batch_id = p_batch_id", sql)


if __name__ == "__main__":
    unittest.main()
