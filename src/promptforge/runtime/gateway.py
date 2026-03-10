from __future__ import annotations

import asyncio
import json
import os
import shutil
import tempfile
from time import perf_counter
from pathlib import Path
from typing import Any, Protocol

from openai import APIConnectionError, APITimeoutError, AsyncOpenAI, InternalServerError, RateLimitError
from tenacity import AsyncRetrying, retry_if_exception_type, stop_after_attempt, wait_exponential_jitter

from promptforge.agents.prompt_judge.agent import load_judge_instructions
from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput
from promptforge.core.config import settings
from promptforge.core.models import ModelExecutionResult, ProviderName, RunConfig, ScoringConfig
from promptforge.core.openai_client import get_openai_compatible_client


TRANSIENT_ERRORS = (APIConnectionError, APITimeoutError, InternalServerError, RateLimitError, asyncio.TimeoutError)
CODEX_TRANSIENT_MARKERS = (
    "rate limit",
    "timeout",
    "timed out",
    "internal server error",
    "connection error",
    "temporarily unavailable",
)


class CodexTransientError(RuntimeError):
    pass


class CodexExecutionError(RuntimeError):
    pass


def _normalize_codex_json_schema(value: Any) -> Any:
    if isinstance(value, dict):
        normalized = {key: _normalize_codex_json_schema(item) for key, item in value.items()}
        if normalized.get("type") == "object":
            normalized["additionalProperties"] = False
            if "properties" in normalized and isinstance(normalized["properties"], dict):
                normalized["required"] = list(normalized["properties"].keys())
        return normalized
    if isinstance(value, list):
        return [_normalize_codex_json_schema(item) for item in value]
    return value


def _summarize_codex_error(stderr_text: str) -> str:
    for line in stderr_text.splitlines():
        if '"message":' in line:
            return line.strip()
    lines = [line.strip() for line in stderr_text.splitlines() if line.strip()]
    return lines[-1] if lines else "Codex execution failed."


class ModelGateway(Protocol):
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
        ...

    async def judge(
        self,
        *,
        model: str,
        payload: str,
        scoring_config: ScoringConfig,
        timeout_seconds: float,
    ) -> RubricJudgeOutput:
        ...


class OpenAICompatibleGateway:
    def __init__(self, client: AsyncOpenAI, provider: ProviderName) -> None:
        self.client = client
        self.provider = provider
        self.judge_instructions = load_judge_instructions()

    async def _retry(self, operation, *, retries: int):
        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(retries + 1),
            wait=wait_exponential_jitter(initial=1, max=8),
            retry=retry_if_exception_type(TRANSIENT_ERRORS),
            reraise=True,
        ):
            with attempt:
                return await operation()

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
        started = perf_counter()
        warnings: list[str] = []

        request_kwargs: dict[str, Any] = {
            "model": model,
            "instructions": system_prompt,
            "input": user_prompt,
            "max_output_tokens": run_config.max_output_tokens,
            "metadata": {
                "run_id": run_id,
                "case_id": case_id,
                "prompt_version": prompt_version,
                "config_hash": config_hash,
            },
            "prompt_cache_key": f"pf:{prompt_version}:{case_id}:{config_hash}",
            "prompt_cache_retention": "24h",
            "store": False,
            "timeout": run_config.timeout_seconds,
            "user": f"promptforge:{run_id}",
        }
        if run_config.temperature is not None:
            if model in {"gpt-5", "gpt-5-mini", "gpt-5-nano"}:
                warnings.append(f"Model {model} does not reliably accept temperature; request omitted it.")
            else:
                request_kwargs["temperature"] = run_config.temperature
        if run_config.seed is not None:
            warnings.append("Seed recorded for reproducibility but not applied because Responses API has no seed field.")

        response = await self._retry(
            lambda: self.client.responses.create(**request_kwargs),
            retries=run_config.retries,
        )
        latency_ms = int((perf_counter() - started) * 1000)
        usage = response.usage.model_dump(mode="json") if getattr(response, "usage", None) else {}
        return ModelExecutionResult(
            case_id=case_id,
            prompt_version=prompt_version,
            model=model,
            provider=self.provider,
            output_text=getattr(response, "output_text", ""),
            response_id=getattr(response, "id", None),
            usage=usage,
            latency_ms=latency_ms,
            warnings=warnings,
        )

    async def judge(
        self,
        *,
        model: str,
        payload: str,
        scoring_config: ScoringConfig,
        timeout_seconds: float,
    ) -> RubricJudgeOutput:
        request_kwargs: dict[str, Any] = {
            "model": model,
            "instructions": self.judge_instructions,
            "input": payload,
            "text_format": RubricJudgeOutput,
            "max_output_tokens": scoring_config.judge_max_output_tokens,
            "timeout": timeout_seconds,
            "store": False,
            "verbosity": "low",
        }
        if scoring_config.judge_temperature is not None and model not in {"gpt-5", "gpt-5-mini", "gpt-5-nano"}:
            request_kwargs["temperature"] = scoring_config.judge_temperature
        response = await self._retry(
            lambda: self.client.responses.parse(**request_kwargs),
            retries=2,
        )
        if response.output_parsed is None:
            raise RuntimeError("Judge response did not parse into the expected schema.")
        return response.output_parsed


