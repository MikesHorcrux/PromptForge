from __future__ import annotations

import asyncio
import platform
import uuid
from collections import defaultdict
from pathlib import Path
from typing import Any

from promptforge import __version__
from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput, RubricTraitScore
from promptforge.core.config import settings
from promptforge.core.hashing import sha256_model
from promptforge.core.logging import configure_logging, log_event
from promptforge.core.models import (
    AggregateScores,
    CachedResponse,
    CaseScore,
    DatasetCase,
    Lockfile,
    ModelExecutionResult,
    PromptPack,
    RunManifest,
    RunRequest,
    ScoresArtifact,
    TraitScore,
    utc_now_iso,
)
from promptforge.datasets.loader import load_dataset
from promptforge.prompts.loader import load_prompt_pack, render_user_prompt, validate_case_inputs
from promptforge.runtime.artifacts import ArtifactStore
from promptforge.runtime.cache import ResponseCache
from promptforge.runtime.compare_service import CompareService
from promptforge.runtime.gateway import ModelGateway
from promptforge.runtime.report_service import render_comparison_report, render_evaluation_report
from promptforge.scoring.judge import RubricJudge
from promptforge.scoring.rules import derive_hard_fail_reasons, evaluate_rule_checks


def generate_run_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


class EvaluationService:
    def __init__(self, gateway: ModelGateway) -> None:
        self.gateway = gateway
        self.logger = configure_logging()
        self.artifacts = ArtifactStore()
        self.cache = ResponseCache(settings.cache_db_path)
        self.judge = RubricJudge(gateway)
        self.compare_service = CompareService()

    async def run(self, request: RunRequest) -> RunManifest:
        prompt_pack = load_prompt_pack(request.prompt_version)
        dataset = load_dataset(request.dataset_path)
        for case in dataset.cases:
            validate_case_inputs(prompt_pack, case)

        config_hash = sha256_model(
            {
                "prompt_version": prompt_pack.manifest.version,
                "prompt_pack_hash": prompt_pack.content_hash,
                "dataset_hash": dataset.content_hash,
                "model": request.model,
                "provider": request.provider,
                "judge_provider": request.judge_provider or request.provider,
                "run_config": request.run_config.model_dump(mode="json"),
                "scoring_config": request.scoring_config.model_dump(mode="json"),
            }
        )
        run_id = generate_run_id("run")
        run_dir = self.artifacts.create_run_dir(run_id)
        manifest = RunManifest(
            run_id=run_id,
            kind="evaluation",
            created_at=utc_now_iso(),
            provider=request.provider,
            judge_provider=request.judge_provider or request.provider,
            prompt_version=prompt_pack.manifest.version,
            model=request.model,
            dataset_path=str(dataset.path),
            config_hash=config_hash,
            output_dir=str(run_dir),
        )
        warnings: list[str] = []
        lockfile = Lockfile(
            run_id=run_id,
            created_at=manifest.created_at,
            provider=request.provider,
            judge_provider=request.judge_provider or request.provider,
            prompt_version=prompt_pack.manifest.version,
            model=request.model,
            dataset_path=str(dataset.path),
            dataset_hash=dataset.content_hash,
            prompt_pack_hash=prompt_pack.content_hash,
            config_hash=config_hash,
            run_config=request.run_config.model_dump(mode="json"),
            scoring_config=request.scoring_config.model_dump(mode="json"),
            python_version=platform.python_version(),
            package_version=__version__,
        )
        self.artifacts.write_manifest(run_dir / "run.json", manifest)
        self.artifacts.write_json(run_dir / "run.lock.json", lockfile.model_dump(mode="json"))

        log_event(
            self.logger,
            "run_started",
            run_id=run_id,
            prompt_version=prompt_pack.manifest.version,
            model=request.model,
            dataset_path=str(dataset.path),
            config_hash=config_hash,
        )
        outputs, rendered_prompts = await self._execute_cases(
            run_id=run_id,
            prompt_pack=prompt_pack,
            cases=dataset.cases,
            model=request.model,
            config_hash=config_hash,
            run_request=request,
        )
        warnings.extend([warning for result in outputs for warning in result.warnings])
        scores = await self._score_outputs(
            run_id=run_id,
            prompt_pack=prompt_pack,
            cases=dataset.cases,
            outputs=outputs,
            rendered_prompts=rendered_prompts,
            run_request=request,
            dataset_hash=dataset.content_hash,
            config_hash=config_hash,
            warnings=warnings,
        )

        comparison_placeholder = {
            "mode": "single",
            "prompt_version": prompt_pack.manifest.version,
            "message": "No comparison requested for this run.",
        }
        report = render_evaluation_report(manifest=manifest, scores=scores)
        lockfile.warnings = scores.warnings
        self.artifacts.write_jsonl(
            run_dir / "outputs.jsonl",
            [result.model_dump(mode="json") for result in outputs],
        )
        self.artifacts.write_json(run_dir / "scores.json", scores.model_dump(mode="json"))
        self.artifacts.write_json(run_dir / "comparison.json", comparison_placeholder)
        self.artifacts.write_json(run_dir / "run.lock.json", lockfile.model_dump(mode="json"))
        self.artifacts.write_text(run_dir / "report.md", report)
        log_event(
            self.logger,
            "run_completed",
            run_id=run_id,
            failed_cases=scores.aggregate.failed_cases,
            hard_fail_count=scores.aggregate.hard_fail_count,
            average_effective_score=scores.aggregate.average_effective_score,
        )
        return manifest

    async def compare(
        self,
        *,
        prompt_a: str,
        prompt_b: str,
        model: str,
        dataset_path: str,
        run_config: Any,
        scoring_config: Any,
        provider: str = "openai",
        judge_provider: str = "openai",
    ) -> RunManifest:
        request_a = RunRequest(
            prompt_version=prompt_a,
            model=model,
            dataset_path=dataset_path,
            run_config=run_config,
            scoring_config=scoring_config,
            provider=provider,
            judge_provider=judge_provider,
        )
        request_b = RunRequest(
            prompt_version=prompt_b,
            model=model,
            dataset_path=dataset_path,
            run_config=run_config,
            scoring_config=scoring_config,
            provider=provider,
            judge_provider=judge_provider,
        )
        manifest_a = await self.run(request_a)
        manifest_b = await self.run(request_b)

        run_dir_a = self.artifacts.resolve_run_dir(manifest_a.run_id)
        run_dir_b = self.artifacts.resolve_run_dir(manifest_b.run_id)
        scores_a = ScoresArtifact.model_validate(self.artifacts.read_json(run_dir_a / "scores.json"))
        scores_b = ScoresArtifact.model_validate(self.artifacts.read_json(run_dir_b / "scores.json"))

        compare_run_id = generate_run_id("cmp")
        compare_dir = self.artifacts.create_run_dir(compare_run_id)
        compare_config_hash = sha256_model(
            {
                "a": scores_a.config_hash,
                "b": scores_b.config_hash,
                "dataset_hash": scores_a.dataset_hash,
                "model": model,
                "provider": provider,
                "judge_provider": judge_provider,
            }
        )
        comparison = self.compare_service.compare(
            run_id=compare_run_id,
            prompt_a=prompt_a,
            prompt_b=prompt_b,
            model=model,
            scores_a=scores_a,
            scores_b=scores_b,
            tie_margin=scoring_config.tie_margin,
        )
        manifest = RunManifest(
            run_id=compare_run_id,
            kind="comparison",
            created_at=utc_now_iso(),
            provider=provider,
            judge_provider=judge_provider,
            compare_a=prompt_a,
            compare_b=prompt_b,
            model=model,
            dataset_path=dataset_path,
            config_hash=compare_config_hash,
            output_dir=str(compare_dir),
            notes=[manifest_a.run_id, manifest_b.run_id],
        )
        self.artifacts.write_manifest(compare_dir / "run.json", manifest)
        report = render_comparison_report(manifest=manifest, comparison=comparison)
        combined_outputs = self._combine_output_rows(run_dir_a / "outputs.jsonl", run_dir_b / "outputs.jsonl")
        combined_scores = {
            "prompt_a": scores_a.model_dump(mode="json"),
            "prompt_b": scores_b.model_dump(mode="json"),
        }
        compare_lockfile = Lockfile(
            run_id=compare_run_id,
            created_at=manifest.created_at,
            provider=provider,
            judge_provider=judge_provider,
            compare_a=prompt_a,
            compare_b=prompt_b,
            model=model,
            dataset_path=dataset_path,
            dataset_hash=scores_a.dataset_hash,
            prompt_pack_hash_a=scores_a.prompt_pack_hash,
            prompt_pack_hash_b=scores_b.prompt_pack_hash,
            config_hash=compare_config_hash,
            run_config=run_config.model_dump(mode="json"),
            scoring_config=scoring_config.model_dump(mode="json"),
            python_version=platform.python_version(),
            package_version=__version__,
            warnings=sorted(set(scores_a.warnings + scores_b.warnings)),
        )
        self.artifacts.write_jsonl(compare_dir / "outputs.jsonl", combined_outputs)
        self.artifacts.write_json(compare_dir / "scores.json", combined_scores)
        self.artifacts.write_json(compare_dir / "comparison.json", comparison.model_dump(mode="json"))
        self.artifacts.write_json(compare_dir / "run.lock.json", compare_lockfile.model_dump(mode="json"))
        self.artifacts.write_text(compare_dir / "report.md", report)
        return manifest

    async def _execute_cases(
        self,
        *,
        run_id: str,
        prompt_pack: PromptPack,
        cases: list[DatasetCase],
        model: str,
        config_hash: str,
        run_request: RunRequest,
    ) -> tuple[list[ModelExecutionResult], dict[str, str]]:
        semaphore = asyncio.Semaphore(run_request.run_config.concurrency)
        stop_event = asyncio.Event()
        rendered_prompts: dict[str, str] = {}
        counters = defaultdict(int)
        lock = asyncio.Lock()

        async def execute_case(case: DatasetCase) -> ModelExecutionResult:
            async with semaphore:
                if stop_event.is_set():
                    return ModelExecutionResult(
                        case_id=case.id,
                        prompt_version=prompt_pack.manifest.version,
                        model=model,
                        provider=run_request.provider,
                        error="skipped after failure threshold was exceeded",
                    )

                rendered_prompt = render_user_prompt(prompt_pack, case)
                rendered_prompts[case.id] = rendered_prompt
                cache_key = sha256_model(
                    {
                        "prompt_version": prompt_pack.manifest.version,
                        "case_id": case.id,
                        "model": model,
                        "config_hash": config_hash,
                    }
                )
                cached = self.cache.get(cache_key) if run_request.run_config.use_cache else None
                if cached:
                    result = ModelExecutionResult(
                        case_id=case.id,
                        prompt_version=prompt_pack.manifest.version,
                        model=model,
                        provider=run_request.provider,
                        output_text=cached.output_text,
                        cached=True,
                        response_id=cached.response_id,
                        usage=cached.usage,
                        warnings=cached.warnings,
                    )
                else:
                    try:
                        result = await self.gateway.generate(
                            prompt_version=prompt_pack.manifest.version,
                            case_id=case.id,
                            model=model,
                            system_prompt=prompt_pack.system_prompt,
                            user_prompt=rendered_prompt,
                            run_id=run_id,
                            config_hash=config_hash,
                            run_config=run_request.run_config,
                        )
                        if run_request.run_config.use_cache:
                            self.cache.set(
                                CachedResponse(
                                    key=cache_key,
                                    prompt_version=prompt_pack.manifest.version,
                                    case_id=case.id,
                                    model=model,
                                    config_hash=config_hash,
                                    output_text=result.output_text or "",
                                    response_id=result.response_id,
                                    usage=result.usage,
                                    warnings=result.warnings,
                                )
                            )
                    except Exception as exc:
                        result = ModelExecutionResult(
                            case_id=case.id,
                            prompt_version=prompt_pack.manifest.version,
                            model=model,
                            provider=run_request.provider,
                            error=str(exc),
                        )

                async with lock:
                    counters["processed"] += 1
                    if result.error:
                        counters["failed"] += 1
                    failure_rate = counters["failed"] / counters["processed"]
                    if failure_rate > run_request.run_config.failure_threshold:
                        stop_event.set()
                log_event(
                    self.logger,
                    "case_executed",
                    run_id=run_id,
                    case_id=case.id,
                    cached=result.cached,
                    error=result.error,
                )
                return result

        results = await asyncio.gather(*(execute_case(case) for case in cases))
        return results, rendered_prompts

    async def _score_outputs(
        self,
        *,
        run_id: str,
        prompt_pack: PromptPack,
        cases: list[DatasetCase],
        outputs: list[ModelExecutionResult],
        rendered_prompts: dict[str, str],
        run_request: RunRequest,
        dataset_hash: str,
        config_hash: str,
        warnings: list[str],
    ) -> ScoresArtifact:
        outputs_by_id = {output.case_id: output for output in outputs}
        case_scores: list[CaseScore] = []
        cached_cases = sum(1 for output in outputs if output.cached)
        failed_cases = sum(1 for output in outputs if output.error)

        for case in cases:
            output = outputs_by_id[case.id]
            if output.error or not output.output_text:
                trait_scores = {
                    trait: TraitScore(score=0, reason="No output available for scoring.", evidence=[])
                    for trait in run_request.scoring_config.rubric_weights.keys()
                }
                case_scores.append(
                    CaseScore(
                        case_id=case.id,
                        hard_fail=True,
                        hard_fail_reasons=[output.error or "missing model output"],
                        rule_checks=evaluate_rule_checks(
                            output_text="",
                            case=case,
                            prompt_pack=prompt_pack,
                            hard_fail_rules=run_request.scoring_config.hard_fail_rules,
                        ),
                        trait_scores=trait_scores,
                        raw_weighted_score=0.0,
                        effective_weighted_score=0.0,
                        normalized_score=0.0,
                        summary="No score available because execution failed.",
                    )
                )
                continue

            rule_checks = evaluate_rule_checks(
                output_text=output.output_text,
                case=case,
                prompt_pack=prompt_pack,
                hard_fail_rules=run_request.scoring_config.hard_fail_rules,
            )
            hard_fail_reasons = derive_hard_fail_reasons(rule_checks, run_request.scoring_config.hard_fail_rules)
            try:
                judge_output = await self.judge.score(
                    prompt_pack=prompt_pack,
                    case=case,
                    rendered_prompt=rendered_prompts[case.id],
                    output_text=output.output_text,
                    scoring_config=run_request.scoring_config,
                    timeout_seconds=run_request.run_config.timeout_seconds,
                )
            except Exception as exc:
                warnings.append(f"Judge failed for case {case.id}: {exc}")
                judge_output = self._fallback_judge_output(str(exc), rule_checks.format_score)
                hard_fail_reasons.append(f"judge failure: {exc}")

            trait_scores = self._merge_trait_scores(judge_output, rule_checks.format_score)
            raw_weighted_score = round(
                sum(
                    trait_scores[trait].score * weight
                    for trait, weight in run_request.scoring_config.rubric_weights.items()
                ),
                4,
            )
            effective_weighted_score = 0.0 if hard_fail_reasons else raw_weighted_score
            normalized_score = round((effective_weighted_score / 5) * 100, 2)
            case_scores.append(
                CaseScore(
                    case_id=case.id,
                    hard_fail=bool(hard_fail_reasons),
                    hard_fail_reasons=hard_fail_reasons,
                    rule_checks=rule_checks,
                    trait_scores=trait_scores,
                    raw_weighted_score=raw_weighted_score,
                    effective_weighted_score=effective_weighted_score,
                    normalized_score=normalized_score,
                    summary=judge_output.summary,
                )
            )

        hard_fail_count = sum(1 for case in case_scores if case.hard_fail)
        total_cases = len(case_scores)
        trait_averages = {
            trait: round(sum(case.trait_scores[trait].score for case in case_scores) / total_cases, 4)
            for trait in run_request.scoring_config.rubric_weights.keys()
        }
        aggregate = AggregateScores(
            total_cases=total_cases,
            completed_cases=total_cases - failed_cases,
            cached_cases=cached_cases,
            failed_cases=failed_cases,
            hard_fail_count=hard_fail_count,
            hard_fail_rate=round(hard_fail_count / max(1, total_cases), 4),
            average_raw_score=round(sum(case.raw_weighted_score for case in case_scores) / total_cases, 4),
            average_effective_score=round(sum(case.effective_weighted_score for case in case_scores) / total_cases, 4),
            average_normalized_score=round(sum(case.normalized_score for case in case_scores) / total_cases, 2),
            trait_averages=trait_averages,
        )
        return ScoresArtifact(
            run_id=run_id,
            created_at=utc_now_iso(),
            prompt_version=prompt_pack.manifest.version,
            model=run_request.model,
            config_hash=config_hash,
            dataset_hash=dataset_hash,
            prompt_pack_hash=prompt_pack.content_hash,
            aggregate=aggregate,
            cases=case_scores,
            warnings=sorted(set(warnings)),
        )

    def _fallback_judge_output(self, error: str, format_score: float) -> RubricJudgeOutput:
        rounded_format = max(0, min(5, int(round(format_score))))
        return RubricJudgeOutput(
            instruction_adherence=RubricTraitScore(score=0, reason=f"Judge unavailable: {error}", evidence=[]),
            format_compliance=RubricTraitScore(score=rounded_format, reason="Rule-based fallback score.", evidence=[]),
            clarity_conciseness=RubricTraitScore(score=0, reason=f"Judge unavailable: {error}", evidence=[]),
            domain_relevance=RubricTraitScore(score=0, reason=f"Judge unavailable: {error}", evidence=[]),
            tone_alignment=RubricTraitScore(score=0, reason=f"Judge unavailable: {error}", evidence=[]),
            summary=f"Rule-only fallback used because the judge failed: {error}",
            failure_signals=[error],
        )

    def _merge_trait_scores(self, judge_output: RubricJudgeOutput, format_score: float) -> dict[str, TraitScore]:
        trait_scores = {
            "instruction_adherence": TraitScore.model_validate(judge_output.instruction_adherence.model_dump()),
            "format_compliance": TraitScore.model_validate(judge_output.format_compliance.model_dump()),
            "clarity_conciseness": TraitScore.model_validate(judge_output.clarity_conciseness.model_dump()),
            "domain_relevance": TraitScore.model_validate(judge_output.domain_relevance.model_dump()),
            "tone_alignment": TraitScore.model_validate(judge_output.tone_alignment.model_dump()),
        }
        trait_scores["format_compliance"] = TraitScore(
            score=max(0, min(5, int(round(min(trait_scores["format_compliance"].score, format_score))))),
            reason=f"{trait_scores['format_compliance'].reason} Rule score: {format_score:.2f}.",
            evidence=trait_scores["format_compliance"].evidence,
        )
        return trait_scores

    def _combine_output_rows(self, path_a: Path, path_b: Path) -> list[dict[str, Any]]:
        rows_a = self._read_jsonl(path_a)
        rows_b = self._read_jsonl(path_b)
        rows_b_by_id = {row["case_id"]: row for row in rows_b}
        combined = []
        for row in rows_a:
            combined.append(
                {
                    "case_id": row["case_id"],
                    "a": row,
                    "b": rows_b_by_id.get(row["case_id"]),
                }
            )
        return combined

    def _read_jsonl(self, path: Path) -> list[dict[str, Any]]:
        return self.artifacts.read_jsonl(path)
