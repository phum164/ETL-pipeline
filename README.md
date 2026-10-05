# Sales-Stock Data Engineering

Standalone Python and Pandas ETL for moving sales and stock data from the operational PostgreSQL database (`omsdb`) into the isolated warehouse (`warehouse_db`). The backend application, Prisma schema, and OLTP data are not modified.

## Flow

1. Read warehouse watermarks.
2. Extract OLTP data in a repeatable-read, read-only transaction.
3. Validate and normalize each chunk with Pandas.
4. Bulk-copy frames into `stg.*` using a UUID batch.
5. Call `etl.apply_sales_stock_batch(batch_id)` to build dimensions, facts, snapshots, and marts.
6. Return a scheduler-friendly exit code and retain the audit trail.

Sales channels, SKU/Product/Category, and SKU-channel stock are full daily snapshots. Orders, order lines, order status history, Facebook reserves, payment transactions, and inventory movements are incremental with a five-minute overlap by default. Order extraction also snapshots the buyer name, province, and postal code when available; `dw.dim_customer` keeps the latest of those order snapshots for known buyers while facts retain their order-time values. Address lines, phone, email, payment credentials, slip images, tokens, and secrets are not copied. Social-payment facts retain only amounts, status, and payment-confirmation timestamps needed by the CF metric. Treat `buyer_name` as restricted personal data and grant dashboard access only to authorized users.

OLTP naive timestamps follow the application's UTC storage contract. Extraction
interprets them explicitly as UTC; ETL source and warehouse sessions also use
UTC, including incremental watermark comparisons. Warehouse facts retain
instants, while `etl.business_date` converts them to `Asia/Bangkok` for reporting.
Changing the VPS operating-system or PostgreSQL default timezone neither changes
this contract nor repairs already stored historical facts. If historical source
values mix UTC and Thai local time, stop and investigate before rebuilding.

## Warehouse setup

Provision a separate `warehouse_db` database, then run the warehouse SQL in order:

```powershell
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\001_bootstrap.sql
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\002_transform.sql
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\003_marts.sql
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -v analytics_role=rm_analytics_reader -f .\warehouse\005_analytics_readonly_grants.sql
# Optional: run the rollback-wrapped fixture verification against warehouse_db_test.
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\004_verify.sql
```

Never apply these files to `omsdb`.

Create a separate backend role with no access to `dw` or `stg`, then grant the
analytics read contract (replace the role/password through your secret
manager):

```powershell
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -c "CREATE ROLE rm_analytics_reader LOGIN PASSWORD 'change-me';"
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -v analytics_role=rm_analytics_reader -f .\warehouse\005_analytics_readonly_grants.sql
```

Create the role only when it does not already exist. Set
`WAREHOUSE_ANALYTICS_ROLE` in the VPS release environment to the same role used
by the backend `WAREHOUSE_DATABASE_URL`. Deployment checks that this role exists
before changing the release, applies `005_analytics_readonly_grants.sql` after
the marts, and grants only the `mart` views plus ETL freshness audit tables.
The deploy applies `001` through `003` as PostgreSQL's configured `POSTGRES_USER`,
so the default privileges in `005` are attached to that same view owner.
`WAREHOUSE_WRITER_ROLE` is optional in the release environment and defaults to
`etl_writer`; it must match the ETL `WAREHOUSE_DATABASE_URL` user and already
exist. Deploy validates both role identifiers and rejects the same role for
writer and reader before changing the image. After DDL it reapplies writer
schema usage, table DML, sequence access, and ETL function execution separately
from reader grants. It grants no writer rights to the analytics reader.

Set the backend `WAREHOUSE_DATABASE_URL` to that role. The API also requests a
read-only PostgreSQL session as a second guard.

## Run with Docker

Copy `.env.example` to `.env` and use dedicated database roles. The OLTP role must be read-only.

```powershell
docker compose run --rm warehouse-db-etl check
docker compose run --rm warehouse-db-etl full
docker compose run --rm warehouse-db-etl incremental
docker compose run --rm warehouse-db-etl reconcile
```

Run `full` once. For unattended Windows runs, keep secrets outside the repository
at `C:\ProgramData\RM\data-engineering\etl.env`, then install
`scripts\RM-DataEngineering-Daily.xml`. The task invokes
`scripts\run_daily.ps1`, writes logs to
`C:\ProgramData\RM\data-engineering\logs`, runs at 02:00 Asia/Bangkok,
retries three times at 15-minute intervals, and prevents overlapping instances.

