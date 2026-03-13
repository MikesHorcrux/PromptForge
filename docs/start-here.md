# Start Here

PromptForge is easiest to understand if you ignore most of the internal names and use this model:

## Product Model

- `app`: the macOS prompt IDE
- `engine`: the bundled local Python runtime
- `agent`: the in-app editing and testing assistant
- `tests`: saved prompt test suites and cases
- `review`: comparison results against the baseline prompt
- `ship`: copy the approved candidate back to baseline

## Current Truth

The repo already has all three main layers:

- macOS app in `apps/macos/PromptForge/`
- local helper and runtime in `src/promptforge/`
- packaging support in `packaging/`
- file-backed project state in `prompts/`, `datasets/`, `scenarios/`, and `var/`

The confusing part is that the codebase still mixes older names with the product you actually want:

- `forge` means `app` or workspace in many places
- `scenario` means `tests`
- `promote` means `ship`
- `builder` usually means `agent`

For product work, read them using the simpler names above.

## What To Open First

If you want the product surface:

1. [README](../README.md)
2. [CLI reference](cli-reference.md)
3. [Architecture](architecture.md)

If you want the app:

1. `apps/README.md`
2. `apps/macos/PromptForge/PromptForge/ContentView.swift`
3. `apps/macos/PromptForge/PromptForge/Item.swift`

If you want the engine:

1. `src/README.md`
2. `src/promptforge/helper/server.py`
3. `src/promptforge/forge/workspace.py`
4. `src/promptforge/forge/service.py`
5. `src/promptforge/runtime/gateway.py`
6. `src/promptforge/runtime/run_service.py`

If you want packaging:

1. `packaging/README.md`
2. `packaging/macos/bundle_engine.sh`

## Product Loop

The core loop should be read as:

1. Open a prompt in the app.
2. Edit prompt files with help from the agent.
3. Run quick checks or saved tests.
4. Review diffs, failures, and regressions.
5. Ship the candidate back to baseline.

Everything outside that loop is secondary.
