from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import shutil
import subprocess
from pathlib import Path
from typing import Any

from promptforge.core.config import settings
from promptforge.core.models import RunConfig, ScoringConfig
from promptforge.forge.workspace import ForgeWorkspaceService
from promptforge.project import PromptForgeProject


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
    completed = subprocess.run(
        [codex_path, "login", "status"],
        check=False,
        capture_output=True,
        text=True,
    )
    detail = completed.stdout.strip() or completed.stderr.strip() or f"Codex CLI found at {codex_path}"
    return completed.returncode == 0, detail


class PromptForgeHelper:
    def __init__(self, *, project_root: Path) -> None:
        self.project_root = project_root.resolve()
        os.chdir(self.project_root)
        self.project = PromptForgeProject.open_or_create(self.project_root)
        self.workspace = self._build_workspace()

    def _build_workspace(self) -> ForgeWorkspaceService:
        metadata = self.project.metadata
        judge_provider = metadata.preferred_judge_provider or metadata.preferred_provider
        return ForgeWorkspaceService(
            dataset_path=metadata.full_evaluation_dataset,
            bench_dataset_path=metadata.quick_benchmark_dataset,
            model=metadata.preferred_generation_model,
            agent_model="gpt-5-mini",
            provider=metadata.preferred_provider,
            judge_provider=judge_provider,
            run_config=RunConfig(),
            scoring_config=ScoringConfig(judge_model=metadata.preferred_judge_model),
            bench_repeats=1,
            full_repeats=1,
        )

    async def handle(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        if method == "health":
            return {"status": "ok", "project_root": str(self.project_root)}
        if method == "status.get":
            return self._status_payload()
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
            return {"prompt": self.workspace.load_visible_prompt(prompt).model_dump(mode="json")}
        if method == "agent.prepare_edit":
            prompt = self._resolve_prompt_ref(params)
            proposal = await self.workspace.prepare_agent_request(prompt, str(params["request"]))
            return {"proposal": proposal.model_dump(mode="json")}
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
        if method == "events.subscribe":
            return {
                "subscribed": True,
                "note": "Event streaming is reserved for a later helper revision.",
                "events": [],
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
            },
        }

    async def _latest_insights(self, prompt: str) -> dict[str, Any]:
        session = await self.workspace.ensure_session(prompt)
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
