from __future__ import annotations

import argparse
import asyncio
import json
import os
import platform
import sys
from pathlib import Path

import yaml
from rich.table import Table

from promptforge.core.config import settings
from promptforge.core.models import ProviderName, RunConfig, RunRequest, ScoringConfig
from promptforge.datasets.loader import load_dataset
from promptforge.forge.workspace import ForgeWorkspaceService, WorkspaceState
from promptforge.project import PromptForgeProject
from promptforge.prompts.loader import load_prompt_pack
from promptforge.runtime.artifacts import ArtifactStore
from promptforge.runtime.codex_cli import codex_login_status
from promptforge.runtime.gateway import build_gateway
from promptforge.runtime.report_service import render_comparison_report, render_evaluation_report
from promptforge.runtime.run_service import EvaluationService
from promptforge.setup_wizard import run_setup_wizard
from promptforge.ui import console, print_banner, print_compare_summary, print_doctor_results, print_info, print_key_value_block, print_report_location, print_run_summary, print_success, print_warning
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


def _default_model_for_provider(provider: ProviderName, *, purpose: str) -> str:
    if provider == "openrouter":
        return "openai/gpt-5-mini" if purpose == "judge" else "openai/gpt-5"
    if provider == "codex":
        return "gpt-5-mini"
    return "gpt-5-mini" if purpose == "judge" else "gpt-5.4"


def _normalize_model_choice(model: str | None, provider: ProviderName, *, purpose: str) -> str:
    candidate = (model or "").strip()
    if candidate.lower() in {"", "y", "yes", "n", "no"}:
        return _default_model_for_provider(provider, purpose=purpose)
    return candidate


def _resolve_judge_provider(args: argparse.Namespace) -> ProviderName:
    return args.judge_provider or args.provider


def _build_provider_service(args: argparse.Namespace) -> EvaluationService:
    judge_provider = _resolve_judge_provider(args)
    return EvaluationService(build_gateway(provider=args.provider, judge_provider=judge_provider))


async def _run_command(args: argparse.Namespace) -> int:
    print_banner("Run")
    scoring_config = _load_scoring_config(args.scoring_config)
    run_config = _build_run_config(args)
    judge_provider = _resolve_judge_provider(args)
    args.model = _normalize_model_choice(args.model, args.provider, purpose="generation")
    scoring_config.judge_model = _normalize_model_choice(scoring_config.judge_model, judge_provider, purpose="judge")
    print_info(f"Running prompt `{args.prompt}` against dataset `{args.dataset}`.")
    with console.status("[ember]Evaluating cases...[/ember]"):
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
    scores = ScoresArtifact.model_validate(
        ArtifactStore().read_json(Path(manifest.output_dir) / "scores.json")
    )
    print_run_summary(
        run_id=manifest.run_id,
        prompt_version=args.prompt,
        provider=args.provider,
        judge_provider=judge_provider,
        average_effective_score=scores.aggregate.average_effective_score,
        hard_fail_count=scores.aggregate.hard_fail_count,
        total_cases=scores.aggregate.total_cases,
        artifact_dir=manifest.output_dir,
    )
    return 0


