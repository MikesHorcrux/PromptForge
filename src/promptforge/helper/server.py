from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import shutil
import subprocess
from collections import deque
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from promptforge.core.config import settings
from promptforge.core.models import RunConfig, ScoringConfig
from promptforge.forge.workspace import ForgeWorkspaceService
from promptforge.project import PromptForgeProject
from promptforge.scenarios.models import ScenarioSuite


class HelperEventStream:
    def __init__(self, *, backlog_limit: int = 256) -> None:
        self._condition = asyncio.Condition()
        self._backlog: deque[dict[str, Any]] = deque(maxlen=backlog_limit)
        self._sequence = 0

    async def publish(self, event_type: str, **payload: Any) -> dict[str, Any]:
        async with self._condition:
            self._sequence += 1
            event = {
                "sequence": self._sequence,
                "type": event_type,
                "timestamp": _utc_now(),
                "payload": payload,
            }
            self._backlog.append(event)
            self._condition.notify_all()
            return event

    async def subscribe(
        self,
        *,
        after: int = 0,
        timeout_seconds: float = 30.0,
        limit: int = 50,
    ) -> dict[str, Any]:
        timeout_seconds = max(0.0, timeout_seconds)
        limit = max(1, min(limit, 200))

        async with self._condition:
            if not self._events_after(after):
                try:
                    await asyncio.wait_for(
                        self._condition.wait_for(lambda: bool(self._events_after(after))),
                        timeout=timeout_seconds,
                    )
                except TimeoutError:
                    pass
            events = self._events_after(after)[-limit:]
            cursor = events[-1]["sequence"] if events else after
            return {
                "subscribed": True,
                "cursor": cursor,
                "events": events,
            }

    def _events_after(self, after: int) -> list[dict[str, Any]]:
        return [event for event in self._backlog if event["sequence"] > after]


def _utc_now() -> str:
    return datetime.now(UTC).isoformat()