Manual installation (run elevated):

The XML is prefilled for `BOM-PH\ACER` and this workspace path; edit
`<UserId>` and `<WorkingDirectory>` when installing under another Windows
account or checkout path.

```powershell
Register-ScheduledTask -TaskName 'RM Data Engineering Daily' `
  -Xml (Get-Content .\scripts\RM-DataEngineering-Daily.xml -Raw) -Force
```

Exit codes:

- `0`: `SUCCEEDED`
- `2`: `SUCCEEDED_WITH_REJECTS`; inspect `etl.rejected_row`
- `1`: configuration, connection, extraction, validation, or transform failure

## Ubuntu VPS

The `main` workflow tests Python and warehouse SQL, publishes a commit-SHA image,
and records its immutable digest. On the VPS, keep only the deployment files and
secrets:

```bash
sudo install -d -m 0755 /opt/cfmanager/data-engineering /opt/cfmanager/releases
sudo install -d -m 0700 /opt/cfmanager/secrets
sudo install -m 0644 deploy/compose.yaml /opt/cfmanager/data-engineering/compose.yaml
sudo install -m 0600 deploy/production.env.example /opt/cfmanager/secrets/data-engineering.env
sudo install -m 0644 deploy/release.env.example /opt/cfmanager/releases/data-engineering.env
```

Replace every placeholder and copy the exact digest-pinned `ETL_IMAGE` from a
successful workflow's summary. The production Compose file joins the backend
stack's external `cfmanager_data-network`; adjust that name only if the backend
Compose project uses another project name. Then authenticate to GHCR if the
package is private and validate before the first load:

```bash
sudo docker login ghcr.io
sudo docker compose --env-file /opt/cfmanager/releases/data-engineering.env \
  -f /opt/cfmanager/data-engineering/compose.yaml pull
sudo docker compose --env-file /opt/cfmanager/releases/data-engineering.env \
  -f /opt/cfmanager/data-engineering/compose.yaml run --rm warehouse-db-etl check
sudo docker compose --env-file /opt/cfmanager/releases/data-engineering.env \
  -f /opt/cfmanager/data-engineering/compose.yaml run --rm warehouse-db-etl full
```

After the one-time full load succeeds, install the daily timer:

```bash
sudo install -m 0644 deploy/data-engineering.service /etc/systemd/system/
sudo install -m 0644 deploy/data-engineering.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now data-engineering.timer
systemctl list-timers data-engineering.timer
```

The timer runs at 02:00 Asia/Bangkok with a small randomized delay. The service
retries failures up to three times per hour; the ETL's PostgreSQL advisory lock
still prevents overlapping warehouse runs. Inspect failures with
`journalctl -u data-engineering.service`.

### Automatic production deployment

A push to `main` tests the pipeline and warehouse SQL, publishes an immutable
digest-pinned image, then deploys it through `deploy/scripts/deploy.sh`. Changes
under `etl/` or `warehouse/` run a full backfill; other changes run incremental
ETL. The deployment stops the timer, backs up `warehouse_db`, applies warehouse
SQL `001` through `003`, reapplies the mart-only `005` grants for the configured
existing analytics role and the ETL writer's scoped permissions, runs `check`,
runs the selected ETL mode, and runs
`reconcile`. Reconciliation uses the configured OLTP connection (not a container's
default database), compares orders, UTC instants, Bangkok dates, channels, gross
amounts, and physical-return evidence, and fails on mismatches. Resume the timer
only after all checks pass. A failed apply/reconciliation leaves it stopped;
restoring the old image reference does not restore warehouse data. The script
verifies that its custom-format backup can be listed and fully read, but a
successful archive read is not proof of a tested database restore. It never runs
`004_verify.sql` or resets warehouse schemas during automatic deployment.

### Historical date-bucket release gate

A successful full ETL and idempotent rerun do not prove historical date
assignment. `reconcile` is the automated release gate, not an aggregate-only
return count. Existing facts may preserve an old, incorrect earliest timestamp;
full ETL alone does not promise to repair them. Any mismatch stops deployment.
Historical correction needs separate approval; for a disposable test warehouse,
use the one-time rebuild below rather than an automatic timestamp-shift patch.
Incomplete delivery evidence is a separate release blocker, not proof of a
timezone mismatch: a retained gross POS checkout can lack its original
`COMPLETED` history after cancellation/refund, and non-POS delivery timestamps
may be mutable update-time estimates. Reconciliation reports incomplete evidence
without changing preserved business facts. Review and recover source evidence;
do not shift timestamps, discard gross sales history, or reset to silence this
failure. Rebuilding cannot recreate missing historical events.
Source writes during loading/reconciliation can also cause a safe failure; pause
them for the rebuild, or rerun ETL and reconciliation after the source stabilizes.

### One-time rebuild of a test warehouse (manual, approval required)

This procedure is instructions only, not part of the push workflow. It destroys
only the four warehouse schemas, not the OLTP database, Docker volume, or roles.
Execute it only after confirming that the target is a disposable **test**
`warehouse_db`. Local source is normally `omsdb`; the VPS example is `cfmanager`.
Use the actual `OLTP_DATABASE_URL` identity, never infer it from `POSTGRES_DB`.

First identify both connections without displaying credentials:

```bash
cd /opt/cfmanager
set -Eeuo pipefail
dc() { sudo docker compose --env-file /opt/cfmanager/releases/data-engineering.env -f /opt/cfmanager/data-engineering/compose.yaml "$@"; }
dc run --rm --no-deps --entrypoint python warehouse-db-etl -c '
import psycopg
from etl.config import Settings, database_identity
s = Settings.from_env()
for label, url in (("source", s.oltp_database_url), ("warehouse", s.warehouse_database_url)):
    print(label, database_identity(url))
    with psycopg.connect(url) as c:
        with c.transaction():
            c.execute("SET TRANSACTION READ ONLY")
            print(c.execute("SELECT current_database(), current_user, current_setting('\''TimeZone'\'')").fetchone())
