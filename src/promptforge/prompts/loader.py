from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import yaml
from jinja2 import Environment, StrictUndefined
from jsonschema import Draft202012Validator

from promptforge.core.config import settings
from promptforge.core.hashing import sha256_model
from promptforge.core.models import DatasetCase, LoadedPrompt, PromptManifest


PROMPT_FILES = ("manifest.yaml", "system.md", "user_template.md", "variables.schema.json")


def resolve_prompt_path(prompt_version: str | Path) -> Path:
    path = Path(prompt_version)
    if path.exists():
        return path
    candidate = settings.prompt_dir / prompt_version
    if candidate.exists():
        return candidate
    raise FileNotFoundError(f"Prompt not found: {prompt_version}")


def load_prompt(prompt_version: str | Path) -> LoadedPrompt:
    root = resolve_prompt_path(prompt_version)
    missing = [name for name in PROMPT_FILES if not (root / name).exists()]
    if missing:
        raise FileNotFoundError(f"Prompt {root} is missing files: {', '.join(missing)}")

    manifest = PromptManifest.model_validate(
        yaml.safe_load((root / "manifest.yaml").read_text(encoding="utf-8"))
    )
    system_prompt = (root / "system.md").read_text(encoding="utf-8").strip()
    user_template = (root / "user_template.md").read_text(encoding="utf-8").strip()
    variables_schema = json.loads((root / "variables.schema.json").read_text(encoding="utf-8"))
    content_hash = sha256_model(
        {
            "manifest": manifest.model_dump(mode="json", by_alias=True),
            "system": system_prompt,
            "user_template": user_template,
            "schema": variables_schema,
        }
    )
    return LoadedPrompt(
        root=root,
        manifest=manifest,
        system_prompt=system_prompt,
        user_template=user_template,
        variables_schema=variables_schema,
        content_hash=content_hash,
    )


def validate_case_inputs(prompt: LoadedPrompt, case: DatasetCase) -> None:
    Draft202012Validator(prompt.variables_schema).validate(case.input)


def render_user_prompt(prompt: LoadedPrompt, case: DatasetCase) -> str:
    validate_case_inputs(prompt, case)
    env = Environment(undefined=StrictUndefined, autoescape=False, trim_blocks=True, lstrip_blocks=True)
    template = env.from_string(prompt.user_template)
    payload: dict[str, Any] = dict(case.input)
    payload["input"] = case.input
    payload["context"] = case.context
    payload["case_id"] = case.id
    payload["rubric_targets"] = case.rubric_targets
    payload["format_expectations"] = case.format_expectations.model_dump(mode="json")
    return template.render(**payload).strip()