def _provider_auth_status(provider: str) -> tuple[bool, str]:
    if provider == "openai":
        return bool(settings.openai_api_key), (
            "OPENAI_API_KEY is set" if settings.openai_api_key else "OPENAI_API_KEY is missing"
        )
    if provider == "openrouter":
        return bool(settings.openrouter_api_key), (
            "OPENROUTER_API_KEY is set" if settings.openrouter_api_key else "OPENROUTER_API_KEY is missing"
        )
    codex_path = settings.codex_bin
    if shutil.which(codex_path) is None:
        return False, f"Codex CLI not found: {codex_path}"
    try:
        completed = subprocess.run(
            [codex_path, "login", "status"],
            check=False,
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception as exc:
        return False, f"Codex status unavailable: {exc}"
    detail = completed.stdout.strip() or completed.stderr.strip() or f"Codex CLI found at {codex_path}"
    return completed.returncode == 0, detail


class PromptForgeHelper:
    def __init__(self, *, project_root: Path) -> None:
        self.project_root = project_root.resolve()
        os.chdir(self.project_root)
        self.project = PromptForgeProject.open_or_create(self.project_root)
        self.workspace = self._build_workspace()
        self.events = HelperEventStream()

    def _build_workspace(self) -> ForgeWorkspaceService:
        metadata = self.project.metadata
        judge_provider = metadata.preferred_judge_provider or metadata.preferred_provider
        return ForgeWorkspaceService(
            dataset_path=metadata.full_evaluation_dataset,
            bench_dataset_path=metadata.quick_benchmark_dataset,
            model=metadata.preferred_generation_model,
            agent_model=metadata.preferred_agent_model,
            provider=metadata.preferred_provider,
            judge_provider=judge_provider,
            run_config=RunConfig(),
            scoring_config=ScoringConfig(judge_model=metadata.preferred_judge_model),
            bench_repeats=metadata.quick_benchmark_repeats,
            full_repeats=metadata.full_evaluation_repeats,
        )

    async def handle(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if method == "events.subscribe":
            return await self.events.subscribe(
                after=int(params.get("after", 0) or 0),
                timeout_seconds=float(params.get("timeout_seconds", 30.0) or 0.0),
                limit=int(params.get("limit", 50) or 50),
            )

        await self.events.publish("request.started", method=method, params=params)
        try:
            result = await self._handle(method, params)
        except Exception as exc:
            await self.events.publish(
                "request.failed",
                method=method,
                params=params,
                error=str(exc),
            )
            raise
        await self.events.publish("request.completed", method=method, params=params, result=result)
        return result

    async def _handle(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if method == "health":
            return {"status": "ok", "project_root": str(self.project_root)}
        if method == "status.get":
            return self._status_payload()
        if method == "settings.get":
            return self._settings_payload()
        if method == "settings.update":
            metadata = self.project.metadata
            if "name" in params:
                metadata.name = str(params["name"]).strip() or metadata.name
            if "quick_benchmark_dataset" in params:
                metadata.quick_benchmark_dataset = str(params["quick_benchmark_dataset"]).strip() or metadata.quick_benchmark_dataset
            if "full_evaluation_dataset" in params:
                metadata.full_evaluation_dataset = str(params["full_evaluation_dataset"]).strip() or metadata.full_evaluation_dataset
            if "quick_benchmark_repeats" in params:
                metadata.quick_benchmark_repeats = max(1, int(params["quick_benchmark_repeats"]))
            if "full_evaluation_repeats" in params:
                metadata.full_evaluation_repeats = max(1, int(params["full_evaluation_repeats"]))
            if "preferred_provider" in params:
                metadata.preferred_provider = str(params["preferred_provider"])
            if "preferred_judge_provider" in params:
                judge_provider = str(params["preferred_judge_provider"]).strip()
                metadata.preferred_judge_provider = judge_provider or metadata.preferred_provider
            if "preferred_generation_model" in params:
                metadata.preferred_generation_model = str(params["preferred_generation_model"]).strip() or metadata.preferred_generation_model
            if "preferred_judge_model" in params:
                metadata.preferred_judge_model = str(params["preferred_judge_model"]).strip() or metadata.preferred_judge_model
            if "preferred_agent_model" in params:
                metadata.preferred_agent_model = str(params["preferred_agent_model"]).strip() or metadata.preferred_agent_model
            if "builder_permission_mode" in params:
                metadata.builder_permission_mode = str(params["builder_permission_mode"]).strip() or metadata.builder_permission_mode
            if "builder_research_policy" in params:
                metadata.builder_research_policy = str(params["builder_research_policy"]).strip() or metadata.builder_research_policy
            self.project.save()
            self.workspace = self._build_workspace()
            return self._settings_payload()
        if method == "project.open":
            return self._project_payload()
        if method == "project.create":
            name = params.get("name")
            if name:
                self.project.metadata.name = str(name)
                self.project.save()
            return self._project_payload()
        if method == "prompts.list":
            return {"prompts": [prompt.model_dump(mode="json") for prompt in self.workspace.list_prompts()]}
        if method == "prompts.create":
            prompt = str(params["prompt"])
            destination = self.workspace.create_prompt(
                prompt,
                from_prompt=params.get("from_prompt"),
                name=params.get("name"),
            )
            self.workspace.set_active_prompt(prompt)
            return {"created": str(destination), "prompt": prompt}
        if method == "prompts.clone":
            source = str(params["source"])
            name = str(params["name"])
            destination = self.workspace.create_prompt(
                name,
                from_prompt=source,
                name=params.get("display_name"),
            )
            self.workspace.set_active_prompt(name)
            return {"created": str(destination), "prompt": name}
        if method == "prompts.export":
            prompt = self._resolve_prompt_ref(params)
            destination = await self.workspace.export_prompt(prompt, str(params["name"]))
            return {"exported": str(destination)}
        if method == "prompt.get":
            prompt = self._resolve_prompt_ref(params)
            self.workspace.set_active_prompt(prompt)
            self.workspace.ensure_default_scenario(prompt)
            return {"prompt": self.workspace.load_visible_prompt(prompt).model_dump(mode="json")}
        if method == "prompt.save":
            prompt = self._resolve_prompt_ref(params)
            revision = await self.workspace.save_prompt_workspace(
                prompt,
                system_prompt=str(params["system_prompt"]),
                user_template=str(params["user_template"]),
                purpose=str(params.get("purpose", "")),
                expected_behavior=str(params.get("expected_behavior", "")),
                success_criteria=str(params.get("success_criteria", "")),
                baseline_prompt_ref=str(params.get("baseline_prompt_ref", "")),
                primary_scenario_suites=[str(item) for item in params.get("primary_scenario_suites", [])],
                owner=str(params.get("owner", "")),
                audience=str(params.get("audience", "")),
                release_notes=str(params.get("release_notes", "")),
                builder_agent_model=str(params.get("builder_agent_model", self.project.metadata.preferred_agent_model)),
                builder_permission_mode=str(params.get("builder_permission_mode", self.project.metadata.builder_permission_mode)),
                research_policy=str(params.get("research_policy", self.project.metadata.builder_research_policy)),
            )
            return {
                "revision": revision.model_dump(mode="json"),
                "prompt": self.workspace.load_visible_prompt(prompt).model_dump(mode="json"),
                "insights": await self._latest_insights(prompt),
            }
        if method == "scenarios.list":
            prompt = params.get("prompt")
            suites = self.workspace.list_scenarios(prompt_ref=str(prompt) if prompt else None)
            return {"suites": [suite.model_dump(mode="json") for suite in suites]}
        if method == "scenarios.get":
            suite = self.workspace.load_scenario(str(params["suite_id"]))
            return {"suite": suite.model_dump(mode="json")}
        if method == "scenarios.create":
            prompt = params.get("prompt")
            suite = self.workspace.create_scenario(
                str(params["suite_id"]),
                prompt_ref=str(prompt) if prompt else None,
                name=str(params.get("name") or params["suite_id"]),
                description=str(params.get("description", "")),
            )
            return {"suite": suite.model_dump(mode="json")}
        if method == "scenarios.save":
            suite_model = ScenarioSuite.model_validate(params["suite"])
            suite_path = self.workspace.save_scenario(suite_model)
            saved = self.workspace.load_scenario(Path(suite_path).stem)
            return {"suite": saved.model_dump(mode="json")}
        if method == "playground.run":
            prompt = self._resolve_prompt_ref(params)
            run = await self.workspace.run_playground(
                prompt,
                input_payload=dict(params.get("input_payload") or {}),
                context=params.get("context"),
                samples=max(1, int(params.get("samples", 1))),
                compare_baseline=bool(params.get("compare_baseline", True)),
            )
            return {"playground": run.model_dump(mode="json")}
        if method == "review.run_suite":
            prompt = self._resolve_prompt_ref(params)
            review = await self.workspace.run_scenario_suite(
                prompt,
                str(params["suite_id"]),
                repeats=int(params["repeats"]) if params.get("repeats") is not None else None,
            )
            return {"review": review.model_dump(mode="json")}
        if method == "review.latest":
            prompt = self._resolve_prompt_ref(params)
            reviews = await self.workspace.list_reviews(prompt)
            return {"reviews": [review.model_dump(mode="json") for review in reviews]}
        if method == "builder.actions":
            prompt = self._resolve_prompt_ref(params)
            actions = await self.workspace.list_builder_actions(prompt)
            return {"actions": [action.model_dump(mode="json") for action in actions]}
        if method == "decisions.list":
            prompt = self._resolve_prompt_ref(params)
            decisions = await self.workspace.list_decisions(prompt)
            return {"decisions": [decision.model_dump(mode="json") for decision in decisions]}
        if method == "decisions.record":
            prompt = self._resolve_prompt_ref(params)
            decision = await self.workspace.record_review_decision(
                prompt,
                status=str(params["status"]),
                summary=str(params["summary"]),
                rationale=str(params.get("rationale", "")),
                review_id=str(params.get("review_id")) if params.get("review_id") else None,
                suite_id=str(params.get("suite_id")) if params.get("suite_id") else None,
            )
            return {"decision": decision.model_dump(mode="json")}
        if method == "decisions.promote":
            prompt = self._resolve_prompt_ref(params)
            decision = await self.workspace.promote_to_baseline(
                prompt,
                summary=str(params["summary"]),
                rationale=str(params.get("rationale", "")),
                review_id=str(params.get("review_id")) if params.get("review_id") else None,
                suite_id=str(params.get("suite_id")) if params.get("suite_id") else None,
            )
            return {"decision": decision.model_dump(mode="json"), "insights": await self._latest_insights(prompt)}
        if method == "agent.prepare_edit":
            prompt = self._resolve_prompt_ref(params)
            proposal = await self.workspace.prepare_agent_request(prompt, str(params["request"]))
            return {"proposal": proposal.model_dump(mode="json")}
        if method == "coach.reply":
            prompt = self._resolve_prompt_ref(params)
            reply = await self.workspace.coach(prompt, str(params["request"]))
            return {"reply": reply}
        if method == "agent.chat":
            prompt = self._resolve_prompt_ref(params)
            chat = await self.workspace.agent_chat(prompt, str(params["request"]))
            payload: dict[str, Any] = {
                "chat": chat.model_dump(mode="json"),
            }
            if chat.proposal is not None:
                payload["proposal"] = chat.proposal.model_dump(mode="json")
            if chat.revision is not None:
                payload["revision"] = chat.revision.model_dump(mode="json")
                payload["insights"] = await self._latest_insights(prompt)
            return payload
        if method == "agent.apply_prepared_edit":
            prompt = self._resolve_prompt_ref(params)
            result = await self.workspace.apply_prepared_edit(prompt, str(params["proposal_id"]))
            return {
                "result": result.model_dump(mode="json"),
                "insights": await self._latest_insights(prompt),
            }
        if method == "agent.discard_prepared_edit":
            prompt = self._resolve_prompt_ref(params)
            await self.workspace.discard_prepared_edit(prompt, str(params["proposal_id"]))
            return {"discarded": params["proposal_id"]}
        if method == "bench.run_quick":
            prompt = self._resolve_prompt_ref(params)
            revision = await self.workspace.run_benchmark(prompt)
            return {"revision": revision.model_dump(mode="json"), "insights": await self._latest_insights(prompt)}
        if method == "eval.run_full":
            prompt = self._resolve_prompt_ref(params)
            revision = await self.workspace.run_full_evaluation(prompt)
            return {"revision": revision.model_dump(mode="json"), "insights": await self._latest_insights(prompt)}
        if method == "revisions.list":
            prompt = self._resolve_prompt_ref(params)
            session = await self.workspace.ensure_session(prompt)
            return {"revisions": [revision.model_dump(mode="json") for revision in session.history.revisions]}
        if method == "benchmarks.history":
            prompt = self._resolve_prompt_ref(params)
            session = self.workspace.current_session(prompt)
            if session is None:
                return {"history": [], "trend": []}
            entries: list[dict[str, Any]] = []
            for revision in session.history.revisions:
                benchmark = revision.benchmark
                full_evaluation = revision.full_evaluation
                entries.append(
                    {
                        "revision_id": revision.revision_id,
                        "created_at": revision.created_at,
                        "source": revision.source,
                        "note": revision.note,
                        "score": benchmark.mean_effective_score if benchmark else None,
                        "score_delta_vs_baseline": revision.benchmark_vs_baseline.mean_score_delta if revision.benchmark_vs_baseline else None,
                        "pass_rate": benchmark.pass_rate if benchmark else None,
                        "hard_fail_rate": benchmark.mean_hard_fail_rate if benchmark else None,
                        "full_score": full_evaluation.mean_effective_score if full_evaluation else None,
                    }
                )
            return {
                "history": entries,
                "trend": [
                    {"revision_id": revision_id, "score": score}
                    for revision_id, score in session.score_trend_points()
                ],
            }
        if method == "revisions.restore":
            prompt = self._resolve_prompt_ref(params)
            revision = await self.workspace.restore_revision(prompt, str(params["revision_id"]))
            return {"revision": revision.model_dump(mode="json"), "insights": await self._latest_insights(prompt)}
        if method == "insights.latest":
            prompt = self._resolve_prompt_ref(params)
            return {"insights": await self._latest_insights(prompt)}
        if method == "insights.failures":
            prompt = self._resolve_prompt_ref(params)
            session = await self.workspace.ensure_session(prompt)
            return {
                "failures": [
                    {
                        "case_id": row[0],
                        "score": row[1],
                        "hard_fail_rate": row[2],
                        "reasons": row[3],
                        "summary": row[4],
                    }
                    for row in session.benchmark_case_rows(limit=None, failures_only=True)
                ]
            }
        raise ValueError(f"Unsupported method: {method}")

    def _resolve_prompt_ref(self, params: dict[str, Any]) -> str:
        prompt = params.get("prompt") or self.project.metadata.last_opened_prompt
        if prompt:
            return str(prompt)
        prompts = self.workspace.list_prompts()
        if not prompts:
            raise ValueError("No prompt packs are available in this project.")
        return prompts[0].version

    def _project_payload(self) -> dict[str, Any]:
        return {
            "root": str(self.project_root),
            "metadata": self.project.metadata.model_dump(mode="json"),
        }

    def _status_payload(self) -> dict[str, Any]:
        prompt = self.project.metadata.last_opened_prompt
        session_id = self.workspace.state.prompt_sessions.get(prompt or "", "")
        provider_ok, provider_detail = _provider_auth_status(self.project.metadata.preferred_provider)
        judge_provider = self.project.metadata.preferred_judge_provider or self.project.metadata.preferred_provider
        judge_ok, judge_detail = _provider_auth_status(judge_provider)
        return {
            "project": self._project_payload(),
            "active_prompt": prompt,
            "active_session": session_id or None,
            "auth": {
                "provider": {
                    "name": self.project.metadata.preferred_provider,
                    "ready": provider_ok,
                    "detail": provider_detail,
                },
                "judge": {
                    "name": judge_provider,
                    "ready": judge_ok,
                    "detail": judge_detail,
                },
                "openai_key_set": bool(settings.openai_api_key),
                "openrouter_key_set": bool(settings.openrouter_api_key),
                "connections": self._connection_payload(),
            },
        }

    def _settings_payload(self) -> dict[str, Any]:
        metadata = self.project.metadata
        return {
            "project": self._project_payload(),
            "settings": {
                "name": metadata.name,
                "quick_benchmark_dataset": metadata.quick_benchmark_dataset,
                "full_evaluation_dataset": metadata.full_evaluation_dataset,
                "quick_benchmark_repeats": metadata.quick_benchmark_repeats,
                "full_evaluation_repeats": metadata.full_evaluation_repeats,
                "preferred_provider": metadata.preferred_provider,
                "preferred_judge_provider": metadata.preferred_judge_provider or metadata.preferred_provider,
                "preferred_generation_model": metadata.preferred_generation_model,
                "preferred_judge_model": metadata.preferred_judge_model,
                "preferred_agent_model": metadata.preferred_agent_model,
                "builder_permission_mode": metadata.builder_permission_mode,
                "builder_research_policy": metadata.builder_research_policy,
            },
            "auth": self._status_payload()["auth"],
        }

    def _connection_payload(self) -> dict[str, Any]:
        connections: dict[str, Any] = {}
        for provider in ("openai", "openrouter", "codex"):
            ready, detail = _provider_auth_status(provider)
            connections[provider] = {
                "name": provider,
                "ready": ready,
                "detail": detail,
            }
        return connections

    async def _latest_insights(self, prompt: str) -> dict[str, Any]:
        session = self.workspace.current_session(prompt)
        if session is None:
            return {
                "session_id": None,
                "latest_revision_id": None,
                "status_rows": [],
                "diff_rows": [],
                "weak_cases": [],
                "failures": [],
                "pending_edits": [],
                "builder_actions": [],
                "reviews": [],
                "decisions": [],
            }
        latest = session.latest_revision
        return {
            "session_id": session.manifest.session_id,
            "latest_revision_id": latest.revision_id if latest else None,
            "status_rows": session.status_rows(),
            "diff_rows": session.latest_diff_rows(reference="baseline"),
            "weak_cases": [
                {
                    "case_id": row[0],
                    "score": row[1],
                    "hard_fail_rate": row[2],
                    "reasons": row[3],
                    "summary": row[4],
                }
                for row in session.benchmark_case_rows(limit=5, failures_only=False)
            ],
            "failures": [
                {
                    "case_id": row[0],
                    "score": row[1],
                    "hard_fail_rate": row[2],
                    "reasons": row[3],
                    "summary": row[4],
                }
                for row in session.benchmark_case_rows(limit=5, failures_only=True)
            ],
            "pending_edits": [edit.model_dump(mode="json") for edit in session.list_pending_edits()],
            "builder_actions": [action.model_dump(mode="json") for action in session.list_builder_actions(limit=12)],
            "reviews": [review.model_dump(mode="json") for review in session.history.reviews[-5:]],
            "decisions": [decision.model_dump(mode="json") for decision in session.history.decisions[-5:]],
        }


async def _handle_client(
    reader: asyncio.StreamReader,
    writer: asyncio.StreamWriter,
    *,
    helper: PromptForgeHelper,
    token: str,
) -> None:
    try:
        while not reader.at_eof():
            raw_line = await reader.readline()
            if not raw_line:
                break
            request = json.loads(raw_line.decode("utf-8"))
            request_id = request.get("id")
            try:
                if request.get("token") != token:
                    raise PermissionError("Invalid helper session token.")
                result = await helper.handle(request["method"], request.get("params", {}))
                payload = {"id": request_id, "ok": True, "result": result}
            except Exception as exc:  # noqa: BLE001
                payload = {"id": request_id, "ok": False, "error": str(exc)}
            writer.write((json.dumps(payload) + "\n").encode("utf-8"))
            await writer.drain()
    finally:
        writer.close()
        await writer.wait_closed()


async def _serve(socket_path: Path, helper: PromptForgeHelper, token: str) -> None:
    if socket_path.exists():
        socket_path.unlink()
    server = await asyncio.start_unix_server(
        lambda reader, writer: _handle_client(reader, writer, helper=helper, token=token),
        path=str(socket_path),
    )
    stop_event = asyncio.Event()

    def _request_stop() -> None:
        stop_event.set()

    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            loop.add_signal_handler(sig, _request_stop)
        except NotImplementedError:
            pass

    async with server:
        await stop_event.wait()

    if socket_path.exists():
        socket_path.unlink()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="PromptForge local helper")
    parser.add_argument("--project", required=True, help="PromptForge project root")
    parser.add_argument("--socket", required=True, help="Unix socket path")
    parser.add_argument("--token", required=True, help="Session token expected from the client")
    args = parser.parse_args(argv)

    helper = PromptForgeHelper(project_root=Path(args.project))
    asyncio.run(_serve(Path(args.socket), helper, args.token))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
