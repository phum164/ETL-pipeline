from __future__ import annotations

import argparse
import logging
import sys

from .config import Settings
from .pipeline import check_connections, reconcile_warehouse, run_pipeline


def main() -> int:
    parser = argparse.ArgumentParser(description="Warehouse Sales-Stock Data ETL")
    parser.add_argument("command", choices=("check", "full", "incremental", "reconcile"))
    args = parser.parse_args()

    try:
        settings = Settings.from_env()
    except ValueError as error:
        parser.print_usage(sys.stderr)
        print(f"error: {error}", file=sys.stderr)
        return 1

    logging.basicConfig(
        level=getattr(logging, settings.log_level, logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )

    if args.command == "check":
        check_connections(settings)
        logging.getLogger("warehouse_db_etl").info("source and warehouse contracts are ready")
        return 0
    if args.command == "reconcile":
        try:
            reconcile_warehouse(settings)
        except Exception as error:
            logging.getLogger("warehouse_db_etl").error("reconciliation failed: %s", error)
            return 1
        return 0
    return run_pipeline(settings, args.command)


if __name__ == "__main__":
    raise SystemExit(main())
