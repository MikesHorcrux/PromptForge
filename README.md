# PromptForge

PromptForge is intended to become a self-contained macOS prompt IDE with an integrated agent for authoring, testing, and evaluating prompts locally.

Today, this repository is closer to "engine plus early app" than a finished downloadable product:

- a Python runtime and CLI for running prompt packs against datasets
- reproducible run artifacts, scoring, comparison, and reporting
- a macOS app shell that opens local projects, edits prompt packs, runs checks, and talks to a local helper/agent
- provider paths for OpenAI API and Codex auth today, with room to expand later

## Current State

What already exists:

- versioned prompt packs in `prompt_packs/<version>/`
- JSONL datasets in `datasets/`
- evaluation runs under `var/runs/<run_id>/`
- local workspace/session state under `var/forge/`
- a local helper process used by the macOS app
- agent-assisted prompt editing, prompt reviews, test suites, and quick/full evaluations in the app

What is still missing if the goal is "easy to download and use":

- a polished app distribution story
- a hardened packaged runtime that does not depend on a developer-style local setup
- signing/notarization/release automation for macOS
- simpler onboarding for non-technical users

If your target is a real prompt IDE product, the right framing is:

1. the Python runtime is the engine
2. the macOS app is the product surface
3. the helper is the local boundary between them
4. packaging and release need to be treated as first-class work, not an afterthought

## Development Setup

1. Copy `.env.example` to `.env`
2. Set `OPENAI_API_KEY` if you want the OpenAI provider
3. Make sure `codex login` works if you want the Codex provider
4. Create and activate a virtualenv
5. Install dependencies with `pip install -e '.[dev]'`
6. Run `pf doctor`

## Core Commands

Run one prompt pack:

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
```

Compare two prompt packs:

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
```

Rebuild or print a report:

```bash
pf report --run <run_id>
```

Open the macOS workspace:

```bash
pf app
```

Run tests:

```bash
pytest -q
```

## Architecture

The current architecture is local-first:

- the CLI and app both operate on a project folder
- prompt definitions live on disk under `prompt_packs/`
- datasets are immutable JSONL files
- evaluations write reproducible artifacts to `var/runs/`
- the macOS app launches a local Python helper over a Unix socket
- provider access is abstracted behind the runtime gateway layer

The bundled app path now emits a runtime manifest and can bundle the native Codex CLI into the app resources when it is available at build time. That tightens the runtime contract and moves the app closer to a real self-contained build, but it is still not the same thing as a polished signed/notarized consumer release.

## Repository Layout

```text
apps/macos/PromptForge/       SwiftUI macOS app and bundle script
apps/README.md                Product-surface map
datasets/                     JSONL evaluation datasets
docs/                         Architecture and operational docs
packaging/                    App packaging and release support files
prompt_packs/                 Versioned prompt packs
scenarios/                    Saved prompt test suites
src/README.md                 Engine map
src/promptforge/              Runtime, CLI, helper, workspace, scoring
tests/                        Automated tests
var/                          Generated local artifacts and state
```

## Direction

If the next milestone is the product you described, the priorities should be:

1. make the macOS app the primary experience
2. keep OpenAI API and Codex auth as the first two provider paths
3. tighten the agent workflow inside the IDE around edit, test, review, and ship
4. build a real bundled-runtime and release pipeline for macOS distribution
