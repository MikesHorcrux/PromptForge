# Data Model

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

PromptForge has two kinds of data model:

- in-memory contracts defined with Pydantic
- persisted local state written as JSON, JSONL, Markdown, and SQLite rows

There is no migration framework or central relational database in v1.

## Core entities

| Entity | Source | Purpose |
|---|---|---|
| `PromptPackManifest` | `src/promptforge/core/models.py` | Names a prompt pack, its output format, and required sections |
| `PromptPack` | `src/promptforge/core/models.py` | Fully loaded prompt pack, including prompts, schema, and content hash |
| `DatasetCase` | `src/promptforge/core/models.py` | One JSONL evaluation case with input, optional context, rubric targets, and format expectations |
| `RunConfig` | `src/promptforge/core/models.py` | Execution controls such as concurrency, retries, timeout, and failure threshold |
| `ScoringConfig` | `src/promptforge/core/models.py` | Rubric weights, hard-fail rules, judge model, and tie margin |
| `ModelExecutionResult` | `src/promptforge/core/models.py` | One case result from generation, including caching status, latency, and provider |
| `CaseScore` | `src/promptforge/core/models.py` | One scored case with rule checks, trait scores, and hard-fail status |
| `ScoresArtifact` | `src/promptforge/core/models.py` | Evaluation summary plus all per-case scores |
| `ComparisonArtifact` | `src/promptforge/core/models.py` | Head-to-head comparison between prompt A and prompt B |
| `Lockfile` | `src/promptforge/core/models.py` | Reproducibility record with hashes, config, Python version, and package version |
| `CachedResponse` | `src/promptforge/core/models.py` | Local memoized generation output stored in SQLite |

## Persisted state

### Filesystem artifacts

Each run creates a directory under `var/runs/<run_id>/`.

| File | Written by | Meaning |
|---|---|---|
| `run.json` | `ArtifactStore.write_manifest()` | Run manifest and high-level metadata |
| `run.lock.json` | `EvaluationService.run()` / `compare()` | Reproducibility record with hashes and config |
| `outputs.jsonl` | `EvaluationService.run()` / `compare()` | Raw model outputs; compare runs contain paired `a` and `b` rows |
| `scores.json` | `EvaluationService.run()` / `compare()` | Evaluation runs store one `ScoresArtifact`; comparison runs store `{prompt_a, prompt_b}` |
| `comparison.json` | `EvaluationService.run()` / `compare()` | Placeholder for single runs, full `ComparisonArtifact` for compare runs |
| `report.md` | `render_evaluation_report()` / `render_comparison_report()` | Human-readable summary |

### SQLite cache

`var/state/cache.sqlite3` contains a single table: `response_cache`.

| Column | Meaning |
|---|---|
| `cache_key` | Primary key derived from prompt version, case ID, model, and config hash |
| `prompt_version` | Prompt pack version |
| `case_id` | Dataset case ID |
| `model` | Generation model |
| `config_hash` | Stable hash of prompt pack, dataset, provider choice, and configs |
| `response_json` | Serialized `CachedResponse` payload |
| `created_at` | UTC timestamp |

## Entity relationships

```mermaid
erDiagram
  PROMPT_PACK {
    string version PK
    string content_hash
    string output_format
  }

  DATASET {
    string path PK
    string content_hash
  }

  DATASET_CASE {
    string id PK
    string input_json
  }

  RUN_MANIFEST {
    string run_id PK
    string kind
    string provider
    string judge_provider
    string config_hash
    string output_dir
  }

  LOCKFILE {
    string run_id PK
    string dataset_hash
    string prompt_pack_hash
    string python_version
    string package_version
  }

  MODEL_OUTPUT {
    string run_id FK
    string case_id FK
    string provider
    boolean cached
  }

  SCORE_CASE {
    string run_id FK
    string case_id FK
    float effective_weighted_score
    boolean hard_fail
  }

  COMPARISON_ARTIFACT {
    string run_id PK
    string prompt_a
    string prompt_b
    string dataset_hash
  }

  RESPONSE_CACHE {
    string cache_key PK
    string case_id
    string config_hash
    string response_json
  }

  DATASET ||--|{ DATASET_CASE : contains
  PROMPT_PACK ||--o{ RUN_MANIFEST : evaluated_in
  DATASET ||--o{ RUN_MANIFEST : evaluated_on
  RUN_MANIFEST ||--|| LOCKFILE : has
  RUN_MANIFEST ||--o{ MODEL_OUTPUT : writes
  RUN_MANIFEST ||--o{ SCORE_CASE : writes
  RUN_MANIFEST ||--o| COMPARISON_ARTIFACT : may_write
  DATASET_CASE ||--o{ MODEL_OUTPUT : produces
  DATASET_CASE ||--o{ SCORE_CASE : scored_as
  RESPONSE_CACHE }o--|| DATASET_CASE : memoizes
```

## Run directory structure

```mermaid
flowchart TB
  RunDir["var/runs/<run_id>/"] --> RunJson["run.json"]
  RunDir --> Lock["run.lock.json"]
  RunDir --> Outputs["outputs.jsonl"]
  RunDir --> Scores["scores.json"]
  RunDir --> Comparison["comparison.json"]
  RunDir --> Report["report.md"]
```

## Versioning and migration notes

### Prompt packs

- Prompt packs include `apiVersion`, `version`, `name`, `output_format`, and `required_sections`.
- `apiVersion` is loaded and stored, but current runtime logic does not branch on it. Treat it as metadata today.
- Prompt pack changes affect the `prompt_pack_hash`, which feeds the `config_hash`, which invalidates cache reuse automatically.

### Datasets

- Datasets are plain JSONL files.
- Case IDs are optional in source files; the loader will synthesize `line-0001`, `line-0002`, and so on if missing.
- Any dataset content change changes `dataset_hash`, which also invalidates cache reuse.

### Cache schema

- The SQLite table is created lazily inside `ResponseCache.__init__()`.
- There is no migration framework.
- If cache schema changes or the cache becomes suspect, delete `var/state/cache.sqlite3` and rerun.

### Artifact schemas

- Evaluation `scores.json` matches `ScoresArtifact`.
- Comparison `scores.json` is intentionally different: it is a JSON object with `prompt_a` and `prompt_b` keys, each containing a full evaluation artifact.
- `run.lock.json` is the closest thing to a stable reproducibility contract. It records package version, Python version, provider choice, hashes, and effective configs.

## Source of truth

- [`../src/promptforge/core/models.py`](../src/promptforge/core/models.py)
- [`../src/promptforge/runtime/artifacts.py`](../src/promptforge/runtime/artifacts.py)
- [`../src/promptforge/runtime/cache.py`](../src/promptforge/runtime/cache.py)
- [`../src/promptforge/runtime/run_service.py`](../src/promptforge/runtime/run_service.py)

