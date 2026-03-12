# ADR-0002: Multi-provider Gateway for Generation and Judging

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

- Status: Accepted

## Context

PromptForge supports three runtime paths:

- direct OpenAI-compatible API calls
- OpenRouter through an OpenAI-compatible client
- Codex CLI execution

It also allows the generation provider and the judge provider to differ.
That means the runtime needs a stable internal contract even though provider
transport and auth models differ.

## Decision

Hide provider-specific behavior behind a gateway contract with two operations:

- `generate(...)`
- `judge(...)`

Use:

- `OpenAICompatibleGateway` for `openai` and `openrouter`
- `CodexGateway` for `codex`
- `CompositeGateway` when judge and generation providers differ

## Consequences

Positive:

- CLI and orchestration code stay provider-agnostic
- teams can mix provider choices without rewriting run logic
- provider-specific retries and warnings stay localized

Tradeoffs:

- capability differences leak through warnings and omitted options
- provider parity is not perfect; for example, `seed` is recorded but not applied
- Codex has a broader local execution context than plain API calls

## Evidence in code

- Gateway interface and provider implementations: [`../../src/promptforge/runtime/gateway.py`](../../src/promptforge/runtime/gateway.py)
- Client construction and auth sources: [`../../src/promptforge/core/openai_client.py`](../../src/promptforge/core/openai_client.py)
- Provider selection from CLI flags: [`../../src/promptforge/cli.py`](../../src/promptforge/cli.py)
