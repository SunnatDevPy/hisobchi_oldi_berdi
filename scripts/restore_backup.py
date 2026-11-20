"""Restore a plain (.json.gz) or encrypted (.json.gz.enc) backup into an EMPTY database.

Usage:
    python scripts/restore_backup.py hisobchi_backup_XXXX.json.gz
    python scripts/restore_backup.py hisobchi_backup_XXXX.json.gz.enc --password SECRET
"""

from __future__ import annotations

import argparse
import asyncio
import getpass
import gzip
import json
import os
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import DateTime, func, insert, select, text  # noqa: E402

from database.models import Base  # noqa: E402
from database.session import async_session_maker, init_db  # noqa: E402
from services.backup import ENC_MAGIC, decrypt_backup_bytes  # noqa: E402


async def main(path: str, password: str | None = None) -> None:
    raw_bytes = Path(path).read_bytes()
    if raw_bytes.startswith(ENC_MAGIC):
        pwd = password or os.environ.get("BACKUP_PASSWORD") or getpass.getpass("Backup paroli: ")
        raw_bytes = decrypt_backup_bytes(raw_bytes, pwd)
    data = json.loads(gzip.decompress(raw_bytes).decode("utf-8"))["tables"]

    await init_db()
    async with async_session_maker() as db:
        for table in Base.metadata.sorted_tables:
            rows = data.get(table.name, [])
            if not rows:
                continue
            existing = await db.scalar(select(func.count()).select_from(table))
            if existing and table.name != "supplier_configs":
                print(f"SKIP {table.name}: bo'sh emas ({existing} qator)")
                continue
            if table.name == "supplier_configs" and existing:
                await db.execute(table.delete())
            for row in rows:
                for col in table.columns:
                    if isinstance(col.type, DateTime) and row.get(col.name):
                        row[col.name] = datetime.fromisoformat(row[col.name])
            await db.execute(insert(table), rows)
            print(f"OK {table.name}: {len(rows)} qator")
        await db.commit()
        if db.bind.dialect.name == "postgresql":
            for table in Base.metadata.sorted_tables:
                if "id" in table.columns and table.columns["id"].primary_key:
                    await db.execute(
                        text(
                            f"SELECT setval(pg_get_serial_sequence('{table.name}', 'id'), "
                            f"COALESCE((SELECT MAX(id) FROM {table.name}), 1))"
                        )
                    )
            await db.commit()
    print("Tugadi.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Restore Hisobot Bot backup.")
    parser.add_argument("backup_file", help="Path to .json.gz or .json.gz.enc file")
    parser.add_argument("--password", default=None, help="Encryption password if encrypted")
    args = parser.parse_args()
    asyncio.run(main(args.backup_file, args.password))
