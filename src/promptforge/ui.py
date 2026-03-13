from __future__ import annotations

from pathlib import Path
from typing import Sequence

from rich.console import Console
from rich.panel import Panel
from rich.rule import Rule
from rich.table import Table
from rich.text import Text
from rich.theme import Theme


THEME = Theme(
    {
        "ember": "bold dark_orange3",
        "gold": "bold yellow3",
        "steel": "bold grey70",
        "moss": "green3",
        "warning": "bold red3",
        "dimmed": "grey50",
        "accent": "bold cyan",
        "title": "bold yellow3",
    }
)

console = Console(theme=THEME)

def print_banner(command_name: str, *, subtitle: str = "Local prompt evaluation") -> None:
    title = Text(command_name, style="title")
    console.print(Panel.fit(title, title="PromptForge", border_style="steel", padding=(0, 2), subtitle=subtitle))
    console.print()


def print_section(title: str, description: str | None = None) -> None:
    console.print(Rule(title, style="ember"))
    if description:
        console.print(f"[dimmed]{description}[/dimmed]")


def _truncate(value: str, limit: int = 72) -> str:
    text = " ".join(value.split())
    if len(text) <= limit:
        return text
    return text[: limit - 3] + "..."


def print_key_value_block(title: str, rows: Sequence[tuple[str, str]]) -> None:
    table = Table.grid(padding=(0, 2))
    table.add_column(style="gold", justify="right", no_wrap=True)
    table.add_column(style="steel")
    for key, value in rows:
        table.add_row(key, value)
    console.print(Panel(table, title=title, border_style="steel"))


def print_run_summary(
    *,
    run_id: str,
    prompt_version: str,
    provider: str,
    judge_provider: str,
    average_effective_score: float,
    hard_fail_count: int,
    total_cases: int,
    artifact_dir: str,
) -> None:
    rows = [
        ("Run ID", run_id),
        ("Prompt", prompt_version),
        ("Provider", provider),
        ("Judge", judge_provider),
        ("Score", f"{average_effective_score:.2f} / 5.00"),
        ("Hard fails", f"{hard_fail_count} / {total_cases}"),
        ("Artifacts", artifact_dir),
    ]
    print_key_value_block("Evaluation Run", rows)


def print_compare_summary(
    *,
    run_id: str,
    prompt_a: str,
    prompt_b: str,
    provider: str,
    judge_provider: str,
    winner: str,
    confidence: float,
    wins_a: int,
    wins_b: int,
    ties: int,
    artifact_dir: str,
) -> None:
    rows = [
        ("Run ID", run_id),
        ("Prompt A", prompt_a),
        ("Prompt B", prompt_b),
        ("Provider", provider),
        ("Judge", judge_provider),
        ("Winner", winner),
        ("Confidence", f"{confidence:.2f}"),
        ("Case wins", f"A={wins_a}  B={wins_b}  ties={ties}"),
        ("Artifacts", artifact_dir),
    ]
    print_key_value_block("Comparison", rows)


def print_report_location(path: Path, *, printed: bool) -> None:
    message = "Printed to stdout" if printed else str(path)
    print_key_value_block("Report", [("Location", message)])


def print_doctor_results(checks: Sequence[tuple[str, bool, str]], *, hint: str | None = None) -> None:
    table = Table(title="Environment Check", border_style="steel")
    table.add_column("Check", style="gold", no_wrap=True)
    table.add_column("Status", no_wrap=True)
    table.add_column("Detail", style="steel")
    for name, ok, detail in checks:
        state = "[moss]PASS[/moss]" if ok else "[warning]FAIL[/warning]"
        table.add_row(name, state, detail)
    console.print(table)
    if hint:
        console.print(Panel.fit(hint, border_style="warning"))


def print_setup_summary(
    *,
    provider: str,
    judge_provider: str,
    generation_model: str,
    judge_model: str,
    openai_saved: bool,
    openrouter_saved: bool,
) -> None:
    rows = [
        ("Provider", provider),
        ("Judge", judge_provider),
        ("Generation model", generation_model),
        ("Judge model", judge_model),
        ("OpenAI key", "saved" if openai_saved else "unchanged"),
        ("OpenRouter key", "saved" if openrouter_saved else "unchanged"),
    ]
    print_key_value_block("Setup Summary", rows)


def print_info(message: str) -> None:
    console.print(f"[steel]{message}[/steel]")


def print_success(message: str) -> None:
    console.print(f"[moss]{message}[/moss]")


def print_warning(message: str) -> None:
    console.print(f"[warning]{message}[/warning]")


def print_text_panel(title: str, content: str) -> None:
    console.print(Panel(content.strip() or "(empty)", title=title, border_style="steel"))


def print_agent_result(*, summary: str, changed_files: Sequence[str], diff_preview: str) -> None:
    rows = [
        ("Changed", ", ".join(changed_files) if changed_files else "--"),
        ("Summary", summary or "--"),
    ]
    print_key_value_block("Agent Edit", rows)
    if diff_preview:
        print_text_panel("Prompt Diff", diff_preview)


