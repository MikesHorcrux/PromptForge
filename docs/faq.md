# FAQ

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

## Do I need an OpenAI API key to use PromptForge?

No. You can use the `codex` provider if `codex login` is already configured, or
the `openrouter` provider if you have an OpenRouter key.

## Does PromptForge use the OpenAI Agents SDK?

No. The runtime uses the Python `openai` SDK for OpenAI-compatible requests and
the Codex CLI for the Codex provider path.

## What exactly is a prompt pack?

A prompt pack is a directory with:

- `manifest.yaml`
- `system.md`
- `user_template.md`
- `variables.schema.json`

The loader treats all four files as required.

## What happens if a dataset case is missing an `id`?

The loader creates one based on the line number, such as `line-0001`.

## Why did a case get a score of zero?

Check `scores.json.cases[*].hard_fail_reasons`. The most common causes are:

- missing required sections
- invalid JSON when JSON output was required
- judge failure fallback
- provider execution error or threshold skip

## Why did the run stop before all cases were sent?

The failure threshold may have tripped. PromptForge stops launching remaining
queued cases once `failed / processed` exceeds `RunConfig.failure_threshold`.
Tasks already in flight still finish.

## What is the difference between `raw_weighted_score` and `effective_weighted_score`?

`raw_weighted_score` is the rubric score before hard-fail penalties.
`effective_weighted_score` is zeroed out when a case hard-fails.

## What does the cache actually store?

The SQLite cache stores raw output text and metadata for successful generation
results. It does not store the original dataset input body.

## How do I clear the cache?

Delete `var/state/cache.sqlite3`. The table will be recreated automatically on
the next run.

## How do I rollback a bad prompt change?

There is no rollback command. Use the previous prompt pack version or revert to
an earlier Git commit, then rerun `pf compare` against the candidate.

## Can I run PromptForge as a service?

Not in its current form. The implementation is CLI-first and does not include an
HTTP API, scheduler, or worker process.

## Are there approval gates for risky actions?

No. PromptForge currently evaluates prompts only. It does not ship with a human
approval system.

## Does `pf report` rerun models?

No. It rebuilds `report.md` from `scores.json` or `comparison.json` when those
files already exist.

## Why would I choose Codex over direct OpenAI API calls?

Mostly for auth and workflow reasons. If your operators already use Codex login,
the Codex provider avoids storing an `OPENAI_API_KEY` for runtime use. The tradeoff
is a broader execution environment than plain API calls, even with the read-only
sandbox default.

## Why would I choose OpenRouter?

Use it when you want OpenAI-compatible request handling but manage models through
OpenRouter instead of direct OpenAI credentials.

## Where should non-technical stakeholders look?

Start with:

- `report.md` for the latest run
- `comparison.json` if they need structured evidence
- [README](../README.md) and [eval philosophy](eval-philosophy.md) for value and boundaries

