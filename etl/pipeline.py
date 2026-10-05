from __future__ import annotations

import logging
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, Iterable, Iterator

import pandas as pd
import psycopg
from psycopg import sql

from .config import Settings


LOGGER = logging.getLogger("warehouse_db_etl")
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
PIPELINE_LOCK_NAME = "warehouse_db:etl_pipeline"

# Keep this contract beside DATASETS so `check` fails before a batch is created
# when an OLTP table/column used by an extract has drifted.
SOURCE_CONTRACTS: dict[str, tuple[str, ...]] = {
    "sales_channels": ("sales_id", "code", "name", "deleted_at", "updated_at"),
    "skus": (
        "id", "sku_code", "products_id", "attribute", "size", "cost", "selling_price",
        "stock_quantity", "reserved_quantity", "min_stock_level", "is_active", "deleted_at", "updated_at",
    ),
    "products": ("id", "name", "is_active", "deleted_at", "updated_at", "categories_category_id"),
    "categories": ("category_id", "name", "is_active", "deleted_at", "updated_at"),
    "orders": (
        "id", "order_number", "order_date", "status", "sales_channels_sales_id", "customer_id",
        "shipping_details_id", "subtotal", "discount_amount", "shipping_fee", "tax_amount",
        "total_price", "deleted_at", "updated_at",
    ),
    "customer": ("id", "name", "deleted_at", "updated_at"),
    "shipping_details": ("id", "recipient_name", "shipping_address_id", "updated_at", "deleted_at"),
    "address": ("id", "name", "zip_code", "deleted_at", "updated_at", "province_id", "subdistrict_id"),
    "Province": ("id", "province"),
    "Subdistrict": ("id", "zip_code"),
    "order_status_history": ("id", "orders_id", "new_status", "action", "created_at"),
    "facebook_reserves": (
        "id", "order_id", "created_at", "reserved_until", "status", "deleted_at", "updated_at",
    ),
    "payment_transactions": (
        "id", "orders_id", "amount", "status", "payment_date", "verified_at", "slip_checks_id",
        "deleted_at", "updated_at",
    ),
    "slip_checks": ("id", "status", "checked_at", "updated_at"),
    "return_requests": ("id", "orders_id", "received_at", "updated_at"),
    "return_items": ("id", "return_requests_id", "received_quantity", "updated_at"),
    "order_details": (
        "id", "orders_id", "skus_id", "quantity", "unit_price", "discount", "subtotal",
        "deleted_at", "updated_at",
    ),
    "inventory_movements": (
        "id", "skus_id", "created_at", "on_hand_delta", "reserved_delta", "on_hand_before",
        "on_hand_after", "reserved_before", "reserved_after", "inventory_version", "operation",
        "reason", "source", "reference_type", "reference_id",
    ),
    "sku_on_channel": (
        "skus_id", "sales_channels_sales_id", "allocated_quantity", "allocated_reserved", "safety_stock",
        "target_quantity", "remote_quantity", "inventory_dirty", "is_active", "deleted_at", "updated_at",
    ),
}

WAREHOUSE_CONTRACTS: dict[tuple[str, str], tuple[str, ...]] = {
    ("etl", "load_batch"): ("batch_id", "source_system", "status", "completed_at"),
    ("etl", "watermark"): ("source_system", "entity_name", "last_changed_at", "last_source_id", "last_successful_batch_id"),
    ("etl", "rejected_row"): ("batch_id", "entity_name", "source_id", "reason"),
    ("dw", "dim_customer"): (
        "customer_key", "source_system", "customer_source_id", "customer_name",
        "latest_province_name", "latest_postal_code", "source_updated_at", "last_loaded_batch_id",
    ),
    ("dw", "fact_order"): (
        "customer_key", "buyer_source_id", "province_name", "return_received_at",
    ),
    ("dw", "fact_facebook_reserve"): (
        "source_system", "reserve_source_id", "order_source_id", "created_at", "reserved_until",
        "status", "is_deleted", "source_updated_at",
    ),
    ("dw", "fact_payment_transaction"): (
        "source_system", "payment_source_id", "order_source_id", "amount", "current_status",
        "payment_at", "verified_at", "is_deleted", "source_updated_at",
    ),
    ("dw", "fact_order_status_event"): (
        "source_system", "event_source_id", "order_source_id", "new_status", "action",
        "occurred_at", "source_updated_at",
    ),
    ("dw", "fact_social_order"): (
        "source_system", "order_source_id", "cf_at", "payment_due_at", "required_amount",
        "confirmed_paid_amount", "paid_in_full_at", "is_cod", "is_cancelled", "is_deleted",
        "is_data_complete", "snapshot_as_of",
    ),
    ("mart", "v_delivered_product_category_daily"): (
        "business_date", "channel_code", "category_source_id", "category_name",
        "product_source_id", "product_name", "units_sold", "line_subtotal_amount",
    ),
    ("mart", "v_delivered_sku_daily"): (
        "business_date", "channel_code", "product_source_id", "product_name",
        "sku_source_id", "sku_code", "attribute_value", "size_value",
        "units_sold", "line_subtotal_amount",
    ),
    ("mart", "v_social_order_status"): (
        "order_source_id", "cf_at", "payment_due_at", "required_amount", "confirmed_paid_amount",
        "paid_in_full_at", "is_cod", "is_cancelled", "is_data_complete", "is_deleted", "snapshot_as_of",
    ),
}


