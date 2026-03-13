from __future__ import annotations

import os
from pathlib import Path

from dotenv import load_dotenv
from pydantic import BaseModel, Field


load_dotenv()


class Settings(BaseModel):
    engine_root: Path = Field(default_factory=lambda: Path(os.getenv("PF_ENGINE_ROOT", ".")).expanduser())
    openai_api_key: str | None = os.getenv("OPENAI_API_KEY")
    openai_base_model: str = os.getenv("OPENAI_BASE_MODEL", "gpt-5.4")
    openai_judge_model: str = os.getenv("OPENAI_JUDGE_MODEL", "gpt-5-mini")
    openrouter_api_key: str | None = os.getenv("OPENROUTER_API_KEY")
    openrouter_base_url: str = os.getenv("OPENROUTER_BASE_URL", "https://openrouter.ai/api/v1")
    app_env: str = os.getenv("PF_APP_ENV", "local")
    log_level: str = os.getenv("PF_LOG_LEVEL", "INFO")
    prompt_dir: Path = Field(default_factory=lambda: Path(os.getenv("PF_PROMPT_DIR", "prompts")))
    dataset_dir: Path = Field(default_factory=lambda: Path(os.getenv("PF_DATASET_DIR", "datasets")))
    scenario_dir: Path = Field(default_factory=lambda: Path(os.getenv("PF_SCENARIO_DIR", "scenarios")))
    var_dir: Path = Field(default_factory=lambda: Path(os.getenv("PF_VAR_DIR", "var")))
    provider: str = os.getenv("PF_PROVIDER", "openai")
    judge_provider: str | None = os.getenv("PF_JUDGE_PROVIDER") or None
    default_timeout_seconds: float = float(os.getenv("PF_DEFAULT_TIMEOUT_SECONDS", "60"))
    default_max_output_tokens: int = int(os.getenv("PF_DEFAULT_MAX_OUTPUT_TOKENS", "800"))
    default_retries: int = int(os.getenv("PF_DEFAULT_RETRIES", "2"))
    default_concurrency: int = int(os.getenv("PF_DEFAULT_CONCURRENCY", "8"))
    default_failure_threshold: float = float(os.getenv("PF_DEFAULT_FAILURE_THRESHOLD", "0.40"))
    stdout_logs: bool = os.getenv("PF_STDOUT_LOGS", "false").lower() == "true"
    codex_bin: str = os.getenv("PF_CODEX_BIN", "codex")
    codex_profile: str | None = os.getenv("PF_CODEX_PROFILE") or None
    codex_reasoning_effort: str = os.getenv("PF_CODEX_REASONING_EFFORT", "medium")
    codex_sandbox: str = os.getenv("PF_CODEX_SANDBOX", "read-only")

    @property
    def logs_dir(self) -> Path:
        return self.var_dir / "logs"

    @property
    def state_dir(self) -> Path:
        return self.var_dir / "state"

    @property
    def runs_dir(self) -> Path:
        return self.var_dir / "runs"

    @property
    def forge_dir(self) -> Path:
        return self.var_dir / "forge"

    @property
    def cache_db_path(self) -> Path:
        return self.state_dir / "cache.sqlite3"

    @property
    def workspace_state_path(self) -> Path:
        return self.state_dir / "forge_workspace.json"

    @property
    def project_dir(self) -> Path:
        return Path(".promptforge")

    @property
    def project_metadata_path(self) -> Path:
        return self.project_dir / "project.json"


settings = Settings()
