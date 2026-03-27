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

    printf "Signing app bundle: %s\n" "$app_bundle"
    codesign --force --deep --sign - "$app_bundle"
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
"$CMAKE_BIN" \
    -S "$ROOT_DIR" \
    -B "$BUILD_DIR" \
    -D CMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -D BARRIER_BUILD_INSTALLER=ON \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -D CMAKE_OSX_SYSROOT="$SDK_PATH" \
    -D CMAKE_OSX_DEPLOYMENT_TARGET=10.9 \
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
