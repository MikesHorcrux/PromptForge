from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

from promptforge.core.config import settings


SENSITIVE_KEYS = ("api_key", "authorization", "secret", "token", "password")


def _redact(value: Any) -> Any:
    if isinstance(value, dict):
        redacted: dict[str, Any] = {}
        for key, item in value.items():
            if any(marker in key.lower() for marker in SENSITIVE_KEYS):
                redacted[key] = "***REDACTED***"
            else:
                redacted[key] = _redact(item)
        return redacted
    if isinstance(value, list):
        return [_redact(item) for item in value]
    return value


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        extra = getattr(record, "payload", None)
        if isinstance(extra, dict):
            payload.update(_redact(extra))
        return json.dumps(payload, sort_keys=True)


def configure_logging() -> logging.Logger:
    settings.logs_dir.mkdir(parents=True, exist_ok=True)
    logger = logging.getLogger("promptforge")
    if logger.handlers:
        return logger

    logger.setLevel(settings.log_level.upper())
    log_path = settings.logs_dir / "promptforge.log"
    handler = logging.FileHandler(log_path)
    handler.setFormatter(JsonFormatter())
    logger.addHandler(handler)
    stream_handler = logging.StreamHandler()
    stream_handler.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(stream_handler)
    return logger


def log_event(logger: logging.Logger, message: str, **payload: Any) -> None:
    logger.info(message, extra={"payload": payload})

