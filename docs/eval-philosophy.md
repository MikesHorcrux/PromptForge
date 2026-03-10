# Eval Philosophy

PromptForge is built around a simple premise: prompt changes should be judged by
evidence, not by intuition after one lucky chat turn.

## Rules first

Hard requirements like JSON validity, required sections, and safety markers are
checked deterministically. If a prompt misses the contract, that should not be
hidden by a pleasant sounding answer.

## Rubric second

Quality still matters, so PromptForge grades adherence, clarity, relevance, and
tone against explicit rubric targets per case. The rubric is weighted so teams
can bias toward the traits that matter for their product.

## Compare behavior

PromptForge treats hard fails as first-class comparison signals. A prompt with a
slightly higher quality score still loses head-to-head if it breaks required
output contracts.

