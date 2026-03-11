from __future__ import annotations

import asyncio
import difflib
import json
import os
import shutil
import tempfile
from pathlib import Path
from statistics import fmean, pstdev
from typing import Any

import yaml

from promptforge.core.config import settings
from promptforge.core.logging import configure_logging, log_event
from promptforge.core.models import (
    DatasetCase,
    ModelExecutionResult,
    RunConfig,
    RunRequest,
    ScoresArtifact,
    TraitName,
    utc_now_iso,
)
from promptforge.datasets.loader import load_dataset
from promptforge.forge.models import (
    AgentEditResult,
    AgentChatResult,
    AssertionResult,
    BenchmarkCaseSummary,
    BenchmarkDiff,
    BenchmarkSnapshot,
    BuilderAction,
    ChatHistory,
    ChatTurn,
    DecisionRecord,
    ForgeHistory,
    PendingEdits,
    PlaygroundRun,
    PlaygroundSample,
    PreparedAgentEdit,
    ReviewCase,
    ReviewSummary,
    ForgeRevision,
    ForgeSessionManifest,
    RevisionSource,
)
from promptforge.prompts.brief import ensure_prompt_brief
from promptforge.prompts.loader import load_prompt_pack, render_user_prompt
from promptforge.runtime.artifacts import ArtifactStore
from promptforge.runtime.gateway import ModelGateway
from promptforge.runtime.run_service import EvaluationService, generate_run_id
from promptforge.scenarios.models import ScenarioAssertion, ScenarioCase, ScenarioSuite


EDITABLE_PROMPT_FILES = (
    "prompt.json",
    "system.md",
    "user_template.md",
    "manifest.yaml",
    "variables.schema.json",
)

AGENT_EDIT_PROMPT_TEMPLATE = """You are PromptForge's editing agent in a prompt-pack workspace.

You may inspect files, edit prompt-pack files, and run shell commands in the current working directory if that helps you make a better prompt change.

Hard boundaries:
- Only modify these files unless the user explicitly asks otherwise:
  - prompt.json
  - system.md
  - user_template.md
  - manifest.yaml
  - variables.schema.json
- Do not touch files outside the current prompt pack workspace.
- Keep prompt edits concise and purposeful.
- Preserve valid YAML and JSON when editing manifest.yaml or variables.schema.json.
- Use the benchmark evidence below to guide the change.
- After editing, respond with a short summary of what changed and why.

Current benchmark state:
{benchmark_summary}

Most important problem cases:
{problem_cases}

Current delta vs baseline:
{baseline_diff}

User request:
{request}
"""


COACH_SYSTEM_PROMPT = """You are PromptForge, a terminal prompt engineering coach.

Your job is to help a user improve a prompt pack based on benchmark evidence.

Rules:
- Recommend concrete edits to the system prompt and user template.
- Be specific about why the benchmark signals imply the change.
- Keep the answer practical and short.
- Do not invent benchmark outcomes not present in the input.
- Do not rewrite the full prompt unless the user explicitly asks for a rewrite.
"""

AGENT_CHAT_SYSTEM_PROMPT = """You are PromptForge, an interactive prompt engineering agent inside a local workspace.

You are collaborating with the user on one prompt pack.

Rules:
- Converse naturally and build on prior turns.
- Use the prompt brief, current prompt files, and benchmark evidence only when relevant to the user's request.
- Answer direct questions directly.
- When recommending changes, be concrete about what to adjust and why.
- If the user is greeting you, greet them back and ask what they want to do.
- If the user is making small talk or asking a meta question, respond naturally instead of forcing prompt advice.
- Do not invent benchmark outcomes or prompt contents.
- Keep answers concise and practical.
- Only mention slash commands when the user is explicitly asking how to trigger a specific action.
"""

CHAT_HISTORY_LIMIT = 24
SIMPLE_GREETINGS = {
    "hey",
    "hey there",
    "hi",
    "hello",
    "yo",
    "sup",
    "good morning",
    "good afternoon",
    "good evening",
}


