# CLI Reference

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

PromptForge exposes one console entrypoint: `pf`.

```bash
pf <command> [options]
```

Available commands:

- `setup`
- `status`
- `doctor`
- `forge`
- `prompts`
- `scenario`
- `review`
- `promote`
- `run`
- `compare`
- `report`

## Shared Concepts

### Providers

| Provider | Auth path | Runtime path |
|---|---|---|
| `openai` | `OPENAI_API_KEY` | OpenAI Responses API |
| `openrouter` | `OPENROUTER_API_KEY` + `OPENROUTER_BASE_URL` | OpenAI-compatible client with custom base URL |
| `codex` | `codex login` | `codex exec` subprocesses |

### Shared execution flags for `run` and `compare`

| Flag | Meaning | Default source |
|---|---|---|
| `--model` | generation model | provider-specific default or `.env` |
| `--provider` | generation provider | `PF_PROVIDER` |
| `--judge-provider` | judge provider | `PF_JUDGE_PROVIDER` or generation provider |
| `--temperature` | generation temperature | unset |
| `--max-tokens` | max output tokens | `PF_DEFAULT_MAX_OUTPUT_TOKENS` |
| `--seed` | recorded for reproducibility | unset |
| `--retries` | request retries | `PF_DEFAULT_RETRIES` |
| `--timeout` | per-request timeout seconds | `PF_DEFAULT_TIMEOUT_SECONDS` |
| `--concurrency` | max concurrent cases | `PF_DEFAULT_CONCURRENCY` |
| `--failure-threshold` | soft-stop threshold | `PF_DEFAULT_FAILURE_THRESHOLD` |
| `--scoring-config` | YAML scoring override file | unset |

## Command Reference

## `pf setup`

Interactive onboarding for auth and provider defaults.

```bash
pf setup
pf setup --env-file .env.local
```

Flags:

| Flag | Meaning |
|---|---|
| `--env-file` | environment file to create or update |
| `--example-env-file` | template used when the env file does not exist |

What it does:

- creates `.env` from `.env.example` when needed
- asks for generation and judge providers
- suggests provider-specific default models
- prompts for OpenAI/OpenRouter keys when needed
- checks `codex login status` and can launch login
- optionally runs `pf doctor`

Use it when:

- bootstrapping a repo
- switching providers
- changing default models

Troubleshooting:

- Codex missing: install the CLI or set `PF_CODEX_BIN`
- auth saved but still broken: rerun `pf doctor` in the same shell

## `pf status`

Shows local project and auth state without running a full evaluation.

```bash
pf status
```

Shows:

- env file location
- default provider and judge provider
- generation and judge models
- redacted OpenAI/OpenRouter key presence
- Codex login status
- project root and directory layout
- active prompt and active forge session

Use it when:

- checking a fresh shell
- confirming which project is active
- confirming model/provider defaults

## `pf doctor`

Validates environment, inputs, and live model access.

```bash
pf doctor
pf doctor --prompt v2 --dataset datasets/core.jsonl
pf doctor --provider codex --judge-provider codex --model gpt-5-mini
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | prompt pack to validate |
| `--dataset` | dataset to validate |
| `--model` | model used for the live check |
| `--provider` | provider to test |
| `--judge-provider` | judge provider to test alongside the generation provider |

Checks:

- Python version
- prompt-pack loading
- dataset loading
- workspace directories
- provider auth
- model access by asking the provider to return `PF_OK`

Use it when:

- before the first run on a machine
- after auth changes
- after switching providers or models

## `pf forge`

Launches the macOS app for the current project.

```bash
pf forge
pf forge --project /path/to/project
```

Flags:

| Flag | Meaning |
|---|---|
| `--project` | project root to open |

Behavior:

- ensures the target folder has PromptForge project scaffolding
- locates `PromptForge.app`
- launches the app with `--project <root>` and `--engine-root <repo-root>`

The app then prefers:

1. explicit engine root
2. bundled engine in the app resources
3. saved engine root
4. debug-only project fallback

Use it when:

- editing prompts interactively
- managing case sets
- running reviews and playground trials

## `pf prompts list`

Lists prompt packs in the current project.

```bash
pf prompts list
```

Use it when:

- checking what prompt versions exist
- scripting prompt selection

## `pf prompts create`

Creates a new prompt pack, optionally cloned from an existing pack.

```bash
pf prompts create --prompt draft-v2
pf prompts create --prompt draft-v2 --from v1 --name "Draft v2"
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | new prompt pack version |
| `--from` | optional source prompt pack to clone |
| `--name` | optional display name |

Creates:

- `manifest.yaml`
- `system.md`
- `user_template.md`
- `variables.schema.json`
- `prompt.json`

## `pf scenario list`

Lists saved scenario suites.