@dataclass(frozen=True)
class DatasetSpec:
    name: str
    staging_table: str
    columns: tuple[str, ...]
    query: str
    full_snapshot: bool = False
    required_columns: tuple[str, ...] = ()
    key_columns: tuple[str, ...] = ()


DATASETS: tuple[DatasetSpec, ...] = (
    DatasetSpec(
        name="sales_channels",
        staging_table="sales_channels",
        columns=("batch_id", "source_id", "code", "name", "is_active", "deleted_at", "source_updated_at"),
        full_snapshot=True,
        required_columns=("source_id", "code", "name", "source_updated_at"),
        key_columns=("source_id",),
        query="""
            SELECT
              sales_id::bigint AS source_id,
              code,
              name,
              deleted_at IS NULL AS is_active,
              deleted_at AT TIME ZONE 'UTC' AS deleted_at,
              updated_at AT TIME ZONE 'UTC' AS source_updated_at
            FROM sales_channels
            ORDER BY sales_id
        """,
    ),
    DatasetSpec(
        name="skus",
        staging_table="skus",
        columns=(
            "batch_id", "source_id", "sku_code", "product_source_id", "product_name",
            "category_source_id", "category_name", "attribute_value", "size_value",
            "unit_cost", "selling_price", "on_hand_quantity", "reserved_quantity",
            "min_stock_level", "is_active", "deleted_at", "source_updated_at", "as_of_at",
        ),
        full_snapshot=True,
        required_columns=(
            "source_id", "sku_code", "product_source_id", "product_name",
            "on_hand_quantity", "reserved_quantity", "source_updated_at",
        ),
        key_columns=("source_id",),
        query="""
            SELECT
              s.id::bigint AS source_id,
              s.sku_code,
              p.id::bigint AS product_source_id,
              p.name AS product_name,
              c.category_id::bigint AS category_source_id,
              c.name AS category_name,
              s.attribute AS attribute_value,
              s.size AS size_value,
              s.cost AS unit_cost,
              s.selling_price,
              s.stock_quantity AS on_hand_quantity,
              s.reserved_quantity,
              s.min_stock_level,
              (s.is_active AND p.is_active AND c.is_active
                AND s.deleted_at IS NULL AND p.deleted_at IS NULL AND c.deleted_at IS NULL) AS is_active,
              COALESCE(s.deleted_at, p.deleted_at, c.deleted_at) AT TIME ZONE 'UTC' AS deleted_at,
              GREATEST(s.updated_at, p.updated_at, c.updated_at) AT TIME ZONE 'UTC' AS source_updated_at
            FROM skus AS s
            JOIN products AS p ON p.id = s.products_id
            JOIN categories AS c ON c.category_id = p.categories_category_id
            ORDER BY s.id
        """,
    ),
    DatasetSpec(
        name="orders",
        staging_table="orders",
        columns=(
            "batch_id", "source_id", "order_number", "order_at", "current_status",
            "channel_source_id", "buyer_source_id", "buyer_name", "province_name", "postal_code",
            "return_received_at",
            "subtotal_amount", "discount_amount", "shipping_fee_amount",
            "tax_amount", "total_amount", "deleted_at", "source_updated_at",
        ),
        required_columns=("source_id", "order_at", "current_status", "source_updated_at"),
        key_columns=("source_id",),
        query="""
            WITH return_receipts AS (
              SELECT
                rr.orders_id,
                MIN(rr.received_at) AT TIME ZONE 'UTC' AS return_received_at,
                MAX(GREATEST(
                  rr.updated_at AT TIME ZONE 'UTC',
                  ri.updated_at AT TIME ZONE 'UTC'
                )) AS source_updated_at
              FROM return_requests AS rr
              JOIN return_items AS ri ON ri.return_requests_id = rr.id
              WHERE rr.received_at IS NOT NULL
                AND ri.received_quantity > 0
              GROUP BY rr.orders_id
            ), order_extract AS (
              SELECT
                o.id::bigint AS source_id,
                o.order_number,
                o.order_date AT TIME ZONE 'UTC' AS order_at,
                o.status AS current_status,
                o.sales_channels_sales_id::bigint AS channel_source_id,
                o.customer_id::bigint AS buyer_source_id,
                COALESCE(
                  NULLIF(BTRIM(CASE WHEN c.deleted_at IS NULL THEN c.name END), ''),
                  NULLIF(BTRIM(sd.recipient_name), ''),
                  NULLIF(BTRIM(a.name), '')
                ) AS buyer_name,
                CASE WHEN a.deleted_at IS NULL THEN p.province END AS province_name,
                COALESCE(
                  NULLIF(BTRIM(a.zip_code), ''),
                  NULLIF(BTRIM(sd_sub.zip_code::text), '')
                ) AS postal_code,
                returns.return_received_at,
                o.subtotal AS subtotal_amount,
                o.discount_amount,
                o.shipping_fee AS shipping_fee_amount,
                o.tax_amount,
                o.total_price AS total_amount,
                o.deleted_at AT TIME ZONE 'UTC' AS deleted_at,
                GREATEST(
                  o.updated_at AT TIME ZONE 'UTC',
                  COALESCE(c.updated_at AT TIME ZONE 'UTC', o.updated_at AT TIME ZONE 'UTC'),
                  COALESCE(sd.updated_at AT TIME ZONE 'UTC', o.updated_at AT TIME ZONE 'UTC'),
                  COALESCE(a.updated_at AT TIME ZONE 'UTC', o.updated_at AT TIME ZONE 'UTC'),
                  COALESCE(returns.source_updated_at, o.updated_at AT TIME ZONE 'UTC')
                ) AS source_updated_at
              FROM orders AS o
              LEFT JOIN customer AS c ON c.id = o.customer_id
              LEFT JOIN shipping_details AS sd ON sd.id = o.shipping_details_id
              LEFT JOIN address AS a ON a.id = sd.shipping_address_id
              LEFT JOIN "Province" AS p ON p.id = a.province_id
              LEFT JOIN "Subdistrict" AS sd_sub ON sd_sub.id = a.subdistrict_id
              LEFT JOIN return_receipts AS returns ON returns.orders_id = o.id
            )
            SELECT *
            FROM order_extract
            WHERE (source_updated_at, source_id) > (%(window_start)s, %(cursor_id)s)
              AND source_updated_at <= %(window_end)s
            ORDER BY source_updated_at, source_id
        """,
    ),
    DatasetSpec(
        name="order_status_history",
        staging_table="order_status_history",
        columns=(
            "batch_id", "source_id", "order_source_id", "new_status", "action",
            "occurred_at", "source_updated_at",
        ),
        required_columns=(
            "source_id", "order_source_id", "new_status", "occurred_at", "source_updated_at",
        ),
        key_columns=("source_id",),
        query="""
            SELECT
              history.id::bigint AS source_id,
              history.orders_id::bigint AS order_source_id,
              history.new_status,
              history.action,
              history.created_at AT TIME ZONE 'UTC' AS occurred_at,
              GREATEST(
                history.created_at AT TIME ZONE 'UTC',
                orders.updated_at AT TIME ZONE 'UTC'
              ) AS source_updated_at
            FROM order_status_history AS history
            JOIN orders ON orders.id = history.orders_id
            WHERE (GREATEST(
                     history.created_at AT TIME ZONE 'UTC',
                     orders.updated_at AT TIME ZONE 'UTC'
                   ), history.id) > (%(window_start)s, %(cursor_id)s)
              AND GREATEST(
                    history.created_at AT TIME ZONE 'UTC',
                    orders.updated_at AT TIME ZONE 'UTC'
                  ) <= %(window_end)s
            ORDER BY source_updated_at, history.id
        """,
    ),
    DatasetSpec(
        name="facebook_reserves",
        staging_table="facebook_reserves",
        columns=(
            "batch_id", "source_id", "order_source_id", "created_at", "reserved_until",
            "status", "deleted_at", "source_updated_at",
        ),
        required_columns=("source_id", "created_at", "status", "source_updated_at"),
        key_columns=("source_id",),
        query="""
            SELECT
              id::bigint AS source_id,
              order_id::bigint AS order_source_id,
              created_at AT TIME ZONE 'UTC' AS created_at,
              reserved_until AT TIME ZONE 'UTC' AS reserved_until,
              status,
              deleted_at AT TIME ZONE 'UTC' AS deleted_at,
              updated_at AT TIME ZONE 'UTC' AS source_updated_at
            FROM facebook_reserves
            WHERE (updated_at AT TIME ZONE 'UTC', id) > (%(window_start)s, %(cursor_id)s)
              AND (updated_at AT TIME ZONE 'UTC') <= %(window_end)s
            ORDER BY source_updated_at, id
        """,
    ),
    DatasetSpec(
        name="payment_transactions",
        staging_table="payment_transactions",
        columns=(
            "batch_id", "source_id", "order_source_id", "amount", "current_status",
            "payment_at", "verified_at", "deleted_at", "source_updated_at",
        ),
        required_columns=(
            "source_id", "order_source_id", "amount", "current_status", "source_updated_at",
        ),
        key_columns=("source_id",),
        query="""
            SELECT
              payment.id::bigint AS source_id,
              payment.orders_id::bigint AS order_source_id,
              payment.amount,
              payment.status AS current_status,
              payment.payment_date AT TIME ZONE 'UTC' AS payment_at,
              COALESCE(
                payment.verified_at AT TIME ZONE 'UTC',
                CASE WHEN LOWER(BTRIM(slip_check.status)) = 'complete'
                  THEN slip_check.checked_at AT TIME ZONE 'UTC'
                END
              ) AS verified_at,
              payment.deleted_at AT TIME ZONE 'UTC' AS deleted_at,
              GREATEST(
                payment.updated_at AT TIME ZONE 'UTC',
                COALESCE(slip_check.updated_at AT TIME ZONE 'UTC', payment.updated_at AT TIME ZONE 'UTC')
              ) AS source_updated_at
            FROM payment_transactions AS payment
            LEFT JOIN slip_checks AS slip_check ON slip_check.id = payment.slip_checks_id
            WHERE (GREATEST(
                     payment.updated_at AT TIME ZONE 'UTC',
                     COALESCE(slip_check.updated_at AT TIME ZONE 'UTC', payment.updated_at AT TIME ZONE 'UTC')
                   ), payment.id) > (%(window_start)s, %(cursor_id)s)
              AND GREATEST(
                    payment.updated_at AT TIME ZONE 'UTC',
                    COALESCE(slip_check.updated_at AT TIME ZONE 'UTC', payment.updated_at AT TIME ZONE 'UTC')
                  ) <= %(window_end)s
            ORDER BY source_updated_at, payment.id
        """,
    ),
    DatasetSpec(
        name="order_lines",
        staging_table="order_lines",
        columns=(
            "batch_id", "source_id", "order_source_id", "sku_source_id", "quantity",
            "unit_price", "line_discount_amount", "line_subtotal_amount", "deleted_at",
            "source_updated_at",
        ),
        required_columns=(
            "source_id", "order_source_id", "sku_source_id", "quantity", "unit_price",
            "line_subtotal_amount", "source_updated_at",
        ),
        key_columns=("source_id",),
        query="""
            SELECT
              id::bigint AS source_id,
              orders_id::bigint AS order_source_id,
              skus_id::bigint AS sku_source_id,
              quantity,
              unit_price,
              discount AS line_discount_amount,
              subtotal AS line_subtotal_amount,
              deleted_at AT TIME ZONE 'UTC' AS deleted_at,
              updated_at AT TIME ZONE 'UTC' AS source_updated_at
            FROM order_details
            WHERE (updated_at AT TIME ZONE 'UTC', id) > (%(window_start)s, %(cursor_id)s)
              AND (updated_at AT TIME ZONE 'UTC') <= %(window_end)s
            ORDER BY updated_at, id
        """,
    ),
    DatasetSpec(
        name="inventory_movements",
        staging_table="inventory_movements",
        columns=(
            "batch_id", "source_id", "sku_source_id", "movement_at", "on_hand_delta",
            "reserved_delta", "on_hand_before", "on_hand_after", "reserved_before",
            "reserved_after", "inventory_version", "operation", "reason", "source_name",
            "reference_type", "reference_id",
        ),
        required_columns=(
            "source_id", "sku_source_id", "movement_at", "on_hand_delta", "on_hand_before",
            "on_hand_after", "reserved_before", "reserved_after", "inventory_version",
            "operation", "reason", "source_name",
        ),
        key_columns=("source_id",),
        query="""
            SELECT
              id::bigint AS source_id,
              skus_id::bigint AS sku_source_id,
              created_at AT TIME ZONE 'UTC' AS movement_at,
              on_hand_delta,
              reserved_delta,
              on_hand_before,
              on_hand_after,
              reserved_before,
              reserved_after,
              inventory_version,
              operation::text AS operation,
              reason,
              source::text AS source_name,
              reference_type,
              reference_id
            FROM inventory_movements
            WHERE (created_at AT TIME ZONE 'UTC', id) > (%(window_start)s, %(cursor_id)s)
              AND (created_at AT TIME ZONE 'UTC') <= %(window_end)s
            ORDER BY created_at, id
        """,
    ),
    DatasetSpec(
        name="sku_on_channel",
        staging_table="sku_on_channel",
        columns=(
            "batch_id", "sku_source_id", "channel_source_id", "allocated_quantity",
            "allocated_reserved_quantity", "safety_stock_quantity", "target_quantity",
            "remote_quantity", "available_quantity", "inventory_dirty", "is_active",
            "deleted_at", "source_updated_at", "as_of_at",
        ),
        full_snapshot=True,
        required_columns=(
            "sku_source_id", "channel_source_id", "allocated_quantity", "target_quantity",
            "available_quantity", "source_updated_at",
        ),
        key_columns=("sku_source_id", "channel_source_id"),
        query="""
            SELECT
              sc.skus_id::bigint AS sku_source_id,
              sc.sales_channels_sales_id::bigint AS channel_source_id,
              sc.allocated_quantity,
              sc.allocated_reserved AS allocated_reserved_quantity,
              sc.safety_stock AS safety_stock_quantity,
              sc.target_quantity,
              sc.remote_quantity,
              GREATEST(s.stock_quantity - s.reserved_quantity, 0) AS available_quantity,
              sc.inventory_dirty,
              (sc.is_active AND sc.deleted_at IS NULL) AS is_active,
              sc.deleted_at AT TIME ZONE 'UTC' AS deleted_at,
              GREATEST(sc.updated_at, s.updated_at) AT TIME ZONE 'UTC' AS source_updated_at
            FROM sku_on_channel AS sc
            JOIN skus AS s ON s.id = sc.skus_id
            ORDER BY sc.skus_id, sc.sales_channels_sales_id
        """,
    ),
)


