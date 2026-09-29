# Sales-Stock Data Engineering

Standalone Python and Pandas ETL for moving sales and stock data from the operational PostgreSQL database (`omsdb`) into the isolated warehouse (`warehouse_db`). The backend application, Prisma schema, and OLTP data are not modified.

## Flow

1. Read warehouse watermarks.
2. Extract OLTP data in a repeatable-read, read-only transaction.
3. Validate and normalize each chunk with Pandas.
4. Bulk-copy frames into `stg.*` using a UUID batch.
5. Call `etl.apply_sales_stock_batch(batch_id)` to build dimensions, facts, snapshots, and marts.
6. Return a scheduler-friendly exit code and retain the audit trail.

Sales channels, SKU/Product/Category, and SKU-channel stock are full daily snapshots. Orders, order lines, order status history, and inventory movements are incremental with a five-minute overlap by default. Order extraction also snapshots the buyer name, province, and postal code when available; `dw.dim_customer` keeps the latest of those order snapshots for known buyers while facts retain their order-time values. Address lines, phone, email, credentials, tokens, and payment details are not copied. Treat `buyer_name` as restricted personal data and grant dashboard access only to authorized users.

## Warehouse setup

Provision a separate `warehouse_db` database, then run the warehouse SQL in order:

```powershell
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\001_bootstrap.sql
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\002_transform.sql
psql $env:WAREHOUSE_DATABASE_URL -v ON_ERROR_STOP=1 -f .\warehouse\003_marts.sql
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

Set the backend `WAREHOUSE_DATABASE_URL` to that role. The API also requests a
read-only PostgreSQL session as a second guard.

## Run with Docker

Copy `.env.example` to `.env` and use dedicated database roles. The OLTP role must be read-only.

```powershell
docker compose run --rm warehouse-db-etl check
docker compose run --rm warehouse-db-etl full
docker compose run --rm warehouse-db-etl incremental
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
SQL `001` through `003`, runs `check`, runs the selected ETL mode, reconciles
completed physical returns, and restores the timer. It never runs
`004_verify.sql` in production.

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

The `check` command validates every source table/column used by the extract
queries and every staging/audit column required by the warehouse contract.
Each ETL run takes a warehouse session advisory lock before source extraction;
the lock is released when the run completes or the connection closes.
