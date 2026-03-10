from __future__ import annotations

import sqlite3
from pathlib import Path

from promptforge.core.models import CachedResponse


class ResponseCache:
    def __init__(self, db_path: Path) -> None:
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self.db_path = db_path
        self._conn = sqlite3.connect(db_path)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute(
            """
            CREATE TABLE IF NOT EXISTS response_cache (
                cache_key TEXT PRIMARY KEY,
                prompt_version TEXT NOT NULL,
                case_id TEXT NOT NULL,
                model TEXT NOT NULL,
                config_hash TEXT NOT NULL,
                response_json TEXT NOT NULL,
                created_at TEXT NOT NULL
            )
            """
        )
        self._conn.commit()

    def get(self, cache_key: str) -> CachedResponse | None:
        row = self._conn.execute(
            "SELECT response_json FROM response_cache WHERE cache_key = ?",
            (cache_key,),
        ).fetchone()
        if not row:
            return None
        return CachedResponse.model_validate_json(row["response_json"])

    def set(self, response: CachedResponse) -> None:
        self._conn.execute(
            """
            INSERT OR REPLACE INTO response_cache (
                cache_key, prompt_version, case_id, model, config_hash, response_json, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                response.key,
                response.prompt_version,
                response.case_id,
                response.model,
                response.config_hash,
                response.model_dump_json(),
                response.created_at,
            ),
        )
        self._conn.commit()

