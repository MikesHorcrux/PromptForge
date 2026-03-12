# Documentation Index

Start with [Start Here](start-here.md) if the repo feels bigger than it should.

PromptForge is easiest to reason about as:

- a macOS app
- a bundled local engine
- an in-app agent
- saved prompt tests and review artifacts

## Recommended Order

1. [Start Here](start-here.md)
2. [README](../README.md)
3. [CLI reference](cli-reference.md)
4. [Architecture](architecture.md)

After that, use the specialized docs only as needed.

## Core Docs

| Document | Why to read it |
|---|---|
| [Start Here](start-here.md) | Simple product model and vocabulary map |
| [README](../README.md) | Current product direction and gaps |
| [CLI reference](cli-reference.md) | Commands, aliases, and examples |
| [Architecture](architecture.md) | App, helper, runtime, and persistence boundaries |
| [Data model](data-model.md) | What lives on disk and where |
| [Runtime and pipeline](runtime-and-pipeline.md) | How runs, comparison, and scoring actually execute |
| [Operations](operations.md) | Setup, troubleshooting, and recovery |
| [Security and safety](security-and-safety.md) | Auth, local data handling, and trust boundaries |
| [Testing and quality](testing-and-quality.md) | Test coverage and release checks |
| [FAQ](faq.md) | Short operational answers |

## Code Map

| Area | Modules |
|---|---|
| App surface | `apps/README.md`, `apps/macos/PromptForge/PromptForge/*.swift` |
| Engine | `src/README.md`, `src/promptforge/*` |
| Packaging | `packaging/README.md`, `packaging/macos/bundle_engine.sh` |
| Helper boundary | `src/promptforge/helper/server.py` |
| Prompt workspace and agent loop | `src/promptforge/forge/*` |
| Runtime execution | `src/promptforge/runtime/*` |

## Note On Naming

Some older internal names still exist in code and docs:

- `forge` often means app/workspace
- `scenario` means test suite
- `promote` means ship

The product docs now prefer the simpler names, but the code has not been fully renamed.