async def _compare_command(args: argparse.Namespace) -> int:
    print_banner("Compare")
    scoring_config = _load_scoring_config(args.scoring_config)
    run_config = _build_run_config(args)
    judge_provider = _resolve_judge_provider(args)
    args.model = _normalize_model_choice(args.model, args.provider, purpose="generation")
    scoring_config.judge_model = _normalize_model_choice(scoring_config.judge_model, judge_provider, purpose="judge")
    print_info(f"Comparing `{args.a}` and `{args.b}` on dataset `{args.dataset}`.")
    with console.status("[ember]Running baseline and candidate evaluations...[/ember]"):
        manifest = await _build_provider_service(args).compare(
            prompt_a=args.a,
            prompt_b=args.b,
            model=args.model,
            dataset_path=args.dataset,
            run_config=run_config,
            scoring_config=scoring_config,
            provider=args.provider,
            judge_provider=judge_provider,
        )
    comparison = ComparisonArtifact.model_validate(
        ArtifactStore().read_json(Path(manifest.output_dir) / "comparison.json")
    )
    winner = {
        "a": args.a,
        "b": args.b,
        "tie": "tie",
    }[comparison.aggregate.overall_winner]
    print_compare_summary(
        run_id=manifest.run_id,
        prompt_a=args.a,
        prompt_b=args.b,
        provider=args.provider,
        judge_provider=judge_provider,
        winner=winner,
        confidence=comparison.aggregate.confidence,
        wins_a=comparison.aggregate.case_wins_a,
        wins_b=comparison.aggregate.case_wins_b,
        ties=comparison.aggregate.ties,
        artifact_dir=manifest.output_dir,
    )
    return 0


def _report_command(args: argparse.Namespace) -> int:
    if not args.print:
        print_banner("Report")
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
        print_report_location(report_path, printed=False)
    return 0


def _mask_secret(value: str | None) -> str:
    if not value:
        return "(not set)"
    if len(value) <= 8:
        return "*" * len(value)
    return f"{value[:4]}...{value[-4:]}"


def _load_workspace_state() -> WorkspaceState:
    path = settings.workspace_state_path
    if not path.exists():
        return WorkspaceState()
    return WorkspaceState.model_validate(json.loads(path.read_text(encoding="utf-8")))


def _status_command(args: argparse.Namespace) -> int:
    print_banner("Status")
    codex_ok, codex_detail = _provider_auth_status("codex")
    workspace_state = _load_workspace_state()
    project = PromptForgeProject.open_or_create(Path.cwd())
    env_path = Path(".env")
    active_prompt = project.metadata.last_opened_prompt or workspace_state.active_prompt
    active_session = workspace_state.prompt_sessions.get(active_prompt or "", "")

    auth_rows = [
        ("Config file", str(env_path.resolve()) if env_path.exists() else "(no local .env found)"),
        ("Default provider", project.metadata.preferred_provider),
        ("Judge provider", project.metadata.preferred_judge_provider or project.metadata.preferred_provider),
        ("Generation model", project.metadata.preferred_generation_model),
        ("Judge model", project.metadata.preferred_judge_model),
        ("OpenAI key", _mask_secret(settings.openai_api_key)),
        ("OpenRouter key", _mask_secret(settings.openrouter_api_key)),
        ("Codex login", codex_detail if codex_ok else f"not ready: {codex_detail}"),
    ]
    print_key_value_block("Auth and Defaults", auth_rows)

    workspace_rows = [
        ("Project", project.metadata.name),
        ("Project root", str(project.root)),
        ("Prompts", str(settings.prompt_dir)),
        ("Datasets", str(settings.dataset_dir)),
        ("Var dir", str(settings.var_dir)),
        ("Quick-check dataset", project.metadata.quick_benchmark_dataset),
        ("Evaluation dataset", project.metadata.full_evaluation_dataset),
        ("Active prompt", active_prompt or "--"),
        ("Active workspace session", active_session or "--"),
    ]
    print_key_value_block("Workspace", workspace_rows)
    return 0


async def _doctor_command(args: argparse.Namespace) -> int:
    print_banner("Doctor")
    checks: list[tuple[str, bool, str]] = []
    python_ok = sys.version_info >= (3, 11)
    checks.append(("python", python_ok, platform.python_version()))

    judge_provider = _resolve_judge_provider(args)
    args.model = _normalize_model_choice(args.model, args.provider, purpose="generation")
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

    hint = None
    if not all(ok for _, ok, _ in checks):
        hint = "Run `pf setup` to configure auth, keys, and default providers."
    print_doctor_results(checks, hint=hint)
    return 0 if all(ok for _, ok, _ in checks) else 1


