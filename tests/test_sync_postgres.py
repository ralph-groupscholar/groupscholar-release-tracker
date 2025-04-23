import os
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = ROOT / "scripts"
sys.path.insert(0, str(SCRIPT_DIR))

from sync_postgres import build_database_url, parse_records, load_payload  # noqa: E402


class SyncPostgresTests(unittest.TestCase):
    def setUp(self):
        self.env_backup = dict(os.environ)

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.env_backup)

    def test_parse_records_from_seed(self):
        payload = load_payload(ROOT / "db" / "seed_releases.json")
        records = parse_records(payload)
        self.assertEqual(len(records), 5)
        self.assertEqual(records[0]["id"], 1)
        self.assertEqual(records[0]["status"], "pending")
        self.assertTrue(records[0]["created_at"].tzinfo is not None)

    def test_build_database_url_from_env(self):
        os.environ["RELEASE_TRACKER_DATABASE_URL"] = "postgresql+psycopg://user:pass@host:5432/postgres"
        url = build_database_url()
        self.assertEqual(url, os.environ["RELEASE_TRACKER_DATABASE_URL"])


if __name__ == "__main__":
    unittest.main()
