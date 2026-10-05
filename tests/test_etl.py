from __future__ import annotations

import os
import sys
import unittest
import uuid
from datetime import datetime, timezone
from io import StringIO
from pathlib import Path
from unittest.mock import patch

import pandas as pd

from etl.config import Settings, normalize_postgres_url
from etl.pipeline import DATASETS, SOURCE_CONTRACTS, WAREHOUSE_CONTRACTS, _assert_delivery_evidence, _assert_reconciled, _python_value, exit_code_for_status, prepare_frame
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

    def test_social_marts_are_checked_as_warehouse_contracts(self) -> None:
        self.assertIn("is_data_complete", WAREHOUSE_CONTRACTS[("dw", "fact_social_order")])
        self.assertIn("category_source_id", WAREHOUSE_CONTRACTS[("mart", "v_delivered_product_category_daily")])
        self.assertIn("snapshot_as_of", WAREHOUSE_CONTRACTS[("mart", "v_social_order_status")])

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
