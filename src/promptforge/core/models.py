from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, Field, field_validator, model_validator


RUBRIC_TRAITS = (
    "instruction_adherence",
    "format_compliance",
    "clarity_conciseness",
    "domain_relevance",
    "tone_alignment",
)

TraitName = Literal[
    "instruction_adherence",
    "format_compliance",
    "clarity_conciseness",
    "domain_relevance",
    "tone_alignment",
]
ProviderName = Literal["openai", "openrouter", "codex"]


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


class PromptPackManifest(BaseModel):
    api_version: int = Field(default=1, alias="apiVersion")
    version: str
    name: str
    description: str = ""
    output_format: Literal["markdown", "json", "text"] = "markdown"
    required_sections: list[str] = Field(default_factory=list)
    metadata: dict[str, Any] = Field(default_factory=dict)


class PromptPack(BaseModel):
    root: Path
    manifest: PromptPackManifest
    system_prompt: str
    user_template: str
    variables_schema: dict[str, Any]
    content_hash: str


class FormatExpectations(BaseModel):
    output_format: Literal["markdown", "json", "text"] | None = None
    required_sections: list[str] = Field(default_factory=list)
    required_json_fields: list[str] = Field(default_factory=list)
    required_strings: list[str] = Field(default_factory=list)
    forbidden_strings: list[str] = Field(default_factory=list)
    max_words: int | None = None


class DatasetCase(BaseModel):
    id: str
    input: dict[str, Any]
    context: str | dict[str, Any] | list[Any] | None = None
    rubric_targets: dict[str, str] = Field(default_factory=dict)
    format_expectations: FormatExpectations = Field(default_factory=FormatExpectations)
    tags: list[str] = Field(default_factory=list)


class LoadedDataset(BaseModel):
    path: Path
    cases: list[DatasetCase]
    content_hash: str


class RunConfig(BaseModel):
    temperature: float | None = None
    max_output_tokens: int = 800
    seed: int | None = None
    retries: int = 2
    timeout_seconds: float = 60.0
    concurrency: int = 8
    failure_threshold: float = 0.40

    @field_validator("concurrency")
    @classmethod
    def validate_concurrency(cls, value: int) -> int:
        if value < 1:
            raise ValueError("concurrency must be >= 1")
        return value

    @field_validator("failure_threshold")
    @classmethod
    def validate_failure_threshold(cls, value: float) -> float:
        if value <= 0 or value > 1:
            raise ValueError("failure_threshold must be between 0 and 1")
        return value


class HardFailRules(BaseModel):
    fail_on_missing_sections: bool = True
    fail_on_invalid_json_when_required: bool = True
    fail_on_policy_markers: bool = True
    policy_markers: list[str] = Field(
        default_factory=lambda: [
            "[policy_violation]",
            "[unsafe_content]",
            "SAFETY_VIOLATION",
        ]
    )


class ScoringConfig(BaseModel):
    rubric_weights: dict[TraitName, float] = Field(
        default_factory=lambda: {
            "instruction_adherence": 0.30,
            "format_compliance": 0.20,
            "clarity_conciseness": 0.20,
            "domain_relevance": 0.20,
            "tone_alignment": 0.10,
        }
    )
    hard_fail_rules: HardFailRules = Field(default_factory=HardFailRules)
    judge_model: str = "gpt-5-mini"
    judge_max_output_tokens: int = 700
    judge_temperature: float | None = 0.0
    tie_margin: float = 0.20

    @model_validator(mode="after")
    def validate_weights(self) -> "ScoringConfig":
        total = sum(self.rubric_weights.values())
        if round(total, 5) != 1.0:
            raise ValueError("rubric weights must sum to 1.0")
        missing = set(RUBRIC_TRAITS) - set(self.rubric_weights.keys())
        if missing:
            raise ValueError(f"rubric weights missing traits: {sorted(missing)}")
        return self


class RunRequest(BaseModel):
    prompt_version: str
    model: str
    dataset_path: str
    run_config: RunConfig
    scoring_config: ScoringConfig
    provider: ProviderName = "openai"
    judge_provider: ProviderName | None = None


class RuleCheckResult(BaseModel):
    required_sections: list[str] = Field(default_factory=list)
    missing_sections: list[str] = Field(default_factory=list)
    required_json_fields: list[str] = Field(default_factory=list)
    missing_json_fields: list[str] = Field(default_factory=list)
    required_strings: list[str] = Field(default_factory=list)
    missing_strings: list[str] = Field(default_factory=list)
    forbidden_strings_found: list[str] = Field(default_factory=list)
    invalid_json: bool = False
    json_required: bool = False
    output_format: str | None = None
    policy_markers_found: list[str] = Field(default_factory=list)
    word_count: int = 0
    over_max_words: bool = False
    format_score: float = 5.0


