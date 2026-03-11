from __future__ import annotations

import json
from pathlib import Path

from pydantic import BaseModel


PROMPT_BRIEF_FILE = "prompt.json"


class PromptBrief(BaseModel):
    format_version: int = 1
    purpose: str = ""
    expected_behavior: str = ""
    success_criteria: str = ""


def default_prompt_brief(*, description: str = "") -> PromptBrief:
    return PromptBrief(purpose=description.strip())


def load_prompt_brief(prompt_root: str | Path, *, description: str = "") -> PromptBrief:
    path = Path(prompt_root) / PROMPT_BRIEF_FILE
    if not path.exists():
        return default_prompt_brief(description=description)
    return PromptBrief.model_validate(json.loads(path.read_text(encoding="utf-8")))


def save_prompt_brief(prompt_root: str | Path, brief: PromptBrief) -> Path:
    path = Path(prompt_root) / PROMPT_BRIEF_FILE
    path.write_text(
        json.dumps(brief.model_dump(mode="json"), indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return path


def ensure_prompt_brief(prompt_root: str | Path, *, description: str = "") -> PromptBrief:
    prompt_root = Path(prompt_root)
    brief = load_prompt_brief(prompt_root, description=description)
    if not (prompt_root / PROMPT_BRIEF_FILE).exists():
        save_prompt_brief(prompt_root, brief)
    return brief
