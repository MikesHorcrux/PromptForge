#!/bin/sh
set -eu

REPO_ROOT="${PROJECT_DIR}/../../.."
ENGINE_SOURCE_ROOT="${REPO_ROOT}"
ENGINE_OUTPUT_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/engine"

SRC_ROOT="${ENGINE_SOURCE_ROOT}/src"
DATASET_ROOT="${ENGINE_SOURCE_ROOT}/datasets"
VENV_ROOT="${ENGINE_SOURCE_ROOT}/.venv"
BIN_ROOT="${ENGINE_OUTPUT_DIR}/bin"
MANIFEST_PATH="${ENGINE_OUTPUT_DIR}/runtime-manifest.json"

if [ ! -d "${SRC_ROOT}" ] || [ ! -x "${VENV_ROOT}/bin/python" ]; then
  echo "error: PromptForge bundled engine is missing src/ or .venv/. Rebuild the local engine runtime before building the app." >&2
  exit 1
fi

resolve_realpath() {
  /usr/bin/python3 - "$1" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
}

CODEX_SOURCE=""
RG_SOURCE=""

detect_codex_bundle_sources() {
  if [ -n "${PF_CODEX_BUNDLE_SOURCE:-}" ]; then
    if [ ! -x "${PF_CODEX_BUNDLE_SOURCE}" ]; then
      echo "error: PF_CODEX_BUNDLE_SOURCE is not executable: ${PF_CODEX_BUNDLE_SOURCE}" >&2
      exit 1
    fi
    CODEX_SOURCE="${PF_CODEX_BUNDLE_SOURCE}"
    if [ -n "${PF_CODEX_RG_SOURCE:-}" ]; then
      if [ ! -x "${PF_CODEX_RG_SOURCE}" ]; then
        echo "error: PF_CODEX_RG_SOURCE is not executable: ${PF_CODEX_RG_SOURCE}" >&2
        exit 1
      fi
      RG_SOURCE="${PF_CODEX_RG_SOURCE}"
    fi
    return
  fi

  if ! command -v codex >/dev/null 2>&1; then
    return
  fi

  case "$(uname -m)" in
    arm64)
      CODEX_PACKAGE_DIR="codex-darwin-arm64"
      CODEX_TRIPLE="aarch64-apple-darwin"
      ;;
    x86_64)
      CODEX_PACKAGE_DIR="codex-darwin-x64"
      CODEX_TRIPLE="x86_64-apple-darwin"
      ;;
    *)
      return
      ;;
  esac

  CODEX_ENTRY="$(resolve_realpath "$(command -v codex)")"
  CODEX_PACKAGE_ROOT="$(cd "$(dirname "${CODEX_ENTRY}")/.." && pwd)"
  CODEX_CANDIDATE="${CODEX_PACKAGE_ROOT}/node_modules/@openai/${CODEX_PACKAGE_DIR}/vendor/${CODEX_TRIPLE}/codex/codex"
  RG_CANDIDATE="${CODEX_PACKAGE_ROOT}/node_modules/@openai/${CODEX_PACKAGE_DIR}/vendor/${CODEX_TRIPLE}/path/rg"

  if [ ! -x "${CODEX_CANDIDATE}" ]; then
    CODEX_CANDIDATE="${CODEX_PACKAGE_ROOT}/vendor/${CODEX_TRIPLE}/codex/codex"
    RG_CANDIDATE="${CODEX_PACKAGE_ROOT}/vendor/${CODEX_TRIPLE}/path/rg"
  fi

  if [ -x "${CODEX_CANDIDATE}" ]; then
    CODEX_SOURCE="${CODEX_CANDIDATE}"
  fi
  if [ -x "${RG_CANDIDATE}" ]; then
    RG_SOURCE="${RG_CANDIDATE}"
  fi
}

rm -rf "${ENGINE_OUTPUT_DIR}"
mkdir -p "${ENGINE_OUTPUT_DIR}"

/usr/bin/rsync -a \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${SRC_ROOT}/" "${ENGINE_OUTPUT_DIR}/src/"

if [ -d "${DATASET_ROOT}" ]; then
  /usr/bin/rsync -a \
    --exclude '__pycache__' \
    --exclude '*.pyc' \
    "${DATASET_ROOT}/" "${ENGINE_OUTPUT_DIR}/datasets/"
fi

/usr/bin/rsync -a \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "${VENV_ROOT}/" "${ENGINE_OUTPUT_DIR}/.venv/"

detect_codex_bundle_sources

PATH_ENTRIES_JSON='[]'
CODEX_BIN_JSON='null'

if [ -n "${CODEX_SOURCE}" ]; then
  mkdir -p "${BIN_ROOT}"
  /usr/bin/install -m 755 "${CODEX_SOURCE}" "${BIN_ROOT}/codex"
  CODEX_BIN_JSON='"bin/codex"'
  PATH_ENTRIES_JSON='["bin"]'
  if [ -n "${RG_SOURCE}" ]; then
    /usr/bin/install -m 755 "${RG_SOURCE}" "${BIN_ROOT}/rg"
  fi
elif [ "${PF_REQUIRE_BUNDLED_CODEX:-0}" = "1" ]; then
  echo "error: PromptForge could not bundle a native Codex CLI. Install Codex first or set PF_CODEX_BUNDLE_SOURCE." >&2
  exit 1
else
  echo "warning: PromptForge could not bundle a native Codex CLI. The app will fall back to PF_CODEX_BIN or a system codex install." >&2
fi

GENERATED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

cat > "${MANIFEST_PATH}" <<EOF
{
  "schema_version": 1,
  "generated_at": "${GENERATED_AT}",
  "python_executable": ".venv/bin/python",
  "helper_module": "promptforge.helper.server",
  "python_path_entries": ["src"],
  "path_entries": ${PATH_ENTRIES_JSON},
  "codex_binary": ${CODEX_BIN_JSON}
}
EOF
