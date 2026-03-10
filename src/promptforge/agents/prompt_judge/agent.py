from __future__ import annotations

from pathlib import Path


def load_judge_instructions() -> str:
    return Path(__file__).with_name("instructions.md").read_text(encoding="utf-8").strip()

