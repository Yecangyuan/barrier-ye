#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build-macos"
BUILD_TYPE="Release"
INSTALL_DIR="/Applications"
INSTALL_APP=1
CLEAN_BUILD=0
CONFIGURE_ONLY=0
SIGN_APP=1
DEPLOYMENT_TARGET=""
CODESIGN_IDENTITY="${BARRIER_CODESIGN_IDENTITY:-}"
BUNDLE_ID="${BARRIER_BUNDLE_ID:-io.github.yecangyuan.barrier-ye}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build Barrier on macOS and optionally install Barrier.app.

Options:
  --debug              Build with Debug configuration
  --release            Build with Release configuration (default)
  --build-dir <path>   Override the build directory
  --install-dir <path> Override the application install directory
  --no-install         Build only, do not copy Barrier.app
  --no-sign            Build without code signing the app bundle
  --codesign-identity <name>
                       Use a fixed signing identity instead of ad-hoc signing
  --bundle-id <id>     Override CFBundleIdentifier for Barrier.app
  --deployment-target <version>
                       Override CMAKE_OSX_DEPLOYMENT_TARGET
  --configure-only     Run CMake configure only
  --clean              Remove the build directory before configuring
  -h, --help           Show this help
EOF
}

require_command() {
    local cmd=$1
    if ! command -v "$cmd" >/dev/null 2>&1; then
        printf "Missing required command: %s\n" "$cmd" >&2
        exit 1
    fi
}

detect_macos_deployment_target() {
    if command -v sw_vers >/dev/null 2>&1; then
        sw_vers -productVersion | awk -F. '{ if (NF >= 2) printf "%s.%s\n", $1, $2; else printf "%s.0\n", $1; }'
    else
        printf "10.9\n"
    fi
}

detect_existing_codesign_identity() {
    local app_bundle=$1
    local codesign_info
    local authority

    if [ ! -d "$app_bundle" ]; then
        return 1
    fi

    codesign_info="$(codesign -dv --verbose=4 "$app_bundle" 2>&1 || true)"
    if printf "%s\n" "$codesign_info" | grep -q '^Signature=adhoc$'; then
        return 1
    fi

    authority="$(printf "%s\n" "$codesign_info" | awk -F= '/^Authority=/{print $2; exit}')"
    if [ -n "$authority" ]; then
        printf "%s\n" "$authority"
        return 0
    fi

    return 1
}

copy_app() {
    local src_app=$1
    local dst_dir=$2
    local dst_app="${dst_dir}/Barrier.app"

    if [ ! -d "$src_app" ]; then
        printf "App bundle not found: %s\n" "$src_app" >&2
        exit 1
    fi

    mkdir -p "$dst_dir" 2>/dev/null || true

    if [ -w "$dst_dir" ]; then
        rm -rf "$dst_app"
        ditto "$src_app" "$dst_app"
    else
        printf "Installing to %s requires administrator privileges\n" "$dst_dir"
        sudo rm -rf "$dst_app"
        sudo mkdir -p "$dst_dir"
        sudo ditto "$src_app" "$dst_app"
    fi

    printf "Installed: %s\n" "$dst_app"
}

sign_app() {
    local app_bundle=$1

    if [ ! -d "$app_bundle" ]; then
        printf "App bundle not found for signing: %s\n" "$app_bundle" >&2
        exit 1
    fi

    if [ -z "$CODESIGN_IDENTITY" ]; then
        local installed_app="${INSTALL_DIR}/Barrier.app"
        if CODESIGN_IDENTITY="$(detect_existing_codesign_identity "$installed_app")"; then
            printf "Reusing installed app signing identity: %s\n" "$CODESIGN_IDENTITY"
        else
            CODESIGN_IDENTITY="-"
            printf "No stable signing identity found, falling back to ad-hoc signing.\n"
            printf "Warning: ad-hoc signatures can cause macOS Accessibility permission prompts to reappear after rebuilds.\n"
        fi
    fi

    printf "Signing app bundle with identity '%s': %s\n" "$CODESIGN_IDENTITY" "$app_bundle"
    codesign --force --deep --sign "$CODESIGN_IDENTITY" "$app_bundle"
}

