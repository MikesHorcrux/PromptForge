from __future__ import annotations

import argparse
import asyncio
import platform
import shutil
import sys
from pathlib import Path

import yaml

from promptforge.core.config import settings
from promptforge.core.models import ProviderName, RunConfig, RunRequest, ScoringConfig
from promptforge.datasets.loader import load_dataset
from promptforge.prompts.loader import load_prompt_pack
from promptforge.runtime.artifacts import ArtifactStore
from promptforge.runtime.gateway import build_gateway
from promptforge.runtime.report_service import render_comparison_report, render_evaluation_report
from promptforge.runtime.run_service import EvaluationService
from promptforge.core.models import ComparisonArtifact, RunManifest, ScoresArtifact


def _load_scoring_config(path: str | None) -> ScoringConfig:
    if not path:
        return ScoringConfig(judge_model=settings.openai_judge_model)
    payload = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    return ScoringConfig.model_validate(payload)


def _build_run_config(args: argparse.Namespace) -> RunConfig:
    return RunConfig(
        temperature=args.temperature,
        max_output_tokens=args.max_tokens,
        seed=args.seed,
        retries=args.retries,
        timeout_seconds=args.timeout,
        concurrency=args.concurrency,
        failure_threshold=args.failure_threshold,
    )


def _resolve_judge_provider(args: argparse.Namespace) -> ProviderName:
    return args.judge_provider or args.provider


def _build_provider_service(args: argparse.Namespace) -> EvaluationService:
    judge_provider = _resolve_judge_provider(args)
    return EvaluationService(build_gateway(provider=args.provider, judge_provider=judge_provider))


async def _run_command(args: argparse.Namespace) -> int:
    scoring_config = _load_scoring_config(args.scoring_config)
    run_config = _build_run_config(args)
    judge_provider = _resolve_judge_provider(args)
    manifest = await _build_provider_service(args).run(
        RunRequest(
            prompt_version=args.prompt,
            model=args.model,
            dataset_path=args.dataset,
            run_config=run_config,
            scoring_config=scoring_config,
            provider=args.provider,
            judge_provider=judge_provider,
        )
    )
    print(f"run_id={manifest.run_id}")
    print(f"artifacts={manifest.output_dir}")
    return 0


async def _compare_command(args: argparse.Namespace) -> int:
    scoring_config = _load_scoring_config(args.scoring_config)
    run_config = _build_run_config(args)
    manifest = await _build_provider_service(args).compare(
        prompt_a=args.a,
        prompt_b=args.b,
        model=args.model,
        dataset_path=args.dataset,
        run_config=run_config,
        scoring_config=scoring_config,
        provider=args.provider,
        judge_provider=_resolve_judge_provider(args),
    )
    print(f"run_id={manifest.run_id}")
    print(f"artifacts={manifest.output_dir}")
    return 0


def _report_command(args: argparse.Namespace) -> int:
    store = ArtifactStore()
    run_dir = store.resolve_run_dir(args.run)
    manifest = RunManifest.model_validate(store.read_json(run_dir / "run.json"))
    report_path = run_dir / "report.md"
    if not report_path.exists():
        if manifest.kind == "evaluation":
            scores = ScoresArtifact.model_validate(store.read_json(run_dir / "scores.json"))
            report = render_evaluation_report(manifest=manifest, scores=scores)
        else:
            comparison = ComparisonArtifact.model_validate(store.read_json(run_dir / "comparison.json"))
            report = render_comparison_report(manifest=manifest, comparison=comparison)
        store.write_text(report_path, report)
    if args.print:
        print(report_path.read_text(encoding="utf-8"))
    else:
        print(str(report_path))
    return 0


