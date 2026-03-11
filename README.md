<p align="center">
  <img src="docs/assets/promptforge-banner.png" alt="PromptForge banner" width="100%" />
</p>

# PromptForge

_Last verified against commit `065f5120dee568fe5b33c7565e7d62942d325db0`._

PromptForge is a macOS-first prompt engineering workbench with a local Python
engine. The app is the main interactive surface. The CLI stays in place for
setup, status, batch evaluation, comparison, and reporting.

It is built for:

- Prompt engineers comparing prompt pack revisions against a fixed dataset
- Operators who need a predictable local workflow and durable artifacts
- Technical and non-technical stakeholders who need a readable report, not raw model transcripts

What it does:

- Loads a versioned prompt pack from `prompt_packs/<version>/`
- Keeps per-prompt intent and editing context in `prompt_packs/<version>/prompt.json`
- Loads a JSONL evaluation dataset from `datasets/`
- Opens a local macOS app for prompt-first, chat-driven iteration
- Includes an in-app settings surface for providers, models, datasets, auth status, and first-run onboarding
- Opens each prompt into a simpler prompt-first flow with an overview dashboard and a dedicated chat editor
- Treats plain chat messages as an agent conversation for the active prompt instead of requiring slash commands for every action
- Shows benchmark trend history and revision summaries in the macOS UI
- Uses a local helper process over a Unix socket for agent edits and benchmark calls
- Resolves app API keys from macOS Keychain before falling back to inherited local env values
- Runs each case through one of three provider paths: `openai`, `openrouter`, or `codex`
- Scores outputs with deterministic rule checks plus a rubric judge
- Compares prompt versions case-by-case and overall
- Writes reproducible artifacts under `var/runs/<run_id>/`

What it does not do:

- It is not a web service or background worker
- It does not mutate datasets
- It does not include a human approval workflow
- It does not guarantee provider-side retention or privacy beyond the request flags it sends

## Why teams use it

- Faster prompt iteration with cached reruns and reproducible lockfiles
- Clear operator workflow: `setup`, `status`, `doctor`, `forge`, `prompts`, `run`, `compare`, `report`
- Evidence-rich outputs for reviews, release decisions, and regressions
- Minimal local footprint: filesystem artifacts plus a single SQLite cache

```mermaid
flowchart LR
  Author["Prompt author"] --> CLI["pf setup / pf status / pf compare"]
  Author --> App["PromptForge.app"]
  App --> Helper["Local helper<br/>src/promptforge/helper/server.py"]
  Helper --> Engine["Forge + eval engine<br/>src/promptforge/forge/* + runtime/*"]
  Engine --> Artifacts["var/runs/ + var/forge/"]
  Engine --> Providers["OpenAI / OpenRouter / Codex"]
```

## 5-minute quickstart

Prerequisites:

- Python 3.11+
- One auth path:
  - OpenAI API key, or
  - OpenRouter API key, or
  - A working Codex CLI login

Install and run:

```bash
make bootstrap
. .venv/bin/activate
pf setup
pf doctor
pf forge
```

What the wizard does:

- Creates or updates `.env` from `.env.example`
- Lets you choose `openai`, `openrouter`, or `codex`
- Stores provider defaults such as `PF_PROVIDER`, `OPENAI_BASE_MODEL`, and `OPENAI_JUDGE_MODEL`
- Prompts for API keys where needed
- Checks `codex login status` and can launch `codex login`

On macOS, `pf forge` opens `PromptForge.app` for the current project. The app
handles prompt selection, prompt intent fields, prompt-file editing, agent chat,
staged edit proposals, apply/discard, settings, onboarding, and benchmark
feedback. The helper RPC exposes a live long-poll event stream through
`events.subscribe`, and the app hydrates OpenAI/OpenRouter API keys from the
macOS Keychain when launching the helper. Prompt opens are intentionally cheap:
the app loads prompt files and dashboard state first, then creates a forge
session only when the user chats, stages edits, saves into a session, or runs an
evaluation. The CLI remains the setup, status, and batch-evaluation surface.

## Core workflow

