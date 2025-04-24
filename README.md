# GroupScholar Release Tracker

Group Scholar operations often need to track media release forms, consent documents, and usage approvals tied to scholars, mentors, and partners. This Zig CLI keeps a local JSON ledger of release requests and statuses so the team can see what is pending, received, approved, or expired.

## Features
- Initialize a release ledger JSON file
- Add release requests with due dates, contacts, and notes
- Update status and notes for existing records
- List records with optional status filtering
- Generate a quick status report
- Expire overdue records as of a given date
- Sync the local ledger to Postgres for centralized reporting

## Usage

```bash
zig build run -- init data/releases.json

zig build run -- add data/releases.json \
  --name "Avery Hudson" \
  --type "Photo Release" \
  --contact "avery@example.org" \
  --due 2026-03-01 \
  --notes "Needed for spring cohort story"

zig build run -- list data/releases.json --status pending

zig build run -- update data/releases.json --id 1 --status received --notes "Signed 2026-02-05"

zig build run -- report data/releases.json

zig build run -- expire data/releases.json --as-of 2026-02-15
```

## Postgres Sync

This project includes a helper script to sync a JSON ledger into a Postgres schema for shared reporting.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

export RELEASE_TRACKER_DATABASE_URL="postgresql+psycopg://USER:PASSWORD@HOST:PORT/postgres"

python scripts/sync_postgres.py --path data/releases.json
```

You can also seed the database using the bundled sample data:

```bash
python scripts/sync_postgres.py --truncate
```

## Data Model
Each record stores:
- `id`
- `name`
- `doc_type`
- `contact`
- `due_date` (YYYY-MM-DD)
- `status` (`pending`, `received`, `approved`, `expired`)
- `notes`
- `created_at` (unix timestamp)

## Tests

```bash
zig build test
```

```bash
python -m unittest discover -s tests -p "test_*.py"
```

## Technology
- Zig 0.15.x
- Python 3.11 (Postgres sync helper)
