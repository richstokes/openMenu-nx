#!/bin/bash
# Builds the latest GD MENU Card Manager (AvaloniaUI) for this Mac and launches it.
# Usage: ./build-and-run-card-manager-macOS.sh
#
# Output goes to "GD MENU Card Manager/_build-macos" (gitignored) and is
# replaced on every run.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${REPO_ROOT}/GD MENU Card Manager"
APP_NAME="GDMENUCardManager"
BUILD_DIR="_build-macos"

# Common .NET SDK install locations that may be missing from a non-login PATH
export PATH="$HOME/.dotnet:/usr/local/share/dotnet:/opt/homebrew/bin:$PATH"

if [ "$(uname)" != "Darwin" ]; then
    echo "ERROR: This script only runs on macOS."
    exit 1
fi

if ! command -v dotnet &> /dev/null; then
    echo "ERROR: dotnet not found. Install the .NET 8 SDK:"
    echo "  https://dotnet.microsoft.com/download/dotnet/8.0"
    echo "  or: brew install --cask dotnet-sdk"
    exit 1
fi

case "$(uname -m)" in
    arm64)
        ARCH="arm64"
        RID="osx-arm64"
        REDUMP2CDI_DIR="macos-aarch64"
        ;;
    x86_64)
        ARCH="x64"
        RID="osx-x64"
        REDUMP2CDI_DIR="macos-x86_64"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $(uname -m)"
        exit 1
        ;;
esac

cd "${PROJECT_DIR}"

VERSION="$(tr -d '[:space:]' < src/version.txt)"
PUBLISH_DIR="${BUILD_DIR}/publish-${RID}"
BUNDLE_PATH="${BUILD_DIR}/${APP_NAME}.app"

echo "================================================"
echo "Building ${APP_NAME} ${VERSION} for ${RID}"
echo "================================================"

# Quit any running copy so the new build is what actually launches
if pgrep -x "${APP_NAME}" > /dev/null; then
    echo "Stopping running ${APP_NAME}..."
    pkill -x "${APP_NAME}" || true
    while pgrep -x "${APP_NAME}" > /dev/null; do sleep 0.2; done
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${PUBLISH_DIR}"

dotnet publish src/GDMENUCardManager.AvaloniaUI/GDMENUCardManager.AvaloniaUI.csproj \
    -c Release --self-contained true -r "${RID}" \
    -p:PublishSingleFile=false -p:IncludeNativeLibrariesForSelfExtract=true \
    -o "${PUBLISH_DIR}"

cp -R src/GDMENUCardManager.Core/tools "${PUBLISH_DIR}/"
# Never ship user-generated menu options files.
rm -f "${PUBLISH_DIR}/tools/openMenu/menu_data/DEFAULTS.INI" "${PUBLISH_DIR}/tools/openMenu/menu_data/BGM.ADP"

if [ -f "redump2cdi/${REDUMP2CDI_DIR}/redump2cdi" ]; then
    cp "redump2cdi/${REDUMP2CDI_DIR}/redump2cdi" "${PUBLISH_DIR}/tools/"
    chmod +x "${PUBLISH_DIR}/tools/redump2cdi"
else
    echo "Warning: redump2cdi/${REDUMP2CDI_DIR}/redump2cdi not found; Redump conversion will be unavailable."
fi

cp LICENSE README.md "${PUBLISH_DIR}/"

echo "Creating macOS .app bundle..."
KEEP_APP_BUNDLE=1 bash create-macos-bundle.sh "${PUBLISH_DIR}" "${VERSION}" "${BUILD_DIR}" "${ARCH}"
rm -rf "${PUBLISH_DIR}"

echo "Launching ${BUNDLE_PATH}..."
open "${BUNDLE_PATH}"
