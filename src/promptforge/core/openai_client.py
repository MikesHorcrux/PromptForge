from __future__ import annotations

from functools import lru_cache

from openai import AsyncOpenAI

from promptforge.core.config import settings


@lru_cache(maxsize=1)
def get_openai_client() -> AsyncOpenAI:
    if not settings.openai_api_key:
        raise RuntimeError("OPENAI_API_KEY is not set.")
    return AsyncOpenAI(api_key=settings.openai_api_key)


@lru_cache(maxsize=4)
def get_openai_compatible_client(provider: str) -> AsyncOpenAI:
    if provider == "openai":
        return get_openai_client()
    if provider == "openrouter":
        if not settings.openrouter_api_key:
            raise RuntimeError("OPENROUTER_API_KEY is not set.")
        return AsyncOpenAI(
            api_key=settings.openrouter_api_key,
            base_url=settings.openrouter_base_url,
        )
    raise ValueError(f"Unsupported OpenAI-compatible provider: {provider}")
