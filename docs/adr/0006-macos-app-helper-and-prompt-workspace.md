# ADR-0006: macOS App, Local Helper, and Prompt Workspace as the Primary Interactive Surface

_Last verified against commit `065f5120dee568fe5b33c7565e7d62942d325db0`._

- Status: Accepted

## Context

The original PromptForge shape was CLI-first. That worked for setup, status,
and batch evaluation, but it was too blunt for interactive prompt iteration.

The current implementation now has:

- a SwiftUI macOS app
- a local Unix-socket helper process
- prompt-scoped overview metadata in `prompt_packs/<version>/prompt.json`
- prompt-scoped forge sessions in `var/forge/<session_id>/`
- an agent chat flow that can converse, stage edits, and trigger evaluations

That interactive surface needs different behavior than the batch CLI:

- prompt open should be cheap
- prompt files and prompt intent should be viewable before session startup
- secrets should be surfaced through app-safe connection state, not raw values
- prompt history, pending edits, and chat state should stay local and prompt-scoped

## Decision

Treat the macOS app plus local helper as the primary interactive surface for
prompt work, while keeping the CLI for setup, status, and batch execution.

Concretely:

- `pf forge` launches the app for the current project
- the app talks only to the local helper over a Unix socket
- prompt packs now include `prompt.json` for prompt intent fields
- the app shows a prompt overview and a separate editor/chat surface
- normal chat is routed through agent chat instead of forcing slash commands
- forge sessions are created lazily on the first real interactive action
- quick benchmarks and full evaluations are explicit user actions, not hidden prompt-open work

## Consequences

Positive:

- prompt iteration is faster to understand because prompt intent, prompt files,
  chat, and benchmark history are separated in the UI
- prompt open latency is reduced because prompt dashboards do not auto-run benchmarks
- the app can show auth state and onboarding without exposing secrets
- prompt history, pending edits, and chat context stay local and inspectable

Tradeoffs:

- there are now two first-class surfaces to maintain: app/helper and CLI
- helper RPC shape becomes part of the effective architecture surface
- first agent use on a prompt still pays forge-session startup cost
- Codex-backed chat can still feel slower than direct OpenAI-compatible calls

## Evidence in code

- App shell: [`../../apps/macos/PromptForge/PromptForge/ContentView.swift`](../../apps/macos/PromptForge/PromptForge/ContentView.swift)
- App model and helper client: [`../../apps/macos/PromptForge/PromptForge/Item.swift`](../../apps/macos/PromptForge/PromptForge/Item.swift)
- Helper RPC surface: [`../../src/promptforge/helper/server.py`](../../src/promptforge/helper/server.py)
- Prompt workspace service: [`../../src/promptforge/forge/workspace.py`](../../src/promptforge/forge/workspace.py)
- Forge session behavior: [`../../src/promptforge/forge/service.py`](../../src/promptforge/forge/service.py)
- Prompt intent metadata: [`../../src/promptforge/prompts/brief.py`](../../src/promptforge/prompts/brief.py)
