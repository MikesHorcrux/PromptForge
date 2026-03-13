from __future__ import annotations

import json

from promptforge.agents.prompt_judge.schemas import RubricJudgeOutput
from promptforge.core.models import DatasetCase, LoadedPrompt, ScoringConfig
from promptforge.runtime.gateway import ModelGateway


def build_judge_payload(
    *,
    prompt: LoadedPrompt,
    case: DatasetCase,
    rendered_prompt: str,
    output_text: str,
) -> str:
    payload = {
        "prompt_version": prompt.manifest.version,
        "prompt_name": prompt.manifest.name,
        "system_prompt": prompt.system_prompt,
        "rendered_user_prompt": rendered_prompt,
        "case": case.model_dump(mode="json"),
        "model_output": output_text,
    }
    return json.dumps(payload, indent=2, sort_keys=True)


class RubricJudge:
    def __init__(self, gateway: ModelGateway) -> None:
        self.gateway = gateway

    async def score(
        self,
        *,
        prompt: LoadedPrompt,
        case: DatasetCase,
        rendered_prompt: str,
        output_text: str,
        scoring_config: ScoringConfig,
        timeout_seconds: float,
    ) -> RubricJudgeOutput:
        payload = build_judge_payload(
            prompt=prompt,
            case=case,
            rendered_prompt=rendered_prompt,
            output_text=output_text,
        )
        return await self.gateway.judge(
            model=scoring_config.judge_model,
            payload=payload,
            scoring_config=scoring_config,
            timeout_seconds=timeout_seconds,
        )