class CodexGateway:
    def __init__(self, *, codex_bin: str, workdir: Path, profile: str | None, sandbox: str, reasoning_effort: str) -> None:
        self.codex_bin = codex_bin
        self.workdir = workdir
        self.profile = profile
        self.sandbox = sandbox
        self.reasoning_effort = reasoning_effort
        self.judge_instructions = load_judge_instructions()
        if shutil.which(codex_bin) is None:
            raise RuntimeError(f"Codex binary not found: {codex_bin}")

    async def _retry(self, operation, *, retries: int):
        async for attempt in AsyncRetrying(
            stop=stop_after_attempt(retries + 1),
            wait=wait_exponential_jitter(initial=1, max=8),
            retry=retry_if_exception_type((CodexTransientError, asyncio.TimeoutError)),
            reraise=True,
        ):
            with attempt:
                return await operation()

    def _base_command(self, model: str) -> list[str]:
        command = [
            self.codex_bin,
            "exec",
            "--skip-git-repo-check",
            "--sandbox",
            self.sandbox,
            "-m",
            model,
            "-c",
            f'model_reasoning_effort="{self.reasoning_effort}"',
            "-C",
            str(self.workdir),
        ]
        if self.profile:
            command.extend(["-p", self.profile])
        return command

    async def _run_codex(
        self,
        *,
        model: str,
        prompt: str,
        timeout_seconds: float,
        output_schema: dict[str, Any] | None = None,
        retries: int = 0,
    ) -> str:
        async def operation() -> str:
            schema_path: str | None = None
            output_path: str | None = None
            try:
                with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as output_handle:
                    output_path = output_handle.name
                if output_schema is not None:
                    with tempfile.NamedTemporaryFile("w", encoding="utf-8", delete=False) as schema_handle:
                        json.dump(output_schema, schema_handle)
                        schema_path = schema_handle.name

                command = self._base_command(model)
                if schema_path:
                    command.extend(["--output-schema", schema_path])
                command.extend(["-o", output_path, "-"])

                process = await asyncio.create_subprocess_exec(
                    *command,
                    stdin=asyncio.subprocess.PIPE,
                    stdout=asyncio.subprocess.PIPE,
                    stderr=asyncio.subprocess.PIPE,
                )
                stdout, stderr = await asyncio.wait_for(
                    process.communicate(prompt.encode("utf-8")),
                    timeout=timeout_seconds + 5,
                )
                stderr_text = stderr.decode("utf-8", errors="replace")
                if process.returncode != 0:
                    lowered = stderr_text.lower()
                    if any(marker in lowered for marker in CODEX_TRANSIENT_MARKERS):
                        raise CodexTransientError(_summarize_codex_error(stderr_text))
                    raise CodexExecutionError(
                        _summarize_codex_error(stderr_text)
                        or stdout.decode("utf-8", errors="replace").strip()
                    )
                if not output_path or not os.path.exists(output_path):
                    raise CodexExecutionError("Codex did not produce an output artifact.")
                return Path(output_path).read_text(encoding="utf-8").strip()
            finally:
                for path in (schema_path, output_path):
                    if path and os.path.exists(path):
                        try:
                            os.unlink(path)
                        except OSError:
                            pass

        return await self._retry(operation, retries=retries)

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
        started = perf_counter()
        warnings: list[str] = []
        if run_config.temperature is not None:
            warnings.append("Codex provider ignores temperature configuration.")
        if run_config.seed is not None:
            warnings.append("Codex provider records seed but cannot apply it.")
        prompt = (
            "You are executing a prompt evaluation case.\n"
            "Do not inspect files, do not run shell commands, and do not use external tools.\n"
            "Return only the final answer content.\n\n"
            f"System instructions:\n{system_prompt}\n\n"
            f"User prompt:\n{user_prompt}\n"
        )
        output_text = await self._run_codex(
            model=model,
            prompt=prompt,
            timeout_seconds=run_config.timeout_seconds,
            retries=run_config.retries,
        )
        latency_ms = int((perf_counter() - started) * 1000)
        return ModelExecutionResult(
            case_id=case_id,
            prompt_version=prompt_version,
            model=model,
            provider="codex",
            output_text=output_text,
            latency_ms=latency_ms,
            warnings=warnings,
        )

    async def judge(
        self,
        *,
        model: str,
        payload: str,
        scoring_config: ScoringConfig,
        timeout_seconds: float,
    ) -> RubricJudgeOutput:
        prompt = (
            f"{self.judge_instructions}\n\n"
            "Score the following payload and return only the schema-defined JSON.\n\n"
            f"{payload}\n"
        )
        if scoring_config.judge_temperature is not None:
            pass
        output_text = await self._run_codex(
            model=model,
            prompt=prompt,
            timeout_seconds=timeout_seconds,
            output_schema=_normalize_codex_json_schema(RubricJudgeOutput.model_json_schema()),
            retries=2,
        )
        return RubricJudgeOutput.model_validate_json(output_text)