1. Create or update a prompt pack in `prompt_packs/<version>/`, including `prompt.json`, or use `pf prompts create`.
2. Add or update dataset cases in `datasets/*.jsonl`.
3. Use `pf forge` to open the app and work through a prompt's overview and editor flow.
4. Chat with the agent in plain language, then explicitly run `Run Bench` or `Full Eval` when you want evidence.
5. Inspect `report.md`, `scores.json`, `comparison.json`, and `run.lock.json`.
6. Keep the winning prompt pack version and repeat.

## Key commands

| Command | Purpose | Typical use |
|---|---|---|
| `pf setup` | Interactive onboarding for auth and defaults | First-time setup, provider changes |
| `pf status` | Show auth, provider defaults, and active workspace info | Quick sanity check before using the forge |
| `pf doctor` | Validate auth, model access, prompt pack, dataset, and workspace dirs | Preflight check before a run |
| `pf forge` | Open the PromptForge macOS app for the current project | Day-to-day prompt iteration |
| `pf prompts list` | List the available prompt packs | Review or script multi-prompt workspaces |
| `pf prompts create --prompt draft-v1 --from v1` | Create a new prompt pack | Start a new prompt version quickly |
| `pf run --prompt v1 --dataset datasets/core.jsonl` | Evaluate one prompt pack | Score a single version |
| `pf compare --a v1 --b v2 --dataset datasets/core.jsonl` | Compare two prompt packs | Promotion or regression checks |
| `pf report --run <run_id>` | Print or rebuild a report for an existing run | Share or regenerate human-readable output |

Common provider examples:

```bash
pf run --prompt v1 --dataset datasets/core.jsonl --provider openai --model gpt-5.4
pf run --prompt v1 --dataset datasets/core.jsonl --provider openrouter --model openai/gpt-5
pf run --prompt v1 --dataset datasets/core.jsonl --provider codex --judge-provider codex --model gpt-5-mini
```

## Repository layout

```text
prompt_packs/                 Versioned prompt packs, including per-prompt prompt.json intent files
datasets/                     JSONL evaluation datasets
src/promptforge/              CLI, runtime, scoring, providers, and setup flow
src/promptforge/helper/       Local helper server used by the macOS app
src/promptforge/forge/        Prompt workspace, staged edits, and revision logic
apps/macos/PromptForge/       SwiftUI macOS app
tests/                        Unit and integration-style tests
docs/                         Architecture, operations, security, ADRs, and reference docs
var/                          Generated logs, cache, forge sessions, and run artifacts
```

## Where to go next

- [Documentation index](docs/index.md)
- [Architecture](docs/architecture.md)
- [Runtime and pipeline](docs/runtime-and-pipeline.md)
- [CLI reference](docs/cli-reference.md)
- [Operations](docs/operations.md)
- [Security and safety](docs/security-and-safety.md)
- [Testing and quality](docs/testing-and-quality.md)
- [FAQ](docs/faq.md)
- [Architecture Decision Records](docs/adr/README.md)
- [Eval philosophy](docs/eval-philosophy.md)

## Source-of-truth modules

- CLI and command parsing: [`src/promptforge/cli.py`](src/promptforge/cli.py)
- macOS app shell: [`apps/macos/PromptForge/PromptForge/ContentView.swift`](apps/macos/PromptForge/PromptForge/ContentView.swift)
- macOS app model and helper bridge: [`apps/macos/PromptForge/PromptForge/Item.swift`](apps/macos/PromptForge/PromptForge/Item.swift)
- Setup wizard: [`src/promptforge/setup_wizard.py`](src/promptforge/setup_wizard.py)
- Project metadata: [`src/promptforge/project.py`](src/promptforge/project.py)
- Local helper: [`src/promptforge/helper/server.py`](src/promptforge/helper/server.py)
- Runtime orchestration: [`src/promptforge/runtime/run_service.py`](src/promptforge/runtime/run_service.py)
- Forge session orchestration: [`src/promptforge/forge/service.py`](src/promptforge/forge/service.py)
- Provider backends: [`src/promptforge/runtime/gateway.py`](src/promptforge/runtime/gateway.py)
- Data models: [`src/promptforge/core/models.py`](src/promptforge/core/models.py)
- Prompt and dataset loading: [`src/promptforge/prompts/loader.py`](src/promptforge/prompts/loader.py), [`src/promptforge/datasets/loader.py`](src/promptforge/datasets/loader.py)

<p align="center">
  <img src="docs/assets/promptforge-footer.png" alt="PromptForge footer banner" width="100%" />
</p>
