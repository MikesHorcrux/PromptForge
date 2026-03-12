# Eval Philosophy

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

PromptForge is built around one principle:

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
- required strings are missing
- forbidden markers appear

These count as hard failures regardless of how polished the prose sounds.

## Why rubric judging still matters

PromptForge also evaluates:

- instruction adherence
- format compliance
- clarity and conciseness
- domain relevance
- tone alignment

That combination is why the score model uses both:

- deterministic checks in `src/promptforge/scoring/rules.py`
- structured rubric judging in `src/promptforge/scoring/judge.py`

## How PromptForge treats regressions

- hard-fail pass/fail outranks weighted-score deltas during comparison
- small score differences within `tie_margin` are treated as ties
- comparison highlights both improved and regressed traits instead of only a winner label

## What this means for teams

- a prompt can be operationally valid but still mediocre
- a prompt can sound better but still lose if it breaks hard requirements
- a run can succeed while the prompt still fails quality expectations

That distinction is intentional.

## Source of truth

- [src/promptforge/scoring/rules.py](../src/promptforge/scoring/rules.py)
- [src/promptforge/scoring/judge.py](../src/promptforge/scoring/judge.py)
- [src/promptforge/runtime/compare_service.py](../src/promptforge/runtime/compare_service.py)
