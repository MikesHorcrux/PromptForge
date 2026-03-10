import asyncio
import json
from pathlib import Path

import yaml

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, ScoringConfig
from promptforge.forge.service import ForgeSession


class FakeForgeGateway:
    def __init__(self) -> None:
        self.generation_calls = 0
        self.coach_calls = 0

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
        if prompt_version == "forge-coach":
            self.coach_calls += 1
            return ModelExecutionResult(
                case_id=case_id,
                prompt_version=prompt_version,
                model=model,
                output_text="Tighten the system prompt and remove filler from the user template.",
            )

        self.generation_calls += 1
        output = _build_output(user_prompt=user_prompt, improved="improved" in system_prompt.lower())
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


def _build_output(*, user_prompt: str, improved: bool) -> str:
    lower = user_prompt.lower()
    if "tracking number" in lower:
        answer = "Tracking has stalled for 6 days, so support can open a carrier claim."
        next_steps = "Reply with the tracking number so we can verify and open the claim."
    elif "used vaporizer" in lower:
        answer = "Because the device is used and past 30 days, a refund is not available."
        next_steps = "Reply if you want troubleshooting support for the vaporizer."
    else:
        answer = "Refunds are available within 30 days for unused items with proof of purchase."
        next_steps = "Reply with the order number and proof of purchase so support can review it."
    summary = "Precise answer." if improved else "Baseline answer."
    if improved and "tracking number" in lower:
        answer += " As a premium customer, a replacement can be offered after verification."
    if improved and "used vaporizer" in lower:
        next_steps = "Reply if you want troubleshooting support or device care guidance."
    return (
        f"## Summary\n{summary}\n"
        f"## Answer\n{answer}\n"
        f"## Next Steps\n{next_steps}\n"
    )


def test_forge_session_tracks_revisions_and_disables_cache_for_repeats(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")
    monkeypatch.setattr(settings, "prompt_pack_dir", tmp_path / "exported_packs")

    gateway = FakeForgeGateway()
    session = asyncio.run(
        ForgeSession.create(
            prompt_ref="prompt_packs/v1",
            dataset_path="datasets/core.jsonl",
            bench_dataset_path=None,
            model="fake-model",
            agent_model="gpt-5-mini",
            provider="openai",
            judge_provider="openai",
            run_config=RunConfig(use_cache=True),
            scoring_config=ScoringConfig(judge_model="fake-judge"),
            bench_repeats=2,
            full_repeats=1,
            gateway=gateway,
        )
    )

    assert session.manifest.session_id.startswith("forge_")
    assert session.baseline_revision.revision_id == "r000"
    assert session.baseline_revision.benchmark is not None
    assert gateway.generation_calls == 6

    system_path, system_content = session.read_prompt_file("system")
    assert system_path.name == "system.md"

    revision = asyncio.run(
        session.edit_prompt_file(
            target="system",
            content=system_content + "\nAdd improved guidance.\n",
        )
    )

    assert revision.revision_id == "r001"
    assert revision.benchmark is not None
    assert revision.benchmark.mean_effective_score > session.baseline_revision.benchmark.mean_effective_score
    assert revision.benchmark_vs_baseline is not None
    assert revision.benchmark_vs_baseline.winner == "candidate"
    assert len(session.history.revisions) == 2
    assert gateway.generation_calls == 12
    assert session.latest_diff_rows(reference="baseline")
    case_rows = session.benchmark_case_rows(limit=3)
    assert len(case_rows) == 3
    assert all(row[4] for row in case_rows)
    assert session.benchmark_case_rows(limit=None, failures_only=True) == []

    coach_reply = asyncio.run(session.coach("Make it more concise."))
    assert "Tighten the system prompt" in coach_reply
    assert gateway.coach_calls == 1

    latest = asyncio.run(session.run_full_evaluation())
    assert latest.full_evaluation is not None

    export_path = session.export_prompt_pack("v-forge-export")
    exported_manifest = yaml.safe_load((export_path / "manifest.yaml").read_text(encoding="utf-8"))
    assert exported_manifest["version"] == "v-forge-export"

    reloaded = ForgeSession.load(session_id=session.manifest.session_id, gateway=gateway)
    assert reloaded.latest_revision is not None
    assert reloaded.latest_revision.revision_id == "r001"


def test_prepare_and_apply_agent_request_stages_then_creates_revision(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")
    monkeypatch.setattr(settings, "prompt_pack_dir", tmp_path / "exported_packs")

    gateway = FakeForgeGateway()
    session = asyncio.run(
        ForgeSession.create(
            prompt_ref="prompt_packs/v1",
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
            gateway=gateway,
        )
    )

    async def fake_agent_edit(self, request: str, *, workdir=None) -> str:
        system_path = (workdir or self.working_prompt_dir) / "system.md"
        current = system_path.read_text(encoding="utf-8")
        system_path.write_text(current + "\nAdd improved guidance.\n", encoding="utf-8")
        return f"Applied request: {request}"

    monkeypatch.setattr(ForgeSession, "_run_codex_edit_agent", fake_agent_edit)

    before = (session.working_prompt_dir / "system.md").read_text(encoding="utf-8")
    proposal = asyncio.run(session.prepare_agent_request("make the prompt more precise"))

    assert proposal.changed_files == ["system.md"]
    assert proposal.proposal_id == "p000"
    assert "Add improved guidance." not in (session.working_prompt_dir / "system.md").read_text(encoding="utf-8")
    assert "before/system.md" in proposal.diff_preview

    result = asyncio.run(session.apply_prepared_edit(proposal.proposal_id))

    assert result.changed_files == ["system.md"]
    assert result.revision is not None
    assert result.revision.source == "agent_edit"
    assert before != (session.working_prompt_dir / "system.md").read_text(encoding="utf-8")
    assert "Add improved guidance." in (session.working_prompt_dir / "system.md").read_text(encoding="utf-8")
    assert "before/system.md" in result.diff_preview
    assert result.revision.benchmark is not None
    assert session.benchmark_case_rows(limit=2)


def test_discard_prepared_edit_keeps_working_prompt_unchanged(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(settings, "var_dir", tmp_path / "var")
    monkeypatch.setattr(settings, "prompt_pack_dir", tmp_path / "exported_packs")

    gateway = FakeForgeGateway()
    session = asyncio.run(
        ForgeSession.create(
            prompt_ref="prompt_packs/v1",
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
            gateway=gateway,
        )
    )

    async def fake_agent_edit(self, request: str, *, workdir=None) -> str:
        system_path = (workdir or self.working_prompt_dir) / "system.md"
        current = system_path.read_text(encoding="utf-8")
        system_path.write_text(current + "\nAdd improved guidance.\n", encoding="utf-8")
        return f"Applied request: {request}"

    monkeypatch.setattr(ForgeSession, "_run_codex_edit_agent", fake_agent_edit)

    before = (session.working_prompt_dir / "system.md").read_text(encoding="utf-8")
    proposal = asyncio.run(session.prepare_agent_request("discard this change"))
    session.discard_prepared_edit(proposal.proposal_id)

    assert (session.working_prompt_dir / "system.md").read_text(encoding="utf-8") == before
    assert session.list_pending_edits() == []
