from __future__ import annotations

import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path


ANSI_ESCAPE_RE = re.compile(r"\x1B\[[0-?]*[ -/]*[@-~]")
DEVICE_CODE_RE = re.compile(r"\b([A-Z0-9]{4,}(?:-[A-Z0-9]{4,})+)\b")
URL_RE = re.compile(r"https?://\S+")


@dataclass(frozen=True)
class CodexDeviceAuthResult:
    verification_uri: str | None
    user_code: str | None
    instructions: str


def resolve_codex_bin(codex_bin: str) -> str | None:
    expanded = os.path.expanduser(codex_bin)
    if os.path.sep in expanded:
        candidate = Path(expanded)
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate.resolve())
        return None
    return shutil.which(expanded)


def strip_ansi(value: str) -> str:
    return ANSI_ESCAPE_RE.sub("", value)


def codex_login_status(codex_bin: str, *, timeout: float = 5.0) -> tuple[bool, str]:
    resolved = resolve_codex_bin(codex_bin)
    if resolved is None:
        return False, f"Codex CLI not found: {codex_bin}"

    try:
        completed = subprocess.run(
            [resolved, "login", "status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except Exception as exc:
        return False, f"Codex status unavailable: {exc}"

    detail = strip_ansi(completed.stdout.strip() or completed.stderr.strip() or f"Codex CLI found at {resolved}")
    return completed.returncode == 0, detail


def codex_login_with_api_key(
    codex_bin: str,
    *,
    api_key: str,
    timeout: float = 15.0,
) -> tuple[bool, str]:
    resolved = resolve_codex_bin(codex_bin)
    if resolved is None:
        return False, f"Codex CLI not found: {codex_bin}"

    normalized_key = api_key.strip()
    if not normalized_key:
        return False, "OpenAI API key is required for Codex API-key login."

    try:
        completed = subprocess.run(
            [resolved, "login", "--with-api-key"],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            input=f"{normalized_key}\n",
        )
    except Exception as exc:
        return False, f"Codex login failed: {exc}"

    detail = strip_ansi(completed.stdout.strip() or completed.stderr.strip() or "Codex login completed.")
    if completed.returncode != 0:
        return False, detail

    return codex_login_status(resolved, timeout=timeout)


def codex_begin_device_auth(codex_bin: str, *, timeout: float = 15.0) -> CodexDeviceAuthResult:
    resolved = resolve_codex_bin(codex_bin)
    if resolved is None:
        raise RuntimeError(f"Codex CLI not found: {codex_bin}")

    try:
        completed = subprocess.run(
            [resolved, "login", "--device-auth"],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except Exception as exc:
        raise RuntimeError(f"Could not start Codex device auth: {exc}") from exc

    output = strip_ansi(completed.stdout.strip() or completed.stderr.strip())
    if completed.returncode != 0:
        raise RuntimeError(output or "Codex device auth failed.")

    verification_uri = None
    url_match = URL_RE.search(output)
    if url_match:
        verification_uri = url_match.group(0)

    user_code = None
    code_match = DEVICE_CODE_RE.search(output)
    if code_match:
        user_code = code_match.group(1)

    if user_code and verification_uri:
        instructions = f"Open {verification_uri} and enter code {user_code}."
    else:
        instructions = output or "Codex device auth started."

    return CodexDeviceAuthResult(
        verification_uri=verification_uri,
        user_code=user_code,
        instructions=instructions,
    )