def exit_code_for_status(status: str) -> int:
    return {"SUCCEEDED": 0, "SUCCEEDED_WITH_REJECTS": 2}.get(status, 1)


def _python_value(value: Any) -> Any:
    if value is None:
        return None
    try:
        if pd.isna(value):
            return None
    except (TypeError, ValueError):
        pass
    if isinstance(value, pd.Timestamp):
        value = value.to_pydatetime()
    if isinstance(value, datetime) and value.tzinfo is None:
        raise ValueError("ETL timestamp is timezone-naive; interpret the OLTP field as UTC in the extract")
    if hasattr(value, "item") and not isinstance(value, (str, bytes, Decimal)):
        value = value.item()
    if isinstance(value, float) and value.is_integer():
        return int(value)
    return value


def prepare_frame(frame: pd.DataFrame, spec: DatasetSpec, batch_id: uuid.UUID, as_of_at: datetime) -> pd.DataFrame:
    frame = frame.copy()
    missing_columns = [column for column in spec.columns if column not in frame.columns and column not in {"batch_id", "as_of_at"}]
    if missing_columns:
        raise ValueError(f"{spec.name}: missing columns {', '.join(missing_columns)}")

    frame.insert(0, "batch_id", str(batch_id))
    if "as_of_at" in spec.columns:
        frame["as_of_at"] = as_of_at

    null_columns = [column for column in spec.required_columns if frame[column].isna().any()]
    if null_columns:
        raise ValueError(f"{spec.name}: null values in {', '.join(null_columns)}")
    if spec.key_columns and frame.duplicated(list(spec.key_columns)).any():
        raise ValueError(f"{spec.name}: duplicate source keys in extract chunk")
    return frame.loc[:, spec.columns]


