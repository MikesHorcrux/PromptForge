# CLI Reference

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

PromptForge exposes one console entrypoint: `pf`.

## Global usage

```bash
pf <command> [options]
```

Available commands:

- `setup`
- `status`
- `doctor`
- `forge`
- `prompts`
- `run`
- `compare`
- `report`

## Shared concepts

### Providers

| Provider | How it authenticates | Runtime path |
|---|---|---|
| `openai` | `OPENAI_API_KEY` | `AsyncOpenAI.responses.*` |
| `openrouter` | `OPENROUTER_API_KEY` + `OPENROUTER_BASE_URL` | `AsyncOpenAI` with custom `base_url` |
| `codex` | `codex login` or `codex login --with-api-key` | `codex exec` subprocesses |

### Shared flags for `run` and `compare`

| Flag | Meaning | Default source |
|---|---|---|
| `--dataset` | Dataset JSONL path | required |
| `--model` | Generation model | `OPENAI_BASE_MODEL` |
| `--provider` | Generation provider | `PF_PROVIDER` |
| `--judge-provider` | Judge provider; if omitted or empty, runtime falls back to `--provider` | `PF_JUDGE_PROVIDER` |
| `--temperature` | Generation temperature | `None` |
| `--max-tokens` | Max output tokens | `PF_DEFAULT_MAX_OUTPUT_TOKENS` |
| `--seed` | Recorded in config hash; not applied by current providers | `None` |
| `--retries` | Provider retry count | `PF_DEFAULT_RETRIES` |
| `--timeout` | Per-request timeout in seconds | `PF_DEFAULT_TIMEOUT_SECONDS` |
| `--concurrency` | Max concurrent case executions | `PF_DEFAULT_CONCURRENCY` |
| `--failure-threshold` | Soft stop threshold for failed/processed cases | `PF_DEFAULT_FAILURE_THRESHOLD` |
| `--scoring-config` | YAML file for `ScoringConfig` overrides | optional |

## `pf setup`

Interactive onboarding for auth and default provider settings.

```bash
pf setup
pf setup --env-file .env.local
```

Flags:

| Flag | Meaning |
|---|---|
| `--env-file` | Path to the environment file to update |
| `--example-env-file` | Template file used when the env file does not yet exist |

What it does:

- creates `.env` from `.env.example` if needed
- asks for default generation and judge providers
- prompts for API keys for OpenAI or OpenRouter
- checks `codex login status` and can launch `codex login`
- writes provider defaults such as `PF_PROVIDER`, `PF_JUDGE_PROVIDER`, `OPENAI_BASE_MODEL`, and `OPENAI_JUDGE_MODEL`

Troubleshooting:

- If the wizard says Codex is missing, install the CLI or update `PF_CODEX_BIN`.
- If keys are saved but `pf doctor` still fails, check whether the active shell is reading the same `.env` file you updated.

## `pf doctor`

Preflight validation for auth, prompt pack resolution, dataset resolution, workspace directories, and model access.

```bash
pf doctor
pf doctor --provider codex --judge-provider codex --model gpt-5-mini
pf doctor --prompt v2 --dataset datasets/core.jsonl
```

Flags:

| Flag | Meaning |
|---|---|
| `--prompt` | Prompt pack to validate |
| `--dataset` | Dataset to validate |
| `--model` | Model used for the live provider check |
| `--provider` | Provider to test |
| `--judge-provider` | Judge provider to verify alongside the generation provider |

What it checks:

- Python version is at least 3.11
- provider auth or Codex CLI availability
- prompt pack resolution
- dataset resolution
- `var/` directories exist
- provider can produce the literal string `PF_OK`

Troubleshooting:

- `openai_auth` broken: run `pf setup` and store a valid `OPENAI_API_KEY`
- `openrouter_auth` broken: verify `OPENROUTER_API_KEY` and `OPENROUTER_BASE_URL`
- `codex_auth` broken: run `codex login` or rerun `pf setup`
- `model_access` broken: auth may exist but the chosen model may not be available to that provider

## `pf status`

Quick auth and workspace status without running a live model check.

```bash
pf status
```

What it shows:

- project metadata from `.promptforge/project.json`
- configured default provider and judge provider
- configured generation and judge models
- whether OpenAI or OpenRouter keys are present, in redacted form
- Codex login status
- active prompt and active forge session

## `pf run`

