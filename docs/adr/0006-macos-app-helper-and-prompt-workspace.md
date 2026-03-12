# ADR-0006: macOS App, Local Helper, and Prompt Workspace as the Primary Interactive Surface

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

- Status: Accepted

## Context

PromptForge started as a CLI-first prompt evaluation tool. That is still true
for setup, status, batch execution, and reporting, but it is not sufficient for
interactive prompt authoring.

The current implementation includes:

- a SwiftUI macOS app
- a local Unix-socket helper
- prompt-scoped forge sessions under `var/forge/`
- prompt-scoped metadata in `prompt.json`
- an interactive workspace with navigator, Forgie chat, editor, cases, results, and inspector

Interactive prompt work needs different behavior than the batch CLI:

- opening a prompt should be cheap
- empty projects should still open cleanly
- sessions should be created lazily
- edits should be staged or applied through revision-aware workspace flows
- provider connection checks should not make normal app navigation slow

## Decision

Treat the macOS app plus local helper as the primary interactive surface for
prompt work, while keeping the CLI as the primary setup and batch surface.

Concretely:

- `pf forge` launches `PromptForge.app`
- the app talks only to the local helper over a Unix socket
- the helper exposes prompt, scenario, review, and agent RPCs
- prompt files and prompt metadata can be viewed without creating a forge session
- the first real action, such as chat, save, quick check, suite run, or playground run, creates or reloads the session lazily
- app connection probes are explicit through `connections.refresh`
- the app prefers a bundled Python engine, with explicit or debug fallbacks for development

## Consequences

Positive:

- prompt authoring, case editing, and review have a native local workspace
- prompt open stays fast because it does not implicitly benchmark
- empty projects are valid onboarding states
- app auth state can be shown without exposing raw secret values
- prompt revisions, proposals, reviews, and decisions remain local and inspectable

Tradeoffs:

- there are now two first-class surfaces to maintain: CLI and app/helper
- helper RPCs are part of the effective architecture contract
- the helper is still single-project-per-process because it binds itself to one cwd
- interactive performance still depends on provider choice, especially for Codex

## Evidence In Code

- App shell: [../../apps/macos/PromptForge/PromptForge/ContentView.swift](../../apps/macos/PromptForge/PromptForge/ContentView.swift)
- App model and helper client: [../../apps/macos/PromptForge/PromptForge/Item.swift](../../apps/macos/PromptForge/PromptForge/Item.swift)
- App runtime locator: [../../apps/macos/PromptForge/PromptForge/PromptForgeApp.swift](../../apps/macos/PromptForge/PromptForge/PromptForgeApp.swift)
- Bundled runtime build script: [../../apps/macos/PromptForge/scripts/bundle_engine.sh](../../apps/macos/PromptForge/scripts/bundle_engine.sh)
- Helper RPC surface: [../../src/promptforge/helper/server.py](../../src/promptforge/helper/server.py)
- Workspace service: [../../src/promptforge/forge/workspace.py](../../src/promptforge/forge/workspace.py)
- Forge session behavior: [../../src/promptforge/forge/service.py](../../src/promptforge/forge/service.py)
- Prompt metadata: [../../src/promptforge/prompts/brief.py](../../src/promptforge/prompts/brief.py)
