# Architecture

PromptForge follows the reusable-agent baseline but keeps v1 narrow.

## Runtime split

- Prompt execution uses the OpenAI Responses API directly because the evaluated
  surface is a prompt pack, not a tool-rich orchestrator.
- Rubric judging uses structured parse calls against a dedicated judge schema.
- Runs are CLI-first and artifact-driven, with filesystem storage plus a SQLite
  response cache.

## Core flow

1. Load prompt pack and dataset
2. Validate every case against the prompt variable schema
3. Compute a config hash and create a run lockfile
4. Execute cases with concurrency limits and transient-error retries
5. Score outputs with rule checks plus rubric judging
6. Optionally compare two prompt versions
7. Write artifacts and a Markdown report

## Storage

- `var/state/cache.sqlite3`: response cache
- `var/runs/<run_id>/`: run artifacts
- `var/logs/promptforge.log`: structured JSON logs

