from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

from promptforge.core.models import RunConfig, ScoringConfig, TraitName, utc_now_iso


BenchmarkLabel = Literal["benchmark", "full_evaluation"]
RevisionSource = Literal["baseline", "manual_edit", "manual_benchmark", "agent_edit", "reset", "restore"]
ChatRole = Literal["user", "assistant"]


class BenchmarkCaseSummary(BaseModel):
    case_id: str
    average_effective_score: float
    average_raw_score: float
    hard_fail_rate: float
    latest_summary: str = ""
    hard_fail_reasons: list[str] = Field(default_factory=list)


class BenchmarkDiff(BaseModel):
    reference: str
    winner: Literal["candidate", "reference", "tie"]
    confidence: float
    mean_score_delta: float
    pass_rate_delta: float
    hard_fail_rate_delta: float
    trait_deltas: dict[TraitName, float]
    improved_traits: list[str] = Field(default_factory=list)
    regressed_traits: list[str] = Field(default_factory=list)
    top_improved_cases: list[str] = Field(default_factory=list)
    top_regressed_cases: list[str] = Field(default_factory=list)


class BenchmarkSnapshot(BaseModel):
    label: BenchmarkLabel
    dataset_path: str
    repeats: int
    run_ids: list[str]
    use_cache: bool
    temperature: float | None = None
    mean_effective_score: float
    best_effective_score: float
    worst_effective_score: float
    score_stddev: float
    mean_raw_score: float
    mean_hard_fail_rate: float
    pass_rate: float
    total_cases: int
    trait_means: dict[TraitName, float]
    warnings: list[str] = Field(default_factory=list)
    cases: list[BenchmarkCaseSummary] = Field(default_factory=list)


class ForgeRevision(BaseModel):
    revision_id: str
    created_at: str
    source: RevisionSource
    note: str = ""
    changed_files: list[str] = Field(default_factory=list)
    prompt_pack_hash: str
    prompt_snapshot_dir: str
    benchmark: BenchmarkSnapshot | None = None
    full_evaluation: BenchmarkSnapshot | None = None
    benchmark_vs_baseline: BenchmarkDiff | None = None
    benchmark_vs_previous: BenchmarkDiff | None = None


class ForgeSessionManifest(BaseModel):
    session_id: str
    created_at: str
    baseline_prompt_ref: str
    baseline_prompt_dir: str
    working_prompt_dir: str
    benchmark_dataset_path: str
    full_dataset_path: str
    model: str
    provider: str
    judge_provider: str
    agent_model: str = "gpt-5-mini"
    run_config: RunConfig
    scoring_config: ScoringConfig
    bench_repeats: int = 1
    full_repeats: int = 1
    baseline_revision_id: str | None = None
    latest_revision_id: str | None = None


class ForgeHistory(BaseModel):
    revisions: list[ForgeRevision] = Field(default_factory=list)


class ChatTurn(BaseModel):
    role: ChatRole
    content: str
    created_at: str = Field(default_factory=utc_now_iso)


class ChatHistory(BaseModel):
    turns: list[ChatTurn] = Field(default_factory=list)


class PreparedAgentEdit(BaseModel):
    proposal_id: str
    created_at: str
    request: str
    summary: str
    changed_files: list[str] = Field(default_factory=list)
    diff_preview: str = ""
    staged_prompt_dir: str


class PendingEdits(BaseModel):
    edits: list[PreparedAgentEdit] = Field(default_factory=list)


class AgentEditResult(BaseModel):
    summary: str
    changed_files: list[str] = Field(default_factory=list)
    diff_preview: str = ""
    revision: ForgeRevision | None = None


class AgentChatResult(BaseModel):
    kind: Literal["reply", "proposal", "benchmark", "full_evaluation"]
    message: str
    proposal: PreparedAgentEdit | None = None
    revision: ForgeRevision | None = None
