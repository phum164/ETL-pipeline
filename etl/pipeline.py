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


LOGGER = logging.getLogger("rm_dw_etl")
EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)
PIPELINE_LOCK_NAME = "rm_dw:etl_pipeline"

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
    "order_status_history": ("id", "orders_id", "new_status", "created_at"),
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
              deleted_at,
              updated_at AS source_updated_at
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
              COALESCE(s.deleted_at, p.deleted_at, c.deleted_at) AS deleted_at,
              GREATEST(s.updated_at, p.updated_at, c.updated_at) AS source_updated_at
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
            "subtotal_amount", "discount_amount", "shipping_fee_amount",
            "tax_amount", "total_amount", "deleted_at", "source_updated_at",
        ),
        required_columns=("source_id", "order_at", "current_status", "source_updated_at"),
        key_columns=("source_id",),
        query="""
            WITH order_extract AS (
              SELECT
                o.id::bigint AS source_id,
                o.order_number,
                o.order_date AS order_at,
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
                o.subtotal AS subtotal_amount,
                o.discount_amount,
                o.shipping_fee AS shipping_fee_amount,
                o.tax_amount,
                o.total_price AS total_amount,
                o.deleted_at,
                GREATEST(
                  o.updated_at,
                  COALESCE(c.updated_at, o.updated_at),
                  COALESCE(sd.updated_at, o.updated_at),
                  COALESCE(a.updated_at, o.updated_at)
                ) AS source_updated_at
              FROM orders AS o
              LEFT JOIN customer AS c ON c.id = o.customer_id
              LEFT JOIN shipping_details AS sd ON sd.id = o.shipping_details_id
              LEFT JOIN address AS a ON a.id = sd.shipping_address_id
              LEFT JOIN "Province" AS p ON p.id = a.province_id
              LEFT JOIN "Subdistrict" AS sd_sub ON sd_sub.id = a.subdistrict_id
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
        columns=("batch_id", "source_id", "order_source_id", "new_status", "occurred_at"),
        required_columns=("source_id", "order_source_id", "new_status", "occurred_at"),
        key_columns=("source_id",),
        query="""
            SELECT
              id::bigint AS source_id,
              orders_id::bigint AS order_source_id,
              new_status,
              created_at AS occurred_at
            FROM order_status_history
            WHERE (created_at, id) > (%(window_start)s, %(cursor_id)s)
              AND created_at <= %(window_end)s
            ORDER BY created_at, id
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
              deleted_at,
              updated_at AS source_updated_at
            FROM order_details
            WHERE (updated_at, id) > (%(window_start)s, %(cursor_id)s)
              AND updated_at <= %(window_end)s
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
              created_at AS movement_at,
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
            WHERE (created_at, id) > (%(window_start)s, %(cursor_id)s)
              AND created_at <= %(window_end)s
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
              sc.deleted_at,
              GREATEST(sc.updated_at, s.updated_at) AS source_updated_at
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
        return value.to_pydatetime()
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
    # ponytail: one warehouse-wide lock keeps daily/manual ETL runs deterministic;
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
    with psycopg.connect(settings.oltp_database_url) as source, psycopg.connect(settings.warehouse_database_url) as target:
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
    with psycopg.connect(settings.oltp_database_url) as source, psycopg.connect(settings.warehouse_database_url) as target:
        _check_contracts(source, target)
