from __future__ import annotations

import asyncio

from promptforge.core.config import settings
from promptforge.core.openai_client import get_openai_client


async def _main() -> None:
    client = get_openai_client()
    response = await client.responses.create(
        model=settings.openai_base_model,
        input="Reply with exactly: OPENAI_OK",
        max_output_tokens=20,
        store=False,
    )
    print(response.output_text)


def main() -> None:
    asyncio.run(_main())


if __name__ == "__main__":
    main()

