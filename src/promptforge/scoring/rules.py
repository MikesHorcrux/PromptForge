from __future__ import annotations

import json
from typing import Any

from promptforge.core.models import DatasetCase, HardFailRules, PromptPack, RuleCheckResult


def _lower_list(values: list[str]) -> list[str]:
    return [value.lower() for value in values]


def evaluate_rule_checks(
    *,
    output_text: str,
    case: DatasetCase,
    prompt_pack: PromptPack,
    hard_fail_rules: HardFailRules,
) -> RuleCheckResult:
    expectations = case.format_expectations
    required_sections = list(dict.fromkeys(prompt_pack.manifest.required_sections + expectations.required_sections))
    output_lower = output_text.lower()
    missing_sections = [section for section in required_sections if section.lower() not in output_lower]
    missing_strings = [value for value in expectations.required_strings if value.lower() not in output_lower]
    forbidden_strings_found = [value for value in expectations.forbidden_strings if value.lower() in output_lower]

    output_format = expectations.output_format or prompt_pack.manifest.output_format
    json_required = output_format == "json" or bool(expectations.required_json_fields)
    invalid_json = False
    missing_json_fields: list[str] = []
    if json_required:
        try:
            parsed = json.loads(output_text)
            if isinstance(parsed, dict):
                missing_json_fields = [field for field in expectations.required_json_fields if field not in parsed]
            else:
                invalid_json = True
                missing_json_fields = expectations.required_json_fields[:]
        except json.JSONDecodeError:
            invalid_json = True
            missing_json_fields = expectations.required_json_fields[:]

    policy_markers_lower = _lower_list(hard_fail_rules.policy_markers)
    policy_markers_found = [
        marker
        for marker, lower in zip(hard_fail_rules.policy_markers, policy_markers_lower)
        if lower in output_lower
    ]

    word_count = len(output_text.split())
    over_max_words = expectations.max_words is not None and word_count > expectations.max_words
    checks = len(required_sections) + len(expectations.required_strings) + len(expectations.required_json_fields)
    penalties = len(missing_sections) + len(missing_strings) + len(missing_json_fields) + len(forbidden_strings_found)
    if json_required:
        checks += 1
        penalties += int(invalid_json)
    if expectations.max_words is not None:
        checks += 1
        penalties += int(over_max_words)
    format_score = 5.0 if checks == 0 else max(0.0, round(5 * (1 - min(1, penalties / checks)), 2))

    return RuleCheckResult(
        required_sections=required_sections,
        missing_sections=missing_sections,
        required_json_fields=expectations.required_json_fields,
        missing_json_fields=missing_json_fields,
        required_strings=expectations.required_strings,
        missing_strings=missing_strings,
        forbidden_strings_found=forbidden_strings_found,
        invalid_json=invalid_json,
        json_required=json_required,
        output_format=output_format,
        policy_markers_found=policy_markers_found,
        word_count=word_count,
        over_max_words=over_max_words,
        format_score=format_score,
    )


def derive_hard_fail_reasons(rule_checks: RuleCheckResult, rules: HardFailRules) -> list[str]:
    reasons: list[str] = []
    if rules.fail_on_missing_sections and rule_checks.missing_sections:
        reasons.append(f"missing required sections: {', '.join(rule_checks.missing_sections)}")
    if rules.fail_on_invalid_json_when_required and rule_checks.json_required and rule_checks.invalid_json:
        reasons.append("invalid JSON when JSON output was required")
    if rules.fail_on_policy_markers and rule_checks.policy_markers_found:
        reasons.append(f"policy markers detected: {', '.join(rule_checks.policy_markers_found)}")
    return reasons
