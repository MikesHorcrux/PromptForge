# Packaging

This directory contains packaging and release support files.

Current contents:

- `macos/bundle_engine.sh`: builds the app-bundled local engine payload for the macOS app
  - copies `src/`, `datasets/`, and the local `.venv`
  - emits `runtime-manifest.json` so the app can validate the bundled runtime explicitly
  - bundles the native Codex CLI and bundled `rg` helper when available
  - supports `PF_REQUIRE_BUNDLED_CODEX=1` to fail the build if no native Codex bundle can be produced

The goal of this directory is to keep packaging concerns separate from:

- app UI code in `apps/`
- engine/runtime code in `src/`
- product docs in `docs/`