'
```

Pause dashboard access and **source writes** (checkout, CF/payment processing,
webhooks, imports, and background jobs) during the rebuild. Review source history
against order/payment evidence to establish the UTC contract; a timezone setting
alone cannot prove how old naive values were written. Compare source IDs with
existing warehouse facts and inspect missing/deleted source rows, status history,
payment/CF evidence, physical returns, and old stock snapshots. Stop if required
history exists only in warehouse: full extraction cannot recover it. Preserve
that evidence separately before any approved disposal. New inventory snapshots
represent current state, not reconstructed historical stock.

Independent provider/slip timestamps can confirm the UTC contract for rows that
have them. Older rows without independent epoch evidence are supported by the
application storage contract, not independently proven timestamps. Record this
proof boundary; do not silently reinterpret ambiguous or contradictory rows.

Stop the timer, verify no ETL service/container is still running, then back up:

```bash
sudo systemctl stop data-engineering.timer
systemctl show data-engineering.service -p ActiveState -p SubState
dc ps --all
sudo docker ps --filter label=com.docker.compose.service=warehouse-db-etl
# Continue only when the service is inactive and no ETL container is running.
sudo install -d -m 0700 /opt/cfmanager/backups
backup_file="/opt/cfmanager/backups/warehouse_db-before-test-rebuild-$(date -u +%Y%m%dT%H%M%SZ).dump"
sudo docker exec cfmanager-postgres sh -lc 'pg_dump -Fc -U "$POSTGRES_USER" -d warehouse_db' | sudo tee "$backup_file" >/dev/null
sudo test -s "$backup_file"
sudo chmod 600 "$backup_file"
sudo cat "$backup_file" | sudo docker exec -i cfmanager-postgres pg_restore --list >/dev/null
sudo cat "$backup_file" | sudo docker exec -i cfmanager-postgres pg_restore --file=/dev/null
sudo sha256sum "$backup_file"
```

Use Bash `set -Eeuo pipefail` for these command blocks; stop on the first failure.
For stronger recovery proof, restore this archive into a separate throwaway
database before proceeding. Keep the backup path/hash outside the warehouse.

Review dependencies **before** dropping anything. The following reports external
or unidentified dependents; view rewrite rules are resolved to their owning view.
Investigate every returned row and stop until no unapproved dependency remains.

```bash
sudo docker exec -i cfmanager-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d warehouse_db' <<'SQL'
SELECT current_database(), current_user;
SELECT pg_describe_object(d.classid, d.objid, d.objsubid) AS dependent,
       pg_describe_object(d.refclassid, d.refobjid, d.refobjsubid) AS warehouse_object