def _extract_frames(
    source: psycopg.Connection,
    spec: DatasetSpec,
    params: dict[str, Any],
    chunk_size: int,
) -> Iterator[pd.DataFrame]:
    cursor_name = f"etl_{spec.name}_{uuid.uuid4().hex[:8]}"
    with source.cursor(name=cursor_name) as cursor:
        cursor.execute(spec.query, params)
        columns = [description.name for description in cursor.description]
        while rows := cursor.fetchmany(chunk_size):
            yield pd.DataFrame.from_records(rows, columns=columns)


def _copy_frame(target: psycopg.Connection, table_name: str, frame: pd.DataFrame) -> int:
    statement = sql.SQL("COPY {}.{} ({}) FROM STDIN").format(
        sql.Identifier("stg"),
        sql.Identifier(table_name),
        sql.SQL(", ").join(map(sql.Identifier, frame.columns)),
    )
    with target.cursor().copy(statement) as copy:
        for row in frame.itertuples(index=False, name=None):
            copy.write_row(tuple(_python_value(value) for value in row))
    return len(frame.index)


def _read_watermarks(target: psycopg.Connection, source_system: str) -> dict[str, tuple[datetime, int]]:
    with target.cursor() as cursor:
        cursor.execute(
            """
            SELECT entity_name, last_changed_at, last_source_id
            FROM etl.watermark
            WHERE source_system = %s
            """,
            (source_system,),
        )
        return {name: (changed_at, source_id) for name, changed_at, source_id in cursor.fetchall()}


