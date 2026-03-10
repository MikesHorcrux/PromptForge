# Architecture Decision Records

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

This directory captures the architecture decisions visible in the current code.
These ADRs are descriptive of the implementation as it exists today. They are
useful for new engineers, reviewers, and operators who need the reasoning behind
the current shape of the system.

## ADR Index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](0001-cli-first-artifact-driven-runtime.md) | CLI-first, artifact-driven runtime | Accepted |
| [ADR-0002](0002-multi-provider-gateway.md) | Multi-provider gateway for generation and judging | Accepted |
| [ADR-0003](0003-filesystem-artifacts-plus-sqlite-cache.md) | Filesystem artifacts plus SQLite cache | Accepted |
| [ADR-0004](0004-schema-first-evaluation-contract.md) | Schema-first contracts for prompt packs, datasets, and artifacts | Accepted |
| [ADR-0005](0005-compare-builds-on-full-child-runs.md) | Compare builds on full child evaluation runs | Accepted |

## How to use this folder

- Read ADR-0001 through ADR-0003 first if you are new to the repo.
- Read ADR-0004 before changing prompt pack, dataset, or artifact schemas.
- Read ADR-0005 before changing compare behavior or report generation.

## Source of truth

- [`../../src/promptforge/cli.py`](../../src/promptforge/cli.py)
- [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
- [`../../src/promptforge/runtime/gateway.py`](../../src/promptforge/runtime/gateway.py)
- [`../../src/promptforge/runtime/cache.py`](../../src/promptforge/runtime/cache.py)
- [`../../src/promptforge/core/models.py`](../../src/promptforge/core/models.py)
