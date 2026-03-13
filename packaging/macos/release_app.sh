#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/../.." && pwd)"
PROJECT_PATH="${REPO_ROOT}/apps/macos/PromptForge/PromptForge.xcodeproj"
SCHEME="PromptForge"

detect_version() {
  /usr/bin/python3 - "${REPO_ROOT}/pyproject.toml" <<'PY'
import pathlib
import re
import sys

content = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r'^version\s*=\s*"([^"]+)"', content, re.MULTILINE)
if not match:
    raise SystemExit("Could not determine version from pyproject.toml")
print(match.group(1))
PY
}

APP_VERSION="${APP_VERSION:-$(detect_version)}"
APP_BUILD="${APP_BUILD:-1}"
PYTHON_BIN="${PYTHON_BIN:-python3.11}"
RELEASE_ROOT="${PF_RELEASE_ROOT:-${REPO_ROOT}/dist/macos/${APP_VERSION}}"
ENGINE_STAGE_ROOT="${PF_ENGINE_STAGE_ROOT:-${RELEASE_ROOT}/engine-stage}"
ARCHIVE_PATH="${PF_ARCHIVE_PATH:-${RELEASE_ROOT}/PromptForge.xcarchive}"
APP_PATH="${PF_APP_PATH:-${RELEASE_ROOT}/PromptForge.app}"
ZIP_PATH="${PF_ZIP_PATH:-${RELEASE_ROOT}/PromptForge-${APP_VERSION}.zip}"
CODESIGN_ALLOWED="${PF_CODESIGN_ALLOWED:-1}"

rm -rf "${ENGINE_STAGE_ROOT}" "${ARCHIVE_PATH}" "${APP_PATH}" "${ZIP_PATH}"
mkdir -p "${ENGINE_STAGE_ROOT}" "${RELEASE_ROOT}"

"${PYTHON_BIN}" -m venv "${ENGINE_STAGE_ROOT}/.venv"
"${ENGINE_STAGE_ROOT}/.venv/bin/pip" install --upgrade pip
"${ENGINE_STAGE_ROOT}/.venv/bin/pip" install "${REPO_ROOT}"

echo "Building PromptForge ${APP_VERSION} (${APP_BUILD})..."

if [ "${CODESIGN_ALLOWED}" = "0" ]; then
  PF_ENGINE_SOURCE_ROOT="${REPO_ROOT}" \
  PF_ENGINE_VENV_ROOT="${ENGINE_STAGE_ROOT}/.venv" \
  /usr/bin/xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    archive \
    MARKETING_VERSION="${APP_VERSION}" \
    CURRENT_PROJECT_VERSION="${APP_BUILD}" \
    CODE_SIGNING_ALLOWED=NO
else
  PF_ENGINE_SOURCE_ROOT="${REPO_ROOT}" \
  PF_ENGINE_VENV_ROOT="${ENGINE_STAGE_ROOT}/.venv" \
  /usr/bin/xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -archivePath "${ARCHIVE_PATH}" \
    archive \
    MARKETING_VERSION="${APP_VERSION}" \
    CURRENT_PROJECT_VERSION="${APP_BUILD}"
fi

/usr/bin/ditto "${ARCHIVE_PATH}/Products/Applications/PromptForge.app" "${APP_PATH}"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

if [ "${PF_NOTARIZE:-0}" = "1" ]; then
  : "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required for notarization}"
  : "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required for notarization}"
  : "${APP_STORE_CONNECT_API_KEY_P8:?APP_STORE_CONNECT_API_KEY_P8 is required for notarization}"

  /usr/bin/xcrun notarytool submit "${ZIP_PATH}" \
    --issuer "${APP_STORE_CONNECT_ISSUER_ID}" \
    --key-id "${APP_STORE_CONNECT_KEY_ID}" \
    --key "${APP_STORE_CONNECT_API_KEY_P8}" \
    --wait
  /usr/bin/xcrun stapler staple "${APP_PATH}"
fi

echo "PromptForge release build ready:"
echo "  app: ${APP_PATH}"
echo "  zip: ${ZIP_PATH}"
echo "  version: ${APP_VERSION} (${APP_BUILD})"
