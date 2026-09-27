#!/bin/bash
# Builds openMenu for the Dreamcast, then builds the latest GD MENU Card
# Manager (AvaloniaUI) for this Mac with that openMenu inside it, and launches it.
# Usage: ./build-and-run-card-manager-macOS.sh
#
# openMenu is cross-compiled in Docker (see openMenu/BUILD_INSTRUCTIONS.md).
# The image is built for the Mac's own architecture, so Apple Silicon runs it
# natively rather than under amd64 emulation. The first run builds the
# toolchain image, which takes a while; later runs reuse it. The resulting 1ST_READ.BIN replaces the copy the Card Manager
# ships in src/GDMENUCardManager.Core/tools/openMenu/menu_data, so the card
# always gets the openMenu built from this checkout.
#
# Card Manager output goes to "GD MENU Card Manager/_build-macos" (gitignored)
# and is replaced on every run.

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

if ! command -v docker &> /dev/null; then
    echo "ERROR: docker not found. Install Docker Desktop (needed to build openMenu):"
    echo "  brew install --cask docker"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "ERROR: Docker is not running. Start Docker Desktop and try again."
    exit 1
fi

# ---- openMenu (Dreamcast) ----
OPENMENU_DIR="${REPO_ROOT}/openMenu"
OPENMENU_IMAGE="openmenu-build"
OPENMENU_BIN="${OPENMENU_DIR}/cmake-build-dc-release/bin/1ST_READ.BIN"
CARD_MANAGER_OPENMENU_BIN="${PROJECT_DIR}/src/GDMENUCardManager.Core/tools/openMenu/menu_data/1ST_READ.BIN"

echo "================================================"
echo "Building openMenu for Dreamcast"
echo "================================================"

if ! docker image inspect "${OPENMENU_IMAGE}" &> /dev/null; then
    echo "Toolchain image ${OPENMENU_IMAGE} not found; building it (first time only, this is slow)..."
    docker build -t "${OPENMENU_IMAGE}" "${OPENMENU_DIR}/docker"
fi

docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "${OPENMENU_DIR}:/workspaces/openmenu" -w /workspaces/openmenu \
    "${OPENMENU_IMAGE}" \
    bash -c "source /opt/toolchains/dc/kos/environ.sh && cmake --preset dc-release && cmake --build --preset dc-release"

if [ ! -f "${OPENMENU_BIN}" ]; then
    echo "ERROR: openMenu build produced no ${OPENMENU_BIN}"
    exit 1
fi

cp "${OPENMENU_BIN}" "${CARD_MANAGER_OPENMENU_BIN}"
echo "Installed openMenu into Card Manager: ${CARD_MANAGER_OPENMENU_BIN}"

# ---- GD MENU Card Manager (macOS) ----
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
