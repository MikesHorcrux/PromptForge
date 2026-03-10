from __future__ import annotations

import json
from pathlib import Path

from promptforge.core.config import settings
from promptforge.core.hashing import sha256_file
from promptforge.core.models import DatasetCase, LoadedDataset


def resolve_dataset_path(dataset_path: str | Path) -> Path:
    path = Path(dataset_path)
    if path.exists():
        return path
    candidate = settings.dataset_dir / dataset_path
    if candidate.exists():
        return candidate
    raise FileNotFoundError(f"Dataset not found: {dataset_path}")


def load_dataset(dataset_path: str | Path) -> LoadedDataset:
    path = resolve_dataset_path(dataset_path)
    cases: list[DatasetCase] = []
    with path.open("r", encoding="utf-8") as handle:
        for line_number, raw_line in enumerate(handle, start=1):
            line = raw_line.strip()
            if not line:
                continue
            payload = json.loads(line)
            if "id" not in payload:
                payload["id"] = f"line-{line_number:04d}"
            cases.append(DatasetCase.model_validate(payload))
    if not cases:
        raise ValueError(f"Dataset is empty: {path}")
    return LoadedDataset(path=path, cases=cases, content_hash=sha256_file(path))

