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
from etl.pipeline import DATASETS, WAREHOUSE_CONTRACTS, _python_value, exit_code_for_status, prepare_frame
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

    def test_customer_dimension_is_part_of_warehouse_contract(self) -> None:
        self.assertIn("customer_source_id", WAREHOUSE_CONTRACTS[("dw", "dim_customer")])
        self.assertIn("customer_key", WAREHOUSE_CONTRACTS[("dw", "fact_order")])

    def test_status_exit_codes(self) -> None:
        self.assertEqual(exit_code_for_status("SUCCEEDED"), 0)
        self.assertEqual(exit_code_for_status("SUCCEEDED_WITH_REJECTS"), 2)
        self.assertEqual(exit_code_for_status("FAILED"), 1)

    def test_nullable_integer_values_are_copy_safe(self) -> None:
        self.assertEqual(_python_value(69.0), 69)
        self.assertIsNone(_python_value(float("nan")))

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
