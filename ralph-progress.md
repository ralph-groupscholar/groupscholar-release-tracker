# Ralph Progress Log

## Iteration 30 (2026-02-08)
- Added an expire command to mark overdue release records as expired based on an as-of date.
- Expanded CLI usage docs and README with the new expiry workflow.
- Added Zig tests for the expiry logic.

## Iteration 31 (2026-02-08)
- Created the `groupscholar-release-tracker` Zig CLI for tracking release forms.
- Implemented JSON-backed storage with add/update/list/report commands.
- Added validation, tests, and documentation.

## Iteration 32 (2026-02-08)
- Added Postgres sync helper with SQLAlchemy for centralized reporting.
- Seeded the production database schema with realistic sample records.
- Documented database sync flow and added Python tests + .gitignore updates.

## Iteration 126 (2026-02-08)
- Fixed the Postgres sync helper to accept a configurable table name and corrected the sync completion message.
- Documented the optional schema/table targeting for the sync script.
