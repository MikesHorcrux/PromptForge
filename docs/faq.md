# FAQ

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

## What is PromptForge in one sentence?

PromptForge is a local prompt engineering workbench that evaluates versioned
prompts against fixed datasets, lets you iterate interactively in a macOS
app, and writes reproducible artifacts.

## Do I need the macOS app to use PromptForge?

No. The CLI is enough for setup, status, runs, comparisons, reports, prompt
creation, scenario operations, review inspection, and promotion.

The app is the interactive workspace for:

- Forgie chat
- prompt editing
- cases
- results review
- try-input playground runs

## Is the app macOS-only?

Yes. `pf forge` is a macOS path. The Python CLI and runtime are still useful
outside the app.

## What exactly is a prompt?

A prompt is a directory containing:

- `manifest.yaml`
- `system.md`
- `user_template.md`
- `variables.schema.json`

PromptForge also uses:

- `prompt.json`

for prompt metadata and authoring context.

## What is `prompt.json` for?

It stores prompt-level metadata such as:

- purpose
- expected behavior
- success criteria
- baseline prompt reference
- linked scenario suites
- owner and audience fields
- builder settings

If an older prompt does not have `prompt.json`, PromptForge can create a
default one when the prompt is opened.

## Why do I see `prompt_blocks` in the metadata if the UI is file-first now?

Because PromptForge still carries a compatibility field for older prompt-brief
data. The current app centers on full-file editing, but the metadata contract
still preserves `prompt_blocks` for older saved prompts.

## What is the difference between dataset cases and scenario cases?

- dataset cases drive batch evaluation with `pf run` and `pf compare`
- scenario cases drive saved review-style checks in the forge workspace and app

Scenario suites are closer to acceptance tests for prompt behavior.

## What is `Try Input`?

`Try Input` is the playground surface.

It lets you:

- run one ad hoc input against the current prompt
- optionally compare against the baseline
- generate a few samples
- promote a useful scratch input into a saved case later

## Why does opening a prompt in the app feel fast now?

Because prompt open does not create a forge session or run a benchmark. The app
loads prompt files and metadata first, then creates the forge session lazily on
the first real action.

## Why can the first real action still feel slower?

The first chat, save, quick check, suite run, or playground run may need to:

- create or reload the forge session
- start provider calls
- warm provider-side caches

This is most noticeable with the Codex provider path.

## What happens if a dataset case is missing an `id`?

The loader synthesizes one based on the line number, such as `line-0001`.

## Why did a case score zero?

Check `scores.json.cases[*].hard_fail_reasons`.

Common causes:

- missing required sections
- invalid JSON when JSON output was required
- forbidden markers
- provider execution failure
- judge failure fallback

## Why did a run stop before every case finished?

The failure threshold likely tripped.

PromptForge soft-stops by:

- stopping new queued work
- allowing already-running tasks to finish
- writing a partial but inspectable run

## Does PromptForge rerun models when I call `pf report`?

No. `pf report` rebuilds or prints `report.md` from saved artifacts.

## What does the response cache store?

The cache stores successful generation outputs and metadata keyed by:

- prompt version
- case ID
- model
- config hash

It does not store the full dataset file as rows in SQLite.

## How do I clear cached generations?

Delete:

```bash
rm -f var/state/cache.sqlite3
```

The cache table is recreated automatically on the next run.

## Can I open a brand-new empty project?

Yes. Empty projects are now a first-class state in the app and helper.

You can open the project, then create or import a prompt.

## Why does the app say the bundled runtime is missing?

The app could not find a valid packaged engine.

For official release builds, reinstall the app or re-download the release zip.

For source builds, rebuild the app after rebuilding the local engine runtime so
the app bundle contains a usable:

- `engine/.venv/bin/python`
- `engine/src/promptforge/helper/server.py`

## How do I rollback a bad prompt change?

Use one of:

- forge revision restore
- baseline promotion from a known-good state
- `pf compare` against a known-good prompt version
- Git history

## Is there a human approval gate?

No. PromptForge records decisions, but it does not implement a multi-user
approval workflow.

## Can I run PromptForge as a service?

Not in the current implementation. It is a local CLI plus local macOS app and
helper process, not an HTTP service or worker system.

## When should I use Codex instead of OpenAI or OpenRouter?

Use Codex when your team prefers Codex login and CLI-based provider access.

Tradeoffs:

- broader local execution context than direct API calls
- slower cold-start feel in some interactive flows
- different risk profile even with read-only sandboxing

## Where should a non-technical stakeholder look first?

Start with:

- `report.md`
- `comparison.json` when a structured diff matters
- the app `Results` view for interactive review
- [README](../README.md) for scope and boundaries
