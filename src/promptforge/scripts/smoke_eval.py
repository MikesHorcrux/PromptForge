from __future__ import annotations

import asyncio

from promptforge.core.config import settings
from promptforge.core.models import RunConfig, RunRequest, ScoringConfig
from promptforge.runtime.gateway import build_gateway
from promptforge.runtime.run_service import EvaluationService


async def _main() -> None:
    provider = settings.provider
    judge_provider = settings.judge_provider or provider
    service = EvaluationService(build_gateway(provider=provider, judge_provider=judge_provider))
    manifest = await service.run(
        RunRequest(
            prompt_version="v1",
            model=settings.openai_base_model,
            dataset_path="datasets/core.jsonl",
            run_config=RunConfig(),
            scoring_config=ScoringConfig(judge_model=settings.openai_judge_model),
            provider=provider,
            judge_provider=judge_provider,
        )
    )
    print(manifest.run_id)


def main() -> None:
    asyncio.run(_main())


if __name__ == "__main__":
    main()
