from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput
from promptforge.runtime.gateway import _normalize_codex_json_schema


def test_codex_schema_is_closed_recursively() -> None:
    schema = _normalize_codex_json_schema(RubricJudgeOutput.model_json_schema())

    assert schema["additionalProperties"] is False
    assert set(schema["required"]) == set(schema["properties"].keys())
    assert schema["$defs"]["RubricTraitScore"]["additionalProperties"] is False
    assert set(schema["$defs"]["RubricTraitScore"]["required"]) == set(schema["$defs"]["RubricTraitScore"]["properties"].keys())
