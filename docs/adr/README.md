# Architecture Decision Records

_Last verified against commit `065f5120dee568fe5b33c7565e7d62942d325db0`._

This directory captures the architecture decisions visible in the current code.
These ADRs are descriptive of the implementation as it exists today. They are
useful for new engineers, reviewers, and operators who need the reasoning behind
the current shape of the system.

## ADR Index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](0001-cli-first-artifact-driven-runtime.md) | CLI-first, artifact-driven runtime | Superseded |
| [ADR-0002](0002-multi-provider-gateway.md) | Multi-provider gateway for generation and judging | Accepted |
| [ADR-0003](0003-filesystem-artifacts-plus-sqlite-cache.md) | Filesystem artifacts plus SQLite cache | Accepted |
| [ADR-0004](0004-schema-first-evaluation-contract.md) | Schema-first contracts for prompt packs, datasets, and artifacts | Accepted |
| [ADR-0005](0005-compare-builds-on-full-child-runs.md) | Compare builds on full child evaluation runs | Accepted |
| [ADR-0006](0006-macos-app-helper-and-prompt-workspace.md) | macOS app, local helper, and prompt workspace as the primary interactive surface | Accepted |

## How to use this folder

- Read ADR-0001 through ADR-0003 first if you are new to the repo.
- Read ADR-0004 before changing prompt pack, dataset, or artifact schemas.
- Read ADR-0005 before changing compare behavior or report generation.
- Read ADR-0006 before changing macOS app flow, helper RPCs, prompt workspace behavior, or lazy forge-session startup.

## Source of truth

- [`../../apps/macos/PromptForge/PromptForge/ContentView.swift`](../../apps/macos/PromptForge/PromptForge/ContentView.swift)
- [`../../apps/macos/PromptForge/PromptForge/Item.swift`](../../apps/macos/PromptForge/PromptForge/Item.swift)
- [`../../src/promptforge/cli.py`](../../src/promptforge/cli.py)
- [`../../src/promptforge/helper/server.py`](../../src/promptforge/helper/server.py)
- [`../../src/promptforge/forge/workspace.py`](../../src/promptforge/forge/workspace.py)
- [`../../src/promptforge/forge/service.py`](../../src/promptforge/forge/service.py)
- [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
- [`../../src/promptforge/runtime/gateway.py`](../../src/promptforge/runtime/gateway.py)
- [`../../src/promptforge/runtime/cache.py`](../../src/promptforge/runtime/cache.py)
- [`../../src/promptforge/core/models.py`](../../src/promptforge/core/models.py)
