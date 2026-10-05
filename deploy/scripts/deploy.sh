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
    echo "Image rollback does not restore warehouse data. Review the backup before retrying." >&2
  fi

  if [[ "$status" -eq 0 && "$TIMER_WAS_ACTIVE" == "1" ]]; then
    if ! systemctl_write start data-engineering.timer; then
      echo "Release checks passed, but restarting data-engineering.timer failed." >&2
      status=1
    fi
  elif [[ "$status" -ne 0 && "$TIMER_WAS_ACTIVE" == "1" ]]; then
    echo "Deployment failed; data-engineering.timer remains stopped. Reconcile or restore the warehouse before restarting it." >&2
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

ANALYTICS_ROLE="$(awk -F= '$1 == "WAREHOUSE_ANALYTICS_ROLE" { print $2; exit }' "$RELEASE_ENV")"
ANALYTICS_ROLE="${ANALYTICS_ROLE:-rm_analytics_reader}"
[[ "$ANALYTICS_ROLE" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
  echo "WAREHOUSE_ANALYTICS_ROLE must be a PostgreSQL role name" >&2
  exit 1
}
analytics_role_exists="$(
  docker exec cfmanager-postgres sh -lc \
    "psql -X -U \"\$POSTGRES_USER\" -d warehouse_db -Atc \"SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$ANALYTICS_ROLE');\""
)"
[[ "$analytics_role_exists" == "t" ]] || {
  echo "Warehouse analytics role $ANALYTICS_ROLE does not exist; create it before deployment." >&2
  exit 1
}

WRITER_ROLE="$(awk -F= '$1 == "WAREHOUSE_WRITER_ROLE" { print $2; exit }' "$RELEASE_ENV")"
WRITER_ROLE="${WRITER_ROLE:-etl_writer}"
[[ "$WRITER_ROLE" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
  echo "WAREHOUSE_WRITER_ROLE must be a PostgreSQL role name" >&2
  exit 1
}
[[ "$WRITER_ROLE" != "$ANALYTICS_ROLE" ]] || {
  echo "Warehouse writer and analytics reader must be different roles" >&2
  exit 1
}
writer_role_exists="$(
  docker exec cfmanager-postgres sh -lc \
    "psql -X -U \"\$POSTGRES_USER\" -d warehouse_db -Atc \"SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$WRITER_ROLE');\""
)"
[[ "$writer_role_exists" == "t" ]] || {
  echo "Warehouse writer role $WRITER_ROLE does not exist; create it before deployment." >&2
  exit 1
}

mkdir -p "$BACKUP_ROOT"
chmod 700 "$BACKUP_ROOT"
backup_file="$BACKUP_ROOT/warehouse_db-before-etl-$(date -u +%Y%m%dT%H%M%SZ).dump"
docker exec cfmanager-postgres sh -lc \
  'pg_dump -Fc -U "$POSTGRES_USER" -d warehouse_db' > "$backup_file"
[[ -s "$backup_file" ]] || { echo "Warehouse backup is empty" >&2; exit 1; }
chmod 600 "$backup_file"
docker exec -i cfmanager-postgres pg_restore --list < "$backup_file" >/dev/null
docker exec -i cfmanager-postgres pg_restore --file=/dev/null < "$backup_file"
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

echo "Applying warehouse ETL writer grants for $WRITER_ROLE"
docker exec -i cfmanager-postgres sh -lc \
  "psql -X -v ON_ERROR_STOP=1 -v writer_role='$WRITER_ROLE' -U \"\$POSTGRES_USER\" -d warehouse_db" <<'SQL'
GRANT USAGE ON SCHEMA etl, stg, dw, mart TO :"writer_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA etl, stg, dw, mart TO :"writer_role";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA etl, stg, dw, mart TO :"writer_role";
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA etl TO :"writer_role";
SQL

echo "Applying mart-only analytics grants for $ANALYTICS_ROLE"
compose run --rm --no-deps --entrypoint cat \
  warehouse-db-etl "/app/warehouse/005_analytics_readonly_grants.sql" |
  docker exec -i cfmanager-postgres sh -lc \
    "psql -X -v ON_ERROR_STOP=1 -v analytics_role='$ANALYTICS_ROLE' -U \"\$POSTGRES_USER\" -d warehouse_db"

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

echo "Reconciling source and warehouse order timestamps, Bangkok dates, channels, gross amounts, and physical returns"
compose run --rm warehouse-db-etl reconcile

printf '%s etl %s %s reconciliation=passed\n' \
  "$(date -u +%FT%TZ)" "$IMAGE_DIGEST" "$RUN_MODE" \
  >> "$BASE_DIR/releases/deployments.log"

RELEASE_CHANGED=0
echo "ETL deployment completed: $IMAGE mode=$RUN_MODE reconciliation=passed"