FROM pg_depend d
CROSS JOIN LATERAL pg_identify_object(d.refclassid, d.refobjid, d.refobjsubid) r
CROSS JOIN LATERAL pg_identify_object(d.classid, d.objid, d.objsubid) o
LEFT JOIN pg_rewrite rw ON d.classid = 'pg_rewrite'::regclass AND rw.oid = d.objid
LEFT JOIN pg_class vc ON vc.oid = rw.ev_class
LEFT JOIN pg_namespace vn ON vn.oid = vc.relnamespace
WHERE (r.schema IN ('etl','stg','dw','mart')
       OR (r.type = 'schema' AND r.name IN ('etl','stg','dw','mart')))
  AND COALESCE(vn.nspname, o.schema, '') NOT IN ('etl','stg','dw','mart')
  AND d.deptype NOT IN ('i','a');
SQL
```

After confirming the exact target, approved disposable contents and dependency
review, rebuild. The guard cannot establish test-environment status by itself:
that must be confirmed by the operator. No `DROP DATABASE`, no volume deletion.
If the analytics role differs from `rm_analytics_reader`, replace it in both the
role guard and `005` invocation below before executing anything.
If `WAREHOUSE_WRITER_ROLE`/the ETL connection uses a different writer, replace
every `etl_writer` occurrence below. Keep writer and analytics roles distinct.

```bash
sudo docker exec -i cfmanager-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d warehouse_db' <<'SQL'
BEGIN;
DO $$ BEGIN
  IF current_database() <> 'warehouse_db' THEN RAISE EXCEPTION 'Wrong target database'; END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'etl_writer') THEN
    RAISE EXCEPTION 'Missing existing etl_writer role';
  END IF;
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'rm_analytics_reader') THEN
    RAISE EXCEPTION 'Missing existing analytics role';
  END IF;
END $$;
DROP SCHEMA etl, stg, dw, mart CASCADE;
CREATE SCHEMA etl AUTHORIZATION etl_writer;
CREATE SCHEMA stg AUTHORIZATION etl_writer;
CREATE SCHEMA dw AUTHORIZATION etl_writer;
CREATE SCHEMA mart AUTHORIZATION etl_writer;
COMMIT;
SQL
for sql_file in 001_bootstrap.sql 002_transform.sql 003_marts.sql; do
  dc run --rm --no-deps --entrypoint cat warehouse-db-etl "/app/warehouse/$sql_file" |
    sudo docker exec -i cfmanager-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d warehouse_db'
done
sudo docker exec -i cfmanager-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d warehouse_db' <<'SQL'
GRANT USAGE ON SCHEMA etl, stg, dw, mart TO etl_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA etl, stg, dw, mart TO etl_writer;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA etl, stg, dw, mart TO etl_writer;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA etl TO etl_writer;
SQL
# This role must already exist and match the backend connection and release config.
# Replace rm_analytics_reader below if WAREHOUSE_ANALYTICS_ROLE uses another name.
dc run --rm --no-deps --entrypoint cat warehouse-db-etl /app/warehouse/005_analytics_readonly_grants.sql |
  sudo docker exec -i cfmanager-postgres sh -lc 'psql -X -v ON_ERROR_STOP=1 -v analytics_role=rm_analytics_reader -U "$POSTGRES_USER" -d warehouse_db'
dc run --rm warehouse-db-etl check
dc run --rm warehouse-db-etl full
dc run --rm warehouse-db-etl reconcile
dc run --rm warehouse-db-etl full
dc run --rm warehouse-db-etl incremental
dc run --rm warehouse-db-etl reconcile
```

Record per-order and daily/channel counts, gross amounts, and physical-return
dates before/after. Full reruns and incremental must not duplicate order/line/
movement facts or sales; inventory snapshot counts can grow with new batch dates.
Check the backend analytics API under its configured read-only connection and
confirm access to mart views/audit only, with no `dw`/`stg` access. Run fixture
`004_verify.sql` **only** against `warehouse_db_test`, never this rebuilt target.

If any step fails, leave the timer stopped and dashboard paused. To restore,
stop all warehouse users and remove only these same four schemas again after
the same target/dependency checks, then restore the full archived database
contents into the existing warehouse. Do not use `--no-owner`/`--no-acl` unless
there is an explicit privilege restoration plan:

```bash
sudo cat "$backup_file" | sudo docker exec -i cfmanager-postgres sh -lc \
  'pg_restore --exit-on-error --clean --if-exists -U "$POSTGRES_USER" -d warehouse_db'
