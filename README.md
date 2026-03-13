<p align="center">
  <img src="docs/assets/promptforge-banner.png" alt="PromptForge banner" width="100%" />
</p>

# PromptForge

PromptForge is building toward a self-contained macOS prompt IDE with an integrated agent for editing prompts, trying inputs, running tests, and reviewing changes locally.

Today, this repo already includes:

- a macOS app shell for prompt editing and agent-driven workflows
- a local engine and helper boundary
- prompt projects stored on disk under `prompts/`
- OpenAI API and Codex auth provider paths
- reproducible datasets, scenario suites, and evaluation runs

## Product Shape

PromptForge is the tool you use to create and improve prompts.

- prompts live in `prompts/<version>/`
- datasets live in `datasets/`
- saved test suites live in `scenarios/`
- run artifacts live in `var/runs/<run_id>/`
- local workspace state lives in `var/forge/`

The direction is straightforward:

1. the macOS app is the main product surface
2. the helper is the local boundary for agent and runtime work
3. OpenAI API and Codex auth are the first provider paths
4. the app moves toward a fully bundled native macOS release

## Development Setup

1. Copy `.env.example` to `.env`
2. Set `OPENAI_API_KEY` if you want the OpenAI provider
3. Make sure `codex login` works if you want the Codex provider
4. Create and activate a virtualenv
5. Install dependencies with `pip install -e '.[dev]'`
6. Run `pf doctor`

## Core Commands

Open the macOS app:

```bash
pf app
```

Run one prompt:

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
```

Compare two prompts:

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
```

Rebuild or print a report:

```bash
pf report --run <run_id>
```

Run tests:

```bash
pytest -q
```

## Repository Layout

```text
apps/macos/PromptForge/       SwiftUI macOS app
apps/README.md                Product-surface map
datasets/                     JSONL evaluation datasets
docs/                         Architecture and operational docs
packaging/                    App packaging and release support files
prompts/                      Versioned prompt definitions
scenarios/                    Saved test suites
src/README.md                 Engine map
src/promptforge/              Runtime, CLI, helper, workspace, scoring
tests/                        Automated tests
var/                          Generated local artifacts and state
```

## Current State

This is still closer to "engine plus app in progress" than a finished consumer download.

What is already working:

- prompt editing and project management in the macOS app
- local helper-backed workflows for prompt loading, saving, tests, and reviews
- reproducible evaluation runs and comparison reports
- OpenAI and Codex connectivity paths

What still needs hardening for release:

- a fully bundled runtime contract
- first-run onboarding polish
- signing, notarization, and release automation
- a smaller native helper surface as the Swift migration continues

<p align="center">
  <img src="docs/assets/promptforge-footer.png" alt="PromptForge footer banner" width="100%" />
</p>
