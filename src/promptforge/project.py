from __future__ import annotations

import json
from pathlib import Path

from pydantic import BaseModel, Field

from promptforge.core.config import settings
from promptforge.core.models import ProviderName, utc_now_iso


PROJECT_DIR_NAME = ".promptforge"
PROJECT_METADATA_FILE = "project.json"


class ProjectMetadata(BaseModel):
    format_version: int = 1
    name: str = "PromptForge Project"
    last_opened_prompt: str | None = None
    quick_benchmark_dataset: str = "datasets/core.jsonl"
    full_evaluation_dataset: str = "datasets/core.jsonl"
    quick_benchmark_repeats: int = 1
    full_evaluation_repeats: int = 1
    preferred_provider: ProviderName = settings.provider
    preferred_judge_provider: ProviderName | None = settings.judge_provider
    preferred_generation_model: str = settings.openai_base_model
    preferred_judge_model: str = settings.openai_judge_model
    preferred_agent_model: str = "gpt-5-mini"
    builder_permission_mode: str = "proposal_only"
    builder_research_policy: str = "prompt_only"
    created_at: str = Field(default_factory=utc_now_iso)
    updated_at: str = Field(default_factory=utc_now_iso)


class PromptForgeProject:
    def __init__(self, *, root: Path, metadata: ProjectMetadata) -> None:
        self.root = root
        self.metadata = metadata

    @property
    def project_dir(self) -> Path:
        return self.root / PROJECT_DIR_NAME

    @property
    def metadata_path(self) -> Path:
        return self.project_dir / PROJECT_METADATA_FILE

    @classmethod
    def open_or_create(cls, root: Path) -> "PromptForgeProject":
        root = root.resolve()
        metadata_path = root / PROJECT_DIR_NAME / PROJECT_METADATA_FILE
        if metadata_path.exists():
            metadata = ProjectMetadata.model_validate(
                json.loads(metadata_path.read_text(encoding="utf-8"))
            )
            project = cls(root=root, metadata=metadata)
            project.ensure_layout()
            return project

        project = cls(
            root=root,
            metadata=ProjectMetadata(name=root.name or "PromptForge Project"),
        )
        project.ensure_layout()
        project.save()
        return project

    def ensure_layout(self) -> None:
        self.project_dir.mkdir(parents=True, exist_ok=True)
        (self.root / settings.prompt_pack_dir).mkdir(parents=True, exist_ok=True)
        (self.root / settings.dataset_dir).mkdir(parents=True, exist_ok=True)
        (self.root / settings.scenario_dir).mkdir(parents=True, exist_ok=True)
        (self.root / settings.var_dir).mkdir(parents=True, exist_ok=True)

    def save(self) -> None:
        self.metadata.updated_at = utc_now_iso()
        self.project_dir.mkdir(parents=True, exist_ok=True)
        self.metadata_path.write_text(
            json.dumps(self.metadata.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )

    def update_defaults(
        self,
        *,
        quick_benchmark_dataset: str | None = None,
        full_evaluation_dataset: str | None = None,
        quick_benchmark_repeats: int | None = None,
        full_evaluation_repeats: int | None = None,
        preferred_provider: ProviderName | None = None,
        preferred_judge_provider: ProviderName | None = None,
        preferred_generation_model: str | None = None,
        preferred_judge_model: str | None = None,
        preferred_agent_model: str | None = None,
        builder_permission_mode: str | None = None,
        builder_research_policy: str | None = None,
    ) -> None:
        if quick_benchmark_dataset is not None:
            self.metadata.quick_benchmark_dataset = quick_benchmark_dataset
        if full_evaluation_dataset is not None:
            self.metadata.full_evaluation_dataset = full_evaluation_dataset
        if quick_benchmark_repeats is not None:
            self.metadata.quick_benchmark_repeats = quick_benchmark_repeats
        if full_evaluation_repeats is not None:
            self.metadata.full_evaluation_repeats = full_evaluation_repeats
        if preferred_provider is not None:
            self.metadata.preferred_provider = preferred_provider
        if preferred_judge_provider is not None:
            self.metadata.preferred_judge_provider = preferred_judge_provider
        if preferred_generation_model is not None:
            self.metadata.preferred_generation_model = preferred_generation_model
        if preferred_judge_model is not None:
            self.metadata.preferred_judge_model = preferred_judge_model
        if preferred_agent_model is not None:
            self.metadata.preferred_agent_model = preferred_agent_model
        if builder_permission_mode is not None:
            self.metadata.builder_permission_mode = builder_permission_mode
        if builder_research_policy is not None:
            self.metadata.builder_research_policy = builder_research_policy
        self.save()

    def set_last_opened_prompt(self, prompt_ref: str | None) -> None:
        self.metadata.last_opened_prompt = prompt_ref
        self.save()