def _resolve_forge_app_path() -> Path | None:
    candidates = []
    if app_path := os.environ.get("PF_APP_PATH"):
        candidates.append(Path(app_path).expanduser())
    candidates.extend(
        [
            Path("/Applications/PromptForge.app"),
            Path("~/Applications/PromptForge.app").expanduser(),
            Path("apps/macos/PromptForge/build/Debug/PromptForge.app"),
            Path("apps/macos/PromptForge/build/Release/PromptForge.app"),
        ]
    )
    derived_data_root = Path("~/Library/Developer/Xcode/DerivedData").expanduser()
    if derived_data_root.exists():
        for candidate in sorted(
            derived_data_root.glob("PromptForge-*/Build/Products/Debug/PromptForge.app"),
            reverse=True,
        ):
            candidates.append(candidate)
    for candidate in candidates:
        if candidate.exists():
            return candidate.resolve()
    return None


def _build_workspace(project: PromptForgeProject) -> ForgeWorkspaceService:
    return ForgeWorkspaceService(
        dataset_path=project.metadata.full_evaluation_dataset,
        bench_dataset_path=project.metadata.quick_benchmark_dataset,
        model=project.metadata.preferred_generation_model,
        agent_model=project.metadata.preferred_agent_model,
        provider=project.metadata.preferred_provider,
        judge_provider=project.metadata.preferred_judge_provider or project.metadata.preferred_provider,
        run_config=RunConfig(),
        scoring_config=ScoringConfig(judge_model=project.metadata.preferred_judge_model),
        bench_repeats=project.metadata.quick_benchmark_repeats,
        full_repeats=project.metadata.full_evaluation_repeats,
    )


def _forge_command_sync(args: argparse.Namespace) -> int:
    project_root = Path(args.project).resolve()
    engine_root = Path(__file__).resolve().parents[2]
    PromptForgeProject.open_or_create(project_root)
    if platform.system() != "Darwin":
        print_warning("`pf app` opens the macOS workspace, so it only works on macOS.")
        print_info(f"Project ready at {project_root}. Use `pf status`, `pf run`, and `pf compare` from the CLI.")
        return 1

    app_path = _resolve_forge_app_path()
    if app_path is None:
        print_warning("PromptForge.app was not found.")
        print_info("Build or install the macOS workspace app first, then rerun `pf app`.")
        print_info("Expected locations:")
        print_info("- /Applications/PromptForge.app")
        print_info("- ~/Applications/PromptForge.app")
        print_info("- apps/macos/PromptForge/build/Debug/PromptForge.app")
        return 1

    subprocess.run(
        [
            "open",
            "-na",
            str(app_path),
            "--args",
            "--project",
            str(project_root),
            "--engine-root",
            str(engine_root),
        ],
        check=False,
    )
    print_success(f"Opened PromptForge.app for project {project_root}.")
    return 0


def _prompts_command(args: argparse.Namespace) -> int:
    project = PromptForgeProject.open_or_create(Path.cwd())
    workspace = _build_workspace(project)
    if args.prompts_command == "list":
        rows = workspace.list_prompts()
        table = Table(title="Prompt Packs")
        table.add_column("Version", style="bold yellow3")
        table.add_column("Name")
        table.add_column("Description")
        for row in rows:
            table.add_row(row.version, row.name, row.description)
        console.print(table)
        return 0
    if args.prompts_command == "create":
        destination = workspace.create_prompt(
            args.prompt,
            from_prompt=args.from_prompt,
            name=args.name,
        )
        workspace.set_active_prompt(args.prompt)
        print_success(f"Created prompt at {destination}.")
        return 0
    raise ValueError(f"Unknown prompts command: {args.prompts_command}")