class ForgeSession:
    def __init__(
        self,
        *,
        manifest: ForgeSessionManifest,
        history: ForgeHistory,
        gateway: ModelGateway,
    ) -> None:
        self.manifest = manifest
        self.history = history
        self.gateway = gateway
        self.logger = configure_logging()
        self.artifacts = ArtifactStore()
        self.evaluation_service = EvaluationService(gateway)
        self.session_dir = settings.forge_dir / manifest.session_id
        self.revisions_dir = self.session_dir / "revisions"
        self.proposals_dir = self.session_dir / "proposals"
        self.manifest_path = self.session_dir / "session.json"
        self.history_path = self.session_dir / "history.json"
        self.pending_edits_path = self.session_dir / "pending_edits.json"
        self.chat_history_path = self.session_dir / "chat_history.json"
        self.pending_edits = self._load_pending_edits()
        self.chat_history = self._load_chat_history()

    @classmethod
    def load_manifest(cls, session_id: str) -> ForgeSessionManifest:
        session_dir = settings.forge_dir / session_id
        manifest_path = session_dir / "session.json"
        if not manifest_path.exists():
            raise FileNotFoundError(f"Forge session not found: {session_id}")
        return ForgeSessionManifest.model_validate(json.loads(manifest_path.read_text(encoding="utf-8")))

    @classmethod
    def load(cls, *, session_id: str, gateway: ModelGateway) -> "ForgeSession":
        session_dir = settings.forge_dir / session_id
        manifest = cls.load_manifest(session_id)
        history_path = session_dir / "history.json"
        if history_path.exists():
            history = ForgeHistory.model_validate(json.loads(history_path.read_text(encoding="utf-8")))
        else:
            history = ForgeHistory()
        return cls(manifest=manifest, history=history, gateway=gateway)

    @classmethod
    async def create(
        cls,
        *,
        prompt_ref: str,
        dataset_path: str,
        bench_dataset_path: str | None,
        model: str,
        agent_model: str,
        provider: str,
        judge_provider: str,
        run_config: RunConfig,
        scoring_config,
        bench_repeats: int,
        full_repeats: int,
        gateway: ModelGateway,
    ) -> "ForgeSession":
        prompt_pack = load_prompt_pack(prompt_ref)
        benchmark_dataset = load_dataset(bench_dataset_path or dataset_path)
        full_dataset = load_dataset(dataset_path)

        settings.forge_dir.mkdir(parents=True, exist_ok=True)
        session_id = generate_run_id("forge")
        session_dir = settings.forge_dir / session_id
        baseline_dir = session_dir / "baseline"
        working_dir = session_dir / "working"
        revisions_dir = session_dir / "revisions"
        revisions_dir.mkdir(parents=True, exist_ok=True)

        shutil.copytree(prompt_pack.root, baseline_dir)
        shutil.copytree(prompt_pack.root, working_dir)

        manifest = ForgeSessionManifest(
            session_id=session_id,
            created_at=utc_now_iso(),
            baseline_prompt_ref=prompt_ref,
            baseline_prompt_dir=str(baseline_dir),
            working_prompt_dir=str(working_dir),
            benchmark_dataset_path=str(benchmark_dataset.path),
            full_dataset_path=str(full_dataset.path),
            model=model,
            agent_model=agent_model,
            provider=provider,
            judge_provider=judge_provider,
            run_config=run_config,
            scoring_config=scoring_config,
            bench_repeats=bench_repeats,
            full_repeats=full_repeats,
        )
        session = cls(manifest=manifest, history=ForgeHistory(), gateway=gateway)
        session._persist()

        baseline_revision = await session._create_revision_from_prompt_dir(
            prompt_dir=baseline_dir,
            source="baseline",
            note=f"Imported baseline prompt `{prompt_pack.manifest.version}`.",
            changed_files=[],
            run_benchmark=False,
        )
        session.manifest.baseline_revision_id = baseline_revision.revision_id
        session.manifest.latest_revision_id = baseline_revision.revision_id
        session._persist()
        log_event(
            session.logger,
            "forge_session_started",
            session_id=session.manifest.session_id,
            prompt_ref=prompt_ref,
            benchmark_dataset=str(benchmark_dataset.path),
            full_dataset=str(full_dataset.path),
            model=model,
            provider=provider,
            judge_provider=judge_provider,
        )
        return session

    @property
    def baseline_revision(self) -> ForgeRevision:
        if not self.manifest.baseline_revision_id:
            raise RuntimeError("Baseline revision is not initialized.")
        return self.get_revision(self.manifest.baseline_revision_id)

    @property
    def latest_revision(self) -> ForgeRevision | None:
        if not self.manifest.latest_revision_id:
            return None
        return self.get_revision(self.manifest.latest_revision_id)

    @property
    def latest_review(self) -> ReviewSummary | None:
        if not self.history.reviews:
            return None
        return self.history.reviews[-1]

    @property
    def working_prompt_dir(self) -> Path:
        return Path(self.manifest.working_prompt_dir)

    def get_revision(self, revision_id: str) -> ForgeRevision:
        for revision in self.history.revisions:
            if revision.revision_id == revision_id:
                return revision
        raise KeyError(f"Revision not found: {revision_id}")

    def read_prompt_file(self, target: str) -> tuple[Path, str]:
        file_map = {
            "brief": self.working_prompt_dir / "prompt.json",
            "system": self.working_prompt_dir / "system.md",
            "user": self.working_prompt_dir / "user_template.md",
            "manifest": self.working_prompt_dir / "manifest.yaml",
            "schema": self.working_prompt_dir / "variables.schema.json",
        }
        if target not in file_map:
            raise ValueError(f"Unsupported prompt target: {target}")
        path = file_map[target]
        if target == "brief" and not path.exists():
            ensure_prompt_brief(self.working_prompt_dir)
        return path, path.read_text(encoding="utf-8")

    def list_builder_actions(self, *, limit: int | None = 40) -> list[BuilderAction]:
        actions = list(self.history.builder_actions)
        if limit is not None:
            actions = actions[-limit:]
        return actions

    def list_pending_edits(self) -> list[PreparedAgentEdit]:
        return list(self.pending_edits.edits)

    def latest_pending_edit(self) -> PreparedAgentEdit | None:
        if not self.pending_edits.edits:
            return None
        return self.pending_edits.edits[-1]

    def get_pending_edit(self, proposal_id: str) -> PreparedAgentEdit:
        for edit in self.pending_edits.edits:
            if edit.proposal_id == proposal_id:
                return edit
        raise KeyError(f"Prepared edit not found: {proposal_id}")

    async def prepare_agent_request(self, request: str) -> PreparedAgentEdit:
        before = self._read_prompt_file_map(self.working_prompt_dir)
        proposal_id = self._next_proposal_id()
        proposal_dir = self.proposals_dir / proposal_id / "prompt_pack"
        proposal_dir.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.working_prompt_dir, proposal_dir)

        summary = await self._run_codex_edit_agent(request, workdir=proposal_dir)
        after = self._read_prompt_file_map(proposal_dir)
        changed_files = [name for name in EDITABLE_PROMPT_FILES if before.get(name) != after.get(name)]
        diff_preview = self._build_diff_preview(before, after, changed_files)

        proposal = PreparedAgentEdit(
            proposal_id=proposal_id,
            created_at=utc_now_iso(),
            request=request,
            summary=summary or request,
            changed_files=changed_files,
            diff_preview=diff_preview,
            staged_prompt_dir=str(proposal_dir),
        )
        self.pending_edits.edits = [
            edit for edit in self.pending_edits.edits if edit.proposal_id != proposal_id
        ]
        self.pending_edits.edits.append(proposal)
        self._persist()
        log_event(
            self.logger,
            "forge_agent_edit_prepared",
            session_id=self.manifest.session_id,
            proposal_id=proposal_id,
            changed_files=changed_files,
        )
        self._record_builder_action(
            kind="proposal",
            title="Prepared agent proposal",
            details=proposal.summary,
            files=changed_files,
            tools=["prompt_files", "diff"],
        )
        return proposal

    async def apply_prepared_edit(self, proposal_id: str) -> AgentEditResult:
        proposal = self.get_pending_edit(proposal_id)
        staged_dir = Path(proposal.staged_prompt_dir)
        if not staged_dir.exists():
            self._drop_pending_edit(proposal_id)
            raise FileNotFoundError(f"Prepared edit staging dir is missing: {staged_dir}")

        self._replace_working_prompt_dir_from(staged_dir)
        revision: ForgeRevision | None = None
        if proposal.changed_files:
            revision = await self._create_revision_from_prompt_dir(
                prompt_dir=self.working_prompt_dir,
                source="agent_edit",
                note=proposal.summary or proposal.request,
                changed_files=proposal.changed_files,
                run_benchmark=False,
            )
        self._drop_pending_edit(proposal_id)
        log_event(
            self.logger,
            "forge_agent_edit_applied",
            session_id=self.manifest.session_id,
            proposal_id=proposal_id,
            revision_id=revision.revision_id if revision else None,
        )
        self._record_builder_action(
            kind="apply",
            title="Applied staged proposal",
            details=proposal.summary,
            files=proposal.changed_files,
            tools=["prompt_files", "diff"],
        )
        return AgentEditResult(
            summary=proposal.summary,
            changed_files=proposal.changed_files,
            diff_preview=proposal.diff_preview,
            revision=revision,
        )

    def discard_prepared_edit(self, proposal_id: str) -> None:
        self.get_pending_edit(proposal_id)
        self._drop_pending_edit(proposal_id)
        self._record_builder_action(
            kind="proposal",
            title="Discarded staged proposal",
            details=f"Discarded {proposal_id}.",
            tools=["diff"],
        )
        log_event(
            self.logger,
            "forge_agent_edit_discarded",
            session_id=self.manifest.session_id,
            proposal_id=proposal_id,
        )

    async def apply_agent_request(self, request: str) -> AgentEditResult:
        proposal = await self.prepare_agent_request(request)
        if not proposal.changed_files:
            self.discard_prepared_edit(proposal.proposal_id)
            log_event(
                self.logger,
                "forge_agent_request_noop",
                session_id=self.manifest.session_id,
                request=request,
            )
            return AgentEditResult(
                summary=proposal.summary,
                changed_files=[],
                diff_preview=proposal.diff_preview,
            )
        return await self.apply_prepared_edit(proposal.proposal_id)

    async def edit_prompt_file(self, *, target: str, content: str, note: str | None = None) -> ForgeRevision:
        path, _ = self.read_prompt_file(target)
        path.write_text(content.rstrip() + "\n", encoding="utf-8")
        revision = await self._create_revision_from_prompt_dir(
            prompt_dir=self.working_prompt_dir,
            source="manual_edit",
            note=note or f"Edited {path.name}.",
            changed_files=[path.name],
            run_benchmark=False,
        )
        self._record_builder_action(
            kind="apply",
            title="Edited prompt file",
            details=revision.note,
            files=[path.name],
            tools=["prompt_files"],
        )
        return revision

    async def edit_prompt_files(
        self,
        *,
        updates: dict[str, str],
        note: str | None = None,
    ) -> ForgeRevision:
        changed_files: list[str] = []
        target_map = {
            "brief": "prompt.json",
            "system": "system.md",
            "user": "user_template.md",
            "manifest": "manifest.yaml",
            "schema": "variables.schema.json",
        }
        for target, content in updates.items():
            if target not in target_map:
                raise ValueError(f"Unsupported prompt target: {target}")
            path = self.working_prompt_dir / target_map[target]
            normalized = content.rstrip() + "\n"
            existing = path.read_text(encoding="utf-8") if path.exists() else ""
            if existing != normalized:
                path.write_text(normalized, encoding="utf-8")
                changed_files.append(path.name)
        if not changed_files:
            raise ValueError("No prompt changes were detected.")
        revision = await self._create_revision_from_prompt_dir(
            prompt_dir=self.working_prompt_dir,
            source="manual_edit",
            note=note or "Edited prompt files from the forge workspace.",
            changed_files=changed_files,
            run_benchmark=False,
        )
        self._record_builder_action(
            kind="apply",
            title="Saved prompt workspace",
            details=revision.note,
            files=changed_files,
            tools=["prompt_files", "prompt_metadata"],
        )
        return revision

    async def run_manual_benchmark(self, *, note: str | None = None) -> ForgeRevision:
        revision = await self._create_revision_from_prompt_dir(
            prompt_dir=self.working_prompt_dir,
            source="manual_benchmark",
            note=note or "Manual benchmark run.",
            changed_files=[],
        )
        self._record_builder_action(
            kind="benchmark",
            title="Ran quick check",
            details=revision.note,
            tools=["benchmark"],
        )
        return revision

    async def reset_to_baseline(self, *, note: str | None = None) -> ForgeRevision:
        baseline_dir = Path(self.manifest.baseline_prompt_dir)
        self._replace_working_prompt_dir_from(baseline_dir)
        revision = await self._create_revision_from_prompt_dir(
            prompt_dir=self.working_prompt_dir,
            source="reset",
            note=note or "Reset working prompt to the baseline snapshot.",
            changed_files=["prompt.json", "system.md", "user_template.md", "manifest.yaml", "variables.schema.json"],
            run_benchmark=False,
        )
        self._record_builder_action(
            kind="restore",
            title="Reset to baseline",
            details=revision.note,
            files=revision.changed_files,
            tools=["baseline_restore"],
        )
        return revision

    async def restore_revision(self, revision_id: str, *, note: str | None = None) -> ForgeRevision:
        revision = self.get_revision(revision_id)
        self._replace_working_prompt_dir_from(Path(revision.prompt_snapshot_dir))
        restored = await self._create_revision_from_prompt_dir(
            prompt_dir=self.working_prompt_dir,
            source="restore",
            note=note or f"Restored working prompt to {revision_id}.",
            changed_files=["prompt.json", "system.md", "user_template.md", "manifest.yaml", "variables.schema.json"],
            run_benchmark=False,
        )
        self._record_builder_action(
            kind="restore",
            title="Restored revision",
            details=restored.note,
            files=restored.changed_files,
            tools=["revision_restore"],
        )
        return restored

    async def run_full_evaluation(self, *, note: str | None = None) -> ForgeRevision:
        latest = self.latest_revision
        current_hash = load_prompt_pack(self.working_prompt_dir).content_hash
        if latest is None or latest.prompt_pack_hash != current_hash:
            latest = await self.run_manual_benchmark(
                note=note or "Auto-benchmarked current prompt before the full evaluation."
            )

        snapshot = await self._run_snapshot(
            prompt_dir=Path(latest.prompt_snapshot_dir),
            dataset_path=self.manifest.full_dataset_path,
            repeats=self.manifest.full_repeats,
            label="full_evaluation",
        )
        latest.full_evaluation = snapshot
        self._persist()
        log_event(
            self.logger,
            "forge_full_evaluation_completed",
            session_id=self.manifest.session_id,
            revision_id=latest.revision_id,
            run_ids=snapshot.run_ids,
            mean_effective_score=snapshot.mean_effective_score,
            dataset_path=self.manifest.full_dataset_path,
        )
        self._record_builder_action(
            kind="full_evaluation",
            title="Ran full suite",
            details=note or "Full evaluation completed.",
            tools=["full_evaluation"],
        )
        return latest

    async def run_playground(
        self,
        *,
        input_payload: dict[str, Any],
        context: str | dict[str, Any] | list[Any] | None = None,
        samples: int = 1,
        compare_baseline: bool = True,
    ) -> PlaygroundRun:
        samples = max(1, samples)
        case = DatasetCase(
            id="playground",
            input=input_payload,
            context=context,
        )
        candidate_samples = await self._generate_playground_samples(
            prompt_dir=self.working_prompt_dir,
            case=case,
            samples=samples,
            prefix="candidate",
        )
        baseline_samples: list[PlaygroundSample] = []
        if compare_baseline:
            baseline_samples = await self._generate_playground_samples(
                prompt_dir=Path(self.manifest.baseline_prompt_dir),
                case=case,
                samples=samples,
                prefix="baseline",
            )
        run = PlaygroundRun(
            run_id=generate_run_id("play"),
            prompt_ref=self.manifest.baseline_prompt_ref,
            input_payload=input_payload,
            context=context,
            candidate_samples=candidate_samples,
            baseline_samples=baseline_samples,
        )
        self.history.playground_runs.append(run)
        self._persist()
        self._record_builder_action(
            kind="playground",
            title="Ran playground trial",
            details=f"{samples} sample(s) on current prompt.",
            tools=["playground"],
        )
        return run

    async def run_scenario_suite(self, suite: ScenarioSuite, *, repeats: int | None = None) -> ReviewSummary:
        candidate_repeats = max(1, repeats or self.manifest.bench_repeats)
        if not suite.cases:
            raise ValueError(f"Scenario suite `{suite.name}` has no cases.")
        with tempfile.TemporaryDirectory(prefix="promptforge-suite-") as temp_dir:
            dataset_path = Path(temp_dir) / f"{suite.suite_id}.jsonl"
            dataset_rows = [
                case.to_dataset_case().model_dump(mode="json")
                for case in suite.cases
            ]
            dataset_path.write_text(
                "\n".join(json.dumps(row, sort_keys=True) for row in dataset_rows) + "\n",
                encoding="utf-8",
            )
            candidate = await self._run_snapshot(
                prompt_dir=self.working_prompt_dir,
                dataset_path=str(dataset_path),
                repeats=candidate_repeats,
                label="benchmark",
            )
            baseline = await self._run_snapshot(
                prompt_dir=Path(self.manifest.baseline_prompt_dir),
                dataset_path=str(dataset_path),
                repeats=candidate_repeats,
                label="benchmark",
            )
            diff = self._compare_snapshots(
                candidate=candidate,
                reference=baseline,
                reference_label="baseline",
            )
            review = self._build_review_summary(
                suite=suite,
                candidate=candidate,
                baseline=baseline,
                diff=diff,
            )
        self.history.reviews.append(review)
        self._persist()
        self._record_builder_action(
            kind="scenario_run",
            title="Ran scenario suite",
            details=f"{suite.name} with {len(suite.cases)} case(s).",
            tools=["scenario_suite", "benchmark"],
        )
        return review

    def record_decision(
        self,
        *,
        status: str,
        summary: str,
        rationale: str = "",
        review_id: str | None = None,
        suite_id: str | None = None,
    ) -> DecisionRecord:
        if status not in {"iterate", "accept_with_regressions", "promote", "reject"}:
            raise ValueError(f"Unsupported decision status: {status}")
        revision_id = self.latest_revision.revision_id if self.latest_revision else None
        decision = DecisionRecord(
            decision_id=self._next_decision_id(),
            status=status,
            summary=summary,
            rationale=rationale,
            review_id=review_id,
            suite_id=suite_id,
            revision_id=revision_id,
        )
        self.history.decisions.append(decision)
        self._persist()
        self._record_builder_action(
            kind="decision",
            title="Recorded review decision",
            details=summary,
            tools=["review"],
        )
        return decision

    async def promote_current_to_baseline(
        self,
        *,
        summary: str,
        rationale: str = "",
        review_id: str | None = None,
        suite_id: str | None = None,
    ) -> DecisionRecord:
        source_dir = self.working_prompt_dir
        baseline_dir = Path(self.manifest.baseline_prompt_dir)
        if baseline_dir.exists():
            shutil.rmtree(baseline_dir)
        shutil.copytree(source_dir, baseline_dir)
        baseline_revision = await self._create_revision_from_prompt_dir(
            prompt_dir=baseline_dir,
            source="baseline",
            note="Promoted current candidate to baseline.",
            changed_files=list(EDITABLE_PROMPT_FILES),
            run_benchmark=False,
        )
        self.manifest.baseline_revision_id = baseline_revision.revision_id
        self._persist()
        return self.record_decision(
            status="promote",
            summary=summary,
            rationale=rationale,
            review_id=review_id,
            suite_id=suite_id,
        )

    async def coach(self, request: str) -> str:
        return await self._generate_chat_reply(
            request,
            include_history=False,
            system_instructions=COACH_SYSTEM_PROMPT,
            prompt_version="forge-coach",
            response_instructions=(
                "Focus on prompt-improvement guidance. Explain what to change, why it matters, and include a revised snippet when useful."
            ),
        )

    async def agent_chat(self, request: str) -> AgentChatResult:
        normalized = request.strip()
        if not normalized:
            return AgentChatResult(kind="reply", message="Ask about the prompt, request changes, or tell me to run an evaluation.")

        self._record_chat_turn("user", normalized)
        self._record_builder_action(
            kind="chat",
            title="Builder chat",
            details=normalized,
            tools=["chat"],
        )

        if self._is_simple_greeting(normalized):
            message = "Hey. I can help edit this prompt, explain its behavior, inspect failures, or run evaluations. What do you want to do?"
            self._record_chat_turn("assistant", message)
            return AgentChatResult(kind="reply", message=message)

        if self._is_capabilities_question(normalized):
            message = (
                "I can chat through the prompt, suggest or stage prompt changes, run a quick benchmark, run a full evaluation, "
                "and help interpret failures or weak cases."
            )
            self._record_chat_turn("assistant", message)
            return AgentChatResult(kind="reply", message=message)

        if self._should_run_full_evaluation(normalized):
            revision = await self.run_full_evaluation(
                note=f"Agent-triggered full evaluation from chat: {normalized}"
            )
            score = revision.full_evaluation.mean_effective_score if revision.full_evaluation else None
            message = "Ran the full evaluation."
            if score is not None:
                message += f" Latest full-eval score: {score:.2f}/5."
            self._record_chat_turn("assistant", message)
            return AgentChatResult(kind="full_evaluation", message=message, revision=revision)

        if self._should_run_benchmark(normalized):
            revision = await self.run_manual_benchmark(
                note=f"Agent-triggered benchmark from chat: {normalized}"
            )
            score = revision.benchmark.mean_effective_score if revision.benchmark else None
            message = "Ran a quick benchmark."
            if score is not None:
                message += f" Latest benchmark score: {score:.2f}/5."
            self._record_chat_turn("assistant", message)
            return AgentChatResult(kind="benchmark", message=message, revision=revision)

        if self._should_prepare_edit(normalized):
            proposal = await self.prepare_agent_request(normalized)
            changed_files = ", ".join(proposal.changed_files) if proposal.changed_files else "no file changes"
            message = f"Prepared a staged edit proposal touching {changed_files}."
            self._record_chat_turn("assistant", message)
            return AgentChatResult(kind="proposal", message=message, proposal=proposal)

        reply = await self._generate_chat_reply(
            normalized,
            include_history=True,
            system_instructions=AGENT_CHAT_SYSTEM_PROMPT,
            prompt_version="forge-chat",
            response_instructions=(
                "Reply conversationally. If the user is asking for advice, give it plainly. "
                "If they are greeting or asking a simple question, answer naturally without forcing prompt-edit structure."
            ),
        )
        self._record_chat_turn("assistant", reply)
        return AgentChatResult(kind="reply", message=reply)

    async def _generate_chat_reply(
        self,
        request: str,
        *,
        include_history: bool,
        system_instructions: str,
        prompt_version: str,
        response_instructions: str,
    ) -> str:
        latest = self.latest_revision
        latest_summary = "No benchmark has been run yet."
        if latest and latest.benchmark:
            latest_summary = self._format_snapshot_for_prompt(latest.benchmark)
            if latest.benchmark_vs_baseline:
                latest_summary += "\n\nAgainst baseline:\n" + self._format_diff_for_prompt(latest.benchmark_vs_baseline)

        _, brief_text = self.read_prompt_file("brief")
        _, current_system_prompt = self.read_prompt_file("system")
        _, user_template = self.read_prompt_file("user")
        history_block = ""
        if include_history:
            history_block = self._formatted_chat_history(limit=10)
        guidance_prompt = (
            "Prompt brief:\n"
            f"{brief_text.strip()}\n\n"
            "Current prompt pack:\n"
            "=== SYSTEM PROMPT ===\n"
            f"{current_system_prompt.strip()}\n\n"
            "=== USER TEMPLATE ===\n"
            f"{user_template.strip()}\n\n"
            "Latest benchmark snapshot:\n"
            f"{latest_summary}\n\n"
        )
        if history_block:
            guidance_prompt += f"Conversation so far:\n{history_block}\n\n"
        guidance_prompt += (
            "User request:\n"
            f"{request.strip()}\n\n"
            "Response instructions:\n"
            f"{response_instructions.strip()}\n"
        )
        response = await self.gateway.generate(
            prompt_version=prompt_version,
            case_id=prompt_version,
            model=self.manifest.agent_model,
            system_prompt=system_instructions,
            user_prompt=guidance_prompt,
            run_id=self.manifest.session_id,
            config_hash=f"{self.manifest.session_id}-chat",
            run_config=RunConfig(
                temperature=0.2,
                max_output_tokens=max(900, self.manifest.run_config.max_output_tokens),
                seed=None,
                retries=self.manifest.run_config.retries,
                timeout_seconds=self.manifest.run_config.timeout_seconds,
                concurrency=1,
                failure_threshold=1.0,
                use_cache=False,
            ),
        )
        if response.error:
            raise RuntimeError(response.error)
        return (response.output_text or "").strip()

    def export_prompt_pack(self, version: str) -> Path:
        destination = settings.prompt_pack_dir / version
        if destination.exists():
            raise FileExistsError(f"Prompt pack already exists: {version}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(self.working_prompt_dir, destination)
        manifest_path = destination / "manifest.yaml"
        manifest_payload = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
        manifest_payload["version"] = version
        manifest_path.write_text(yaml.safe_dump(manifest_payload, sort_keys=False), encoding="utf-8")
        log_event(
            self.logger,
            "forge_prompt_exported",
            session_id=self.manifest.session_id,
            version=version,
            destination=str(destination),
        )
        return destination

    def history_rows(self) -> list[tuple[str, str, str, str, str]]:
        rows: list[tuple[str, str, str, str, str]] = []
        for revision in self.history.revisions:
            score = "--"
            delta = "--"
            full = "--"
            if revision.benchmark:
                score = f"{revision.benchmark.mean_effective_score:.2f}"
            if revision.benchmark_vs_baseline:
                delta = f"{revision.benchmark_vs_baseline.mean_score_delta:+.2f}"
            if revision.full_evaluation:
                full = f"{revision.full_evaluation.mean_effective_score:.2f}"
            rows.append((revision.revision_id, revision.source, score, delta, full))
        return rows

    def score_trend_points(self) -> list[tuple[str, float]]:
        points: list[tuple[str, float]] = []
        for revision in self.history.revisions:
            if revision.benchmark:
                points.append((revision.revision_id, revision.benchmark.mean_effective_score))
        return points

    def previous_revision_id(self) -> str | None:
        if len(self.history.revisions) < 2:
            return None
        return self.history.revisions[-2].revision_id

    def benchmark_case_rows(
        self,
        *,
        limit: int | None = 10,
        failures_only: bool = False,
    ) -> list[tuple[str, str, str, str, str]]:
        latest = self.latest_revision
        if latest is None or latest.benchmark is None:
            return []

        cases = list(latest.benchmark.cases)
        if failures_only:
            cases = [case for case in cases if case.hard_fail_rate > 0]

        cases.sort(
            key=lambda case: (
                -case.hard_fail_rate,
                case.average_effective_score,
                case.case_id,
            )
        )
        if limit is not None:
            cases = cases[:limit]

        rows: list[tuple[str, str, str, str, str]] = []
        for case in cases:
            reasons = ", ".join(case.hard_fail_reasons) if case.hard_fail_reasons else "--"
            rows.append(
                (
                    case.case_id,
                    f"{case.average_effective_score:.2f}",
                    f"{case.hard_fail_rate:.0%}",
                    reasons,
                    case.latest_summary or "--",
                )
            )
        return rows

    def latest_diff_rows(self, *, reference: str = "baseline") -> list[tuple[str, str]]:
        latest = self.latest_revision
        if latest is None:
            return []

        diff = latest.benchmark_vs_baseline if reference == "baseline" else latest.benchmark_vs_previous
        if diff is None:
            return []

        rows = [
            ("Reference", diff.reference),
            ("Winner", diff.winner),
            ("Confidence", f"{diff.confidence:.2f}"),
            ("Score delta", f"{diff.mean_score_delta:+.2f}"),
            ("Pass rate delta", f"{diff.pass_rate_delta:+.1%}"),
            ("Hard fail delta", f"{diff.hard_fail_rate_delta:+.1%}"),
            ("Improved traits", ", ".join(diff.improved_traits) or "--"),
            ("Regressed traits", ", ".join(diff.regressed_traits) or "--"),
            ("Improved cases", ", ".join(diff.top_improved_cases) or "--"),
            ("Regressed cases", ", ".join(diff.top_regressed_cases) or "--"),
        ]
        return rows

    def status_rows(self) -> list[tuple[str, str]]:
        latest = self.latest_revision
        latest_score = "--"
        latest_note = "--"
        if latest and latest.benchmark:
            latest_score = f"{latest.benchmark.mean_effective_score:.2f} / 5.00"
            latest_note = latest.note or latest.source
        return [
            ("Session", self.manifest.session_id),
            ("Baseline", self.manifest.baseline_prompt_ref),
            ("Benchmark dataset", self.manifest.benchmark_dataset_path),
            ("Full dataset", self.manifest.full_dataset_path),
            ("Model", self.manifest.model),
            ("Agent model", self.manifest.agent_model),
            ("Provider", self.manifest.provider),
            ("Judge", self.manifest.judge_provider),
            ("Bench repeats", str(self.manifest.bench_repeats)),
            ("Pending edits", str(len(self.pending_edits.edits))),
            ("Latest score", latest_score),
            ("Latest note", latest_note),
        ]

    async def _create_revision_from_prompt_dir(
        self,
        *,
        prompt_dir: Path,
        source: RevisionSource,
        note: str,
        changed_files: list[str],
        run_benchmark: bool = True,
    ) -> ForgeRevision:
        prompt_pack = load_prompt_pack(prompt_dir)
        revision_id = self._next_revision_id()
        snapshot_dir = self.revisions_dir / revision_id / "prompt_pack"
        snapshot_dir.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(prompt_dir, snapshot_dir)

        revision = ForgeRevision(
            revision_id=revision_id,
            created_at=utc_now_iso(),
            source=source,
            note=note,
            changed_files=changed_files,
            prompt_pack_hash=prompt_pack.content_hash,
            prompt_snapshot_dir=str(snapshot_dir),
        )
        if run_benchmark:
            await self._ensure_baseline_benchmark()
            revision.benchmark = await self._run_snapshot(
                prompt_dir=snapshot_dir,
                dataset_path=self.manifest.benchmark_dataset_path,
                repeats=self.manifest.bench_repeats,
                label="benchmark",
            )
            if self.history.revisions and self.baseline_revision.benchmark is not None:
                revision.benchmark_vs_baseline = self._compare_snapshots(
                    candidate=revision.benchmark,
                    reference=self.baseline_revision.benchmark,
                    reference_label="baseline",
                )
            previous_benchmark_revision = self._previous_benchmark_revision()
            if previous_benchmark_revision and previous_benchmark_revision.revision_id != revision.revision_id:
                revision.benchmark_vs_previous = self._compare_snapshots(
                    candidate=revision.benchmark,
                    reference=previous_benchmark_revision.benchmark,
                    reference_label=previous_benchmark_revision.revision_id,
                )
        self.history.revisions.append(revision)
        self.manifest.latest_revision_id = revision.revision_id
        if source == "baseline":
            self.manifest.baseline_revision_id = revision.revision_id
        self._persist()
        if revision.benchmark is not None:
            log_event(
                self.logger,
                "forge_revision_benchmarked",
                session_id=self.manifest.session_id,
                revision_id=revision.revision_id,
                source=source,
                prompt_pack_hash=revision.prompt_pack_hash,
                run_ids=revision.benchmark.run_ids if revision.benchmark else [],
                mean_effective_score=revision.benchmark.mean_effective_score if revision.benchmark else None,
            )
        else:
            log_event(
                self.logger,
                "forge_revision_created",
                session_id=self.manifest.session_id,
                revision_id=revision.revision_id,
                source=source,
                prompt_pack_hash=revision.prompt_pack_hash,
                note=note,
            )
        return revision

    def _next_revision_id(self) -> str:
        next_index = len(self.history.revisions)
        for child in self.revisions_dir.iterdir() if self.revisions_dir.exists() else []:
            if not child.is_dir():
                continue
            name = child.name
            if len(name) == 4 and name.startswith("r") and name[1:].isdigit():
                next_index = max(next_index, int(name[1:]) + 1)
        return f"r{next_index:03d}"

    async def _ensure_baseline_benchmark(self) -> None:
        if not self.manifest.baseline_revision_id:
            return
        baseline = self.baseline_revision
        if baseline.benchmark is not None:
            return
        baseline.benchmark = await self._run_snapshot(
            prompt_dir=Path(baseline.prompt_snapshot_dir),
            dataset_path=self.manifest.benchmark_dataset_path,
            repeats=self.manifest.bench_repeats,
            label="benchmark",
        )
        self._persist()

    def _previous_benchmark_revision(self) -> ForgeRevision | None:
        for revision in reversed(self.history.revisions):
            if revision.benchmark:
                return revision
        return None

    async def _run_snapshot(
        self,
        *,
        prompt_dir: Path,
        dataset_path: str,
        repeats: int,
        label: str,
    ) -> BenchmarkSnapshot:
        if repeats < 1:
            raise ValueError("repeats must be >= 1")
        run_ids: list[str] = []
        score_artifacts: list[ScoresArtifact] = []
        effective_use_cache = self.manifest.run_config.use_cache and repeats == 1
        run_config = self.manifest.run_config.model_copy(update={"use_cache": effective_use_cache})

        for _ in range(repeats):
            manifest = await self.evaluation_service.run(
                RunRequest(
                    prompt_version=str(prompt_dir),
                    model=self.manifest.model,
                    dataset_path=dataset_path,
                    run_config=run_config,
                    scoring_config=self.manifest.scoring_config,
                    provider=self.manifest.provider,
                    judge_provider=self.manifest.judge_provider,
                )
            )
            run_ids.append(manifest.run_id)
            scores = ScoresArtifact.model_validate(
                self.artifacts.read_json(Path(manifest.output_dir) / "scores.json")
            )
            score_artifacts.append(scores)
        return self._build_snapshot(
            label=label,
            dataset_path=dataset_path,
            repeats=repeats,
            use_cache=effective_use_cache,
            scores=score_artifacts,
            run_ids=run_ids,
        )

    def _build_snapshot(
        self,
        *,
        label: str,
        dataset_path: str,
        repeats: int,
        use_cache: bool,
        scores: list[ScoresArtifact],
        run_ids: list[str],
    ) -> BenchmarkSnapshot:
        score_values = [artifact.aggregate.average_effective_score for artifact in scores]
        raw_values = [artifact.aggregate.average_raw_score for artifact in scores]
        hard_fail_values = [artifact.aggregate.hard_fail_rate for artifact in scores]
        total_cases = scores[0].aggregate.total_cases if scores else 0
        case_ids = [case.case_id for case in scores[0].cases] if scores else []
        warnings = sorted({warning for artifact in scores for warning in artifact.warnings})
        trait_means: dict[TraitName, float] = {
            trait: round(
                fmean(artifact.aggregate.trait_averages[trait] for artifact in scores),
                4,
            )
            for trait in scores[0].aggregate.trait_averages.keys()
        }
        case_summaries: list[BenchmarkCaseSummary] = []
        for case_id in case_ids:
            matching_cases = [
                next(case for case in artifact.cases if case.case_id == case_id)
                for artifact in scores
            ]
            last_case = matching_cases[-1]
            case_summaries.append(
                BenchmarkCaseSummary(
                    case_id=case_id,
                    average_effective_score=round(
                        fmean(case.effective_weighted_score for case in matching_cases),
                        4,
                    ),
                    average_raw_score=round(
                        fmean(case.raw_weighted_score for case in matching_cases),
                        4,
                    ),
                    hard_fail_rate=round(
                        sum(1 for case in matching_cases if case.hard_fail) / len(matching_cases),
                        4,
                    ),
                    latest_summary=last_case.summary,
                    hard_fail_reasons=sorted(
                        {
                            reason
                            for case in matching_cases
                            for reason in case.hard_fail_reasons
                        }
                    ),
                )
            )
        passed_cases = sum(
            1
            for artifact in scores
            for case in artifact.cases
            if not case.hard_fail
        )
        total_case_attempts = max(1, len(scores) * total_cases)
        return BenchmarkSnapshot(
            label=label,
            dataset_path=dataset_path,
            repeats=repeats,
            run_ids=run_ids,
            use_cache=use_cache,
            temperature=self.manifest.run_config.temperature,
            mean_effective_score=round(fmean(score_values), 4),
            best_effective_score=round(max(score_values), 4),
            worst_effective_score=round(min(score_values), 4),
            score_stddev=round(pstdev(score_values), 4) if len(score_values) > 1 else 0.0,
            mean_raw_score=round(fmean(raw_values), 4),
            mean_hard_fail_rate=round(fmean(hard_fail_values), 4),
            pass_rate=round(passed_cases / total_case_attempts, 4),
            total_cases=total_cases,
            trait_means=trait_means,
            warnings=warnings,
            cases=case_summaries,
        )

    def _compare_snapshots(
        self,
        *,
        candidate: BenchmarkSnapshot | None,
        reference: BenchmarkSnapshot | None,
        reference_label: str,
    ) -> BenchmarkDiff | None:
        if candidate is None or reference is None:
            return None
        score_delta = round(candidate.mean_effective_score - reference.mean_effective_score, 4)
        pass_rate_delta = round(candidate.pass_rate - reference.pass_rate, 4)
        hard_fail_rate_delta = round(candidate.mean_hard_fail_rate - reference.mean_hard_fail_rate, 4)
        trait_deltas = {
            trait: round(candidate.trait_means[trait] - reference.trait_means[trait], 4)
            for trait in candidate.trait_means.keys()
        }
        improved_traits = [trait for trait, delta in trait_deltas.items() if delta > 0]
        regressed_traits = [trait for trait, delta in trait_deltas.items() if delta < 0]

        candidate_cases = {case.case_id: case for case in candidate.cases}
        reference_cases = {case.case_id: case for case in reference.cases}
        case_deltas = {
            case_id: round(
                candidate_cases[case_id].average_effective_score - reference_cases[case_id].average_effective_score,
                4,
            )
            for case_id in candidate_cases.keys()
            if case_id in reference_cases
        }
        top_improved = [
            case_id
            for case_id, _ in sorted(case_deltas.items(), key=lambda item: item[1], reverse=True)
            if case_deltas[case_id] > 0
        ][:3]
        top_regressed = [
            case_id
            for case_id, _ in sorted(case_deltas.items(), key=lambda item: item[1])
            if case_deltas[case_id] < 0
        ][:3]

        tie_margin = self.manifest.scoring_config.tie_margin
        if abs(score_delta) <= tie_margin and abs(pass_rate_delta) <= 0.05 and abs(hard_fail_rate_delta) <= 0.05:
            winner = "tie"
        elif hard_fail_rate_delta < 0 and score_delta >= -tie_margin:
            winner = "candidate"
        elif hard_fail_rate_delta > 0 and score_delta <= tie_margin:
            winner = "reference"
        else:
            winner = "candidate" if score_delta > 0 else "reference"

        confidence = round(
            min(
                1.0,
                (
                    abs(score_delta) / 2.5
                    + abs(pass_rate_delta)
                    + abs(hard_fail_rate_delta)
                )
                / 3,
            ),
            4,
        )
        return BenchmarkDiff(
            reference=reference_label,
            winner=winner,
            confidence=confidence,
            mean_score_delta=score_delta,
            pass_rate_delta=pass_rate_delta,
            hard_fail_rate_delta=hard_fail_rate_delta,
            trait_deltas=trait_deltas,
            improved_traits=improved_traits,
            regressed_traits=regressed_traits,
            top_improved_cases=top_improved,
            top_regressed_cases=top_regressed,
        )

    def _format_snapshot_for_prompt(self, snapshot: BenchmarkSnapshot) -> str:
        lines = [
            f"- Dataset: {snapshot.dataset_path}",
            f"- Repeats: {snapshot.repeats}",
            f"- Mean effective score: {snapshot.mean_effective_score:.2f} / 5.00",
            f"- Pass rate: {snapshot.pass_rate:.1%}",
            f"- Mean hard fail rate: {snapshot.mean_hard_fail_rate:.1%}",
        ]
        for trait, value in snapshot.trait_means.items():
            lines.append(f"- {trait}: {value:.2f}")
        if snapshot.warnings:
            lines.append("- Warnings:")
            lines.extend(f"  - {warning}" for warning in snapshot.warnings)
        return "\n".join(lines)

    def _format_diff_for_prompt(self, diff: BenchmarkDiff) -> str:
        lines = [
            f"- Winner: {diff.winner}",
            f"- Confidence: {diff.confidence:.2f}",
            f"- Mean score delta: {diff.mean_score_delta:+.2f}",
            f"- Pass rate delta: {diff.pass_rate_delta:+.1%}",
            f"- Hard fail delta: {diff.hard_fail_rate_delta:+.1%}",
        ]
        if diff.improved_traits:
            lines.append(f"- Improved traits: {', '.join(diff.improved_traits)}")
        if diff.regressed_traits:
            lines.append(f"- Regressed traits: {', '.join(diff.regressed_traits)}")
        if diff.top_improved_cases:
            lines.append(f"- Improved cases: {', '.join(diff.top_improved_cases)}")
        if diff.top_regressed_cases:
            lines.append(f"- Regressed cases: {', '.join(diff.top_regressed_cases)}")
        return "\n".join(lines)

    def _problem_case_summary(self, *, limit: int = 5) -> str:
        rows = self.benchmark_case_rows(limit=limit, failures_only=False)
        if not rows:
            return "No benchmark case summaries are available yet."
        lines: list[str] = []
        for case_id, score, hard_fail, reasons, summary in rows:
            lines.append(
                f"- {case_id}: score {score}/5.00, hard fail {hard_fail}, reasons: {reasons}, summary: {summary}"
            )
        return "\n".join(lines)

    async def _generate_playground_samples(
        self,
        *,
        prompt_dir: Path,
        case: DatasetCase,
        samples: int,
        prefix: str,
    ) -> list[PlaygroundSample]:
        prompt_pack = load_prompt_pack(prompt_dir)
        user_prompt = render_user_prompt(prompt_pack, case)
        outputs: list[PlaygroundSample] = []
        for index in range(samples):
            result = await self.gateway.generate(
                prompt_version=str(prompt_dir),
                case_id=f"{prefix}-{index}",
                model=self.manifest.model,
                system_prompt=prompt_pack.system_prompt,
                user_prompt=user_prompt,
                run_id=self.manifest.session_id,
                config_hash=f"{self.manifest.session_id}-{prefix}-playground",
                run_config=self.manifest.run_config.model_copy(
                    update={
                        "concurrency": 1,
                        "retries": 0,
                        "failure_threshold": 1.0,
                        "use_cache": False,
                    }
                ),
            )
            if result.error:
                raise RuntimeError(result.error)
            outputs.append(
                PlaygroundSample(
                    sample_id=f"{prefix}-{index}",
                    output_text=(result.output_text or "").strip(),
                    latency_ms=result.latency_ms,
                    usage=result.usage,
                    warnings=result.warnings,
                )
            )
        return outputs

    def _build_review_summary(
        self,
        *,
        suite: ScenarioSuite,
        candidate: BenchmarkSnapshot,
        baseline: BenchmarkSnapshot | None,
        diff: BenchmarkDiff | None,
    ) -> ReviewSummary:
        artifact_store = ArtifactStore()
        candidate_run_id = candidate.run_ids[-1]
        candidate_dir = artifact_store.resolve_run_dir(candidate_run_id)
        candidate_scores = ScoresArtifact.model_validate(
            artifact_store.read_json(candidate_dir / "scores.json")
        )
        candidate_outputs = {
            row["case_id"]: row
            for row in artifact_store.read_jsonl(candidate_dir / "outputs.jsonl")
        }
        baseline_scores_map: dict[str, Any] = {}
        baseline_outputs: dict[str, Any] = {}
        if baseline and baseline.run_ids:
            baseline_dir = artifact_store.resolve_run_dir(baseline.run_ids[-1])
            loaded_baseline_scores = ScoresArtifact.model_validate(
                artifact_store.read_json(baseline_dir / "scores.json")
            )
            baseline_scores_map = {
                case.case_id: case for case in loaded_baseline_scores.cases
            }
            baseline_outputs = {
                row["case_id"]: row
                for row in artifact_store.read_jsonl(baseline_dir / "outputs.jsonl")
            }

        candidate_scores_map = {case.case_id: case for case in candidate_scores.cases}
        latest_files = self.latest_revision.changed_files if self.latest_revision else []
        cases: list[ReviewCase] = []
        for scenario_case in suite.cases:
            candidate_case = candidate_scores_map.get(scenario_case.case_id)
            baseline_case = baseline_scores_map.get(scenario_case.case_id)
            candidate_output = candidate_outputs.get(scenario_case.case_id, {})
            baseline_output = baseline_outputs.get(scenario_case.case_id, {})
            regression = False
            if candidate_case and baseline_case:
                regression = candidate_case.effective_weighted_score < baseline_case.effective_weighted_score
            assertions = self._evaluate_assertions(
                scenario_case,
                candidate_case,
                candidate_output,
            )
            cases.append(
                ReviewCase(
                    case_id=scenario_case.case_id,
                    title=scenario_case.title or scenario_case.case_id,
                    candidate_score=candidate_case.effective_weighted_score if candidate_case else None,
                    baseline_score=baseline_case.effective_weighted_score if baseline_case else None,
                    regression=regression,
                    flaky=bool(
                        next(
                            (
                                summary.hard_fail_rate > 0 and summary.hard_fail_rate < 1
                                for summary in candidate.cases
                                if summary.case_id == scenario_case.case_id
                            ),
                            False,
                        )
                    ),
                    candidate_output=str(candidate_output.get("output_text", "")).strip(),
                    baseline_output=str(baseline_output.get("output_text", "")).strip(),
                    diff_preview=self._build_output_diff(
                        str(baseline_output.get("output_text", "")).strip(),
                        str(candidate_output.get("output_text", "")).strip(),
                        scenario_case.case_id,
                    ),
                    hard_fail_reasons=candidate_case.hard_fail_reasons if candidate_case else [],
                    assertions=assertions,
                    likely_changed_files=latest_files,
                )
            )
        return ReviewSummary(
            review_id=self._next_review_id(),
            suite_id=suite.suite_id,
            suite_name=suite.name,
            revision_id=self.latest_revision.revision_id if self.latest_revision else None,
            candidate=candidate,
            baseline=baseline,
            diff=diff,
            cases=cases,
        )

    def _evaluate_assertions(
        self,
        scenario_case: ScenarioCase,
        candidate_case: Any,
        candidate_output: dict[str, Any],
    ) -> list[AssertionResult]:
        output_text = str(candidate_output.get("output_text", "") or "")
        usage = candidate_output.get("usage", {}) or {}
        latency_ms = int(candidate_output.get("latency_ms", 0) or 0)
        word_count = len(output_text.split())
        results: list[AssertionResult] = []
        for assertion in scenario_case.assertions:
            status = "passed"
            detail = "Passed."
            if assertion.kind == "required_string":
                expected = assertion.expected_text or ""
                if expected.lower() not in output_text.lower():
                    status = "failed"
                    detail = f"Missing required text: {expected}"
            elif assertion.kind == "forbidden_string":
                expected = assertion.expected_text or ""
                if expected.lower() in output_text.lower():
                    status = "failed"
                    detail = f"Found forbidden text: {expected}"
            elif assertion.kind == "required_section":
                expected = assertion.expected_text or ""
                if expected and expected.lower() not in output_text.lower():
                    status = "failed"
                    detail = f"Missing section: {expected}"
            elif assertion.kind == "max_words":
                threshold = int(assertion.threshold or 0)
                if threshold and word_count > threshold:
                    status = "failed"
                    detail = f"Output used {word_count} words; limit is {threshold}."
            elif assertion.kind == "trait_minimum":
                threshold = int(assertion.threshold or 0)
                trait_score = candidate_case.trait_scores.get(assertion.trait).score if (candidate_case and assertion.trait) else 0
                if trait_score < threshold:
                    status = "failed"
                    detail = f"{assertion.trait} scored {trait_score}; expected at least {threshold}."
            elif assertion.kind == "max_latency_ms":
                threshold = int(assertion.threshold or 0)
                if threshold and latency_ms > threshold:
                    status = "failed"
                    detail = f"Latency was {latency_ms}ms; limit is {threshold}ms."
            elif assertion.kind == "max_total_tokens":
                threshold = int(assertion.threshold or 0)
                total_tokens = int(usage.get("total_tokens", 0) or 0)
                if threshold and total_tokens > threshold:
                    status = "failed"
                    detail = f"Total tokens were {total_tokens}; limit is {threshold}."
            if status == "failed" and assertion.severity == "warn":
                status = "warn"
            results.append(
                AssertionResult(
                    assertion_id=assertion.assertion_id,
                    label=assertion.label,
                    status=status,
                    detail=detail,
                )
            )
        return results

    def _build_output_diff(self, before: str, after: str, case_id: str) -> str:
        if not before and not after:
            return ""
        return "\n".join(
            difflib.unified_diff(
                before.splitlines(),
                after.splitlines(),
                fromfile=f"baseline/{case_id}",
                tofile=f"candidate/{case_id}",
                lineterm="",
            )
        )

    def _record_builder_action(
        self,
        *,
        kind: str,
        title: str,
        details: str = "",
        files: list[str] | None = None,
        tools: list[str] | None = None,
        used_research: bool = False,
    ) -> None:
        permission_mode = ensure_prompt_brief(self.working_prompt_dir).builder_permission_mode
        self.history.builder_actions.append(
            BuilderAction(
                action_id=self._next_action_id(),
                kind=kind,  # type: ignore[arg-type]
                title=title,
                details=details,
                files=files or [],
                tools=tools or [],
                used_research=used_research,
                permission_mode=permission_mode,
            )
        )
        self.history.builder_actions = self.history.builder_actions[-100:]
        self._persist()

    def _next_action_id(self) -> str:
        return f"a{len(self.history.builder_actions):03d}"

    def _next_review_id(self) -> str:
        return f"rv{len(self.history.reviews):03d}"

    def _next_decision_id(self) -> str:
        return f"d{len(self.history.decisions):03d}"

    def _persist(self) -> None:
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.proposals_dir.mkdir(parents=True, exist_ok=True)
        self.manifest_path.write_text(
            json.dumps(self.manifest.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )
        self.history_path.write_text(
            json.dumps(self.history.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )
        self.pending_edits_path.write_text(
            json.dumps(self.pending_edits.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )
        self.chat_history_path.write_text(
            json.dumps(self.chat_history.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )

    def _load_pending_edits(self) -> PendingEdits:
        if not self.pending_edits_path.exists():
            return PendingEdits()
        return PendingEdits.model_validate(
            json.loads(self.pending_edits_path.read_text(encoding="utf-8"))
        )

    def _load_chat_history(self) -> ChatHistory:
        if not self.chat_history_path.exists():
            return ChatHistory()
        return ChatHistory.model_validate(
            json.loads(self.chat_history_path.read_text(encoding="utf-8"))
        )

    def _record_chat_turn(self, role: str, content: str) -> None:
        normalized = content.strip()
        if not normalized:
            return
        self.chat_history.turns.append(ChatTurn(role=role, content=normalized))
        self.chat_history.turns = self.chat_history.turns[-CHAT_HISTORY_LIMIT:]
        self._persist()

    def _formatted_chat_history(self, *, limit: int) -> str:
        recent_turns = self.chat_history.turns[-limit:]
        if not recent_turns:
            return ""
        return "\n".join(
            f"{'User' if turn.role == 'user' else 'Assistant'}: {turn.content}"
            for turn in recent_turns
        )

    def _is_simple_greeting(self, request: str) -> bool:
        lowered = " ".join(request.lower().split())
        return lowered in SIMPLE_GREETINGS

    def _is_capabilities_question(self, request: str) -> bool:
        lowered = request.lower()
        return any(
            marker in lowered
            for marker in (
                "what can you do",
                "how can you help",
                "help me",
                "what do you do",
                "what are you able to do",
            )
        )

    def _should_run_benchmark(self, request: str) -> bool:
        lowered = request.lower()
        benchmark_markers = ("run a benchmark", "run benchmark", "benchmark this", "bench this", "test this prompt", "evaluate this prompt", "score this prompt", "run evaluation")
        return any(marker in lowered for marker in benchmark_markers) and "full" not in lowered

    def _should_run_full_evaluation(self, request: str) -> bool:
        lowered = request.lower()
        full_markers = ("full eval", "full evaluation", "run the full", "evaluate the full dataset", "run the full dataset")
        return any(marker in lowered for marker in full_markers)

    def _should_prepare_edit(self, request: str) -> bool:
        lowered = request.lower()
        edit_markers = (
            "edit the prompt",
            "update the prompt",
            "rewrite the prompt",
            "change the prompt",
            "modify the prompt",
            "fix the prompt",
            "improve the prompt",
            "change the system prompt",
            "update the system prompt",
            "rewrite the system prompt",
            "change the user template",
            "update the user template",
            "rewrite the user template",
            "make these changes",
            "apply these changes",
        )
        return any(marker in lowered for marker in edit_markers)

    def _next_proposal_id(self) -> str:
        highest = -1
        if self.proposals_dir.exists():
            for child in self.proposals_dir.iterdir():
                if child.is_dir() and child.name.startswith("p") and child.name[1:].isdigit():
                    highest = max(highest, int(child.name[1:]))
        for edit in self.pending_edits.edits:
            if edit.proposal_id.startswith("p") and edit.proposal_id[1:].isdigit():
                highest = max(highest, int(edit.proposal_id[1:]))
        return f"p{highest + 1:03d}"

    def _drop_pending_edit(self, proposal_id: str) -> None:
        proposal_dir = self.proposals_dir / proposal_id
        if proposal_dir.exists():
            shutil.rmtree(proposal_dir)
        self.pending_edits.edits = [
            edit for edit in self.pending_edits.edits if edit.proposal_id != proposal_id
        ]
        self._persist()

    def _replace_working_prompt_dir_from(self, source_dir: Path) -> None:
        for child in self.working_prompt_dir.iterdir():
            if child.is_dir():
                shutil.rmtree(child)
            else:
                child.unlink()
        for child in source_dir.iterdir():
            destination = self.working_prompt_dir / child.name
            if child.is_dir():
                shutil.copytree(child, destination)
            else:
                shutil.copy2(child, destination)

    def _read_prompt_file_map(self, root: Path) -> dict[str, str]:
        payload: dict[str, str] = {}
        for name in EDITABLE_PROMPT_FILES:
            path = root / name
            payload[name] = path.read_text(encoding="utf-8") if path.exists() else ""
        return payload

    def _build_diff_preview(self, before: dict[str, str], after: dict[str, str], changed_files: list[str]) -> str:
        if not changed_files:
            return ""
        diff_chunks: list[str] = []
        for name in changed_files:
            diff = "\n".join(
                difflib.unified_diff(
                    before.get(name, "").splitlines(),
                    after.get(name, "").splitlines(),
                    fromfile=f"before/{name}",
                    tofile=f"after/{name}",
                    lineterm="",
                )
            )
            if diff:
                diff_chunks.append(diff)
        return "\n\n".join(diff_chunks)

    def _latest_benchmark_summary(self) -> str:
        latest = self.latest_revision
        if latest is None or latest.benchmark is None:
            return "No benchmark has been run yet."
        return self._format_snapshot_for_prompt(latest.benchmark)

    def _latest_baseline_diff_summary(self) -> str:
        latest = self.latest_revision
        if latest is None or latest.benchmark_vs_baseline is None:
            return "No delta against baseline yet."
        return self._format_diff_for_prompt(latest.benchmark_vs_baseline)

    async def _run_codex_edit_agent(self, request: str, *, workdir: Path | None = None) -> str:
        codex_bin = settings.codex_bin
        if shutil.which(codex_bin) is None:
            raise RuntimeError(f"Codex CLI not found on PATH: {codex_bin}")

        benchmark_summary = self._latest_benchmark_summary()
        problem_cases = self._problem_case_summary()
        baseline_diff = self._latest_baseline_diff_summary()
        prompt = AGENT_EDIT_PROMPT_TEMPLATE.format(
            benchmark_summary=benchmark_summary,
            problem_cases=problem_cases,
            baseline_diff=baseline_diff,
            request=request.strip(),
        )
        command = [
            codex_bin,
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            "workspace-write",
            "-m",
            self.manifest.agent_model,
            "-c",
            f'model_reasoning_effort="{settings.codex_reasoning_effort}"',
            "-C",
            str(workdir or self.working_prompt_dir),
        ]
        if settings.codex_profile:
            command.extend(["-p", settings.codex_profile])

        output_path: str | None = None
        try:
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as output_handle:
                output_path = output_handle.name
            command.extend(["-o", output_path, "-"])
            process = await asyncio.create_subprocess_exec(
                *command,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await process.communicate(prompt.encode("utf-8"))
            stderr_text = stderr.decode("utf-8", errors="replace").strip()
            stdout_text = stdout.decode("utf-8", errors="replace").strip()
            summary = ""
            if output_path and os.path.exists(output_path):
                summary = Path(output_path).read_text(encoding="utf-8").strip()
            if process.returncode != 0:
                raise RuntimeError(stderr_text or stdout_text or "Codex editing agent failed.")
            if not summary:
                raise RuntimeError(stderr_text or "Codex editing agent returned no final summary.")
            log_event(
                self.logger,
                "forge_agent_request_applied",
                session_id=self.manifest.session_id,
                model=self.manifest.agent_model,
                request=request,
            )
            return summary
        finally:
            if output_path and os.path.exists(output_path):
                try:
                    os.unlink(output_path)
                except OSError:
                    pass
