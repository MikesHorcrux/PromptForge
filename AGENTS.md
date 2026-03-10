# AGENTS.md

## Repository purpose

This repository contains PromptForge, a CLI-first prompt evaluation agent built on
the OpenAI Responses API. It runs prompt packs against fixed datasets, scores the
outputs, compares versions, and emits reproducible artifacts.

## Setup

1. Copy `.env.example` to `.env`
2. Set `OPENAI_API_KEY`
3. Create and activate a virtualenv
4. Install dependencies with `pip install -e '.[dev]'`
5. Run `pf doctor`

## Commands

- Run one prompt pack: `pf run --prompt v1 --dataset datasets/core.jsonl`
- Compare prompt packs: `pf compare --a v1 --b v2 --dataset datasets/core.jsonl`
- Rebuild a report: `pf report --run <run_id>`
- Run tests: `pytest -q`

## Architecture rules

- Keep prompt definitions in `prompt_packs/<version>/`, not inline strings.
- Never mutate datasets during execution.
- Cache model responses by prompt version, case id, model, and config hash.
- Keep all externally consumed artifacts schema-first and reproducible.
- Never log secrets or raw environment values.

## Change rules

- Update docs when runtime behavior changes.
- Add or update tests for scoring, comparison, and cache behavior.
- Prefer small focused diffs.

