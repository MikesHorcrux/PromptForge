from __future__ import annotations

import json
from pathlib import Path

from promptforge.core.config import settings
from promptforge.core.models import FormatExpectations, utc_now_iso
from promptforge.datasets.loader import load_dataset
from promptforge.scenarios.models import ScenarioAssertion, ScenarioCase, ScenarioSuite


class ScenarioSuiteService:
    def __init__(self, *, root: Path | None = None) -> None:
        self.root = (root or settings.scenario_dir).resolve()
        self.root.mkdir(parents=True, exist_ok=True)

    def list_suites(self) -> list[ScenarioSuite]:
        suites: list[ScenarioSuite] = []
        for path in sorted(self.root.glob("*.json"), key=lambda candidate: candidate.name.lower()):
            try:
                suites.append(self.load_suite(path.stem))
            except Exception:
                continue
        return suites

    def suite_path(self, suite_id: str) -> Path:
        return self.root / f"{suite_id}.json"

    def load_suite(self, suite_id: str) -> ScenarioSuite:
        path = self.suite_path(suite_id)
        if not path.exists():
            raise FileNotFoundError(f"Scenario suite not found: {suite_id}")
        return ScenarioSuite.model_validate(json.loads(path.read_text(encoding="utf-8")))

    def save_suite(self, suite: ScenarioSuite) -> Path:
        suite.updated_at = utc_now_iso()
        path = self.suite_path(suite.suite_id)
        path.write_text(
            json.dumps(suite.model_dump(mode="json"), indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return path

    def create_suite(
        self,
        suite_id: str,
        *,
        name: str | None = None,
        description: str = "",
        linked_prompts: list[str] | None = None,
    ) -> ScenarioSuite:
        path = self.suite_path(suite_id)
        if path.exists():
            raise FileExistsError(f"Scenario suite already exists: {suite_id}")
        suite = ScenarioSuite(
            suite_id=suite_id,
            name=name or suite_id.replace("-", " ").title(),
            description=description,
            linked_prompts=linked_prompts or [],
        )
        self.save_suite(suite)
        return suite

    def ensure_default_suite(self, *, dataset_path: str, prompt_ref: str | None = None) -> ScenarioSuite:
        suites = self.list_suites()
        if suites:
            if prompt_ref:
                for suite in suites:
                    if not suite.linked_prompts or prompt_ref in suite.linked_prompts:
                        return suite
            return suites[0]

        dataset = load_dataset(dataset_path)
        suite_id = dataset.path.stem
        cases: list[ScenarioCase] = []
        for item in dataset.cases:
            assertions: list[ScenarioAssertion] = []
            for index, required in enumerate(item.format_expectations.required_strings):
                assertions.append(
                    ScenarioAssertion(
                        assertion_id=f"{item.id}-required-{index}",
                        label=f"Must mention {required}",
                        kind="required_string",
                        expected_text=required,
                    )
                )
            if item.format_expectations.max_words is not None:
                assertions.append(
                    ScenarioAssertion(
                        assertion_id=f"{item.id}-max-words",
                        label=f"Stay under {item.format_expectations.max_words} words",
                        kind="max_words",
                        threshold=float(item.format_expectations.max_words),
                    )
                )
            for index, section in enumerate(item.format_expectations.required_sections):
                assertions.append(
                    ScenarioAssertion(
                        assertion_id=f"{item.id}-section-{index}",
                        label=f"Include {section} section",
                        kind="required_section",
                        expected_text=section,
                    )
                )
            cases.append(
                ScenarioCase(
                    case_id=item.id,
                    title=item.id,
                    input=item.input,
                    context=item.context,
                    rubric_targets=item.rubric_targets,
                    format_expectations=FormatExpectations.model_validate(
                        item.format_expectations.model_dump(mode="json")
                    ),
                    assertions=assertions,
                    tags=item.tags,
                )
            )
        suite = ScenarioSuite(
            suite_id=suite_id,
            name=dataset.path.stem.replace("-", " ").title(),
            description=f"Imported from {dataset.path.name}.",
            linked_prompts=[prompt_ref] if prompt_ref else [],
            cases=cases,
        )
        self.save_suite(suite)
        return suite
