from __future__ import annotations

import json
import shutil
from pathlib import Path

import yaml
from pydantic import BaseModel, Field

from promptforge.core.config import settings
from promptforge.core.models import RunConfig, ScoringConfig
from promptforge.forge.models import (
    AgentChatResult,
    AgentEditResult,
    BuilderAction,
    DecisionRecord,
    PlaygroundRun,
    PreparedAgentEdit,
    ReviewSummary,
)
from promptforge.forge.service import ForgeSession
from promptforge.project import PromptForgeProject
from promptforge.prompts.brief import PromptBrief, ensure_prompt_brief, save_prompt_brief
from promptforge.prompts.loader import load_prompt_pack
from promptforge.runtime.gateway import build_gateway
from promptforge.scenarios.models import ScenarioSuite
from promptforge.scenarios.service import ScenarioSuiteService


class PromptSummary(BaseModel):
    version: str
    name: str
    description: str = ""
    root: str
    session_id: str | None = None


class PromptView(BaseModel):
    version: str
    name: str
    description: str = ""
    root: str
    system_prompt: str
    user_template: str
    purpose: str = ""
    expected_behavior: str = ""
    success_criteria: str = ""
    baseline_prompt_ref: str = ""
    primary_scenario_suites: list[str] = Field(default_factory=list)
    owner: str = ""
    audience: str = ""
    release_notes: str = ""
    builder_agent_model: str = "gpt-5-mini"
    builder_permission_mode: str = "proposal_only"
    research_policy: str = "prompt_only"
    files: list[str] = Field(default_factory=list)
    session_id: str | None = None


class WorkspaceState(BaseModel):
    active_prompt: str | None = None
    prompt_sessions: dict[str, str] = Field(default_factory=dict)


