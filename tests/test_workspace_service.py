import asyncio
import json
import shutil
from pathlib import Path

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, ScoringConfig
from promptforge.forge.workspace import ForgeWorkspaceService


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


def test_workspace_service_lists_creates_and_tracks_sessions(tmp_path, monkeypatch) -> None:
    prompt_root = tmp_path / "prompt_packs"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompt_packs(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(settings, "prompt_pack_dir", prompt_root)
    monkeypatch.setattr(settings, "dataset_dir", dataset_root)
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")

    gateway = FakeForgeGateway()
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: gateway)

    workspace = ForgeWorkspaceService(
        dataset_path="datasets/core.jsonl",
        bench_dataset_path=None,
        model="fake-model",
        agent_model="gpt-5-mini",
        provider="openai",
        judge_provider="openai",
        run_config=RunConfig(use_cache=True),
        scoring_config=ScoringConfig(judge_model="fake-judge"),
        bench_repeats=1,
        full_repeats=1,
    )

    prompts = workspace.list_prompts()
    assert [prompt.version for prompt in prompts] == ["v1"]
    assert (tmp_path / ".promptforge" / "project.json").exists()

    created = workspace.create_prompt("draft-support")
    assert created.exists()
    cloned = workspace.create_prompt("draft-copy", from_prompt="v1")
    assert cloned.exists()

    prompt_summaries = workspace.list_prompts()
    prompt_versions = [prompt.version for prompt in prompt_summaries]
    assert prompt_versions == ["draft-copy", "draft-support", "v1"]
    prompt_names = {prompt.version: prompt.name for prompt in prompt_summaries}
    assert prompt_names["draft-support"] == "Draft Support"
    assert prompt_names["draft-copy"] == "Draft Copy"

    visible = workspace.load_visible_prompt("v1")
    assert "You are" in visible.system_prompt
    assert visible.prompt_blocks == []

    session = asyncio.run(workspace.ensure_session("v1"))
    assert session.manifest.session_id.startswith("forge_")
    assert workspace.current_session("v1") is not None
    assert settings.workspace_state_path.exists()

    revision = asyncio.run(
        workspace.save_prompt_text(
            "v1",
            system_prompt=visible.system_prompt + "\nAdd improved guidance.\n",
            user_template=visible.user_template,
        )
    )
    assert revision.revision_id == "r001"
    assert revision.benchmark is None

    checked = asyncio.run(workspace.run_benchmark("v1"))
    assert checked.benchmark is not None

    exported = asyncio.run(workspace.export_prompt("v1", "v1-exported"))
    assert exported.exists()

    reloaded = ForgeWorkspaceService(
        dataset_path="datasets/core.jsonl",
        bench_dataset_path=None,
        model="fake-model",
        agent_model="gpt-5-mini",
        provider="openai",
        judge_provider="openai",
        run_config=RunConfig(use_cache=True),
        scoring_config=ScoringConfig(judge_model="fake-judge"),
        bench_repeats=1,
        full_repeats=1,
    )
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: gateway)
    assert reloaded.load_visible_prompt("v1").session_id == session.manifest.session_id
    assert reloaded.project.metadata.last_opened_prompt == "v1"


def test_workspace_service_stages_agent_edits_before_apply(tmp_path, monkeypatch) -> None:
    prompt_root = tmp_path / "prompt_packs"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompt_packs(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(settings, "prompt_pack_dir", prompt_root)
    monkeypatch.setattr(settings, "dataset_dir", dataset_root)
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")

    gateway = FakeForgeGateway()
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: gateway)

    workspace = ForgeWorkspaceService(
        dataset_path="datasets/core.jsonl",
        bench_dataset_path=None,
        model="fake-model",
        agent_model="gpt-5-mini",
        provider="openai",
        judge_provider="openai",
        run_config=RunConfig(use_cache=True),
        scoring_config=ScoringConfig(judge_model="fake-judge"),
        bench_repeats=1,
        full_repeats=1,
    )

    session = asyncio.run(workspace.ensure_session("v1"))

    async def fake_agent_edit(self, request: str, *, workdir=None) -> str:
        system_path = (workdir or self.working_prompt_dir) / "system.md"
        current = system_path.read_text(encoding="utf-8")
        system_path.write_text(current + "\nAdd improved guidance.\n", encoding="utf-8")
        return "Prepared agent change."

    monkeypatch.setattr(session.__class__, "_run_codex_edit_agent", fake_agent_edit)

    before = session.read_prompt_file("system")[1]
    proposal = asyncio.run(workspace.prepare_agent_request("v1", "make it stronger"))
    assert proposal.changed_files == ["system.md"]
    assert session.read_prompt_file("system")[1] == before

    result = asyncio.run(workspace.apply_prepared_edit("v1", proposal.proposal_id))
    assert result.revision is not None
    assert "Add improved guidance." in session.read_prompt_file("system")[1]


def test_workspace_supports_scenarios_playground_and_review_decisions(tmp_path, monkeypatch) -> None:
    prompt_root = tmp_path / "prompt_packs"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompt_packs(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(settings, "prompt_pack_dir", prompt_root)
    monkeypatch.setattr(settings, "dataset_dir", dataset_root)
    monkeypatch.setattr(settings, "scenario_dir", Path("scenarios"))
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")

    gateway = FakeForgeGateway()
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: gateway)

    workspace = ForgeWorkspaceService(
        dataset_path="datasets/core.jsonl",
        bench_dataset_path=None,
        model="fake-model",
        agent_model="gpt-5-mini",
        provider="openai",
        judge_provider="openai",
        run_config=RunConfig(use_cache=True),
        scoring_config=ScoringConfig(judge_model="fake-judge"),
        bench_repeats=1,
        full_repeats=1,
    )

    suites = workspace.list_scenarios(prompt_ref="v1")
    assert suites
    suite = suites[0]
    assert suite.cases

    playground = asyncio.run(
        workspace.run_playground(
            "v1",
            input_payload=suite.cases[0].input,
            context=suite.cases[0].context,
            samples=2,
        )
    )
    assert len(playground.candidate_samples) == 2
    assert len(playground.baseline_samples) == 2

    review = asyncio.run(workspace.run_scenario_suite("v1", suite.suite_id))
    assert review.cases

    decision = asyncio.run(
        workspace.record_review_decision(
            "v1",
            status="iterate",
            summary="Keep iterating after review.",
            review_id=review.review_id,
            suite_id=suite.suite_id,
        )
    )
    assert decision.status == "iterate"

    actions = asyncio.run(workspace.list_builder_actions("v1"))
    assert actions
    assert actions[-1].kind == "decision"
    assert actions[-1].permission_mode == "proposal_only"
    assert "playground" in {tool for action in actions for tool in action.tools}
