import asyncio
import json
from pathlib import Path

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, RunRequest, ScoringConfig
from promptforge.runtime.run_service import EvaluationService


class FakeGateway:
    async def generate(
        self,
        *,
        prompt_version: str,
        case_id: str,
        model: str,
        system_prompt: str,
        user_prompt: str,
        run_id: str,
        config_hash: str,
        run_config: RunConfig,
    ) -> ModelExecutionResult:
        if prompt_version == "v1":
            output = "## Summary\nBaseline answer.\n## Answer\nRefund is allowed within 30 days.\n## Next Steps\nSubmit proof of purchase."
        else:
            output = "## Summary\nPrecise answer.\n## Answer\nRefund is allowed within 30 days with proof of purchase.\n## Next Steps\nReply with the order number so support can process it."
        return ModelExecutionResult(
            case_id=case_id,
            prompt_version=prompt_version,
            model=model,
            output_text=output,
        )

    async def judge(
        self,
        *,
        model: str,
        payload: str,
        scoring_config: ScoringConfig,
        timeout_seconds: float,
    ) -> RubricJudgeOutput:
        parsed = json.loads(payload)
        version = parsed["prompt_version"]
        score = 3 if version == "v1" else 4
        return RubricJudgeOutput(
            instruction_adherence=RubricTraitScore(score=score, reason="ok"),
            format_compliance=RubricTraitScore(score=score, reason="ok"),
            clarity_conciseness=RubricTraitScore(score=score, reason="ok"),
            domain_relevance=RubricTraitScore(score=score, reason="ok"),
            tone_alignment=RubricTraitScore(score=score, reason="ok"),
            summary=f"{version} summary",
            failure_signals=[],
        )


def test_run_and_compare_pipeline(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")
    service = EvaluationService(FakeGateway())
    scoring = ScoringConfig(judge_model="fake-judge")
    run_config = RunConfig()

    manifest = asyncio.run(
        service.run(
            RunRequest(
                prompt_version="v1",
                model="fake-model",
                dataset_path="datasets/core.jsonl",
                run_config=run_config,
                scoring_config=scoring,
                provider="openai",
                judge_provider="openai",
            )
        )
    )

    run_dir = Path(manifest.output_dir)
    assert (run_dir / "outputs.jsonl").exists()
    assert (run_dir / "scores.json").exists()
    assert (run_dir / "comparison.json").exists()
    assert (run_dir / "report.md").exists()

    compare_manifest = asyncio.run(
        service.compare(
            prompt_a="v1",
            prompt_b="v2",
            model="fake-model",
            dataset_path="datasets/core.jsonl",
            run_config=run_config,
            scoring_config=scoring,
        )
    )
    compare_dir = Path(compare_manifest.output_dir)
    comparison = json.loads((compare_dir / "comparison.json").read_text(encoding="utf-8"))

    assert comparison["aggregate"]["overall_winner"] == "b"
    assert (compare_dir / "report.md").exists()
