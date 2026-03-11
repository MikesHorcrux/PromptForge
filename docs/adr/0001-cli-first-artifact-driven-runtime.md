# ADR-0001: CLI-first, Artifact-driven Runtime

_Last verified against commit `065f5120dee568fe5b33c7565e7d62942d325db0`._

- Status: Superseded by ADR-0006

## Context

This record captures the original v1 shape of PromptForge before the macOS app
and local helper became the primary interactive prompt-workspace surface.

PromptForge is still used to evaluate prompt packs locally or in CI-style
workflows. The CLI remains the setup, status, and batch-evaluation surface, and
the system still has no long-running service, scheduler, queue, or HTTP API.

The runtime writes explicit artifacts for every run under `var/runs/<run_id>/`.
Those artifacts are later reused by `pf report` and by operators diagnosing
failures.

## Decision

Keep the system CLI-first and artifact-driven.

One CLI invocation is the unit of work. A run should:

- load inputs from the local filesystem
- execute through a provider backend
- score and compare locally
- persist durable artifacts to disk
- exit cleanly without relying on a control plane

## Consequences

Positive:

- onboarding is simple
- runs are easy to reproduce and inspect
- local and CI usage look the same
- failure recovery is mostly artifact-based, not service-based

Tradeoffs:

- there is no shared job state or remote coordination
- there is no API for multi-user or always-on operation
- scaling beyond a single process requires new architecture

## Evidence in code

- CLI entrypoint and commands: [`../../src/promptforge/cli.py`](../../src/promptforge/cli.py)
- Run orchestration: [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
- Artifact persistence: [`../../src/promptforge/runtime/artifacts.py`](../../src/promptforge/runtime/artifacts.py)
- Report rebuild flow: [`../../src/promptforge/runtime/report_service.py`](../../src/promptforge/runtime/report_service.py)
