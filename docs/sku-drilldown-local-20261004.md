# Delivered SKU drilldown — local validation, 2026-10-04

## Scope

Added `mart.v_delivered_sku_daily` and
`GET /api/analytics/product-skus?productId=...&from=...&to=...&channelCode=...&rankBy=units`.
The mart uses the same delivered-date gross population and discounted line
subtotals as the category report. POS deliveries and subsequently refunded or
cancelled delivered orders stay included. Deleted orders/lines are excluded.
SKU identity is the source SKU ID; current attribute/size labels are displayed.
All sold variants are returned, not a top-N subset. `analytics:view` is required.

## Local database work

Verified database and server address before installing just the new view on
`warehouse_db` and `warehouse_db_test` at `127.0.0.1:5432`, in transactions.
Granted SELECT on that view to the existing `rm_analytics_reader`. No warehouse
reset, full ETL, source writes, Prisma changes, VPS operations, or push.
The reader's `dw` and `stg` schema access remains denied. The live view contains
67 daily/channel/product/SKU rows; the isolated test warehouse remains empty
outside rollback-wrapped fixture tests.

## Checks

- 47 focused backend tests passed: analytics service, permission routes, real
  local warehouse reconciliation, and isolated warehouse fixture integration.
- The real integration check reconciles each returned category product to all
  its SKU units and exact decimal sales, both all-channel and POS/TT scopes.
- Rollback fixtures cover two variants, deleted lines/orders, refunded POS,
  non-POS COMPLETED exclusion, empty product/date/channel scopes, and replay.
- ETL test discovery: 23 passed, 2 opt-in timezone integration checks skipped.
- Local `python -m etl check` passed, including the new SKU mart contract.

Example smoke check for 2026-09-05 through 2026-10-04: product 339 has 3 units
and 2,773.00 THB, split into SKU 1003 (2 units, 1,998.00) and SKU 1002 (1 unit,
775.00).

## Frontend and live browser verification

- Four focused frontend suites passed (30 tests), including query/response
  normalization, product-card actions, and dialog open/closed SSR states.
- TypeScript passed. Scoped ESLint reported no errors and one existing
  `topProvinces` dependency warning. New dialog/test files passed Prettier.
- Verified the authenticated local dashboard in the browser: product 339
  displays both SKU rows and the 3-unit/2,773.00 totals above. Units/revenue
  sorting works; Escape closes the dialog and returns focus to its trigger.
- Changing the dashboard channel to POS preserves the selected date window.
  The selected POS product displays only SKU `BB-001-8GM0KF`: 5 units,
  2,235.00 THB, and 100% revenue share, without the prior product's TT rows.
- Verified widths 390, 768, and 1280 pixels. Mobile uses labeled SKU cards;
  wider views use a semantic table. Fixed the dialog's grid row sizing so its
  scrollable mobile body reaches the last SKU without clipping.
- Saved the actual desktop browser screenshot to
  `local_backups/dashboard-sku-details-20261004.jpg` in the workspace root.

Proof boundary: the existing frontend test environment is Node/SSR, not a
mounted DOM harness. Async error/retry/abort and late-response guards were
code-reviewed, not failure-injected in a mounted component. The real browser
checks cover successful loading, filters, sorting, keyboard close/focus, and
responsive scrolling. No new dependency was added.

## Existing warehouse release

Install warehouse SQL `003_marts.sql` and restore reader grants with
`005_analytics_readonly_grants.sql` before publishing the backend/frontend.
Existing loaded SKU/line/delivery facts are sufficient; no full ETL is required
for this feature alone. Never run fixture `004_verify.sql` on populated
`warehouse_db`; it is restricted to `warehouse_db_test`.