def _missing_contract_columns(
    connection: psycopg.Connection,
    contracts: dict[tuple[str, str], tuple[str, ...]],
) -> list[str]:
    missing: list[str] = []
    with connection.cursor() as cursor:
        for (schema_name, table_name), expected_columns in contracts.items():
            cursor.execute(
                """
                SELECT column_name
                FROM information_schema.columns
                WHERE table_schema = %s AND table_name = %s
                """,
                (schema_name, table_name),
            )
            actual_columns = {row[0] for row in cursor.fetchall()}
            if not actual_columns:
                missing.append(f"{schema_name}.{table_name} (table missing)")
                continue
            missing.extend(
                f"{schema_name}.{table_name}.{column}"
                for column in expected_columns
                if column not in actual_columns
            )
    return missing


def _check_contracts(source: psycopg.Connection, target: psycopg.Connection) -> None:
    source_missing = _missing_contract_columns(
        source,
        {("public", table_name): columns for table_name, columns in SOURCE_CONTRACTS.items()},
    )
    if source_missing:
        raise RuntimeError(f"OLTP source contract is missing: {', '.join(source_missing)}")

    # AT TIME ZONE has opposite meanings for timestamp and timestamptz. Fail
    # before loading if Prisma's UTC-naive source contract changes.
    with source.cursor() as cursor:
        cursor.execute("""
            SELECT table_name, column_name, data_type
            FROM information_schema.columns WHERE table_schema = 'public'
        """)
        types = {(table, column): kind for table, column, kind in cursor.fetchall()}
    for table, columns in SOURCE_CONTRACTS.items():
        for column in columns:
            if column.endswith('_at') or column in {'order_date', 'payment_date', 'reserved_until'}:
                if types.get((table, column)) != 'timestamp without time zone':
                    raise RuntimeError(f"OLTP UTC timestamp contract changed: {table}.{column}")

    target_contracts = dict(WAREHOUSE_CONTRACTS)
    target_contracts.update(
        {
            ("stg", spec.staging_table): tuple(spec.columns)
            for spec in DATASETS
        }
    )
    target_missing = _missing_contract_columns(target, target_contracts)
    with target.cursor() as cursor:
        cursor.execute("SELECT to_regprocedure('etl.apply_sales_stock_batch(uuid)')")
        if cursor.fetchone()[0] is None:
            target_missing.append("etl.apply_sales_stock_batch(uuid) (function missing)")
    if target_missing:
        raise RuntimeError(
            "warehouse contract is missing: "
            f"{', '.join(target_missing)}; apply 001, 002, and 003 first"
        )


