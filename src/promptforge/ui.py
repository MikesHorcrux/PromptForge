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

_BANNER = r"""
______                          _   ______
| ___ \                        | | |  ___|
| |_/ / __ ___  _ __ ___  _ __ | |_| |_ ___  _ __ __ _  ___
|  __/ '__/ _ \| '_ ` _ \| '_ \| __|  _/ _ \| '__/ _` |/ _ \
| |  | | | (_) | | | | | | |_) | |_| || (_) | | | (_| |  __/
\_|  |_|  \___/|_| |_| |_| .__/ \__\_| \___/|_|  \__, |\___|
                         | |                      __/ |
                         |_|                     |___/
"""


def print_banner(command_name: str, *, subtitle: str = "Runehall of Hazar") -> None:
    title = Text(_BANNER.strip("\n"), style="gold")
    body = Text()
    body.append(f"{command_name}\n", style="ember")
    console.print(Panel.fit(title, border_style="ember", padding=(1, 2), subtitle=subtitle))
    console.print(body)
    console.print()


def print_section(title: str, description: str | None = None) -> None:
    console.print(Rule(title, style="ember"))
    if description:
        console.print(f"[dimmed]{description}[/dimmed]")


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
    print_key_value_block("Forged Trial", rows)


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
    print_key_value_block("Duel of Sigils", rows)


def print_report_location(path: Path, *, printed: bool) -> None:
    message = "The chronicle was printed to stdout." if printed else str(path)
    print_key_value_block("Report", [("Location", message)])


def print_doctor_results(checks: Sequence[tuple[str, bool, str]], *, hint: str | None = None) -> None:
    table = Table(title="Ward Inspection", border_style="steel")
    table.add_column("Seal", style="gold", no_wrap=True)
    table.add_column("State", no_wrap=True)
    table.add_column("Detail", style="steel")
    for name, ok, detail in checks:
        state = "[moss]READY[/moss]" if ok else "[warning]BROKEN[/warning]"
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
    print_key_value_block("Forge Attunement", rows)


def print_info(message: str) -> None:
    console.print(f"[steel]{message}[/steel]")


def print_success(message: str) -> None:
    console.print(f"[moss]{message}[/moss]")


def print_warning(message: str) -> None:
    console.print(f"[warning]{message}[/warning]")
