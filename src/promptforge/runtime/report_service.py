from __future__ import annotations

from promptforge.core.models import ComparisonArtifact, RunManifest, ScoresArtifact


def render_evaluation_report(*, manifest: RunManifest, scores: ScoresArtifact) -> str:
    aggregate = scores.aggregate
    hard_fail_cases = [case for case in scores.cases if case.hard_fail][:5]
    lines = [
        f"# PromptForge Report: {manifest.run_id}",
        "",
        "## Summary",
        f"- Prompt version: `{scores.prompt_version}`",
        f"- Model: `{scores.model}`",
        f"- Provider: `{manifest.provider}`",
        f"- Judge provider: `{manifest.judge_provider}`",
        f"- Config hash: `{scores.config_hash}`",
        f"- Cases: {aggregate.total_cases}",
        f"- Hard fails: {aggregate.hard_fail_count} ({aggregate.hard_fail_rate:.1%})",
        f"- Average effective score: {aggregate.average_effective_score:.2f} / 5.00",
        f"- Average normalized score: {aggregate.average_normalized_score:.1f} / 100",
        "",
        "## Trait Averages",
    ]
    for trait, value in aggregate.trait_averages.items():
        lines.append(f"- {trait}: {value:.2f} / 5.00")

    if scores.warnings:
        lines.extend(["", "## Warnings"])
        for warning in scores.warnings:
            lines.append(f"- {warning}")

    lines.extend(["", "## Notable Hard Fails"])
    if hard_fail_cases:
        for case in hard_fail_cases:
            lines.append(f"- `{case.case_id}`: {'; '.join(case.hard_fail_reasons)}")
    else:
        lines.append("- None")

    lines.extend(
        [
            "",
            "## Top Cases",
        ]
    )
    top_cases = sorted(scores.cases, key=lambda item: item.effective_weighted_score, reverse=True)[:5]
    for case in top_cases:
        lines.append(
            f"- `{case.case_id}`: {case.effective_weighted_score:.2f} / 5.00. {case.summary}"
        )
    return "\n".join(lines).strip() + "\n"


def render_comparison_report(*, manifest: RunManifest, comparison: ComparisonArtifact) -> str:
    aggregate = comparison.aggregate
    winner_label = {
        "a": comparison.prompt_a,
        "b": comparison.prompt_b,
        "tie": "tie",
    }[aggregate.overall_winner]
    lines = [
        f"# PromptForge Comparison Report: {manifest.run_id}",
        "",
        "## Summary",
        f"- Prompt A: `{comparison.prompt_a}`",
        f"- Prompt B: `{comparison.prompt_b}`",
        f"- Model: `{comparison.model}`",
        f"- Provider: `{manifest.provider}`",
        f"- Judge provider: `{manifest.judge_provider}`",
        f"- Overall winner: `{winner_label}`",
        f"- Confidence: {aggregate.confidence:.2f}",
        f"- Case wins: A={aggregate.case_wins_a}, B={aggregate.case_wins_b}, ties={aggregate.ties}",
        f"- Average effective score: A={aggregate.average_effective_score_a:.2f}, B={aggregate.average_effective_score_b:.2f}",
        "",
        "## What Improved For B",
    ]
    if aggregate.improved_traits_for_b:
        for trait in aggregate.improved_traits_for_b:
            lines.append(f"- {trait}: +{aggregate.trait_deltas[trait]:.2f}")
    else:
        lines.append("- No rubric trait improved.")

    lines.extend(["", "## What Regressed For B"])
    if aggregate.regressed_traits_for_b:
        for trait in aggregate.regressed_traits_for_b:
            lines.append(f"- {trait}: {aggregate.trait_deltas[trait]:.2f}")
    else:
        lines.append("- No rubric trait regressed.")

    lines.extend(["", "## Per-Case Highlights"])
    highlighted = comparison.cases[:5]
    for case in highlighted:
        lines.append(
            f"- `{case.case_id}`: winner={case.winner}, confidence={case.confidence:.2f}. {case.reason}"
        )
    return "\n".join(lines).strip() + "\n"