async def _scenario_run_command(args: argparse.Namespace) -> int:
    project = PromptForgeProject.open_or_create(Path.cwd())
    workspace = _build_workspace(project)
    review = await workspace.run_scenario_suite(args.prompt, args.suite, repeats=args.repeats)
    if args.json:
        print(json.dumps(review.model_dump(mode="json"), indent=2, sort_keys=True))
        return 0

    print_banner("Test Run")
    print_info(f"Ran test suite `{review.suite_name}` for prompt `{args.prompt}`.")
    summary_rows = [
        ("Review", review.review_id),
        ("Revision", review.revision_id or "--"),
        ("Score delta", f"{review.diff.mean_score_delta:+.2f}" if review.diff and review.diff.mean_score_delta is not None else "--"),
        ("Pass-rate delta", f"{review.diff.pass_rate_delta:+.2%}" if review.diff and review.diff.pass_rate_delta is not None else "--"),
        ("Cases", str(len(review.cases))),
    ]
    print_key_value_block("Review Summary", summary_rows)

    table = Table(title="Test Cases")
    table.add_column("Case", style="bold yellow3")
    table.add_column("Status")
    table.add_column("Candidate")
    table.add_column("Baseline")
    table.add_column("Notes")
    for case in review.cases:
        status = "regressed" if case.regression else ("flaky" if case.flaky else "ok")
        notes = ", ".join(case.hard_fail_reasons) if case.hard_fail_reasons else ""
        table.add_row(
            case.case_id,
            status,
            f"{case.candidate_score:.2f}" if case.candidate_score is not None else "--",
            f"{case.baseline_score:.2f}" if case.baseline_score is not None else "--",
            notes or "--",
        )
    console.print(table)
    return 0


def _scenario_command(args: argparse.Namespace) -> int:
    project = PromptForgeProject.open_or_create(Path.cwd())
    workspace = _build_workspace(project)
    if args.scenario_command == "list":
        suites = workspace.list_scenarios(prompt_ref=args.prompt)
        if args.json:
            print(json.dumps([suite.model_dump(mode="json") for suite in suites], indent=2, sort_keys=True))
            return 0
        table = Table(title="Test Suites")
        table.add_column("Suite", style="bold yellow3")
        table.add_column("Cases")
        table.add_column("Linked prompts")
        table.add_column("Description")
        for suite in suites:
            table.add_row(
                suite.suite_id,
                str(len(suite.cases)),
                ", ".join(suite.linked_prompts) if suite.linked_prompts else "all",
                suite.description or "--",
            )
        console.print(table)
        return 0
    if args.scenario_command == "show":
        suite = workspace.load_scenario(args.suite)
        if args.json:
            print(json.dumps(suite.model_dump(mode="json"), indent=2, sort_keys=True))
            return 0
        print_banner("Test Suite")
        print_key_value_block(
            suite.name,
            [
                ("Suite ID", suite.suite_id),
                ("Tests", str(len(suite.cases))),
                ("Linked prompts", ", ".join(suite.linked_prompts) if suite.linked_prompts else "all"),
                ("Description", suite.description or "--"),
            ],
        )
        case_table = Table(title="Cases")
        case_table.add_column("Case", style="bold yellow3")
        case_table.add_column("Assertions")
        case_table.add_column("Tags")
        for scenario_case in suite.cases:
            case_table.add_row(
                scenario_case.case_id,
                str(len(scenario_case.assertions)),
                ", ".join(scenario_case.tags) if scenario_case.tags else "--",
            )
        console.print(case_table)
        return 0
    if args.scenario_command == "create":
        suite = workspace.create_scenario(
            args.suite,
            prompt_ref=args.prompt,
            name=args.name,
            description=args.description or "",
        )
        print_success(f"Created test suite `{suite.suite_id}`.")
        return 0
    if args.scenario_command == "run":
        return asyncio.run(_scenario_run_command(args))
    raise ValueError(f"Unknown scenario command: {args.scenario_command}")