class ForgeWorkspaceService:
    def __init__(
        self,
        *,
        dataset_path: str,
        bench_dataset_path: str | None,
        model: str,
        agent_model: str,
        provider: str,
        judge_provider: str,
        run_config: RunConfig,
        scoring_config: ScoringConfig,
        bench_repeats: int,
        full_repeats: int,
    ) -> None:
        self.project = PromptForgeProject.open_or_create(Path.cwd())
        self.dataset_path = dataset_path
        self.bench_dataset_path = bench_dataset_path
        self.model = model
        self.agent_model = agent_model
        self.provider = provider
        self.judge_provider = judge_provider
        self.run_config = run_config
        self.scoring_config = scoring_config
        self.bench_repeats = bench_repeats
        self.full_repeats = full_repeats
        self._sessions: dict[str, ForgeSession] = {}
        self.state = self._load_state()
        self.scenarios = ScenarioSuiteService(root=Path.cwd() / settings.scenario_dir)
        self.project.update_defaults(
            quick_benchmark_dataset=bench_dataset_path or dataset_path,
            full_evaluation_dataset=dataset_path,
            quick_benchmark_repeats=bench_repeats,
            full_evaluation_repeats=full_repeats,
            preferred_provider=provider,
            preferred_judge_provider=judge_provider,
            preferred_generation_model=model,
            preferred_judge_model=scoring_config.judge_model,
            preferred_agent_model=agent_model,
        )

    def list_prompts(self) -> list[PromptSummary]:
        settings.prompt_pack_dir.mkdir(parents=True, exist_ok=True)
        prompts: list[PromptSummary] = []
        for child in sorted(settings.prompt_pack_dir.iterdir(), key=lambda path: path.name.lower()):
            if not child.is_dir():
                continue
            try:
                prompt_pack = load_prompt_pack(child)
            except Exception:
                continue
            prompts.append(
                PromptSummary(
                    version=prompt_pack.manifest.version,
                    name=prompt_pack.manifest.name,
                    description=prompt_pack.manifest.description,
                    root=str(prompt_pack.root),
                    session_id=self.state.prompt_sessions.get(prompt_pack.manifest.version),
                )
            )
        return prompts

    def set_active_prompt(self, prompt_ref: str) -> None:
        self.state.active_prompt = prompt_ref
        self.project.set_last_opened_prompt(prompt_ref)
        self._persist_state()

    def create_prompt(self, version: str, *, from_prompt: str | None = None, name: str | None = None) -> Path:
        destination = settings.prompt_pack_dir / version
        if destination.exists():
            raise FileExistsError(f"Prompt pack already exists: {version}")
        destination.parent.mkdir(parents=True, exist_ok=True)

        if from_prompt:
            source = load_prompt_pack(from_prompt).root
            shutil.copytree(source, destination)
            manifest_path = destination / "manifest.yaml"
            manifest = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
            manifest["version"] = version
            manifest["name"] = name or f"{version} prompt"
            manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
            ensure_prompt_brief(destination, description=manifest.get("description", ""))
            return destination

        destination.mkdir(parents=True, exist_ok=False)
        manifest = {
            "apiVersion": 1,
            "version": version,
            "name": name or f"{version} prompt",
            "description": "New prompt pack created from the forge workspace.",
            "output_format": "markdown",
            "required_sections": [],
        }
        (destination / "manifest.yaml").write_text(
            yaml.safe_dump(manifest, sort_keys=False),
            encoding="utf-8",
        )
        (destination / "system.md").write_text(
            (
                "You are a focused assistant.\n\n"
                "Follow the user's request exactly, keep the answer concise, and do not invent facts.\n"
            ),
            encoding="utf-8",
        )
        (destination / "user_template.md").write_text(
            (
                "Use the provided input payload to answer the request.\n\n"
                "{{ input | tojson(indent=2) if input is mapping else input }}\n"
            ),
            encoding="utf-8",
        )
        (destination / "variables.schema.json").write_text(
            json.dumps({"type": "object", "additionalProperties": True}, indent=2) + "\n",
            encoding="utf-8",
        )
        save_prompt_brief(
            destination,
            PromptBrief(
                purpose=f"What this prompt is for in {name or version}.",
                expected_behavior="Describe the behavior, tone, and output shape you expect from the prompt.",
                success_criteria="Describe what a good answer must include and what should be avoided.",
            ),
        )
        return destination

    def load_visible_prompt(self, prompt_ref: str) -> PromptView:
        session_id = self.state.prompt_sessions.get(prompt_ref)
        if session_id:
            try:
                manifest = ForgeSession.load_manifest(session_id)
                if self._session_matches_config(manifest):
                    prompt_pack = load_prompt_pack(manifest.working_prompt_dir)
                    brief = ensure_prompt_brief(prompt_pack.root, description=prompt_pack.manifest.description)
                    return PromptView(
                        version=prompt_ref,
                        name=prompt_pack.manifest.name,
                        description=prompt_pack.manifest.description,
                        root=str(prompt_pack.root),
                        system_prompt=prompt_pack.system_prompt,
                        user_template=prompt_pack.user_template,
                        purpose=brief.purpose,
                        expected_behavior=brief.expected_behavior,
                        success_criteria=brief.success_criteria,
                        baseline_prompt_ref=brief.baseline_prompt_ref,
                        primary_scenario_suites=brief.primary_scenario_suites,
                        owner=brief.owner,
                        audience=brief.audience,
                        release_notes=brief.release_notes,
                        builder_agent_model=brief.builder_agent_model,
                        builder_permission_mode=brief.builder_permission_mode,
                        research_policy=brief.research_policy,
                        files=self._prompt_files(prompt_pack.root),
                        session_id=session_id,
                    )
            except Exception:
                self.state.prompt_sessions.pop(prompt_ref, None)
                self._persist_state()

        prompt_pack = load_prompt_pack(prompt_ref)
        brief = ensure_prompt_brief(prompt_pack.root, description=prompt_pack.manifest.description)
        return PromptView(
            version=prompt_pack.manifest.version,
            name=prompt_pack.manifest.name,
            description=prompt_pack.manifest.description,
            root=str(prompt_pack.root),
            system_prompt=prompt_pack.system_prompt,
            user_template=prompt_pack.user_template,
            purpose=brief.purpose,
            expected_behavior=brief.expected_behavior,
            success_criteria=brief.success_criteria,
            baseline_prompt_ref=brief.baseline_prompt_ref,
            primary_scenario_suites=brief.primary_scenario_suites,
            owner=brief.owner,
            audience=brief.audience,
            release_notes=brief.release_notes,
            builder_agent_model=brief.builder_agent_model,
            builder_permission_mode=brief.builder_permission_mode,
            research_policy=brief.research_policy,
            files=self._prompt_files(prompt_pack.root),
            session_id=None,
        )

    async def ensure_session(self, prompt_ref: str) -> ForgeSession:
        cached = self._sessions.get(prompt_ref)
        if cached is not None:
            return cached

        session_id = self.state.prompt_sessions.get(prompt_ref)
        if session_id:
            try:
                manifest = ForgeSession.load_manifest(session_id)
                if self._session_matches_config(manifest):
                    gateway = build_gateway(
                        provider=manifest.provider,
                        judge_provider=manifest.judge_provider,
                    )
                    session = ForgeSession.load(session_id=session_id, gateway=gateway)
                    self._sessions[prompt_ref] = session
                    return session
            except Exception:
                self.state.prompt_sessions.pop(prompt_ref, None)
                self._persist_state()

        prompt_pack = load_prompt_pack(prompt_ref)
        ensure_prompt_brief(prompt_pack.root, description=prompt_pack.manifest.description)
        gateway = build_gateway(provider=self.provider, judge_provider=self.judge_provider)
        session = await ForgeSession.create(
            prompt_ref=prompt_ref,
            dataset_path=self.dataset_path,
            bench_dataset_path=self.bench_dataset_path,
            model=self.model,
            agent_model=self.agent_model,
            provider=self.provider,
            judge_provider=self.judge_provider,
            run_config=self.run_config,
            scoring_config=self.scoring_config,
            bench_repeats=self.bench_repeats,
            full_repeats=self.full_repeats,
            gateway=gateway,
        )
        self._sessions[prompt_ref] = session
        self.state.prompt_sessions[prompt_ref] = session.manifest.session_id
        self.state.active_prompt = prompt_ref
        self.project.set_last_opened_prompt(prompt_ref)
        self._persist_state()
        return session

    async def prepare_agent_request(self, prompt_ref: str, request: str) -> PreparedAgentEdit:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.prepare_agent_request(request)

    async def coach(self, prompt_ref: str, request: str) -> str:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.coach(request)

    async def agent_chat(self, prompt_ref: str, request: str) -> AgentChatResult:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.agent_chat(request)

    async def apply_prepared_edit(self, prompt_ref: str, proposal_id: str) -> AgentEditResult:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.apply_prepared_edit(proposal_id)

    async def discard_prepared_edit(self, prompt_ref: str, proposal_id: str) -> None:
        session = await self.ensure_session(prompt_ref)
        session.discard_prepared_edit(proposal_id)

    async def apply_agent_request(self, prompt_ref: str, request: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.apply_agent_request(request)

    async def save_prompt_text(self, prompt_ref: str, *, system_prompt: str, user_template: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.edit_prompt_files(
            updates={"system": system_prompt, "user": user_template},
            note="Saved editor changes from the forge workspace.",
        )

    async def save_prompt_workspace(
        self,
        prompt_ref: str,
        *,
        system_prompt: str,
        user_template: str,
        purpose: str,
        expected_behavior: str,
        success_criteria: str,
        baseline_prompt_ref: str = "",
        primary_scenario_suites: list[str] | None = None,
        owner: str = "",
        audience: str = "",
        release_notes: str = "",
        builder_agent_model: str = "gpt-5-mini",
        builder_permission_mode: str = "proposal_only",
        research_policy: str = "prompt_only",
    ):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        brief = PromptBrief(
            purpose=purpose.strip(),
            expected_behavior=expected_behavior.strip(),
            success_criteria=success_criteria.strip(),
            baseline_prompt_ref=baseline_prompt_ref.strip(),
            primary_scenario_suites=primary_scenario_suites or [],
            owner=owner.strip(),
            audience=audience.strip(),
            release_notes=release_notes.strip(),
            builder_agent_model=builder_agent_model.strip() or session.manifest.agent_model,
            builder_permission_mode=builder_permission_mode.strip() or "proposal_only",
            research_policy=research_policy.strip() or "prompt_only",
        )
        return await session.edit_prompt_files(
            updates={
                "system": system_prompt,
                "user": user_template,
                "brief": json.dumps(brief.model_dump(mode="json"), indent=2, sort_keys=True),
            },
            note="Saved prompt overview and editor changes from the forge workspace.",
        )

    async def run_benchmark(self, prompt_ref: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.run_manual_benchmark(note="Manual benchmark from the forge workspace.")

    async def run_full_evaluation(self, prompt_ref: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.run_full_evaluation(note="Full evaluation from the forge workspace.")

    def list_scenarios(self, *, prompt_ref: str | None = None) -> list[ScenarioSuite]:
        if prompt_ref:
            self.ensure_default_scenario(prompt_ref)
        suites = self.scenarios.list_suites()
        if not prompt_ref:
            return suites
        filtered = [
            suite for suite in suites if not suite.linked_prompts or prompt_ref in suite.linked_prompts
        ]
        return filtered or suites

    def ensure_default_scenario(self, prompt_ref: str) -> ScenarioSuite:
        return self.scenarios.ensure_default_suite(
            dataset_path=self.bench_dataset_path or self.dataset_path,
            prompt_ref=prompt_ref,
        )

    def load_scenario(self, suite_id: str) -> ScenarioSuite:
        return self.scenarios.load_suite(suite_id)

    def save_scenario(self, suite: ScenarioSuite) -> Path:
        return self.scenarios.save_suite(suite)

    def create_scenario(
        self,
        suite_id: str,
        *,
        prompt_ref: str | None = None,
        name: str | None = None,
        description: str = "",
    ) -> ScenarioSuite:
        return self.scenarios.create_suite(
            suite_id,
            name=name,
            description=description,
            linked_prompts=[prompt_ref] if prompt_ref else [],
        )

    async def run_scenario_suite(self, prompt_ref: str, suite_id: str, *, repeats: int | None = None) -> ReviewSummary:
        session = await self.ensure_session(prompt_ref)
        suite = self.scenarios.load_suite(suite_id)
        self.set_active_prompt(prompt_ref)
        return await session.run_scenario_suite(suite, repeats=repeats)

    async def run_playground(
        self,
        prompt_ref: str,
        *,
        input_payload: dict[str, object],
        context: str | dict[str, object] | list[object] | None = None,
        samples: int = 1,
        compare_baseline: bool = True,
    ) -> PlaygroundRun:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.run_playground(
            input_payload=input_payload,
            context=context,
            samples=samples,
            compare_baseline=compare_baseline,
        )

    async def record_review_decision(
        self,
        prompt_ref: str,
        *,
        status: str,
        summary: str,
        rationale: str = "",
        review_id: str | None = None,
        suite_id: str | None = None,
    ) -> DecisionRecord:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return session.record_decision(
            status=status,
            summary=summary,
            rationale=rationale,
            review_id=review_id,
            suite_id=suite_id,
        )

    async def promote_to_baseline(
        self,
        prompt_ref: str,
        *,
        summary: str,
        rationale: str = "",
        review_id: str | None = None,
        suite_id: str | None = None,
    ) -> DecisionRecord:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.promote_current_to_baseline(
            summary=summary,
            rationale=rationale,
            review_id=review_id,
            suite_id=suite_id,
        )

    async def list_builder_actions(self, prompt_ref: str) -> list[BuilderAction]:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return session.list_builder_actions()

    async def list_reviews(self, prompt_ref: str) -> list[ReviewSummary]:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return list(session.history.reviews)

    async def list_decisions(self, prompt_ref: str) -> list[DecisionRecord]:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return list(session.history.decisions)

    async def restore_previous(self, prompt_ref: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        previous_revision_id = session.previous_revision_id()
        if previous_revision_id is None:
            raise ValueError("There is no earlier revision to restore.")
        return await session.restore_revision(
            previous_revision_id,
            note=f"Restored previous revision {previous_revision_id}.",
        )

    async def export_prompt(self, prompt_ref: str, version: str) -> Path:
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return session.export_prompt_pack(version)

    async def restore_revision(self, prompt_ref: str, revision_id: str):
        session = await self.ensure_session(prompt_ref)
        self.set_active_prompt(prompt_ref)
        return await session.restore_revision(
            revision_id,
            note=f"Restored revision {revision_id} from the macOS workspace.",
        )

    def current_session(self, prompt_ref: str) -> ForgeSession | None:
        cached = self._sessions.get(prompt_ref)
        if cached is not None:
            return cached

        session_id = self.state.prompt_sessions.get(prompt_ref)
        if not session_id:
            return None
        try:
            manifest = ForgeSession.load_manifest(session_id)
        except Exception:
            return None
        if not self._session_matches_config(manifest):
            return None
        gateway = build_gateway(provider=manifest.provider, judge_provider=manifest.judge_provider)
        session = ForgeSession.load(session_id=session_id, gateway=gateway)
        self._sessions[prompt_ref] = session
        return session

    def _session_matches_config(self, manifest) -> bool:
        return (
            manifest.full_dataset_path == self.dataset_path
            and manifest.benchmark_dataset_path == (self.bench_dataset_path or self.dataset_path)
            and manifest.model == self.model
            and manifest.provider == self.provider
            and manifest.judge_provider == self.judge_provider
            and manifest.agent_model == self.agent_model
        )

    def _load_state(self) -> WorkspaceState:
        path = settings.workspace_state_path
        if not path.exists():
            return WorkspaceState()
        return WorkspaceState.model_validate(json.loads(path.read_text(encoding="utf-8")))

    def _persist_state(self) -> None:
        settings.state_dir.mkdir(parents=True, exist_ok=True)
        settings.workspace_state_path.write_text(
            json.dumps(self.state.model_dump(mode="json"), indent=2, sort_keys=True),
            encoding="utf-8",
        )

    def _prompt_files(self, prompt_root: str | Path) -> list[str]:
        root = Path(prompt_root)
        preferred_order = [
            "prompt.json",
            "system.md",
            "user_template.md",
            "manifest.yaml",
            "variables.schema.json",
        ]
        files = [name for name in preferred_order if (root / name).exists()]
        files.extend(
            child.name
            for child in sorted(root.iterdir(), key=lambda path: path.name.lower())
            if child.is_file() and child.name not in files
        )
        return files