```

Recheck restored counts, permissions, API and the previous digest-pinned image.
Image rollback alone is insufficient. Resume source writes, dashboard access,
and `sudo systemctl start data-engineering.timer` only after the approved rebuilt
warehouse passes every check (or the restored prior state is separately accepted).
Verify `systemctl list-timers data-engineering.timer` and the next service run.

Configure a protected GitHub `production` environment with `VPS_HOST`,
`VPS_PORT`, `VPS_USER`, `VPS_SSH_KEY`, and `VPS_KNOWN_HOSTS`. The VPS deployment
user must have Docker access and narrowly scoped passwordless permission to
start and stop `data-engineering.timer` when it is not root. The VPS must
already contain the production Compose and environment files described above
and be authenticated to GHCR when the image is private.

## Local development

```powershell
python -m pip install -r requirements.txt
python -m unittest discover -s tests -v
python -m etl check
```

Dashboard consumers should query only:

- `mart.v_sales_daily`
- `mart.v_sales_sku_daily`
- `mart.v_sales_product_daily`
- `mart.v_sales_buyer_daily`
- `mart.v_sales_province_daily`
- `mart.v_inventory_daily`
- `mart.v_channel_inventory_daily`
- `mart.v_delivered_product_category_daily`
- `mart.v_delivered_sku_daily`
- `mart.v_social_order_status`

`v_delivered_product_category_daily` attributes delivered lines to the SKU's
current directly assigned category, using delivery date and line subtotals after
line discounts. It includes orders later cancelled, refunded, or returned, but
excludes deleted orders and lines; missing category IDs remain an explicit
unknown-category bucket.

`v_delivered_sku_daily` uses the identical delivered gross population and line
subtotal basis at daily/channel/product/SKU grain. Variants are keyed by source
SKU identity, not code, color, or size. `GET /api/analytics/product-skus` requires
`analytics:view` and a positive `productId`; it retains the dashboard's `from`,
`to`, `channelCode`, and `rankBy` (`units` or `revenue`). The response contains
all sold SKUs, current attribute/size values, and full product totals (no top-N
truncation). SKUs without sales in the selected period are not included.

`GET /api/analytics/categories?categoryId=...&includeProducts=true` adds
`products` (all products in the selected category, including a nullable-ID
unknown-product bucket) and `productTotals: { lineSales, units }` (the full
selected-category totals). `categoryId` is required for this opt-in flag and
accepts `unknown`. The existing `topProducts`, `limit`, global category totals,
and analytics permission remain unchanged. Product composition is ranked by
revenue, regardless of the legacy ranking option; client-side reveal/paging
must not recompute the denominator from visible rows. The dashboard drilldown
uses category/global, product/category, and SKU/product revenue percentages.
This API/UI change uses the installed marts and needs no further warehouse SQL
or ETL run.

For an existing warehouse with loaded SKU/line/delivery facts, this drilldown
only needs `003_marts.sql` and `005_analytics_readonly_grants.sql` installed
before the backend/frontend release. No reset, full ETL, or source-schema change
is needed to expose the view. Test `004_verify.sql` only on `warehouse_db_test`.

`v_social_order_status` has one Facebook CF row per linked order. The 24-hour
deadline comes from the immutable reserve `reserved_until`; valid cohorts use
`reserved_until - 24 hours`. Payment success timing uses verified transaction
time, with a completed linked slip-check timestamp as the historical fallback;
transfer/payment dates alone do not prove timely confirmation. Invalid or short
legacy deadlines, payment evidence without reliable timing, and refund proof
without a current completed full-payment proof are marked incomplete, not
known-unpaid. Invalid-deadline facts keep `cf_at` null so consumers can report
them separately as undated instead of guessing a date-cohort. COD is identified by current or retained order-status history;
payment-method names are free text, so old COD records without status evidence
remain a source-data limitation. `snapshot_as_of` is the latest successful
source extraction cutoff, not the API server's current time.

The `check` command validates every source table/column used by the extract
queries and every staging/audit column required by the warehouse contract.
Each ETL run takes a warehouse session advisory lock before source extraction;
the lock is released when the run completes or the connection closes.