class CompositeGateway:
    def __init__(self, generation_gateway: ModelGateway, judge_gateway: ModelGateway) -> None:
        self.generation_gateway = generation_gateway
        self.judge_gateway = judge_gateway

    async def generate(self, **kwargs) -> ModelExecutionResult:
        return await self.generation_gateway.generate(**kwargs)

    async def judge(self, **kwargs) -> RubricJudgeOutput:
        return await self.judge_gateway.judge(**kwargs)


def build_gateway(*, provider: ProviderName, judge_provider: ProviderName) -> ModelGateway:
    generation_gateway: ModelGateway
    if provider == "codex":
        generation_gateway = CodexGateway(
            codex_bin=settings.codex_bin,
            workdir=Path.cwd(),
            profile=settings.codex_profile,
            sandbox=settings.codex_sandbox,
            reasoning_effort=settings.codex_reasoning_effort,
        )
    else:
        generation_gateway = OpenAICompatibleGateway(get_openai_compatible_client(provider), provider)

    if judge_provider == provider:
        return generation_gateway

    if judge_provider == "codex":
        judge_gateway = CodexGateway(
            codex_bin=settings.codex_bin,
            workdir=Path.cwd(),
            profile=settings.codex_profile,
            sandbox=settings.codex_sandbox,
            reasoning_effort=settings.codex_reasoning_effort,
        )
    else:
        judge_gateway = OpenAICompatibleGateway(get_openai_compatible_client(judge_provider), judge_provider)
    return CompositeGateway(generation_gateway, judge_gateway)
