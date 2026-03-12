# ADR-0004: Schema-first Contracts for Prompt Packs, Datasets, and Artifacts

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

- Status: Accepted

## Context

PromptForge depends on repeatable evaluation inputs and inspectable outputs.
If prompt packs, dataset cases, or artifact shapes drift silently, comparisons
and cache reuse become hard to trust.

The current implementation already models most runtime contracts explicitly with
JSON schema, JSONL validation, and Pydantic models.

## Decision

Treat the evaluation surface as schema-first:

- prompt packs require `manifest.yaml`, `system.md`, `user_template.md`, and `variables.schema.json`
- dataset lines are parsed into typed `DatasetCase` models
- prompt inputs are validated against `variables.schema.json` before execution
- artifacts are written from typed models such as `RunManifest`, `ScoresArtifact`, and `ComparisonArtifact`

## Consequences

Positive:

- bad datasets fail before provider calls
- prompt changes and dataset changes feed content hashes deterministically
- downstream docs and operators can rely on stable artifact shapes

Tradeoffs:

- schema evolution must be handled carefully because there is no migration layer
- comparison `scores.json` intentionally differs from evaluation `scores.json`, so consumers must inspect run kind
- strict validation makes malformed examples fail fast instead of degrading gracefully

## Evidence in code

- Prompt pack loading and validation: [`../../src/promptforge/prompts/loader.py`](../../src/promptforge/prompts/loader.py)
- Dataset loading: [`../../src/promptforge/datasets/loader.py`](../../src/promptforge/datasets/loader.py)
- Typed contracts: [`../../src/promptforge/core/models.py`](../../src/promptforge/core/models.py)
- Artifact generation: [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
