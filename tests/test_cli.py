import json
import shutil
from pathlib import Path

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.cli import build_parser, main
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, ScoringConfig


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


def test_parser_supports_legacy_and_simplified_commands() -> None:
    parser = build_parser()
    assert parser.parse_args(["scenario", "list"]).command == "scenario"
    assert parser.parse_args(["tests", "list"]).command == "tests"
    assert parser.parse_args(["review", "--prompt", "v1"]).command == "review"
    assert parser.parse_args(["promote", "--prompt", "v1"]).command == "promote"
    assert parser.parse_args(["ship", "--prompt", "v1"]).command == "ship"
    assert parser.parse_args(["app"]).command == "app"


def test_cli_supports_scenario_review_and_promote_flows(tmp_path, monkeypatch) -> None:
    prompt_root = tmp_path / "prompt_packs"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompt_packs(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(settings, "prompt_pack_dir", Path("prompt_packs"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "scenario_dir", Path("scenarios"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    assert main(["scenario", "list", "--prompt", "v1", "--json"]) == 0
    assert main(["tests", "list", "--prompt", "v1", "--json"]) == 0
    assert main(["scenario", "run", "--suite", "core", "--prompt", "v1", "--json"]) == 0
    assert main(["tests", "run", "--suite", "core", "--prompt", "v1", "--json"]) == 0
    assert main(["review", "--prompt", "v1", "--json"]) == 0
    assert main(["promote", "--prompt", "v1", "--summary", "Ship scenario candidate"]) == 0
    assert main(["ship", "--prompt", "v1", "--summary", "Ship scenario candidate"]) == 0
