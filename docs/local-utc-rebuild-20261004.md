# Local warehouse UTC rebuild — 2026-10-04

Executed only against `omsdb` (read-only source) and `warehouse_db` on
`127.0.0.1:5432`. No VPS operations, OLTP writes, push, or automatic reset.

## Recovery and preflight

- Backup: `../../local_backups/warehouse_db-before-timezone-rebuild-20261004T083045Z.dump`
- Size: 417,073 bytes.
- SHA-256: `37d857267a4e34c17a2a33b8cde96e730f06e32d1f58b440310fccb9b6bdf65a`
- `pg_restore --list` and full archive read passed; no restore drill was run.
- Source and warehouse each had 86 orders; no warehouse-only orders or missing
  source IDs for retained lines, reserves, payments, history, or stock movements.
- No external-schema dependencies or other active warehouse connections found.
- No matching local warehouse/ETL scheduled task found.
- Rebuilt only `etl`, `stg`, `dw`, and `mart`. The 9 prior ETL batches and 4,046
  inventory snapshots over 6 business dates remain recoverable in the backup.
  Current snapshots contain 681 SKUs over one date; historic stock is not recreated.

## Results

| Check | Result |
| --- | --- |
| Full batch 1 | `00f96c19-2d6c-4a4a-a51c-22fccbcbeda2`, SUCCEEDED, 0 rejects |
| Full batch 2 | `116dce69-12d5-461b-babb-19cdffdd930d`, SUCCEEDED, 0 rejects |
| Incremental batch | `d8124824-48b2-4a4d-9349-3bd381a8ce36`, SUCCEEDED, 0 rejects |
| Stable facts across all 3 runs | 86 orders, 163 lines, 145 status events, 821 stock movements |
| All delivered gross sales | 65 orders, 101,026.00 THB |
| POS delivered gross sales | 53 orders, 79,928.00 THB |
| TikTok delivered gross sales | 12 orders, 21,098.00 THB |
| Physical-return receipts | 3 orders |
| Exact per-order reconciliation | Passed after every run: instants, dates, channels, flags, values, receipts |
| Stock-movement reconciliation | All 821 instants, Bangkok dates, and stock deltas equal source |
| Backend service read check | ready=true; all/POS/TT totals agree |
| Analytics reader | mart access; no dw/stg schema access |

Compared with the archive, 42 order-date buckets and 21 delivery daily/channel
buckets changed. Gross totals did not change. For example, 14 POS orders worth
46,096.00 THB moved from 2026-01-04 to 2026-01-05, matching UTC interpretation
of source timestamps converted into Bangkok business dates.

The isolated `001`–`004` SQL verification passed only on `warehouse_db_test`;
fixtures were rolled back. Backend business API integration checks passed on
the real local warehouse and the isolated rollback-wrapped fixtures. These are
service/SQL checks, not browser or VPS acceptance.

## Timestamp evidence boundary

Both generic source and warehouse connections originally reported Asia/Bangkok;
their settings were not changed globally. ETL now forces UTC per connection and
explicitly interprets Prisma's naive timestamp fields as UTC.

14 modern POS order numbers encode an independent epoch that agrees with raw
UTC order timestamps; their checkout history and 15 related stock movements also
agree within a fraction of a second. 42 legacy POS orders lack that independent
clock evidence. They use the application's UTC storage contract; every historic
row was not independently verified. No positive evidence of mixed UTC/Bangkok
source storage was found. Source data was not shifted or rewritten.

38 current delivered POS facts use the supported `order_at` checkout fallback.
No non-POS mutable delivery-time estimates were present. If retained checkout
history later disappears, reconciliation reports incomplete delivery evidence
and stops release; it does not remove gross sales or invent history.

## Reproduce validation

Run `python -m unittest discover -s tests -v` from `data_engineering`.
The read-only database integration tests require explicitly selected
`ETL_INTEGRATION_SOURCE_URL` (local `omsdb`) and
`ETL_INTEGRATION_WAREHOUSE_URL` (local `warehouse_db_test`); otherwise they skip.
They verify all extracts/watermark boundaries and day/month/year changes under
UTC, Asia/Bangkok, and America/New_York. With the configured ETL environment,
`python -m etl reconcile` is a read-only release check.

For the manual VPS procedure and recovery steps, see [README](../README.md).
VPS execution remains separately authorized; the push workflow never resets schemas.
