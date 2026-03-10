# Contributing

## Principles

- Keep prompt evaluation reproducible.
- Prefer explicit contracts over hidden heuristics.
- Treat regressions as product bugs, not prompt folklore.

## Development loop

1. Create a virtualenv and install with `pip install -e '.[dev]'`
2. Run `pytest -q`
3. Run `pf doctor`
4. Exercise the example compare flow against `datasets/core.jsonl`

## Pull request expectations

- Include tests for scoring, comparison, or cache changes
- Update docs when command behavior or artifact shapes change
- Avoid introducing secrets into fixtures, logs, or sample prompts

