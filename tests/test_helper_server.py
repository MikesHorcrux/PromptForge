import asyncio
import json
import os
import shutil
from pathlib import Path

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, ScoringConfig
from promptforge.helper.server import PromptForgeHelper


class FakeForgeGateway:
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
        improved = "improved" in system_prompt.lower()
        output = (
            "## Summary\nPrecise answer.\n"
            "## Answer\nRefunds are available within 30 days for unused items with proof of purchase.\n"
            "## Next Steps\nReply with the order number and proof of purchase so support can review it.\n"
        )
        if improved:
            output = output.replace("Precise answer.", "Improved answer.")
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
        improved = "improved" in parsed["system_prompt"].lower()
        score = 4 if improved else 3
        return RubricJudgeOutput(
            instruction_adherence=RubricTraitScore(score=score, reason="ok"),
            format_compliance=RubricTraitScore(score=score, reason="ok"),
            clarity_conciseness=RubricTraitScore(score=score, reason="ok"),
            domain_relevance=RubricTraitScore(score=score, reason="ok"),
            tone_alignment=RubricTraitScore(score=score, reason="ok"),
            summary="improved" if improved else "baseline",
            failure_signals=[],
        )


def _seed_prompt_packs(root: Path) -> None:
    shutil.copytree(Path("prompt_packs") / "v1", root / "v1")


def test_helper_exposes_project_prompt_and_benchmark_contract(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompt_packs"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompt_packs(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_pack_dir", Path("prompt_packs"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        prompts = asyncio.run(helper.handle("prompts.list", {}))
        assert prompts["prompts"][0]["version"] == "v1"

        prompt_payload = asyncio.run(helper.handle("prompt.get", {"prompt": "v1"}))
        assert "You are" in prompt_payload["prompt"]["system_prompt"]

        benchmark = asyncio.run(helper.handle("bench.run_quick", {"prompt": "v1"}))
        assert benchmark["revision"]["benchmark"] is not None

        status = asyncio.run(helper.handle("status.get", {}))
        assert status["project"]["metadata"]["name"] == tmp_path.name
    finally:
        os.chdir(original_cwd)
