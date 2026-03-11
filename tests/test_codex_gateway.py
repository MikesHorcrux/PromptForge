import asyncio
import os
from pathlib import Path

import pytest

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput
from promptforge.runtime.gateway import CodexGateway, _normalize_codex_json_schema


def test_codex_schema_is_closed_recursively() -> None:
    schema = _normalize_codex_json_schema(RubricJudgeOutput.model_json_schema())

    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == set(schema["properties"].keys())
    assert schema["$defs"]["RubricTraitScore"]["additionalProperties"] is False
    assert set(schema["$defs"]["RubricTraitScore"]["required"]) == set(schema["$defs"]["RubricTraitScore"]["properties"].keys())


def test_codex_gateway_kills_process_on_timeout(tmp_path, monkeypatch) -> None:
    pid_file = tmp_path / "codex.pid"
    fake_codex = tmp_path / "fake-codex"
    fake_codex.write_text(
        """#!/usr/bin/env python3
import os
import signal
import sys
import time
from pathlib import Path

Path(os.environ["PROMPTFORGE_FAKE_CODEX_PID"]).write_text(str(os.getpid()), encoding="utf-8")
signal.signal(signal.SIGTERM, lambda signum, frame: sys.exit(0))
time.sleep(30)
""",
        encoding="utf-8",
    )
    fake_codex.chmod(0o755)
    monkeypatch.setenv("PROMPTFORGE_FAKE_CODEX_PID", str(pid_file))

    gateway = CodexGateway(
        codex_bin=str(fake_codex),
        workdir=tmp_path,
        profile=None,
        sandbox="read-only",
        reasoning_effort="medium",
    )

    with pytest.raises(asyncio.TimeoutError):
        asyncio.run(gateway._run_codex(model="gpt-5", prompt="hello", timeout_seconds=0.05))

    pid = int(pid_file.read_text(encoding="utf-8"))
    with pytest.raises(ProcessLookupError):
        os.kill(pid, 0)