def _acquire_pipeline_lock(target: psycopg.Connection) -> None:
    # one warehouse-wide lock keeps daily/manual ETL runs deterministic;
    # use per-source locks only after throughput requires concurrent pipelines.
    with target.cursor() as cursor:
        cursor.execute("SELECT pg_advisory_lock(hashtext(%s))", (PIPELINE_LOCK_NAME,))


def _release_pipeline_lock(target: psycopg.Connection) -> None:
    try:
        target.rollback()
        with target.cursor() as cursor:
            cursor.execute("SELECT pg_advisory_unlock(hashtext(%s))", (PIPELINE_LOCK_NAME,))
        target.commit()
    except Exception:
        LOGGER.warning("failed to release ETL advisory lock", exc_info=True)


def _create_batch(
    target: psycopg.Connection,
    batch_id: uuid.UUID,
    settings: Settings,
    window_start: datetime,
    window_end: datetime,
) -> None:
    with target.cursor() as cursor:
        cursor.execute(
            """
            INSERT INTO etl.load_batch (
              batch_id, source_system, source_window_started_at, source_window_ended_at
            ) VALUES (%s, %s, %s, %s)
            """,
            (batch_id, settings.source_system, window_start, window_end),
        )
    target.commit()


def _mark_batch_failed(target: psycopg.Connection, batch_id: uuid.UUID, error: Exception) -> None:
    target.rollback()
    with target.cursor() as cursor:
        cursor.execute(
            """
            UPDATE etl.load_batch
            SET status = 'FAILED', completed_at = CURRENT_TIMESTAMP, error_message = %s
            WHERE batch_id = %s AND status IN ('PENDING', 'RUNNING')
            """,
            (str(error)[:4000], batch_id),
        )
    target.commit()


def _apply_batch(target: psycopg.Connection, batch_id: uuid.UUID) -> tuple[str, int, str | None]:
    with target.cursor() as cursor:
        cursor.execute("SELECT result_status, rejected_count, result_error_message FROM etl.apply_sales_stock_batch(%s)", (batch_id,))
        status, rejected_count, error_message = cursor.fetchone()
    target.commit()
    return status, rejected_count, error_message


def _cleanup_staging(target: psycopg.Connection, retention_days: int) -> None:
    for spec in DATASETS:
        statement = sql.SQL(
            """
            DELETE FROM {}.{} AS staged
            USING etl.load_batch AS batch
            WHERE staged.batch_id = batch.batch_id
              AND batch.status IN ('SUCCEEDED', 'SUCCEEDED_WITH_REJECTS', 'FAILED')
              AND batch.completed_at IS NOT NULL
              AND batch.completed_at < CURRENT_TIMESTAMP - make_interval(days => %s)
            """
        ).format(sql.Identifier("stg"), sql.Identifier(spec.staging_table))
        with target.cursor() as cursor:
            cursor.execute(statement, (retention_days,))
    target.commit()


