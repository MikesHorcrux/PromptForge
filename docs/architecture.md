# Architecture

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

PromptForge is a local, CLI-first prompt evaluation system. A single CLI process
loads a prompt pack and dataset, evaluates cases through a provider backend,
scores the outputs, and writes durable artifacts to disk.

It is intentionally narrow:

- No web API
- No background worker
- No external database beyond a local SQLite cache
- No approval or multi-user control plane

The implementation centers on:

- command orchestration in `src/promptforge/cli.py`
- execution in `src/promptforge/runtime/run_service.py`
- provider abstraction in `src/promptforge/runtime/gateway.py`
- persisted artifacts in `src/promptforge/runtime/artifacts.py`
- local response caching in `src/promptforge/runtime/cache.py`

## System overview

```mermaid
flowchart LR
  User["Developer or operator"] --> CLI["pf CLI<br/>src/promptforge/cli.py"]
  CLI --> Setup["Setup wizard<br/>src/promptforge/setup_wizard.py"]
  CLI --> Service["EvaluationService<br/>src/promptforge/runtime/run_service.py"]

  Service --> Prompts["Prompt loader<br/>src/promptforge/prompts/loader.py"]
  Service --> Datasets["Dataset loader<br/>src/promptforge/datasets/loader.py"]
  Service --> Rules["Rule checks<br/>src/promptforge/scoring/rules.py"]
  Service --> Judge["Rubric judge<br/>src/promptforge/scoring/judge.py"]
  Service --> Compare["Compare service<br/>src/promptforge/runtime/compare_service.py"]
  Service --> Artifacts["Artifact store<br/>src/promptforge/runtime/artifacts.py"]
  Service --> Cache["SQLite cache<br/>src/promptforge/runtime/cache.py"]
  Service --> Gateway["Provider gateway<br/>src/promptforge/runtime/gateway.py"]

  Gateway --> OpenAI["OpenAI-compatible providers<br/>OpenAI or OpenRouter"]
  Gateway --> Codex["Codex CLI provider<br/>codex exec"]

  Artifacts --> RunDir["var/runs/<run_id>/"]
  Cache --> CacheDb["var/state/cache.sqlite3"]
  Service --> Logs["var/logs/promptforge.log"]
```

## Module boundaries

```mermaid
flowchart TB
  subgraph Interface["Interface layer"]
    CLI["CLI parsing and summaries"]
    Setup["Interactive setup"]
    UI["Rich terminal presentation"]
  end

  subgraph Core["Core contracts"]
    Config["Environment-backed settings"]
    Models["Pydantic models"]
    Hashing["Stable hashing"]
    Logging["Structured logging"]
  end

  subgraph Runtime["Execution layer"]
    RunService["EvaluationService"]
    Gateway["Provider gateways"]
    Artifacts["Artifact store"]
    Cache["Response cache"]
    Reports["Report rendering"]
    Compare["Comparison logic"]
  end

  subgraph Assets["Inputs"]
    PromptPacks["Prompt packs"]
    Datasets["JSONL datasets"]
    JudgeAssets["Judge instructions and schema"]
  end

  Interface --> Runtime
  Interface --> Core
  Runtime --> Core
  Runtime --> Assets
```

## Component responsibilities

| Area | Files | Responsibility |
|---|---|---|
| Command surface | `src/promptforge/cli.py` | Parses commands, resolves providers, and prints themed summaries |
| Onboarding | `src/promptforge/setup_wizard.py` | Creates or updates `.env`, configures auth, and launches provider login flows |
| Presentation | `src/promptforge/ui.py` | Rich terminal panels, tables, and banners |
| Settings | `src/promptforge/core/config.py` | Reads environment variables and exposes default paths and provider settings |
| Contracts | `src/promptforge/core/models.py` | Defines prompt pack, dataset, run config, score, cache, and comparison models |
| Prompt loading | `src/promptforge/prompts/loader.py` | Resolves prompt pack paths, loads files, validates inputs, and renders the user prompt |
| Dataset loading | `src/promptforge/datasets/loader.py` | Loads JSONL into `DatasetCase` objects and computes dataset hashes |
| Provider execution | `src/promptforge/runtime/gateway.py` | Sends generation and judge requests through OpenAI-compatible APIs or Codex |
| Execution orchestration | `src/promptforge/runtime/run_service.py` | Creates runs, executes cases, scores outputs, persists artifacts, and builds comparisons |
| Deterministic scoring | `src/promptforge/scoring/rules.py` | Required sections, required strings, JSON validity, policy markers, and word-count checks |
| Rubric scoring | `src/promptforge/scoring/judge.py`, `src/promptforge/agents/prompt_judge/*` | Builds judge payloads and enforces a structured scoring schema |
| Persistence | `src/promptforge/runtime/artifacts.py`, `src/promptforge/runtime/cache.py` | Writes run artifacts to disk and memoizes model outputs in SQLite |
| Reporting | `src/promptforge/runtime/report_service.py` | Renders Markdown summaries for evaluation and comparison runs |

## Runtime boundaries

### What runs locally

- CLI parsing and setup
- Prompt and dataset loading
- JSON schema validation
- Local cache reads and writes
- Run artifact generation
- Structured logging

### What leaves the machine

- Generated prompt requests sent to the selected provider
- Judge payloads, which include rendered prompts, case data, and model output, sent to the selected judge provider

### What is intentionally absent

- No HTTP server
- No message queue
- No scheduler
- No multi-tenant data model
- No approval workflow

## Comparison topology

The compare command does not score two versions in-memory and then discard the
details. It materializes two full evaluation runs first, then writes a third
comparison run that references the child run IDs in `run.json.notes`.

```mermaid
flowchart LR
  Compare["pf compare"] --> EvalA["Evaluation run A"]
  Compare --> EvalB["Evaluation run B"]
  EvalA --> RunA["var/runs/run_*"]
  EvalB --> RunB["var/runs/run_*"]
  RunA --> Aggregate["CompareService"]
  RunB --> Aggregate
  Aggregate --> CompareRun["var/runs/cmp_*"]
```

## Practical architecture implications

- PromptForge is easy to reason about because every invocation is a local process plus explicit artifacts.
- Reproducibility comes from content hashes, `run.lock.json`, and the SQLite cache rather than from a database-backed control plane.
- Operators can diagnose almost everything from `pf doctor`, `var/logs/promptforge.log`, and the run directory.
- Scaling beyond local or CI-style use would require new architecture. There is no current worker pool, API layer, or remote state store.

## Source of truth

- [`../src/promptforge/cli.py`](../src/promptforge/cli.py)
- [`../src/promptforge/runtime/run_service.py`](../src/promptforge/runtime/run_service.py)
- [`../src/promptforge/runtime/gateway.py`](../src/promptforge/runtime/gateway.py)
- [`../src/promptforge/runtime/artifacts.py`](../src/promptforge/runtime/artifacts.py)
- [`../src/promptforge/runtime/cache.py`](../src/promptforge/runtime/cache.py)