def print_forge_status(rows: Sequence[tuple[str, str]]) -> None:
    print_key_value_block("Workspace Status", rows)


def print_forge_revision_summary(revision) -> None:
    benchmark = revision.benchmark
    full_eval = revision.full_evaluation
    rows = [
        ("Revision", revision.revision_id),
        ("Source", revision.source),
        ("Note", revision.note or "--"),
        ("Changed", ", ".join(revision.changed_files) if revision.changed_files else "--"),
    ]
    if benchmark:
        rows.extend(
            [
                ("Bench score", f"{benchmark.mean_effective_score:.2f} / 5.00"),
                ("Pass rate", f"{benchmark.pass_rate:.1%}"),
                ("Hard fail", f"{benchmark.mean_hard_fail_rate:.1%}"),
                ("Repeats", str(benchmark.repeats)),
            ]
        )
    if revision.benchmark_vs_baseline:
        rows.append(
            (
                "Vs baseline",
                f"{revision.benchmark_vs_baseline.mean_score_delta:+.2f} "
                f"({revision.benchmark_vs_baseline.winner})",
            )
        )
        rows.append(
            (
                "Improved cases",
                ", ".join(revision.benchmark_vs_baseline.top_improved_cases) or "--",
            )
        )
        rows.append(
            (
                "Regressed cases",
                ", ".join(revision.benchmark_vs_baseline.top_regressed_cases) or "--",
            )
        )
    if revision.benchmark_vs_previous:
        rows.append(
            (
                "Vs previous",
                f"{revision.benchmark_vs_previous.mean_score_delta:+.2f} "
                f"({revision.benchmark_vs_previous.winner})",
            )
        )
    if full_eval:
        rows.append(("Full eval", f"{full_eval.mean_effective_score:.2f} / 5.00"))
    print_key_value_block("Workspace Revision", rows)


def print_forge_history(rows: Sequence[tuple[str, str, str, str, str]]) -> None:
    table = Table(title="Revision History", border_style="steel")
    table.add_column("Revision", style="gold", no_wrap=True)
    table.add_column("Source", style="steel")
    table.add_column("Bench", justify="right")
    table.add_column("Vs Base", justify="right")
    table.add_column("Full", justify="right")
    for revision_id, source, bench, delta, full in rows:
        table.add_row(revision_id, source, bench, delta, full)
    console.print(table)


def print_forge_case_table(
    rows: Sequence[tuple[str, str, str, str, str]],
    *,
    title: str,
) -> None:
    if not rows:
        print_warning("No benchmark case details are available yet.")
        return
    table = Table(title=title, border_style="steel")
    table.add_column("Case", style="gold", no_wrap=True)
    table.add_column("Score", justify="right", no_wrap=True)
    table.add_column("Hard fail", justify="right", no_wrap=True)
    table.add_column("Reasons", style="steel")
    table.add_column("Judge summary", style="steel")
    for case_id, score, hard_fail, reasons, summary in rows:
        table.add_row(case_id, score, hard_fail, _truncate(reasons), _truncate(summary))
    console.print(table)


def print_forge_diff(rows: Sequence[tuple[str, str]], *, title: str) -> None:
    if not rows:
        print_warning("No benchmark delta is available yet.")
        return
    print_key_value_block(title, rows)


def print_forge_trend(points: Sequence[tuple[str, float]]) -> None:
    if not points:
        print_warning("No benchmark trend is available yet.")
        return
    width = 24
    lines: list[str] = []
    for label, value in points:
        filled = int(round((value / 5.0) * width))
        bar = "#" * filled + "." * (width - filled)
        lines.append(f"{label:>5}  {value:>4.2f} | {bar}")
    print_text_panel("Score Trend", "\n".join(lines))


def print_forge_help() -> None:
    commands = "\n".join(
        [
            "/status                Show the active prompt, model, and latest benchmark",
            "/show system|user      Print the current working prompt file",
            "/edit system|user      Replace a prompt file, then auto-benchmark it",
            "/restore <revision>    Restore a previous revision checkpoint",
            "/undo                  Restore the previous revision checkpoint",
            "/bench [note]          Snapshot the current prompt and run the benchmark lane",
            "/full [note]           Run the full evaluation dataset on the current revision",
            "/history               Show revision history",
            "/graph                 Show the benchmark score trend",
            "/diff                  Show the latest delta versus the baseline",
            "/cases                 Show the weakest benchmark cases",
            "/failures              Show only hard-failing benchmark cases",
            "/coach <request>       Ask for advice without editing the prompt",
            "/save <version>        Export the working prompt to prompts/<version>",
            "/reset [note]          Reset the working prompt back to the baseline",
            "/quit                  Leave the workspace session",
            "",
            "Any line without a leading slash is treated as an agent edit request.",
        ]
    )
    print_text_panel("Workspace Commands", commands)
