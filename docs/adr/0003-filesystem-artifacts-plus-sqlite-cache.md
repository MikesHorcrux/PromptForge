# ADR-0003: Filesystem Artifacts Plus SQLite Cache

_Last verified against commit `bf2bd3481eb50f6507094ec0e49bb6567bcab348`._

- Status: Accepted

## Context

PromptForge needs two different persistence modes:

- durable, human- and machine-readable run outputs
- cheap local memoization of successful generation responses

The project does not have a service database and does not need one for the
current operating model.

## Decision

Persist run artifacts as files under `var/runs/<run_id>/` and persist cached
generation outputs in a local SQLite database at `var/state/cache.sqlite3`.

Artifact files are the operational record. The cache is an optimization.

## Consequences

Positive:

- run outputs are easy to inspect, share, archive, and delete
- cache invalidation is simple because keys include `config_hash`
- the local persistence model is easy to bootstrap

Tradeoffs:

- there is no migration framework for cache schema changes
- partial runs may leave lockfiles and cache entries without final reports
- operators must manage local retention and cleanup explicitly

## Evidence in code

- Artifact read and write helpers: [`../../src/promptforge/runtime/artifacts.py`](../../src/promptforge/runtime/artifacts.py)
- Cache table creation and access: [`../../src/promptforge/runtime/cache.py`](../../src/promptforge/runtime/cache.py)
- Run persistence flow: [`../../src/promptforge/runtime/run_service.py`](../../src/promptforge/runtime/run_service.py)
- State and path defaults: [`../../src/promptforge/core/config.py`](../../src/promptforge/core/config.py)
