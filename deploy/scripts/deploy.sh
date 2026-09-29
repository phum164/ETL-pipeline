#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${CFMANAGER_DIR:-/opt/cfmanager}"
COMPOSE_FILE="$BASE_DIR/data-engineering/compose.yaml"
RELEASE_ENV="$BASE_DIR/releases/data-engineering.env"
PREVIOUS_ENV="$BASE_DIR/releases/data-engineering.previous.env"
ETL_ENV="$BASE_DIR/secrets/data-engineering.env"
BACKUP_ROOT="$BASE_DIR/backups"
IMAGE_DIGEST="${1:-}"
RUN_MODE="${2:-}"
IMAGE_REPOSITORY="ghcr.io/phum164/etl-pipeline"
IMAGE="$IMAGE_REPOSITORY@$IMAGE_DIGEST"
TIMER_WAS_ACTIVE=0
RELEASE_CHANGED=0

usage() {
  echo "Usage: deploy.sh <sha256:image-digest> <full|incremental>" >&2
  exit 2
}

[[ "$IMAGE_DIGEST" =~ ^sha256:[0-9a-f]{64}$ ]] || usage
[[ "$RUN_MODE" == "full" || "$RUN_MODE" == "incremental" ]] || usage
[[ -f "$COMPOSE_FILE" ]] || { echo "Missing $COMPOSE_FILE" >&2; exit 1; }
[[ -f "$RELEASE_ENV" ]] || { echo "Missing $RELEASE_ENV" >&2; exit 1; }
[[ -f "$ETL_ENV" ]] || { echo "Missing $ETL_ENV" >&2; exit 1; }
docker inspect cfmanager-postgres >/dev/null 2>&1 || {
  echo "Missing running cfmanager-postgres container" >&2
  exit 1
}

compose() {
  docker compose --env-file "$RELEASE_ENV" -f "$COMPOSE_FILE" "$@"
}

systemctl_write() {
  if [[ "$(id -u)" == "0" ]]; then
    systemctl "$@"
  else
    sudo -n systemctl "$@"
  fi
}

finish() {
  status=$?
  trap - EXIT

  if [[ "$status" -ne 0 && "$RELEASE_CHANGED" == "1" && -f "$PREVIOUS_ENV" ]]; then
    echo "Deployment failed; restoring previous ETL image reference." >&2
    cp "$PREVIOUS_ENV" "$RELEASE_ENV" || true
    chmod 600 "$RELEASE_ENV" || true
  fi

  if [[ "$TIMER_WAS_ACTIVE" == "1" ]]; then
    systemctl_write start data-engineering.timer || true
  fi

  exit "$status"
}
trap finish EXIT

if systemctl is-active --quiet data-engineering.timer; then
  TIMER_WAS_ACTIVE=1
  systemctl_write stop data-engineering.timer
fi

if systemctl is-active --quiet data-engineering.service; then
  echo "data-engineering.service is running; retry after the current ETL finishes." >&2
  exit 1
fi

current_database="$(
  docker exec cfmanager-postgres sh -lc \
    'psql -X -U "$POSTGRES_USER" -d warehouse_db -Atc "SELECT current_database();"'
)"
[[ "$current_database" == "warehouse_db" ]] || {
  echo "Expected warehouse_db, got: $current_database" >&2
  exit 1
}

mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"
backup_file="$BACKUP_ROOT/warehouse_db-before-etl-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker exec cfmanager-postgres sh -lc \
  'pg_dump -Fc -U "$POSTGRES_USER" -d warehouse_db' > "$backup_file"
[[ -s "$backup_file" ]] || { echo "Warehouse backup is empty" >&2; exit 1; }
chmod 600 "$backup_file"
echo "Warehouse backup: $backup_file"

docker pull "$IMAGE" >/dev/null

cp "$RELEASE_ENV" "$PREVIOUS_ENV"
chmod 600 "$RELEASE_ENV" "$PREVIOUS_ENV"
tmp_file="$(mktemp "$BASE_DIR/releases/data-engineering.env.XXXXXX")"
awk -F= -v value="$IMAGE" '
  BEGIN { updated = 0 }
  $1 == "ETL_IMAGE" { print "ETL_IMAGE=" value; updated = 1; next }
  { print }
  END { if (!updated) print "ETL_IMAGE=" value }
' "$RELEASE_ENV" > "$tmp_file"
mv "$tmp_file" "$RELEASE_ENV"
chmod 600 "$RELEASE_ENV"
RELEASE_CHANGED=1

compose pull warehouse-db-etl

for warehouse_sql in 001_bootstrap.sql 002_transform.sql 003_marts.sql; do
  echo "Applying $warehouse_sql"
  compose run --rm --no-deps --entrypoint cat \
    warehouse-db-etl "/app/warehouse/$warehouse_sql" |
    docker exec -i cfmanager-postgres sh -lc \
      'psql -X -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d warehouse_db'
done

compose run --rm warehouse-db-etl check
compose run --rm warehouse-db-etl "$RUN_MODE"

latest_status="$(
  docker exec cfmanager-postgres sh -lc \
    'psql -X -U "$POSTGRES_USER" -d warehouse_db -Atc "
      SELECT status
      FROM etl.load_batch
      ORDER BY created_at DESC
      LIMIT 1;
    "'
)"
[[ "$latest_status" == "SUCCEEDED" ]] || {
  echo "Latest ETL batch status is $latest_status" >&2
  exit 1
}

source_returned_orders="$(
  docker exec cfmanager-postgres sh -lc \
    'psql -X -U "$POSTGRES_USER" -d "${POSTGRES_DB:-cfmanager}" -Atc "
      SELECT COUNT(DISTINCT rr.orders_id)
      FROM return_requests AS rr
      JOIN return_items AS ri ON ri.return_requests_id = rr.id
      WHERE rr.received_at IS NOT NULL
        AND ri.received_quantity > 0;
    "'
)"
warehouse_returned_orders="$(
  docker exec cfmanager-postgres sh -lc \
    'psql -X -U "$POSTGRES_USER" -d warehouse_db -Atc "
      SELECT COUNT(*)
      FROM dw.fact_order
      WHERE return_received_at IS NOT NULL;
    "'
)"
[[ "$source_returned_orders" == "$warehouse_returned_orders" ]] || {
  echo "Return reconciliation failed: source=$source_returned_orders warehouse=$warehouse_returned_orders" >&2
  exit 1
}

printf '%s etl %s %s returned_orders=%s\n' \
  "$(date -u +%FT%TZ)" "$IMAGE_DIGEST" "$RUN_MODE" "$warehouse_returned_orders" \
  >> "$BASE_DIR/releases/deployments.log"

RELEASE_CHANGED=0
echo "ETL deployment completed: $IMAGE mode=$RUN_MODE returned_orders=$warehouse_returned_orders"