while [ $# -gt 0 ]; do
    case "$1" in
        --debug)
            BUILD_TYPE="Debug"
            ;;
        --release)
            BUILD_TYPE="Release"
            ;;
        --build-dir)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --build-dir\n" >&2; exit 1; }
            BUILD_DIR="$1"
            ;;
        --install-dir)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --install-dir\n" >&2; exit 1; }
            INSTALL_DIR="$1"
            ;;
        --no-install)
            INSTALL_APP=0
            ;;
        --no-sign)
            SIGN_APP=0
            ;;
        --codesign-identity)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --codesign-identity\n" >&2; exit 1; }
            CODESIGN_IDENTITY="$1"
            ;;
        --bundle-id)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --bundle-id\n" >&2; exit 1; }
            BUNDLE_ID="$1"
            ;;
        --deployment-target)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --deployment-target\n" >&2; exit 1; }
            DEPLOYMENT_TARGET="$1"
            ;;
        --configure-only)
            CONFIGURE_ONLY=1
            INSTALL_APP=0
            ;;
        --clean)
            CLEAN_BUILD=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf "Unknown option: %s\n\n" "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if [ "$(uname)" != "Darwin" ]; then
    printf "This script only supports macOS.\n" >&2
    exit 1
fi

if [ -z "$DEPLOYMENT_TARGET" ]; then
    DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$(detect_macos_deployment_target)}"
fi

require_command git
require_command xcode-select
require_command ditto
require_command codesign

if command -v cmake3 >/dev/null 2>&1; then
    CMAKE_BIN="$(command -v cmake3)"
else
    require_command cmake
    CMAKE_BIN="$(command -v cmake)"
fi

cd "$ROOT_DIR"

BARRIER_BUILD_ENV="${BARRIER_BUILD_ENV:-}"
CMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-}"
LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
CPATH="${CPATH:-}"
PKG_CONFIG_PATH="${PKG_CONFIG_PATH:-}"
. "${ROOT_DIR}/osx_environment.sh"
[ -r "${ROOT_DIR}/build_env.sh" ] && . "${ROOT_DIR}/build_env.sh"

git submodule update --init --recursive

if [ "$CLEAN_BUILD" -eq 1 ]; then
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

SDK_PATH="$(xcode-select --print-path)/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if command -v sysctl >/dev/null 2>&1; then
    BUILD_JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || printf "4")"
else
    BUILD_JOBS=4
fi

printf "Configuring Barrier (%s)...\n" "$BUILD_TYPE"
printf "Using macOS deployment target: %s\n" "$DEPLOYMENT_TARGET"
printf "Using macOS bundle identifier: %s\n" "$BUNDLE_ID"
"$CMAKE_BIN" \
    -S "$ROOT_DIR" \
    -B "$BUILD_DIR" \
    -D CMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -D BARRIER_BUILD_INSTALLER=ON \
    -D BARRIER_BUNDLE_ID="$BUNDLE_ID" \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -D CMAKE_OSX_SYSROOT="$SDK_PATH" \
    -D CMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
    ${B_CMAKE_FLAGS:-}

if [ "$CONFIGURE_ONLY" -eq 1 ]; then
    printf "Configuration completed: %s\n" "$BUILD_DIR"
    exit 0
fi

printf "Building Barrier.app...\n"
"$CMAKE_BIN" --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$BUILD_JOBS"

APP_BUNDLE="${BUILD_DIR}/bundle/Barrier.app"
if [ ! -d "$APP_BUNDLE" ]; then
    printf "Build finished, but app bundle was not produced: %s\n" "$APP_BUNDLE" >&2
    exit 1
fi

if [ "$SIGN_APP" -eq 1 ]; then
    sign_app "$APP_BUNDLE"
fi

printf "Built app bundle: %s\n" "$APP_BUNDLE"

if [ "$INSTALL_APP" -eq 1 ]; then
    copy_app "$APP_BUNDLE" "$INSTALL_DIR"
else
    printf "Skipping install because --no-install was provided\n"
fi
