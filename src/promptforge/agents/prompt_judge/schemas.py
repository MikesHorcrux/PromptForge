from __future__ import annotations

from pydantic import BaseModel, Field


class RubricTraitScore(BaseModel):
    score: int = Field(ge=0, le=5)
    reason: str
    evidence: list[str] = Field(default_factory=list)


class RubricJudgeOutput(BaseModel):
    instruction_adherence: RubricTraitScore
    format_compliance: RubricTraitScore
    clarity_conciseness: RubricTraitScore
    domain_relevance: RubricTraitScore
    tone_alignment: RubricTraitScore
    summary: str
    failure_signals: list[str] = Field(default_factory=list)

