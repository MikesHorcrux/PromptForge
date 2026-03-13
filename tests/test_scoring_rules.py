from promptforge.core.models import DatasetCase, FormatExpectations
from promptforge.prompts.loader import load_prompt
from promptforge.scoring.rules import derive_hard_fail_reasons, evaluate_rule_checks


def test_rule_scoring_flags_missing_sections() -> None:
    prompt = load_prompt("v1")
    case = DatasetCase(
        id="case-x",
        input={
            "customer_name": "Test",
            "customer_issue": "Need help",
            "goal": "Respond",
            "tone": "clear",
            "policy_snippet": "Policy",
        },
        format_expectations=FormatExpectations(
            output_format="markdown",
            required_sections=["Summary", "Answer", "Next Steps"],
        ),
    )

    checks = evaluate_rule_checks(
        output_text="## Summary\nAll good.\n## Answer\nHere is the answer.",
        case=case,
        prompt=prompt,
        hard_fail_rules=promptforge_default_rules(),
    )
    reasons = derive_hard_fail_reasons(checks, promptforge_default_rules())

    assert "Next Steps" in checks.missing_sections
    assert any("missing required sections" in reason for reason in reasons)


def test_rule_scoring_flags_invalid_json() -> None:
    prompt = load_prompt("v1")
    case = DatasetCase(
        id="case-json",
        input={
            "customer_name": "Test",
            "customer_issue": "Need JSON",
            "goal": "Respond",
            "tone": "clear",
            "policy_snippet": "Policy",
        },
        format_expectations=FormatExpectations(
            output_format="json",
            required_json_fields=["summary", "answer"],
        ),
    )

    checks = evaluate_rule_checks(
        output_text="not-json",
        case=case,
        prompt=prompt,
        hard_fail_rules=promptforge_default_rules(),
    )
    reasons = derive_hard_fail_reasons(checks, promptforge_default_rules())

    assert checks.invalid_json is True
    assert any("invalid JSON" in reason for reason in reasons)


def promptforge_default_rules():
    from promptforge.core.models import HardFailRules

    return HardFailRules()

