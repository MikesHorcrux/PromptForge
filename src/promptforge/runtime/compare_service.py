from __future__ import annotations

from promptforge.core.models import ComparisonAggregate, ComparisonArtifact, ComparisonCaseResult, RUBRIC_TRAITS, ScoresArtifact, utc_now_iso


def _round(value: float) -> float:
    return round(value, 4)


class CompareService:
    def compare(self, *, run_id: str, prompt_a: str, prompt_b: str, model: str, scores_a: ScoresArtifact, scores_b: ScoresArtifact, tie_margin: float) -> ComparisonArtifact:
        cases_by_id_a = {case.case_id: case for case in scores_a.cases}
        cases_by_id_b = {case.case_id: case for case in scores_b.cases}
        case_ids = [case.case_id for case in scores_a.cases if case.case_id in cases_by_id_b]
        case_results: list[ComparisonCaseResult] = []
        win_a = 0
        win_b = 0
        ties = 0

        for case_id in case_ids:
            case_a = cases_by_id_a[case_id]
            case_b = cases_by_id_b[case_id]
            improved_traits = []
            regressed_traits = []
            for trait in RUBRIC_TRAITS:
                delta = case_b.trait_scores[trait].score - case_a.trait_scores[trait].score
                if delta > 0:
                    improved_traits.append(trait)
                elif delta < 0:
                    regressed_traits.append(trait)

            if case_a.hard_fail and not case_b.hard_fail:
                winner = "b"
                reason = "B passed the hard-fail gates while A did not."
                confidence = 1.0
            elif case_b.hard_fail and not case_a.hard_fail:
                winner = "a"
                reason = "A passed the hard-fail gates while B did not."
                confidence = 1.0
            else:
                delta = case_b.effective_weighted_score - case_a.effective_weighted_score
                if abs(delta) <= tie_margin:
                    winner = "tie"
                    reason = f"Score delta {delta:.2f} is within the tie margin."
                    confidence = _round(max(0.2, abs(delta) / max(tie_margin, 0.01)))
                elif delta > 0:
                    winner = "b"
                    reason = f"B led by {delta:.2f} weighted points."
                    confidence = _round(min(1.0, abs(delta) / 2.5))
                else:
                    winner = "a"
                    reason = f"A led by {abs(delta):.2f} weighted points."
                    confidence = _round(min(1.0, abs(delta) / 2.5))

            if winner == "a":
                win_a += 1
            elif winner == "b":
                win_b += 1
            else:
                ties += 1

            case_results.append(
                ComparisonCaseResult(
                    case_id=case_id,
                    winner=winner,
                    confidence=confidence,
                    effective_score_a=case_a.effective_weighted_score,
                    effective_score_b=case_b.effective_weighted_score,
                    raw_score_delta=_round(case_b.raw_weighted_score - case_a.raw_weighted_score),
                    hard_fail_a=case_a.hard_fail,
                    hard_fail_b=case_b.hard_fail,
                    reason=reason,
                    improved_traits=improved_traits,
                    regressed_traits=regressed_traits,
                )
            )

        trait_deltas = {
            trait: _round(scores_b.aggregate.trait_averages[trait] - scores_a.aggregate.trait_averages[trait])
            for trait in RUBRIC_TRAITS
        }
        improved_traits_for_b = [trait for trait, delta in trait_deltas.items() if delta > 0]
        regressed_traits_for_b = [trait for trait, delta in trait_deltas.items() if delta < 0]

        sorted_by_delta = sorted(case_results, key=lambda item: item.raw_score_delta, reverse=True)
        top_improved = [item.case_id for item in sorted_by_delta[:3] if item.raw_score_delta > 0]
        top_regressed = [item.case_id for item in reversed(sorted_by_delta[-3:]) if item.raw_score_delta < 0]

        avg_a = scores_a.aggregate.average_effective_score
        avg_b = scores_b.aggregate.average_effective_score
        if win_b > win_a and avg_b >= avg_a:
            overall_winner = "b"
        elif win_a > win_b and avg_a >= avg_b:
            overall_winner = "a"
        elif abs(avg_b - avg_a) <= tie_margin:
            overall_winner = "tie"
        else:
            overall_winner = "b" if avg_b > avg_a else "a"

        total_cases = max(1, len(case_results))
        confidence = _round(
            min(
                1.0,
                (
                    abs(avg_b - avg_a) / 2.5
                    + abs(win_b - win_a) / total_cases
                )
                / 2,
            )
        )

        aggregate = ComparisonAggregate(
            case_wins_a=win_a,
            case_wins_b=win_b,
            ties=ties,
            average_effective_score_a=_round(avg_a),
            average_effective_score_b=_round(avg_b),
            overall_winner=overall_winner,
            confidence=confidence,
            trait_deltas=trait_deltas,
            improved_traits_for_b=improved_traits_for_b,
            regressed_traits_for_b=regressed_traits_for_b,
            top_improved_cases_for_b=top_improved,
            top_regressed_cases_for_b=top_regressed,
        )

        return ComparisonArtifact(
            run_id=run_id,
            created_at=utc_now_iso(),
            prompt_a=prompt_a,
            prompt_b=prompt_b,
            model=model,
            dataset_hash=scores_a.dataset_hash,
            config_hash_a=scores_a.config_hash,
            config_hash_b=scores_b.config_hash,
            aggregate=aggregate,
            cases=case_results,
        )