Evaluates a single prompt pack against one dataset.

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
pf run --prompt v2 --dataset datasets/core.jsonl --provider codex --judge-provider codex --model gpt-5-mini
pf run --prompt prompt_packs/v2 --dataset datasets/core.jsonl --provider openrouter --model openai/gpt-5
```

Required flags:

| Flag | Meaning |
|---|---|
| `--prompt` | Prompt pack version or path |
| `--dataset` | Dataset path |

Outputs:

- `var/runs/run_<id>/run.json`
- `var/runs/run_<id>/run.lock.json`
- `var/runs/run_<id>/outputs.jsonl`
- `var/runs/run_<id>/scores.json`
- `var/runs/run_<id>/comparison.json`
- `var/runs/run_<id>/report.md`

Troubleshooting:

- Missing prompt pack files: ensure `manifest.yaml`, `system.md`, `user_template.md`, and `variables.schema.json` all exist
- Input schema validation error: fix the dataset case so `case.input` matches `variables.schema.json`
- Score is unexpectedly zero: inspect `scores.json.cases[*].hard_fail_reasons`
- Run stops early: inspect the failure rate and check whether the failure threshold tripped

## `pf forge`

Opens the PromptForge macOS app for the current project.

```bash
pf forge
pf forge --project .
```

Flags:

| Flag | Meaning |
|---|---|
| `--project` | PromptForge project root to open in the macOS app |

What it does:

- ensures `.promptforge/project.json` exists for the target project
- locates `PromptForge.app`
- launches the app and passes `--project <path>` and `--engine-root <repo-root>`

If the app is not found, PromptForge prints guidance and expected install paths.

Inside the app, the interactive slash commands are:

| Command | Meaning |
|---|---|
| `/help` | Show the available app commands |
| `/prompts` | List available prompt packs |
| `/open <name>` | Open a prompt pack |
| `/new <name>` | Create a new prompt pack |
| `/clone <source> <name>` | Clone an existing prompt pack |
| `/status` | Show provider, auth, and session info |
| `/prompt` | Print the current system prompt into the transcript |
| `/template` | Print the current user template into the transcript |
| `/bench` | Run the quick benchmark lane |
| `/full` | Run the full evaluation lane |
| `/diff` | Show the pending diff or the latest baseline delta |
| `/failures` | Show hard-failing cases |
| `/apply` | Apply the staged proposal and rerun the quick benchmark |
| `/discard` | Discard the staged proposal |
| `/undo` | Restore the previous revision |
| `/export <name>` | Export the current prompt to a new prompt pack |

## `pf prompts`

Prompt-pack management commands for multi-prompt workspaces.

```bash
pf prompts list
pf prompts create --prompt draft-v1
pf prompts create --prompt draft-v2 --from v1
```

Subcommands:

| Command | Meaning |
|---|---|
| `pf prompts list` | List prompt packs under `prompt_packs/` |
| `pf prompts create --prompt <name>` | Create a new prompt pack from the default scaffold |
| `pf prompts create --prompt <name> --from <source>` | Clone an existing prompt pack into a new one |

## `pf compare`

Runs two full evaluations, then creates a separate comparison run.

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
pf compare --a v1 --b v2 --dataset datasets/core.jsonl --provider codex --judge-provider codex --model gpt-5-mini
```

Required flags:

| Flag | Meaning |
|---|---|
| `--a` | Baseline prompt pack version or path |
| `--b` | Candidate prompt pack version or path |
| `--dataset` | Dataset path |

What gets created:

- two child evaluation runs under `var/runs/run_*`
- one comparison run under `var/runs/cmp_*`

Comparison semantics:

- hard-fail pass/fail beats weighted-score deltas
- weighted-score deltas within `tie_margin` are treated as ties
- `comparison.json` records per-case winner, confidence, and trait deltas

Troubleshooting:

- If compare fails after one child run, check `var/runs/` for the child run artifacts and rerun the compare command
- If results are hard to explain, inspect both child `scores.json` files first, then the final `comparison.json`

## `pf report`

Reads or rebuilds the report for an existing run.

```bash
pf report --run run_bc01fa629ba6
pf report --run cmp_123456789abc --print
```

Flags:

| Flag | Meaning |
|---|---|
| `--run` | Existing run ID |
| `--print` / `--no-print` | Print the Markdown report to stdout instead of just the path |

Behavior:

- evaluation runs rebuild from `scores.json`
- comparison runs rebuild from `comparison.json`

Troubleshooting:

- `Run not found`: check `var/runs/` and make sure the run ID is correct
- Missing `report.md`: `pf report` will regenerate it if the source JSON artifact still exists
- Missing `scores.json` or `comparison.json`: the run is incomplete; rerun the original command

## Scoring config override example

`--scoring-config` expects a YAML file shaped like `ScoringConfig`.

```yaml
rubric_weights:
  instruction_adherence: 0.35
  format_compliance: 0.20
  clarity_conciseness: 0.15
  domain_relevance: 0.20
  tone_alignment: 0.10
hard_fail_rules:
  fail_on_missing_sections: true
  fail_on_invalid_json_when_required: true
  fail_on_policy_markers: true
  policy_markers:
    - "[policy_violation]"
    - "[unsafe_content]"
    - "SAFETY_VIOLATION"
judge_model: gpt-5-mini
judge_max_output_tokens: 700
judge_temperature: 0.0
tie_margin: 0.2
```

## Common operator recipes

### First local setup

```bash
make bootstrap
. .venv/bin/activate
pf setup
pf doctor
```

### Compare a new prompt against the baseline

```bash
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
```

### Use Codex for both generation and judging

```bash
pf run --prompt v1 --dataset datasets/core.jsonl --provider codex --judge-provider codex --model gpt-5-mini
```

### Regenerate a missing report

```bash
pf report --run run_bc01fa629ba6
```

### Clear the local cache and rerun

```bash
rm var/state/cache.sqlite3
pf run --prompt v1 --dataset datasets/core.jsonl
```

## Source of truth

- [`../src/promptforge/cli.py`](../src/promptforge/cli.py)
- [`../src/promptforge/setup_wizard.py`](../src/promptforge/setup_wizard.py)
- [`../src/promptforge/core/config.py`](../src/promptforge/core/config.py)
