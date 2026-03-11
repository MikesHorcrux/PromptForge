from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, Field

from promptforge.core.models import DatasetCase, FormatExpectations, TraitName, utc_now_iso


ScenarioAssertionKind = Literal[
    "required_string",
    "forbidden_string",
    "required_section",
    "max_words",
    "trait_minimum",
    "max_latency_ms",
    "max_total_tokens",
]


class ScenarioAssertion(BaseModel):
    assertion_id: str
    label: str
    kind: ScenarioAssertionKind
    expected_text: str | None = None
    threshold: float | None = None
    trait: TraitName | None = None
    severity: Literal["info", "warn", "fail"] = "fail"


class ScenarioCase(BaseModel):
    case_id: str
    title: str = ""
    input: dict[str, Any]
    context: str | dict[str, Any] | list[Any] | None = None
    rubric_targets: dict[str, str] = Field(default_factory=dict)
    format_expectations: FormatExpectations = Field(default_factory=FormatExpectations)
    assertions: list[ScenarioAssertion] = Field(default_factory=list)
    tags: list[str] = Field(default_factory=list)
    notes: str = ""

    def to_dataset_case(self) -> DatasetCase:
        return DatasetCase(
            id=self.case_id,
            input=self.input,
            context=self.context,
            rubric_targets=self.rubric_targets,
            format_expectations=self.format_expectations,
            tags=self.tags,
        )


class ScenarioSuite(BaseModel):
    format_version: int = 1
    suite_id: str
    name: str
    description: str = ""
    linked_prompts: list[str] = Field(default_factory=list)
    cases: list[ScenarioCase] = Field(default_factory=list)
    created_at: str = Field(default_factory=utc_now_iso)
    updated_at: str = Field(default_factory=utc_now_iso)
