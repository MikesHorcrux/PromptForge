# PromptForge

PromptForge is a CLI-first prompt evaluation agent. It loads versioned prompt
packs, runs them against fixed JSONL datasets, scores outputs with deterministic
rules plus rubric judging, and emits reproducible artifacts that make prompt
regressions obvious.

It supports three runtime auth/provider paths:

- `openai`: direct OpenAI API with `OPENAI_API_KEY`
- `codex`: user signs into Codex locally and PromptForge runs through `codex exec`
- `openrouter`: OpenAI-compatible routing with `OPENROUTER_API_KEY`

## What it does

- Loads a prompt pack made of `system.md`, `user_template.md`, and
  `variables.schema.json`
- Validates dataset cases before any API call
- Executes prompt versions with local response caching
- Scores outputs with hard fail rules and weighted rubric traits
- Compares prompt versions and selects a winner with evidence
- Writes `outputs.jsonl`, `scores.json`, `comparison.json`, `report.md`, and
  `run.lock.json` for every run

## Quickstart

```bash
make bootstrap
cp .env.example .env
pf doctor
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
```

## CLI

```bash
pf run --prompt v1 --dataset datasets/core.jsonl
pf run --prompt v1 --dataset datasets/core.jsonl --provider codex
pf run --prompt v1 --dataset datasets/core.jsonl --provider openrouter --model openai/gpt-5
pf compare --a v1 --b v2 --dataset datasets/core.jsonl
pf report --run <run_id>
pf doctor
```

## Repo layout

```text
prompt_packs/
  v1/
  v2/
datasets/
  core.jsonl
docs/
  architecture.md
  eval-philosophy.md
src/promptforge/
  agents/
  core/
  datasets/
  prompts/
  runtime/
  scoring/
  scripts/
tests/
var/
```

## Prompt pack format

Each prompt pack lives in `prompt_packs/<version>/` and contains:

- `manifest.yaml`
- `system.md`
- `user_template.md`
- `variables.schema.json`

## Dataset format

Each JSONL line must include:

```json
{
  "id": "case-001",
  "input": {"customer_issue": "Refund request"},
  "context": "Optional extra context",
  "rubric_targets": {
    "instruction_adherence": "Answer every requested part.",
    "clarity_conciseness": "Stay under 180 words."
  },
  "format_expectations": {
    "output_format": "markdown",
    "required_sections": ["Summary", "Answer", "Next Steps"]
  }
}
```

## Notes

- PromptForge never mutates datasets in place.
- `seed` is tracked in the lockfile and cache key for reproducibility, but the
  current Responses API request shape does not expose a `seed` parameter.
- Some models accept `temperature`; PromptForge records when a requested value
  cannot be applied cleanly.
- `codex` auth is a separate provider path. It does not reuse the Python OpenAI
  SDK directly; PromptForge invokes `codex exec` and relies on the user’s Codex
  login.
- `openrouter` runs through the OpenAI-compatible client path using
  `OPENROUTER_BASE_URL`.