def run_pipeline(settings: Settings, mode: str) -> int:
    if mode not in {"full", "incremental"}:
        raise ValueError("mode must be full or incremental")

    batch_id = uuid.uuid4()
    batch_created = False
    with psycopg.connect(settings.oltp_database_url, options='-c timezone=UTC') as source, psycopg.connect(settings.warehouse_database_url, options='-c timezone=UTC') as target:
        pipeline_lock_acquired = False
        try:
            _acquire_pipeline_lock(target)
            pipeline_lock_acquired = True
            _check_contracts(source, target)
            watermarks = {} if mode == "full" else _read_watermarks(target, settings.source_system)

            source.rollback()
            source.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
            with source.cursor() as cursor:
                cursor.execute("SELECT CURRENT_TIMESTAMP")
                window_end = cursor.fetchone()[0]

            overlap = timedelta(minutes=settings.overlap_minutes)
            cursor_starts = [changed_at - overlap for changed_at, _ in watermarks.values()]
            batch_window_start = min(cursor_starts, default=EPOCH)
            _create_batch(target, batch_id, settings, batch_window_start, window_end)
            batch_created = True

            with target.transaction():
                for spec in DATASETS:
                    watermark_at, watermark_id = watermarks.get(spec.name, (EPOCH, 0))
                    params = {
                        "window_start": EPOCH if mode == "full" else watermark_at - overlap,
                        "cursor_id": 0 if mode == "full" or settings.overlap_minutes else watermark_id,
                        "window_end": window_end,
                    }
                    row_count = 0
                    for frame in _extract_frames(source, spec, params, settings.chunk_size):
                        prepared = prepare_frame(frame, spec, batch_id, window_end)
                        row_count += _copy_frame(target, spec.staging_table, prepared)
                    LOGGER.info("extracted dataset=%s rows=%d batch=%s", spec.name, row_count, batch_id)

            status, rejected_count, error_message = _apply_batch(target, batch_id)
            LOGGER.info(
                "completed batch=%s status=%s rejected=%d error=%s",
                batch_id,
                status,
                rejected_count,
                error_message or "",
            )
            _cleanup_staging(target, settings.staging_retention_days)
            return exit_code_for_status(status)
        except Exception as error:
            if batch_created:
                _mark_batch_failed(target, batch_id, error)
            LOGGER.exception("ETL batch failed batch=%s", batch_id)
            return 1
        finally:
            if pipeline_lock_acquired:
                _release_pipeline_lock(target)


def check_connections(settings: Settings) -> None:
    with psycopg.connect(settings.oltp_database_url, options='-c timezone=UTC') as source, psycopg.connect(settings.warehouse_database_url, options='-c timezone=UTC') as target:
        _check_contracts(source, target)


RECONCILE_SOURCE_SQL = """
WITH receipts AS (
  SELECT rr.orders_id, MIN(rr.received_at) AT TIME ZONE 'UTC' AS received_at,
    MAX(GREATEST(rr.updated_at, ri.updated_at)) AT TIME ZONE 'UTC' AS updated_at
  FROM return_requests rr JOIN return_items ri ON ri.return_requests_id = rr.id
  WHERE rr.received_at IS NOT NULL AND ri.received_quantity > 0
  GROUP BY rr.orders_id
), expected AS (
  SELECT o.id, COALESCE(sc.code, 'UNKNOWN') AS channel_code,
    o.order_date AT TIME ZONE 'UTC' AS order_at,
    COALESCE(h.delivered_at, CASE
      WHEN LOWER(BTRIM(o.status)) = 'delivered' THEN
        GREATEST(o.updated_at AT TIME ZONE 'UTC', c.updated_at AT TIME ZONE 'UTC',
          sd.updated_at AT TIME ZONE 'UTC', a.updated_at AT TIME ZONE 'UTC', r.updated_at)
      WHEN UPPER(BTRIM(sc.code)) = 'POS' AND LOWER(BTRIM(o.status)) = 'completed'
        THEN o.order_date AT TIME ZONE 'UTC'
    END) AS delivered_at,
    r.received_at, LOWER(BTRIM(o.status)) = 'cancelled' AS is_cancelled,
    o.deleted_at IS NOT NULL AS is_deleted, o.total_price
  FROM orders o LEFT JOIN sales_channels sc ON sc.sales_id = o.sales_channels_sales_id
  LEFT JOIN customer c ON c.id = o.customer_id
  LEFT JOIN shipping_details sd ON sd.id = o.shipping_details_id
  LEFT JOIN address a ON a.id = sd.shipping_address_id
  LEFT JOIN receipts r ON r.orders_id = o.id
  LEFT JOIN LATERAL (
    SELECT MIN(history.created_at) AT TIME ZONE 'UTC' AS delivered_at
    FROM order_status_history history WHERE history.orders_id = o.id
      AND (LOWER(BTRIM(history.new_status)) = 'delivered'
        OR (UPPER(BTRIM(sc.code)) = 'POS' AND LOWER(BTRIM(history.new_status)) = 'completed'))
  ) h ON TRUE
)
SELECT id, channel_code, order_at, delivered_at, received_at, is_cancelled, is_deleted, total_price,
  (order_at AT TIME ZONE 'Asia/Bangkok')::DATE,
  (delivered_at AT TIME ZONE 'Asia/Bangkok')::DATE,
  (received_at AT TIME ZONE 'Asia/Bangkok')::DATE
FROM expected ORDER BY id
"""

