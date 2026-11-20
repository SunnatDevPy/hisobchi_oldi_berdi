"""Restore a backup made by services/backup.py into an EMPTY database.

Usage:  python scripts/restore_backup.py hisobchi_backup_XXXX.json.gz
Run inside the bot container/venv so DATABASE_URL from .env is used.
"""

from __future__ import annotations

import asyncio
import gzip
import json
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from sqlalchemy import DateTime, insert, select, func  # noqa: E402

from database.models import Base  # noqa: E402
from database.session import async_session_maker, init_db  # noqa: E402


async def main(path: str) -> None:
    with gzip.open(path, "rt", encoding="utf-8") as fh:
        data = json.load(fh)["tables"]
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
            from sqlalchemy import text

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
    asyncio.run(main(sys.argv[1]))