def _review_command(args: argparse.Namespace) -> int:
    project = PromptForgeProject.open_or_create(Path.cwd())
    workspace = _build_workspace(project)
    reviews = asyncio.run(workspace.list_reviews(args.prompt))
    if not reviews:
        print_warning(f"No reviews recorded for prompt `{args.prompt}`.")
        return 1
    review = reviews[-1]
    if args.json:
        print(json.dumps(review.model_dump(mode="json"), indent=2, sort_keys=True))
        return 0
    print_banner("Latest Review")
    print_key_value_block(
        review.suite_name,
        [
            ("Review", review.review_id),
            ("Revision", review.revision_id or "--"),
            ("Score delta", f"{review.diff.mean_score_delta:+.2f}" if review.diff and review.diff.mean_score_delta is not None else "--"),
            ("Pass-rate delta", f"{review.diff.pass_rate_delta:+.2%}" if review.diff and review.diff.pass_rate_delta is not None else "--"),
        ],
    )
    return 0


def _promote_command(args: argparse.Namespace) -> int:
    project = PromptForgeProject.open_or_create(Path.cwd())
    workspace = _build_workspace(project)
    decision = asyncio.run(
        workspace.promote_to_baseline(
            args.prompt,
            summary=args.summary,
            rationale=args.rationale or "",
            review_id=args.review_id,
            suite_id=args.suite_id,
        )
    )
    print_success(f"Shipped `{args.prompt}` to baseline with decision `{decision.decision_id}`.")
    return 0


