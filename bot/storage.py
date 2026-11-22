"""Persistent database-backed FSM storage for Aiogram 3."""

from __future__ import annotations

import json
from typing import Any, Dict, Optional

from aiogram.fsm.state import State
from aiogram.fsm.storage.base import BaseStorage, StateType, StorageKey
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from database.models import FSMState


class DatabaseFSMStorage(BaseStorage):
    """Store Aiogram FSM state and JSON data in SQLite/PostgreSQL with write-through RAM cache."""

    def __init__(self, session_maker: async_sessionmaker[AsyncSession]) -> None:
        self._session_maker = session_maker
        self._state_cache: Dict[str, Optional[str]] = {}
        self._data_cache: Dict[str, Dict[str, Any]] = {}
        self._data_json_cache: Dict[str, str] = {}

    @staticmethod
    def _make_key(key: StorageKey) -> str:
        return f"{key.bot_id}:{key.chat_id}:{key.user_id}:{key.thread_id or 0}:{key.destiny}"

    async def set_state(self, key: StorageKey, state: StateType = None) -> None:
        skey = self._make_key(key)
        state_str = state.state if isinstance(state, State) else (str(state) if state else None)
        if skey in self._state_cache and self._state_cache[skey] == state_str:
            return
        self._state_cache[skey] = state_str
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
        if skey in self._state_cache:
            return self._state_cache[skey]
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            val = row.state if row else None
            self._state_cache[skey] = val
            return val

    async def set_data(self, key: StorageKey, data: Dict[str, Any]) -> None:
        skey = self._make_key(key)
        data_copy = dict(data or {})
        encoded = json.dumps(data_copy, ensure_ascii=False, default=str)
        if skey in self._data_json_cache and self._data_json_cache[skey] == encoded:
            return
        self._data_cache[skey] = data_copy
        self._data_json_cache[skey] = encoded
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            if row is None:
                if not data_copy:
                    return
                row = FSMState(storage_key=skey, state=None, data_json=encoded)
                db.add(row)
            else:
                row.data_json = encoded
            await db.commit()

    async def get_data(self, key: StorageKey) -> Dict[str, Any]:
        skey = self._make_key(key)
        if skey in self._data_cache:
            return dict(self._data_cache[skey])
        async with self._session_maker() as db:
            row = await db.get(FSMState, skey)
            if row is None or not row.data_json:
                self._data_cache[skey] = {}
                self._data_json_cache[skey] = "{}"
                return {}
            try:
                parsed = json.loads(row.data_json)
                val = parsed if isinstance(parsed, dict) else {}
            except json.JSONDecodeError:
                val = {}
            self._data_cache[skey] = val
            self._data_json_cache[skey] = json.dumps(val, ensure_ascii=False, default=str)
            return dict(val)

    async def close(self) -> None:
        return None
