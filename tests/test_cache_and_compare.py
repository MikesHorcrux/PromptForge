from pathlib import Path

from promptforge.core.models import (
    AggregateScores,
    CachedResponse,
    CaseScore,
    RuleCheckResult,
    ScoresArtifact,
    TraitScore,
    utc_now_iso,
)
from promptforge.runtime.cache import ResponseCache
from promptforge.runtime.compare_service import CompareService


def test_response_cache_round_trip(tmp_path: Path) -> None:
    cache = ResponseCache(tmp_path / "cache.sqlite3")
    entry = CachedResponse(
        key="key-1",
        prompt_version="v1",
        case_id="case-001",
        model="gpt-test",
        config_hash="cfg",
        output_text="hello",
    )
    cache.set(entry)

    loaded = cache.get("key-1")

    assert loaded is not None
    assert loaded.output_text == "hello"


def test_compare_service_prefers_non_hard_fail() -> None:
    compare = CompareService()
    scores_a = make_scores("run-a", "v1", hard_fail=True, effective_score=0.0, raw_score=1.0)
    scores_b = make_scores("run-b", "v2", hard_fail=False, effective_score=4.0, raw_score=4.0)

    artifact = compare.compare(
        run_id="cmp-1",
        prompt_a="v1",
        prompt_b="v2",
        model="gpt-test",
        scores_a=scores_a,
        scores_b=scores_b,
        tie_margin=0.2,
    )

    assert artifact.aggregate.overall_winner == "b"
    assert artifact.cases[0].winner == "b"


def make_scores(run_id: str, prompt_version: str, *, hard_fail: bool, effective_score: float, raw_score: float) -> ScoresArtifact:
    case_score = CaseScore(
        case_id="case-001",
        hard_fail=hard_fail,
        hard_fail_reasons=["failed"] if hard_fail else [],
        rule_checks=RuleCheckResult(),
        trait_scores={
            "instruction_adherence": TraitScore(score=4, reason="ok"),
            "format_compliance": TraitScore(score=4, reason="ok"),
            "clarity_conciseness": TraitScore(score=4, reason="ok"),
            "domain_relevance": TraitScore(score=4, reason="ok"),
            "tone_alignment": TraitScore(score=4, reason="ok"),
        },
        raw_weighted_score=raw_score,
        effective_weighted_score=effective_score,
        normalized_score=effective_score * 20,
        summary="summary",
    )
    aggregate = AggregateScores(
        total_cases=1,
        completed_cases=1,
        cached_cases=0,
        failed_cases=0,
        hard_fail_count=1 if hard_fail else 0,
        hard_fail_rate=1.0 if hard_fail else 0.0,
        average_raw_score=raw_score,
        average_effective_score=effective_score,
        average_normalized_score=effective_score * 20,
        trait_averages={
            "instruction_adherence": 4.0,
            "format_compliance": 4.0,
            "clarity_conciseness": 4.0,
            "domain_relevance": 4.0,
            "tone_alignment": 4.0,
        },
    )
    return ScoresArtifact(
        run_id=run_id,
        created_at=utc_now_iso(),
        prompt_version=prompt_version,
        model="gpt-test",
        config_hash=f"cfg-{prompt_version}",
        dataset_hash="dataset",
        prompt_pack_hash=f"pack-{prompt_version}",
        aggregate=aggregate,
        cases=[case_score],
    )