def _setup_command(args: argparse.Namespace) -> int:
    return run_setup_wizard(
        env_path=Path(args.env_file),
        example_env_path=Path(args.example_env_file),
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pf",
        description="PromptForge local prompt engineering toolkit",
        epilog=(
            "Commands: setup, status, doctor, prompts, tests/scenario, review, "
            "ship/promote, app/forge, run, compare, report"
        ),
    )
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

    run_parser = subparsers.add_parser("run", help="Run one prompt against a dataset")
    run_parser.add_argument("--prompt", required=True, help="Prompt version or path")
    add_shared_args(run_parser)

    compare_parser = subparsers.add_parser("compare", help="Compare two prompts against one dataset")
    compare_parser.add_argument("--a", required=True, help="Baseline prompt version or path")
    compare_parser.add_argument("--b", required=True, help="Candidate prompt version or path")
    add_shared_args(compare_parser)

    forge_parser = subparsers.add_parser(
        "forge",
        aliases=["app"],
        help="Open the PromptForge macOS app for this project",
    )
    forge_parser.add_argument("--project", default=".", help="PromptForge project root to open")

    prompts_parser = subparsers.add_parser("prompts", help="List or create prompts")
    prompts_subparsers = prompts_parser.add_subparsers(dest="prompts_command", required=True)
    prompts_list_parser = prompts_subparsers.add_parser("list", help="List available prompts")
    prompts_list_parser.set_defaults(prompts_command="list")
    prompts_create_parser = prompts_subparsers.add_parser("create", help="Create a new prompt")
    prompts_create_parser.add_argument("--prompt", required=True, help="New prompt version")
    prompts_create_parser.add_argument("--from", dest="from_prompt", default=None, help="Clone from an existing prompt")
    prompts_create_parser.add_argument("--name", default=None, help="Optional display name for the prompt")
    prompts_create_parser.set_defaults(prompts_command="create")

    scenario_parser = subparsers.add_parser(
        "scenario",
        aliases=["tests"],
        help="List, inspect, create, and run saved prompt test suites",
    )
    scenario_subparsers = scenario_parser.add_subparsers(dest="scenario_command", required=True)
    scenario_list_parser = scenario_subparsers.add_parser("list", help="List saved test suites")
    scenario_list_parser.add_argument("--prompt", default=None, help="Optional prompt ref to filter linked suites")
    scenario_list_parser.add_argument("--json", action=argparse.BooleanOptionalAction, default=False)
    scenario_list_parser.set_defaults(scenario_command="list")
    scenario_show_parser = scenario_subparsers.add_parser("show", help="Show one saved test suite")
    scenario_show_parser.add_argument("--suite", required=True, help="Test suite id")
    scenario_show_parser.add_argument("--json", action=argparse.BooleanOptionalAction, default=False)
    scenario_show_parser.set_defaults(scenario_command="show")
    scenario_create_parser = scenario_subparsers.add_parser("create", help="Create a saved test suite")
    scenario_create_parser.add_argument("--suite", required=True, help="New test suite id")
    scenario_create_parser.add_argument("--prompt", default=None, help="Optional prompt ref to link")
    scenario_create_parser.add_argument("--name", default=None, help="Display name")
    scenario_create_parser.add_argument("--description", default="", help="Suite description")
    scenario_create_parser.set_defaults(scenario_command="create")
    scenario_run_parser = scenario_subparsers.add_parser("run", help="Run a saved test suite against a prompt")
    scenario_run_parser.add_argument("--suite", required=True, help="Test suite id")
    scenario_run_parser.add_argument("--prompt", required=True, help="Prompt ref to evaluate")
    scenario_run_parser.add_argument("--repeats", type=int, default=None, help="Optional repeat count override")
    scenario_run_parser.add_argument("--json", action=argparse.BooleanOptionalAction, default=False)
    scenario_run_parser.set_defaults(scenario_command="run")

    review_parser = subparsers.add_parser("review", help="Show the latest saved review for a prompt")
    review_parser.add_argument("--prompt", required=True, help="Prompt ref")
    review_parser.add_argument("--json", action=argparse.BooleanOptionalAction, default=False)

    promote_parser = subparsers.add_parser(
        "promote",
        aliases=["ship"],
        help="Ship the current prompt version to baseline",
    )
    promote_parser.add_argument("--prompt", required=True, help="Prompt ref")
    promote_parser.add_argument("--summary", default="Shipped current candidate to baseline.", help="Decision summary")
    promote_parser.add_argument("--rationale", default="", help="Optional rationale")
    promote_parser.add_argument("--review-id", default=None, help="Optional review id")
    promote_parser.add_argument("--suite-id", default=None, help="Optional test suite id")

    report_parser = subparsers.add_parser("report", help="Print or rebuild a run report")
    report_parser.add_argument("--run", required=True, help="Run id")
    report_parser.add_argument("--print", action=argparse.BooleanOptionalAction, default=False)

    setup_parser = subparsers.add_parser("setup", help="Interactive onboarding for auth and provider defaults")
    setup_parser.add_argument("--env-file", default=".env", help="Environment file to create or update")
    setup_parser.add_argument("--example-env-file", default=".env.example", help="Template environment file")

    subparsers.add_parser("status", help="Show auth, provider defaults, and active workspace state")

    doctor_parser = subparsers.add_parser("doctor", help="Check environment and model access")
    doctor_parser.add_argument("--prompt", default="v1", help="Prompt to validate")
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
    return codex_login_status(settings.codex_bin)


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    argv = list(argv) if argv is not None else sys.argv[1:]
    if not argv or argv == ["help"]:
        parser.print_help()
        return 0
    args = parser.parse_args(argv)
    if args.command == "run":
        return asyncio.run(_run_command(args))
    if args.command == "compare":
        return asyncio.run(_compare_command(args))
    if args.command == "report":
        return _report_command(args)
    if args.command == "setup":
        return _setup_command(args)
    if args.command == "status":
        return _status_command(args)
    if args.command == "doctor":
        return asyncio.run(_doctor_command(args))
    if args.command in {"forge", "app"}:
        return _forge_command_sync(args)
    if args.command == "prompts":
        return _prompts_command(args)
    if args.command in {"scenario", "tests"}:
        return _scenario_command(args)
    if args.command == "review":
        return _review_command(args)
    if args.command in {"promote", "ship"}:
        return _promote_command(args)
    parser.error(f"Unknown command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
