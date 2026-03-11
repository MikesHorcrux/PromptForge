#!/bin/sh
set -eu

ENGINE_SOURCE_ROOT="${PROJECT_DIR}/../../.."
ENGINE_OUTPUT_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/engine"

SRC_ROOT="${ENGINE_SOURCE_ROOT}/src"
DATASET_ROOT="${ENGINE_SOURCE_ROOT}/datasets"
VENV_ROOT="${ENGINE_SOURCE_ROOT}/.venv"

if [ ! -d "${SRC_ROOT}" ] || [ ! -x "${VENV_ROOT}/bin/python" ]; then
  echo "error: PromptForge bundled engine is missing src/ or .venv/. Rebuild the local engine runtime before building the app." >&2
  exit 1
fi

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
