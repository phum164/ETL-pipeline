-- Grant the backend analytics role read-only access to warehouse marts and
-- freshness audit rows. Run with psql -v analytics_role=rm_analytics_reader.
GRANT USAGE ON SCHEMA mart, etl TO :"analytics_role";
GRANT SELECT ON ALL TABLES IN SCHEMA mart TO :"analytics_role";
GRANT SELECT ON etl.load_batch, etl.rejected_row TO :"analytics_role";

-- Keep future mart views/tables readable without granting access to dw/stg.
ALTER DEFAULT PRIVILEGES IN SCHEMA mart
  GRANT SELECT ON TABLES TO :"analytics_role";