RECONCILE_TARGET_SQL = """
SELECT o.order_source_id, c.channel_code, o.order_at, o.delivered_at, o.return_received_at,
  o.is_cancelled, o.is_deleted, o.total_amount, od.calendar_date, dd.calendar_date,
  (o.return_received_at AT TIME ZONE 'Asia/Bangkok')::DATE
FROM dw.fact_order o JOIN dw.dim_channel c ON c.channel_key = o.channel_key
JOIN dw.dim_date od ON od.date_key = o.order_date_key
LEFT JOIN dw.dim_date dd ON dd.date_key = o.delivered_date_key
WHERE o.source_system = %s ORDER BY o.order_source_id
"""


def _assert_reconciled(source_rows: list[tuple], target_rows: list[tuple]) -> None:
    expected = {row[0]: row[1:] for row in source_rows}
    actual = {row[0]: row[1:] for row in target_rows}
    mismatches = sum(expected.get(key) != actual.get(key) for key in expected.keys() | actual.keys())
    if len(expected) != len(source_rows) or len(actual) != len(target_rows) or mismatches:
        # Counts only: no customer identifiers or payment evidence in logs.
        raise RuntimeError(f"Order/date/channel reconciliation failed: source={len(source_rows)} warehouse={len(target_rows)} mismatched={mismatches}")


def _assert_delivery_evidence(source_rows: list[tuple], target_rows: list[tuple], unverifiable_estimates: int) -> None:
    expected = {row[0]: row for row in source_rows}
    missing_history = sum(row[3] is not None and row[0] in expected and expected[row[0]][3] is None
                          for row in target_rows)
    if missing_history or unverifiable_estimates:
        raise RuntimeError('Delivery evidence is incomplete, not a proven timezone mismatch: '
                           f'preserved_without_source_proof={missing_history} '
                           f'non_pos_mutable_estimates={unverifiable_estimates}; '
                           'review retained status history before release or rebuild')


def reconcile_warehouse(settings: Settings) -> None:
    """Read-only release gate. Concurrent OLTP changes fail closed; rerun ETL then retry."""
    with psycopg.connect(settings.oltp_database_url, options='-c timezone=UTC') as source, psycopg.connect(settings.warehouse_database_url, options='-c timezone=UTC') as target:
        source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        target.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
        _check_contracts(source, target)
        status = target.execute("""
            SELECT status FROM etl.load_batch WHERE source_system = %s
            ORDER BY created_at DESC LIMIT 1
        """, (settings.source_system,)).fetchone()
        if status != ('SUCCEEDED',):
            raise RuntimeError('Reconciliation requires the latest source batch to be SUCCEEDED')
        expected = source.execute(RECONCILE_SOURCE_SQL).fetchall()
        actual = target.execute(RECONCILE_TARGET_SQL, (settings.source_system,)).fetchall()
        unverifiable = target.execute("""
            SELECT COUNT(*) FROM dw.fact_order o
            JOIN dw.dim_channel c ON c.channel_key = o.channel_key
            WHERE o.source_system = %s AND o.delivered_at IS NOT NULL
              AND o.delivery_timestamp_source = 'ORDER_UPDATED_AT_ESTIMATE'
              AND UPPER(BTRIM(c.channel_code)) <> 'POS'
        """, (settings.source_system,)).fetchone()[0]
        _assert_delivery_evidence(expected, actual, unverifiable)
        _assert_reconciled(expected, actual)
        # Equality per order includes dates, channel, cancellation/deletion and
        # exact decimal value, so all their daily gross totals agree as well.
        delivered = [row for row in expected if row[3] is not None and not row[6]]
        LOGGER.info('reconciled orders=%d delivered_orders=%d gross=%s physical_returns=%d',
                    len(expected), len(delivered), sum((row[7] for row in delivered), Decimal('0')),
                    sum(row[4] is not None for row in expected))
