"""In-process live synchronization revision tracker across Bot, Web Mini App, and APK."""

from __future__ import annotations

from datetime import datetime, timezone
import secrets
import threading
from typing import Set

from sqlalchemy import event
from sqlalchemy.orm import ORMExecuteState, Session


# Business tables whose committed writes should trigger connected clients to refresh.
# Operational/noise tables (fsm_states, api_tokens, ai_usage_logs) are intentionally excluded.
SYNC_TRACKED_TABLES: frozenset[str] = frozenset(
    {
        "daily_cash_sessions",
        "cash_reconciliations",
        "cash_transactions",
        "nakladnoy_payments",
        "supplier_debts",
        "supplier_configs",
        "prixod_reports",
        "prixod_rows",
        "group_configs",
        "app_settings",
        "user_roles",
        "audit_logs",
    }
)

_LOCK = threading.Lock()
_BOOT_ID = secrets.token_hex(4)
_SEQ = 1
_LAST_EVENT = "startup"
_UPDATED_AT = datetime.now(timezone.utc).isoformat()
_LISTENERS_ATTACHED = False


def bump_sync_revision(reason: str = "update") -> str:
    """Advance the monotonic server revision and return the new ``rev`` token."""
    global _SEQ, _LAST_EVENT, _UPDATED_AT
    clean_reason = (reason or "update").strip()[:120] or "update"
    with _LOCK:
        _SEQ += 1
        _LAST_EVENT = clean_reason
        _UPDATED_AT = datetime.now(timezone.utc).isoformat()
        return f"{_BOOT_ID}:{_SEQ}"


def get_sync_snapshot() -> dict:
    """Return a lightweight JSON-serializable snapshot of the current revision."""
    with _LOCK:
        return {
            "rev": f"{_BOOT_ID}:{_SEQ}",
            "seq": _SEQ,
            "last_event": _LAST_EVENT,
            "updated_at": _UPDATED_AT,
        }


def _record_session_tables(session: Session, table_names: Set[str]) -> None:
    if not table_names:
        return
    tracked = table_names & SYNC_TRACKED_TABLES
    if not tracked:
        return
    bucket = session.info.get("_sync_tables")
    if bucket is None:
        session.info["_sync_tables"] = set(tracked)
    else:
        bucket.update(tracked)


def attach_sync_listeners() -> None:
    """Attach idempotent SQLAlchemy Session hooks to auto-bump revision after commits."""
    global _LISTENERS_ATTACHED
    with _LOCK:
        if _LISTENERS_ATTACHED:
            return
        _LISTENERS_ATTACHED = True

    @event.listens_for(Session, "before_flush")
    def _on_before_flush(session: Session, flush_context, instances) -> None:  # noqa: ANN001
        tables: Set[str] = set()
        for obj in session.new:
            tbl = getattr(obj, "__tablename__", None)
            if isinstance(tbl, str):
                tables.add(tbl)
        for obj in session.deleted:
            tbl = getattr(obj, "__tablename__", None)
            if isinstance(tbl, str):
                tables.add(tbl)
        for obj in session.dirty:
            if session.is_modified(obj, include_collections=False):
                tbl = getattr(obj, "__tablename__", None)
                if isinstance(tbl, str):
                    tables.add(tbl)
        _record_session_tables(session, tables)

    @event.listens_for(Session, "do_orm_execute")
    def _on_do_orm_execute(orm_execute_state: ORMExecuteState) -> None:
        if not (orm_execute_state.is_update or orm_execute_state.is_delete):
            return
        stmt = orm_execute_state.statement
        tbl = getattr(stmt, "table", None)
        tbl_name = getattr(tbl, "name", None)
        if isinstance(tbl_name, str):
            _record_session_tables(orm_execute_state.session, {tbl_name})

    @event.listens_for(Session, "after_commit")
    def _on_after_commit(session: Session) -> None:
        tables = session.info.pop("_sync_tables", None)
        if tables:
            bump_sync_revision(",".join(sorted(tables)))

    @event.listens_for(Session, "after_rollback")
    def _on_after_rollback(session: Session) -> None:
        session.info.pop("_sync_tables", None)
