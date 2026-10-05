"""Opt-in read-only checks against explicitly selected local databases."""
import os
import unittest
from datetime import datetime, timezone

import psycopg

from etl.pipeline import DATASETS, EPOCH, _python_value


@unittest.skipUnless(os.getenv('ETL_INTEGRATION_SOURCE_URL'), 'local source URL not selected')
class SourceTimezoneIntegrationTests(unittest.TestCase):
    def test_all_extracts_have_same_instants_and_watermarks_in_three_timezones(self):
        with psycopg.connect(os.environ['ETL_INTEGRATION_SOURCE_URL']) as source:
            source.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            identity = source.execute("SELECT current_database(),host(inet_server_addr())").fetchone()
            self.assertEqual(identity[0], 'omsdb')
            self.assertIn(identity[1], ('127.0.0.1', '::1'))
            params = {'window_start': EPOCH, 'cursor_id': 0,
                      'window_end': datetime(2100, 1, 1, tzinfo=timezone.utc)}
            for spec in DATASETS:
                baseline = None
                for zone in ('UTC', 'Asia/Bangkok', 'America/New_York'):
                    source.execute("SELECT set_config('TimeZone', %s, true)", (zone,))
                    rows = source.execute(spec.query, params).fetchall()
                    for row in rows:
                        for value in row:
                            _python_value(value)  # rejects untyped, naive timestamps
                    if baseline is None:
                        baseline = rows
                    self.assertEqual(rows, baseline, (spec.name, zone))
                    # Verify the incremental boundary uses the exact extracted
                    # instant, not a session-dependent naive/aware comparison.
                    if rows and 'source_updated_at' in spec.columns and not spec.full_snapshot:
                        column_names = [item.name for item in source.execute(spec.query, params).description]
                        at_index = column_names.index('source_updated_at')
                        id_index = column_names.index('source_id')
                        last = rows[-1]
                        boundary = dict(params, window_start=last[at_index], cursor_id=last[id_index])
                        self.assertEqual(source.execute(spec.query, boundary).fetchall(), [])


@unittest.skipUnless(os.getenv('ETL_INTEGRATION_WAREHOUSE_URL'), 'local test warehouse URL not selected')
class BusinessDateIntegrationTests(unittest.TestCase):
    def test_bangkok_day_month_year_boundaries_are_session_independent(self):
        with psycopg.connect(os.environ['ETL_INTEGRATION_WAREHOUSE_URL']) as target:
            target.execute('SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY')
            identity = target.execute("SELECT current_database(),host(inet_server_addr())").fetchone()
            self.assertEqual(identity[0], 'warehouse_db_test')
            self.assertIn(identity[1], ('127.0.0.1', '::1'))
            for zone in ('UTC', 'Asia/Bangkok', 'America/New_York'):
                target.execute("SELECT set_config('TimeZone', %s, true)", (zone,))
                for stamp, key in (('2026-01-31 16:59:59', 20260131),
                                   ('2026-01-31 17:00:00', 20260201),
                                   ('2026-12-31 17:00:00', 20270101)):
                    actual = target.execute("SELECT etl.date_key(%s::timestamp AT TIME ZONE 'UTC')", (stamp,)).fetchone()[0]
                    self.assertEqual(actual, key)
