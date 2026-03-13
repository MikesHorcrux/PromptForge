# Packaging

This directory contains packaging and release support files.

Current contents:

- `macos/bundle_engine.sh`: builds the app-bundled local engine payload for the macOS app
  - copies `src/`, `datasets/`, and a prepared Python runtime
  - emits `runtime-manifest.json` so the app can validate the bundled runtime explicitly
  - bundles the native Codex CLI and bundled `rg` helper when available
  - supports `PF_REQUIRE_BUNDLED_CODEX=1` to fail the build if no native Codex bundle can be produced
- `macos/release_app.sh`: creates a direct-download macOS release build
  - builds a dedicated release venv instead of reusing the repo `.venv`
  - archives `PromptForge.app`, copies the signed app, and produces a zip
  - supports `PF_CODESIGN_ALLOWED=0` for local verification builds
  - supports `PF_NOTARIZE=1` for notarization when App Store Connect API credentials are available

Release-oriented environment variables:

- `PF_ENGINE_SOURCE_ROOT`: source tree used by `bundle_engine.sh`
- `PF_ENGINE_VENV_ROOT`: prepared venv used by `bundle_engine.sh`
- `PF_REQUIRE_BUNDLED_CODEX`: fail the build when Codex cannot be bundled
- `APP_VERSION`: override the packaged app version during `release_app.sh`
- `APP_BUILD`: override the packaged build number during `release_app.sh`
- `PYTHON_BIN`: Python binary used to create the release venv
- `PF_CODESIGN_ALLOWED`: set to `0` to skip code signing during local verification
- `PF_NOTARIZE`: set to `1` to submit the zip for notarization

The goal of this directory is to keep packaging concerns separate from:

- app UI code in `apps/`
- engine/runtime code in `src/`
- product docs in `docs/`
