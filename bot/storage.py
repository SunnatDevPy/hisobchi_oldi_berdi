"""Persistent database-backed FSM storage for Aiogram 3."""

from __future__ import annotations

import json
from typing import Any, Dict, Optional

from aiogram.fsm.state import State
from aiogram.fsm.storage.base import BaseStorage, StateType, StorageKey
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from database.models import FSMState


class DatabaseFSMStorage(BaseStorage):
    """Store Aiogram FSM state and JSON data in SQLite/PostgreSQL across restarts."""

    def __init__(self, session_maker: async_sessionmaker[AsyncSession]) -> None:
        self._session_maker = session_maker

    @staticmethod
    def _make_key(key: StorageKey) -> str:
        return f"{key.bot_id}:{key.chat_id}:{key.user_id}:{key.thread_id or 0}:{key.destiny}"

    async def set_state(self, key: StorageKey, state: StateType = None) -> None:
        skey = self._make_key(key)
        state_str = state.state if isinstance(state, State) else (str(state) if state else None)
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            if row is None:
                if state_str is None:
                    return
                row = FSMState(storage_key=skey, state=state_str, data_json="{}")
                db.add(row)
            else:
                row.state = state_str
            await db.commit()

    async def get_state(self, key: StorageKey) -> Optional[str]:
        skey = self._make_key(key)
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            return row.state if row else None

    async def set_data(self, key: StorageKey, data: Dict[str, Any]) -> None:
        skey = self._make_key(key)
        encoded = json.dumps(data or {}, ensure_ascii=False, default=str)
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            if row is None:
                if not data:
                    return
                row = FSMState(storage_key=skey, state=None, data_json=encoded)
                db.add(row)
            else:
                row.data_json = encoded
            await db.commit()

    async def get_data(self, key: StorageKey) -> Dict[str, Any]:
        skey = self._make_key(key)
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            if row is None or not row.data_json:
                return {}
            try:
                parsed = json.loads(row.data_json)
                return parsed if isinstance(parsed, dict) else {}
            except json.JSONDecodeError:
                return {}

    async def close(self) -> None:
        return None
