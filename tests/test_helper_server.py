import asyncio
import json
import os
import shutil
import subprocess
from pathlib import Path

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, RunConfig, ScoringConfig
from promptforge.helper.server import PromptForgeHelper
from promptforge.runtime.codex_cli import CodexDeviceAuthResult


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


def _seed_prompts(root: Path) -> None:
    shutil.copytree(Path("prompts") / "v1", root / "v1")


def test_helper_empty_project_status_settings_and_prompts_succeed(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        prompts = asyncio.run(helper.handle("prompts.list", {}))
        assert prompts["prompts"] == []

        status = asyncio.run(helper.handle("status.get", {}))
        assert status["active_prompt"] is None
        assert status["active_session"] is None

        settings_payload = asyncio.run(helper.handle("settings.get", {}))
        assert settings_payload["settings"]["name"] == tmp_path.name
        assert settings_payload["auth"]["connections"]["codex"]["detail"].startswith("Codex status not checked")
    finally:
        os.chdir(original_cwd)


def test_helper_exposes_project_prompt_and_benchmark_contract(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        prompts = asyncio.run(helper.handle("prompts.list", {}))
        assert prompts["prompts"][0]["version"] == "v1"

        prompt_payload = asyncio.run(helper.handle("prompt.get", {"prompt": "v1"}))
        assert "You are" in prompt_payload["prompt"]["system_prompt"]
        assert "purpose" in prompt_payload["prompt"]
        assert "prompt.json" in prompt_payload["prompt"]["files"]

        benchmark = asyncio.run(helper.handle("bench.run_quick", {"prompt": "v1"}))
        assert benchmark["revision"]["benchmark"] is not None

        status = asyncio.run(helper.handle("status.get", {}))
        assert status["project"]["metadata"]["name"] == tmp_path.name
        assert set(status["auth"]["connections"].keys()) == {"openai", "openrouter", "codex"}

        coach = asyncio.run(helper.handle("coach.reply", {"prompt": "v1", "request": "How should this prompt improve?"}))
        assert coach["reply"]

        agent_chat = asyncio.run(helper.handle("agent.chat", {"prompt": "v1", "request": "How should this prompt improve?"}))
        assert agent_chat["chat"]["kind"] == "reply"
        assert agent_chat["chat"]["message"]

        greeting = asyncio.run(helper.handle("agent.chat", {"prompt": "v1", "request": "hey"}))
        assert greeting["chat"]["kind"] == "reply"
        assert "help edit this prompt" in greeting["chat"]["message"].lower()

        agent_benchmark = asyncio.run(helper.handle("agent.chat", {"prompt": "v1", "request": "Please run a benchmark on this prompt"}))
        assert agent_benchmark["chat"]["kind"] == "benchmark"
        assert agent_benchmark["revision"]["benchmark"] is not None

        events = asyncio.run(helper.handle("events.subscribe", {"after": 0, "timeout_seconds": 0.01}))
        assert events["subscribed"] is True
        assert any(event["type"] == "request.started" and event["payload"]["method"] == "prompts.list" for event in events["events"])
        assert any(event["type"] == "request.completed" and event["payload"]["method"] == "bench.run_quick" for event in events["events"])
    finally:
        os.chdir(original_cwd)


def test_helper_event_subscription_long_polls_until_next_event(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    async def scenario() -> None:
        helper = PromptForgeHelper(project_root=tmp_path)

        async def emit_event() -> None:
            await asyncio.sleep(0.05)
            await helper.handle("status.get", {})

        emit_task = asyncio.create_task(emit_event())
        subscription = await helper.handle("events.subscribe", {"after": 0, "timeout_seconds": 0.5})
        await emit_task

        assert subscription["events"]
        assert subscription["events"][0]["payload"]["method"] == "status.get"

    try:
        asyncio.run(scenario())
    finally:
        os.chdir(original_cwd)


def test_helper_settings_can_be_read_and_updated(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        current = asyncio.run(helper.handle("settings.get", {}))
        assert current["settings"]["preferred_provider"] in {"openai", "openrouter", "codex"}

        updated = asyncio.run(
            helper.handle(
                "settings.update",
                {
                    "name": "Workbench",
                    "preferred_provider": "codex",
                    "preferred_judge_provider": "openai",
                    "preferred_generation_model": "gpt-5-mini",
                    "preferred_judge_model": "gpt-5-mini",
                    "quick_benchmark_dataset": "datasets/core.jsonl",
                    "full_evaluation_dataset": "datasets/core.jsonl",
                },
            )
        )

        assert updated["settings"]["name"] == "Workbench"
        assert updated["settings"]["preferred_provider"] == "codex"
        assert updated["settings"]["preferred_judge_provider"] == "openai"
        assert updated["project"]["metadata"]["name"] == "Workbench"
    finally:
        os.chdir(original_cwd)


def test_helper_prompt_views_do_not_force_session_creation(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        prompt_payload = asyncio.run(helper.handle("prompt.get", {"prompt": "v1"}))
        assert prompt_payload["prompt"]["version"] == "v1"

        insights = asyncio.run(helper.handle("insights.latest", {"prompt": "v1"}))
        assert insights["insights"]["session_id"] is None

    finally:
        os.chdir(original_cwd)


def test_helper_prompt_save_persists_prompt_workspace_fields(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        saved = asyncio.run(
            helper.handle(
                "prompt.save",
                    {
                        "prompt": "v1",
                        "system_prompt": "You are improved.\n",
                        "user_template": "Customer name: {{ customer_name }}\nIssue: {{ customer_issue }}\nGoal: {{ goal }}\nTone: {{ tone }}\nPolicy: {{ policy_snippet }}\n",
                        "purpose": "Support refund requests.",
                        "expected_behavior": "Answer in plain language with next steps.",
                        "success_criteria": "Includes policy answer and asks for proof of purchase.",
                        "prompt_blocks": [
                            {
                                "block_id": "refund-policy",
                                "title": "Refund Policy",
                                "body": "Mention the 30 day unopened-item refund policy.",
                                "target": "system",
                                "enabled": True,
                            }
                        ],
                    },
                )
        )

        assert saved["prompt"]["purpose"] == "Support refund requests."
        assert saved["prompt"]["expected_behavior"] == "Answer in plain language with next steps."
        assert saved["prompt"]["success_criteria"] == "Includes policy answer and asks for proof of purchase."
        assert (tmp_path / "var" / "forge").exists()

        prompt_payload = asyncio.run(helper.handle("prompt.get", {"prompt": "v1"}))
        assert prompt_payload["prompt"]["purpose"] == "Support refund requests."
        assert "improved" in prompt_payload["prompt"]["system_prompt"].lower()
        assert prompt_payload["prompt"]["prompt_blocks"][0]["block_id"] == "refund-policy"

        prompt_brief_path = Path(saved["prompt"]["root"]) / "prompt.json"
        assert prompt_brief_path.exists()
        prompt_brief = json.loads(prompt_brief_path.read_text(encoding="utf-8"))
        assert prompt_brief["success_criteria"] == "Includes policy answer and asks for proof of purchase."
        assert prompt_brief["prompt_blocks"][0]["title"] == "Refund Policy"
    finally:
        os.chdir(original_cwd)


def test_helper_status_degrades_when_codex_probe_fails(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)
    dataset_root = tmp_path / "datasets"
    dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())
    monkeypatch.setattr("shutil.which", lambda value: "/opt/homebrew/bin/codex" if value == settings.codex_bin else None)

    def fail_codex(*args, **kwargs):
        raise subprocess.SubprocessError("xcrun: error: cannot be used within an App Sandbox.")

    monkeypatch.setattr("promptforge.runtime.codex_cli.subprocess.run", fail_codex)

    try:
        helper = PromptForgeHelper(project_root=tmp_path)
        status = asyncio.run(helper.handle("status.get", {}))
        assert status["auth"]["connections"]["codex"]["detail"].startswith("Codex status not checked")

        refreshed = asyncio.run(helper.handle("connections.refresh", {}))
        codex = refreshed["auth"]["connections"]["codex"]
        assert codex["ready"] is False
        assert "Codex status unavailable" in codex["detail"]
    finally:
        os.chdir(original_cwd)


def test_helper_exposes_structured_codex_auth_actions(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr(settings, "codex_bin", "/tmp/bundled-codex")
    monkeypatch.setattr("promptforge.helper.server.codex_login_status", lambda _: (True, "Logged in using ChatGPT"))
    monkeypatch.setattr(
        "promptforge.helper.server.codex_begin_device_auth",
        lambda _: CodexDeviceAuthResult(
            verification_uri="https://auth.openai.com/codex/device",
            user_code="ABCD-EFGH",
            instructions="Open https://auth.openai.com/codex/device and enter code ABCD-EFGH.",
        ),
    )
    monkeypatch.setattr("promptforge.helper.server.codex_login_with_api_key", lambda _, api_key: (True, f"Logged in with {api_key}"))

    try:
        helper = PromptForgeHelper(project_root=tmp_path)

        device_auth = asyncio.run(helper.handle("connections.codex.device_auth", {}))
        assert device_auth["verification_uri"] == "https://auth.openai.com/codex/device"
        assert device_auth["user_code"] == "ABCD-EFGH"
        assert device_auth["auth"]["connections"]["codex"]["ready"] is True
        assert device_auth["auth"]["connections"]["codex"]["source"] == "/tmp/bundled-codex"

        api_key_login = asyncio.run(helper.handle("connections.codex.login_api_key", {"api_key": "sk-test-openai"}))
        assert api_key_login["success"] is True
        assert api_key_login["detail"] == "Logged in with sk-test-openai"
        assert api_key_login["auth"]["connections"]["codex"]["ready"] is True
    finally:
        os.chdir(original_cwd)


def test_helper_uses_engine_root_datasets_for_external_projects(tmp_path, monkeypatch) -> None:
    original_cwd = Path.cwd()
    prompt_root = tmp_path / "prompts"
    prompt_root.mkdir(parents=True, exist_ok=True)
    _seed_prompts(prompt_root)

    engine_root = tmp_path / "engine"
    engine_dataset_root = engine_root / "datasets"
    engine_dataset_root.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path("datasets") / "core.jsonl", engine_dataset_root / "core.jsonl")

    monkeypatch.setattr(settings, "prompt_dir", Path("prompts"))
    monkeypatch.setattr(settings, "dataset_dir", Path("datasets"))
    monkeypatch.setattr(settings, "engine_root", engine_root)
    monkeypatch.setattr(settings, "var_dir", Path("var"))
    monkeypatch.setattr("promptforge.forge.workspace.build_gateway", lambda **_: FakeForgeGateway())

    try:
        helper = PromptForgeHelper(project_root=tmp_path)
        benchmark = asyncio.run(helper.handle("bench.run_quick", {"prompt": "v1"}))
        assert benchmark["revision"]["benchmark"] is not None
    finally:
        os.chdir(original_cwd)
