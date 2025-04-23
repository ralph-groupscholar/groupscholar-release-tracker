#!/usr/bin/env python3
import argparse
import json
import os
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import DateTime, Integer, String, Text, create_engine, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker
from sqlalchemy.engine import URL

DEFAULT_SCHEMA = "release_tracker"
DEFAULT_TABLE = "release_records"
DEFAULT_SEED_PATH = Path(__file__).resolve().parents[1] / "db" / "seed_releases.json"


class Base(DeclarativeBase):
    pass


class ReleaseRecord(Base):
    __tablename__ = DEFAULT_TABLE

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    doc_type: Mapped[str] = mapped_column(String(120), nullable=False)
    contact: Mapped[str] = mapped_column(String(200), nullable=False)
    due_date: Mapped[str] = mapped_column(String(10), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    notes: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


def build_database_url() -> str:
    explicit = os.getenv("RELEASE_TRACKER_DATABASE_URL")
    if explicit:
        return explicit

    host = os.getenv("PGHOST")
    port = os.getenv("PGPORT")
    user = os.getenv("PGUSER")
    password = os.getenv("PGPASSWORD")
    database = os.getenv("PGDATABASE", "postgres")

    missing = [key for key, value in {
        "PGHOST": host,
        "PGPORT": port,
        "PGUSER": user,
        "PGPASSWORD": password,
    }.items() if not value]

    if missing:
        raise SystemExit(
            "Missing database configuration. Set RELEASE_TRACKER_DATABASE_URL or "
            + ", ".join(missing)
            + "."
        )

    url = URL.create(
        "postgresql+psycopg",
        username=user,
        password=password,
        host=host,
        port=int(port),
        database=database,
    )
    return str(url)


def load_payload(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def parse_records(payload: dict) -> list[dict]:
    records = []
    for record in payload.get("records", []):
        created_raw = record.get("created_at")
        if created_raw is None:
            created_at = datetime.now(tz=timezone.utc)
        else:
            created_at = datetime.fromtimestamp(int(created_raw), tz=timezone.utc)
        records.append({
            "id": int(record["id"]),
            "name": record["name"],
            "doc_type": record["doc_type"],
            "contact": record["contact"],
            "due_date": record["due_date"],
            "status": record["status"],
            "notes": record.get("notes", ""),
            "created_at": created_at,
        })
    return records


def ensure_schema(engine, schema: str) -> None:
    with engine.begin() as connection:
        connection.execute(text(f"CREATE SCHEMA IF NOT EXISTS {schema}"))


def sync_records(engine, schema: str, records: list[dict], truncate: bool) -> None:
    ReleaseRecord.__table__.schema = schema

    Base.metadata.create_all(engine)

    Session = sessionmaker(engine)
    with Session.begin() as session:
        if truncate:
            session.execute(text(f"TRUNCATE TABLE {schema}.{DEFAULT_TABLE}"))
        if not records:
            return
        stmt = insert(ReleaseRecord).values(records)
        update_cols = {
            col.name: getattr(stmt.excluded, col.name)
            for col in ReleaseRecord.__table__.columns
            if col.name != "id"
        }
        stmt = stmt.on_conflict_do_update(index_elements=[ReleaseRecord.id], set_=update_cols)
        session.execute(stmt)


def main() -> None:
    parser = argparse.ArgumentParser(description="Sync release tracker JSON data to Postgres.")
    parser.add_argument(
        "--path",
        type=Path,
        default=DEFAULT_SEED_PATH,
        help="Path to the JSON ledger (defaults to db/seed_releases.json).",
    )
    parser.add_argument("--schema", default=DEFAULT_SCHEMA, help="Postgres schema name.")
    parser.add_argument("--truncate", action="store_true", help="Truncate table before insert.")

    args = parser.parse_args()

    payload = load_payload(args.path)
    records = parse_records(payload)

    database_url = build_database_url()
    engine = create_engine(database_url, pool_pre_ping=True)

    ensure_schema(engine, args.schema)
    sync_records(engine, args.schema, records, args.truncate)

    print(f"Synced {len(records)} records to {args.schema}.{args.table}.")


if __name__ == "__main__":
    main()
