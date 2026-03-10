# Testing and Quality

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

PromptForge’s automated quality bar is currently test-driven around contracts,
not around live provider traffic.

That is a deliberate choice in the current repo state:

- contract logic is unit tested
- orchestration is integration-tested with a fake gateway
- live provider health is checked manually via `pf doctor`

## How to run checks

### Unit and integration-style tests

```bash
. .venv/bin/activate
pytest -q
```

### Provider and environment preflight

```bash
pf doctor
pf doctor --provider codex --judge-provider codex --model gpt-5-mini
```

### Smoke scripts

```bash
python -m promptforge.scripts.smoke_openai
python -m promptforge.scripts.smoke_eval
```

Notes:

- `smoke_openai` only exercises direct OpenAI auth
- `smoke_eval` uses the configured provider and judge provider from `.env`

## Current automated coverage

| Test file | What it verifies |
|---|---|
| `tests/test_prompt_loader.py` | Prompt pack loading, schema validation path, and Jinja render behavior |
| `tests/test_scoring_rules.py` | Missing section detection and invalid JSON hard-fail logic |
| `tests/test_cache_and_compare.py` | SQLite cache round-trip and comparison preference for non-hard-failing outputs |
| `tests/test_run_service.py` | End-to-end run and compare artifact generation with a fake gateway |
| `tests/test_setup_wizard.py` | OpenAI setup flow and Codex login launch behavior |
| `tests/test_codex_gateway.py` | Codex output-schema normalization for structured judge responses |

## Covered vs uncovered

### Covered well

- prompt pack loading contract
- dataset rendering path
- hard-fail rules
- cache persistence
- comparison winner logic
- setup wizard file writes
- run artifact creation

### Not covered well yet

- live OpenAI provider execution in CI
- live OpenRouter provider execution in CI
- live Codex provider execution in CI
- performance or load testing
- artifact backward compatibility across versions
- log content assertions
- failure-threshold behavior under large concurrent datasets

## Quality model

PromptForge currently relies on four layers of quality defense:

1. input validation
2. deterministic rule checks
3. structured rubric judging
4. human-readable run artifacts for review

That means a run can still "succeed" operationally while surfacing a bad prompt
through hard fails or low scores. Operational success and prompt quality are not
the same thing.

## Release readiness checklist

Before cutting a release or promoting a prompt pack:

- [ ] `pytest -q` passes
- [ ] `pf doctor` passes for the target provider path
- [ ] at least one representative `pf run` completes cleanly
- [ ] if comparing versions, `pf compare` produces a clear report
- [ ] `run.lock.json` reflects the intended provider, model, and hashes
- [ ] `scores.json` has no unexpected warnings
- [ ] generated artifacts are acceptable to share with stakeholders
- [ ] `.env` and logs contain no exposed secrets

## Recommendations for the next quality tier

If the project grows, add:

- fixture datasets that cover JSON output mode
- live-provider smoke tests gated by CI secrets
- regression snapshots for report structure
- a synthetic large dataset for concurrency and failure-threshold tests
- explicit schema compatibility tests for artifact readers

## Source of truth

- [`../tests/test_prompt_loader.py`](../tests/test_prompt_loader.py)
- [`../tests/test_scoring_rules.py`](../tests/test_scoring_rules.py)
- [`../tests/test_cache_and_compare.py`](../tests/test_cache_and_compare.py)
- [`../tests/test_run_service.py`](../tests/test_run_service.py)
- [`../tests/test_setup_wizard.py`](../tests/test_setup_wizard.py)
- [`../tests/test_codex_gateway.py`](../tests/test_codex_gateway.py)
- [`../src/promptforge/scripts/smoke_openai.py`](../src/promptforge/scripts/smoke_openai.py)
- [`../src/promptforge/scripts/smoke_eval.py`](../src/promptforge/scripts/smoke_eval.py)

