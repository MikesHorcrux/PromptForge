# ADR-0005: Compare Builds on Full Child Evaluation Runs

_Last verified against commit `4995d46a2ca16a3f56824412acc547118ed6d804`._

- Status: Accepted

## Context

PromptForge needs to compare prompt versions in a way that leaves behind
evidence, not just a winner label. A direct in-memory comparison would be
lighter, but it would make it harder to inspect each prompt version on its own.

## Decision

Implement `pf compare` as composition:

1. run a full evaluation for prompt A
2. run a full evaluation for prompt B
3. compare the two `ScoresArtifact` values
4. write a third comparison run with its own artifacts

The comparison manifest records the two child run IDs in `notes`.

## Consequences

Positive:

- each prompt version has a standalone artifact trail
- operators can inspect confusing comparisons by reading child runs first
- `pf report` can rebuild reports for both evaluation and comparison runs

Tradeoffs:

- compare is more expensive than a single in-memory diff
- a compare invocation can leave completed child runs even if the final comparison step fails
- artifact readers must understand both evaluation and comparison run layouts

## Evidence in code

- Comparison orchestration: [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
- Winner logic: [`../../src/promptforge/runtime/compare_service.py`](../../src/promptforge/runtime/compare_service.py)
- Comparison report rendering: [`../../src/promptforge/runtime/report_service.py`](../../src/promptforge/runtime/report_service.py)
