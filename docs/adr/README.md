# Architecture Decision Records

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

This folder records the major architecture decisions that are visible in the
current codebase. These ADRs are descriptive, not speculative.

## ADR Index

| ADR | Title | Status |
|---|---|---|
| [ADR-0001](0001-cli-first-artifact-driven-runtime.md) | CLI-first, artifact-driven runtime | Superseded |
| [ADR-0002](0002-multi-provider-gateway.md) | Multi-provider gateway for generation and judging | Accepted |
| [ADR-0003](0003-filesystem-artifacts-plus-sqlite-cache.md) | Filesystem artifacts plus SQLite cache | Accepted |
| [ADR-0004](0004-schema-first-evaluation-contract.md) | Schema-first prompt, dataset, and artifact contracts | Accepted |
| [ADR-0005](0005-compare-builds-on-full-child-runs.md) | Compare builds on full child evaluation runs | Accepted |
| [ADR-0006](0006-macos-app-helper-and-prompt-workspace.md) | macOS app, local helper, and forge workspace as the primary interactive surface | Accepted |

## Reading Order

1. ADR-0001 for the original CLI-first baseline
2. ADR-0002 through ADR-0005 for the runtime architecture
3. ADR-0006 for the interactive app/helper/workspace layer

## What These ADRs Cover

- runtime shape
- provider abstraction
- persistence strategy
- schema-first contracts
- compare semantics
- app/helper/forge workspace architecture

## What These ADRs Do Not Cover Yet

- packaging reproducibility for the bundled app runtime
- the current single-project-per-helper cwd assumption
- the remaining compatibility layer around legacy `prompt_blocks`

Those are real architecture concerns, but they are not yet captured as first-class ADRs in this repo.

## Source Of Truth

- [src/promptforge/cli.py](../../src/promptforge/cli.py)
- [src/promptforge/runtime/run_service.py](../../src/promptforge/runtime/run_service.py)
- [src/promptforge/runtime/gateway.py](../../src/promptforge/runtime/gateway.py)
- [src/promptforge/runtime/cache.py](../../src/promptforge/runtime/cache.py)
- [src/promptforge/forge/workspace.py](../../src/promptforge/forge/workspace.py)
- [src/promptforge/forge/service.py](../../src/promptforge/forge/service.py)
- [src/promptforge/helper/server.py](../../src/promptforge/helper/server.py)
- [apps/macos/PromptForge/PromptForge/ContentView.swift](../../apps/macos/PromptForge/PromptForge/ContentView.swift)
- [apps/macos/PromptForge/PromptForge/Item.swift](../../apps/macos/PromptForge/PromptForge/Item.swift)