```bash
pf scenario list
pf scenario list --prompt v1
pf scenario list --prompt v1 --json
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | optional prompt ref used to filter linked suites |
| `--json` | emit JSON instead of human-friendly output |

## `pf scenario show`

Shows one saved scenario suite.

```bash
pf scenario show --suite core
pf scenario show --suite core --json
```

Flags:

| Flag | Meaning |
|---|---|
| `--suite` | suite ID |
| `--json` | emit JSON |

## `pf scenario create`

Creates a new scenario suite.

```bash
pf scenario create --suite returns
pf scenario create --suite returns --prompt v1 --name "Returns" --description "Return flow cases"
```

Flags:

| Flag | Meaning |
|---|---|
| `--suite` | new suite ID |
| `--prompt` | optional linked prompt |
| `--name` | display name |
| `--description` | suite description |

## `pf scenario run`

Runs one saved scenario suite against one prompt.

```bash
pf scenario run --suite core --prompt v1
pf scenario run --suite core --prompt v1 --repeats 3 --json
```

Flags:

| Flag | Meaning |
|---|---|
| `--suite` | suite ID |
| `--prompt` | prompt ref |
| `--repeats` | optional repeat-count override |
| `--json` | emit JSON |

Behavior:

- creates or reloads the forge session for the prompt
- runs every suite case against the current prompt and the baseline
- stores the resulting review inside the forge session

## `pf review`

Shows the latest saved reviews for a prompt.

```bash
pf review --prompt v1
pf review --prompt v1 --json
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | prompt ref |
| `--json` | emit JSON |

Use it when:

- you want review results from the CLI instead of the app

## `pf promote`

Promotes the current prompt workspace to baseline and records a decision.

```bash
pf promote --prompt v1 --summary "Ship candidate"
pf promote --prompt v1 --summary "Ship candidate" --rationale "Improves case wins"
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | prompt ref |
| `--summary` | short decision summary |
| `--rationale` | optional rationale |
| `--review-id` | optional review identifier |
| `--suite-id` | optional suite identifier |

## `pf run`

Runs one prompt pack against one dataset.

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
pf run --prompt v1 --dataset datasets/core.jsonl --provider openrouter --model openai/gpt-5
pf run --prompt v1 --dataset datasets/core.jsonl --provider codex --judge-provider codex --model gpt-5-mini
```

Required flags:

| Flag | Meaning |
|---|---|
| `--prompt` | prompt pack version or path |
| `--dataset` | path to a JSONL dataset |

Outputs:

- `run.json`
- `run.lock.json`
- `outputs.jsonl`
- `scores.json`
- `comparison.json`
- `report.md`

Use it when:

- you need one repeatable evaluation with durable artifacts

## `pf compare`

Runs two prompt packs against one dataset and writes a comparison run.

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
pf compare --a v1 --b v2 --dataset datasets/core.jsonl --provider codex --judge-provider openai
```

Required flags:

| Flag | Meaning |
|---|---|
| `--a` | baseline prompt pack version or path |
| `--b` | candidate prompt pack version or path |
| `--dataset` | path to a JSONL dataset |

Use it when:

- deciding whether one prompt should replace another
- capturing evidence for promotion or rollback

## `pf report`

Prints or rebuilds `report.md` for an existing run.

```bash
pf report --run run_abc123
pf report --run cmp_abc123 --print
```

Flags:

| Flag | Meaning |
|---|---|
| `--run` | run ID |
| `--print` | print the report to stdout |

Important:

- `pf report` does not rerun provider calls
- it rebuilds the Markdown report from saved artifacts if needed

## Common Operator Recipes

### Validate a workstation

```bash
pf setup
pf doctor
pf status
```

### Evaluate one prompt quickly

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
open var/runs/$(ls -t var/runs | head -n 1)/report.md
```

### Compare a candidate to baseline

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
```

### List and run linked case sets

```bash
pf scenario list --prompt v2
pf scenario run --suite core --prompt v2 --json
```

### Promote after review

```bash
pf review --prompt v2 --json
pf promote --prompt v2 --summary "Promote after passing core review"
```

## Troubleshooting By Command

| Command | Symptom | Likely cause | What to do |
|---|---|---|---|
| `pf setup` | wizard loops on model input | entered `yes` or `no` for a model name | enter a real model name or accept the default |
| `pf status` | wrong active prompt | last opened prompt or workspace state is stale | open the desired prompt in the app or inspect `.promptforge/project.json` |
| `pf doctor` | auth passes but model check fails | selected model not available to that provider | switch model or provider |
| `pf forge` | app fails to open | app not installed or not built | build/install `PromptForge.app` or set `PF_APP_PATH` |
| `pf prompts create` | prompt already exists | version directory already present | choose a new version or remove the old directory |
| `pf scenario run` | suite missing | suite ID not found | run `pf scenario list` first |
| `pf run` | prompt pack invalid | missing required prompt files | fix `manifest.yaml`, `system.md`, `user_template.md`, or `variables.schema.json` |
| `pf run` | dataset case rejected | schema mismatch | fix `case.input` to satisfy `variables.schema.json` |
| `pf compare` | confusing winner | hard-fails outweighed score deltas | inspect child runs and `comparison.json` |
| `pf report` | report missing | run directory incomplete | inspect the run directory and logs, then rerun if needed |

## App Power-User Commands

The macOS app still supports slash commands in the chat composer for power users.
These are not separate CLI commands, but they are part of the current product.

Examples:

- `/help`
- `/prompts`
- `/open <prompt>`
- `/new <prompt>`
- `/clone <source> <name>`
- `/status`
- `/coach <request>`
- `/edit <request>`
- `/save`
- `/bench`
- `/full`
- `/apply`
- `/discard`
- `/undo`
- `/export <name>`

Source:

- [src/promptforge/cli.py](../src/promptforge/cli.py)
- [apps/macos/PromptForge/PromptForge/Item.swift](../apps/macos/PromptForge/PromptForge/Item.swift)
