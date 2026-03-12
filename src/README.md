# Engine

This directory is the local PromptForge engine.

Why it lives under `src/`:

- Python packaging expects installable source here
- the macOS app bundles this tree into its local runtime
- the CLI also imports from here directly

Main areas:

- `promptforge/helper/`: app-to-engine boundary
- `promptforge/forge/`: prompt workspace and agent loop
- `promptforge/runtime/`: evaluation, comparison, and artifact generation
- `promptforge/prompts/`, `promptforge/datasets/`, `promptforge/scenarios/`: file-backed project inputs
