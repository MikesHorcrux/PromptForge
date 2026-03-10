# Eval Philosophy

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

PromptForge is built around one idea:

prompt changes should be judged by repeatable evidence, not by one impressive
chat turn.

## What the runtime optimizes for

- stable inputs through versioned prompt packs and fixed JSONL datasets
- reproducibility through hashes, lockfiles, and cached outputs
- explicit output contracts through format expectations and hard-fail rules
- human-readable conclusions through Markdown reports

## Why hard rules come first

Some failures are not subjective:

- required sections are missing
- JSON is invalid when JSON output is required
- a known policy marker appears

These should count as hard failures regardless of how polished the prose sounds.

## Why rubric judging still matters

Good prompt behavior is more than format compliance. PromptForge still evaluates:

- instruction adherence
- format compliance
- clarity and conciseness
- domain relevance
- tone alignment

That combination is why the score model uses both:

- deterministic checks in `src/promptforge/scoring/rules.py`
- structured rubric judging in `src/promptforge/scoring/judge.py`

## How PromptForge treats regressions

- Hard-fail pass/fail outranks weighted-score deltas during comparison.
- Small score differences within `tie_margin` are treated as ties.
- The comparison report highlights both improved and regressed traits so a "winner" is still inspectable.

## What this means for teams

- A prompt can be operationally valid but still mediocre.
- A prompt can sound better but still lose if it breaks output requirements.
- A run can succeed while a prompt fails.

That is intentional. PromptForge is designed to make those distinctions obvious.

## Source of truth

- [`../src/promptforge/scoring/rules.py`](../src/promptforge/scoring/rules.py)
- [`../src/promptforge/scoring/judge.py`](../src/promptforge/scoring/judge.py)
- [`../src/promptforge/runtime/compare_service.py`](../src/promptforge/runtime/compare_service.py)