async def _doctor_command(args: argparse.Namespace) -> int:
    checks: list[tuple[str, bool, str]] = []
    python_ok = sys.version_info >= (3, 11)
    checks.append(("python", python_ok, platform.python_version()))

    judge_provider = _resolve_judge_provider(args)
    auth_ok, auth_detail = _provider_auth_status(args.provider)
    checks.append((f"{args.provider}_auth", auth_ok, auth_detail))
    if judge_provider != args.provider:
        judge_auth_ok, judge_auth_detail = _provider_auth_status(judge_provider)
        checks.append((f"{judge_provider}_judge_auth", judge_auth_ok, judge_auth_detail))

    try:
        prompt_pack = load_prompt_pack(args.prompt)
        checks.append(("prompt_pack", True, str(prompt_pack.root)))
    except Exception as exc:
        checks.append(("prompt_pack", False, str(exc)))

    try:
        dataset = load_dataset(args.dataset)
        checks.append(("dataset", True, str(dataset.path)))
    except Exception as exc:
        checks.append(("dataset", False, str(exc)))

    settings.logs_dir.mkdir(parents=True, exist_ok=True)
    settings.state_dir.mkdir(parents=True, exist_ok=True)
    settings.runs_dir.mkdir(parents=True, exist_ok=True)
    checks.append(("workspace_dirs", True, str(settings.var_dir)))

    if auth_ok:
        try:
            gateway = build_gateway(provider=args.provider, judge_provider=judge_provider)
            response = await gateway.generate(
                prompt_version="doctor",
                case_id="doctor",
                model=args.model,
                system_prompt="Reply with exactly PF_OK",
                user_prompt="Reply with exactly PF_OK",
                run_id="doctor",
                config_hash="doctor",
                run_config=RunConfig(
                    max_output_tokens=20,
                    timeout_seconds=20,
                    retries=0,
                    concurrency=1,
                    failure_threshold=1.0,
                ),
            )
            checks.append(("model_access", "PF_OK" in (response.output_text or ""), (response.output_text or "").strip()))
        except Exception as exc:
            checks.append(("model_access", False, str(exc)))
    else:
        checks.append(("model_access", False, f"skipped because {auth_detail}"))

    for name, ok, detail in checks:
        status = "OK" if ok else "FAIL"
        print(f"{status:<5} {name:<15} {detail}")
    return 0 if all(ok for _, ok, _ in checks) else 1


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="pf", description="PromptForge prompt evaluation CLI")
    subparsers = parser.add_subparsers(dest="command", required=True)

    def add_shared_args(subparser: argparse.ArgumentParser) -> None:
        subparser.add_argument("--dataset", required=True, help="Path to a JSONL dataset")
        subparser.add_argument("--model", default=settings.openai_base_model, help="Generation model")
        subparser.add_argument("--provider", choices=["openai", "openrouter", "codex"], default=settings.provider)
        subparser.add_argument("--judge-provider", choices=["openai", "openrouter", "codex"], default=settings.judge_provider)
        subparser.add_argument("--temperature", type=float, default=None)
        subparser.add_argument("--max-tokens", type=int, default=settings.default_max_output_tokens)
        subparser.add_argument("--seed", type=int, default=None)
        subparser.add_argument("--retries", type=int, default=settings.default_retries)
        subparser.add_argument("--timeout", type=float, default=settings.default_timeout_seconds)
        subparser.add_argument("--concurrency", type=int, default=settings.default_concurrency)
        subparser.add_argument("--failure-threshold", type=float, default=settings.default_failure_threshold)
        subparser.add_argument("--scoring-config", default=None, help="Optional YAML scoring config")

    run_parser = subparsers.add_parser("run", help="Run one prompt pack against a dataset")
    run_parser.add_argument("--prompt", required=True, help="Prompt pack version or path")
    add_shared_args(run_parser)

    compare_parser = subparsers.add_parser("compare", help="Compare two prompt packs against one dataset")
    compare_parser.add_argument("--a", required=True, help="Baseline prompt pack version or path")
    compare_parser.add_argument("--b", required=True, help="Candidate prompt pack version or path")
    add_shared_args(compare_parser)

    report_parser = subparsers.add_parser("report", help="Print or rebuild a run report")
    report_parser.add_argument("--run", required=True, help="Run id")
    report_parser.add_argument("--print", action=argparse.BooleanOptionalAction, default=False)

    doctor_parser = subparsers.add_parser("doctor", help="Check environment and model access")
    doctor_parser.add_argument("--prompt", default="v1", help="Prompt pack to validate")
    doctor_parser.add_argument("--dataset", default="datasets/core.jsonl", help="Dataset to validate")
    doctor_parser.add_argument("--model", default=settings.openai_base_model, help="Model to test")
    doctor_parser.add_argument("--provider", choices=["openai", "openrouter", "codex"], default=settings.provider)
    doctor_parser.add_argument("--judge-provider", choices=["openai", "openrouter", "codex"], default=settings.judge_provider)
    return parser


def _provider_auth_status(provider: ProviderName) -> tuple[bool, str]:
    if provider == "openai":
        return bool(settings.openai_api_key), "OPENAI_API_KEY is set" if settings.openai_api_key else "OPENAI_API_KEY is missing"
    if provider == "openrouter":
        return bool(settings.openrouter_api_key), "OPENROUTER_API_KEY is set" if settings.openrouter_api_key else "OPENROUTER_API_KEY is missing"
    codex_path = shutil.which(settings.codex_bin)
    return codex_path is not None, f"Codex CLI found at {codex_path}" if codex_path else f"Codex CLI not found: {settings.codex_bin}"


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.command == "run":
        return asyncio.run(_run_command(args))
    if args.command == "compare":
        return asyncio.run(_compare_command(args))
    if args.command == "report":
        return _report_command(args)
    if args.command == "doctor":
        return asyncio.run(_doctor_command(args))
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