class TraitScore(BaseModel):
    score: int = Field(ge=0, le=5)
    reason: str
    evidence: list[str] = Field(default_factory=list)


class CaseScore(BaseModel):
    case_id: str
    hard_fail: bool
    hard_fail_reasons: list[str] = Field(default_factory=list)
    rule_checks: RuleCheckResult
    trait_scores: dict[TraitName, TraitScore]
    raw_weighted_score: float
    effective_weighted_score: float
    normalized_score: float
    summary: str


class AggregateScores(BaseModel):
    total_cases: int
    completed_cases: int
    cached_cases: int
    failed_cases: int
    hard_fail_count: int
    hard_fail_rate: float
    average_raw_score: float
    average_effective_score: float
    average_normalized_score: float
    trait_averages: dict[TraitName, float]


class ScoresArtifact(BaseModel):
    run_id: str
    created_at: str
    prompt_version: str
    model: str
    config_hash: str
    dataset_hash: str
    prompt_pack_hash: str
    aggregate: AggregateScores
    cases: list[CaseScore]
    warnings: list[str] = Field(default_factory=list)


class ModelExecutionResult(BaseModel):
    case_id: str
    prompt_version: str
    model: str
    provider: ProviderName = "openai"
    output_text: str | None = None
    cached: bool = False
    response_id: str | None = None
    usage: dict[str, Any] = Field(default_factory=dict)
    latency_ms: int = 0
    error: str | None = None
    warnings: list[str] = Field(default_factory=list)


class CachedResponse(BaseModel):
    key: str
    prompt_version: str
    case_id: str
    model: str
    config_hash: str
    output_text: str
    response_id: str | None = None
    usage: dict[str, Any] = Field(default_factory=dict)
    warnings: list[str] = Field(default_factory=list)
    created_at: str = Field(default_factory=utc_now_iso)


class RunManifest(BaseModel):
    run_id: str
    kind: Literal["evaluation", "comparison"]
    created_at: str
    provider: ProviderName | None = None
    judge_provider: ProviderName | None = None
    prompt_version: str | None = None
    compare_a: str | None = None
    compare_b: str | None = None
    model: str | None = None
    dataset_path: str | None = None
    config_hash: str | None = None
    output_dir: str
    notes: list[str] = Field(default_factory=list)


class ComparisonCaseResult(BaseModel):
    case_id: str
    winner: Literal["a", "b", "tie"]
    confidence: float
    effective_score_a: float
    effective_score_b: float
    raw_score_delta: float
    hard_fail_a: bool
    hard_fail_b: bool
    reason: str
    improved_traits: list[str] = Field(default_factory=list)
    regressed_traits: list[str] = Field(default_factory=list)


class ComparisonAggregate(BaseModel):
    case_wins_a: int
    case_wins_b: int
    ties: int
    average_effective_score_a: float
    average_effective_score_b: float
    overall_winner: Literal["a", "b", "tie"]
    confidence: float
    trait_deltas: dict[TraitName, float]
    improved_traits_for_b: list[str] = Field(default_factory=list)
    regressed_traits_for_b: list[str] = Field(default_factory=list)
    top_improved_cases_for_b: list[str] = Field(default_factory=list)
    top_regressed_cases_for_b: list[str] = Field(default_factory=list)


class ComparisonArtifact(BaseModel):
    run_id: str
    created_at: str
    prompt_a: str
    prompt_b: str
    model: str
    dataset_hash: str
    config_hash_a: str
    config_hash_b: str
    aggregate: ComparisonAggregate
    cases: list[ComparisonCaseResult]


class Lockfile(BaseModel):
    run_id: str
    created_at: str
    provider: ProviderName | None = None
    judge_provider: ProviderName | None = None
    prompt_version: str | None = None
    compare_a: str | None = None
    compare_b: str | None = None
    model: str
    dataset_path: str
    dataset_hash: str
    prompt_pack_hash: str | None = None
    prompt_pack_hash_a: str | None = None
    prompt_pack_hash_b: str | None = None
    config_hash: str
    run_config: dict[str, Any]
    scoring_config: dict[str, Any]
    python_version: str
    package_version: str
    warnings: list[str] = Field(default_factory=list)
