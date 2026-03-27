#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${ROOT_DIR}/build-ubuntu"
BUILD_TYPE="Release"
INSTALL_PREFIX="/usr/local"
INSTALL_DEPS=0
INSTALL_APP=1
CLEAN_BUILD=0
BUILD_TESTS=OFF

APT_PACKAGES=(
    build-essential
    cmake
    pkg-config
    qtbase5-dev
    qtdeclarative5-dev
    libxtst-dev
    libavahi-compat-libdnssd-dev
    libcurl4-openssl-dev
    libssl-dev
    libx11-dev
    libxext-dev
    libxinerama-dev
    libxi-dev
    libxrandr-dev
    libsm-dev
    libice-dev
)

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Build and install Barrier on Ubuntu.

Options:
  --debug              Build with Debug configuration
  --release            Build with Release configuration (default)
  --build-dir <path>   Override the build directory
  --prefix <path>      Install prefix, default: /usr/local
  --install-deps       Install Ubuntu build dependencies with apt
  --with-tests         Build test targets
  --no-install         Build only, skip cmake --install
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

require_supported_linux() {
    if [ ! -r /etc/os-release ]; then
        printf "Unable to detect Linux distribution.\n" >&2
        exit 1
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    case "${ID:-}" in
        ubuntu|debian|linuxmint|pop|elementary)
            return
            ;;
    esac

    case " ${ID_LIKE:-} " in
        *" ubuntu "*|*" debian "*)
            return
            ;;
    esac

    printf "This script is intended for Ubuntu or Debian-based systems.\n" >&2
    exit 1
}

install_dependencies() {
    printf "Installing Ubuntu build dependencies...\n"
    sudo apt-get update -y
    sudo apt-get install -y "${APT_PACKAGES[@]}"
}

install_barrier() {
    local build_dir=$1
    local prefix=$2

    if [ -w "$prefix" ] || [ ! -e "$prefix" ] && [ -w "$(dirname "$prefix")" ]; then
        "$CMAKE_BIN" --install "$build_dir"
    else
        printf "Installing to %s requires administrator privileges\n" "$prefix"
        sudo "$CMAKE_BIN" --install "$build_dir"
    fi
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
        --prefix)
            shift
            [ $# -gt 0 ] || { printf "Missing value for --prefix\n" >&2; exit 1; }
            INSTALL_PREFIX="$1"
            ;;
        --install-deps)
            INSTALL_DEPS=1
            ;;
        --with-tests)
            BUILD_TESTS=ON
            ;;
        --no-install)
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

if [ "$(uname)" != "Linux" ]; then
    printf "This script only supports Linux.\n" >&2
    exit 1
fi

require_supported_linux
require_command git

if command -v cmake3 >/dev/null 2>&1; then
    CMAKE_BIN="$(command -v cmake3)"
else
    require_command cmake
    CMAKE_BIN="$(command -v cmake)"
fi

if [ "$INSTALL_DEPS" -eq 1 ]; then
    require_command sudo
    install_dependencies
fi

cd "$ROOT_DIR"

[ -r "${ROOT_DIR}/build_env.sh" ] && . "${ROOT_DIR}/build_env.sh"

git submodule update --init --recursive

if [ "$CLEAN_BUILD" -eq 1 ]; then
    rm -rf "$BUILD_DIR"
fi

mkdir -p "$BUILD_DIR"

if command -v nproc >/dev/null 2>&1; then
    BUILD_JOBS="$(nproc)"
else
    BUILD_JOBS=4
fi

printf "Configuring Barrier (%s)...\n" "$BUILD_TYPE"
"$CMAKE_BIN" \
    -S "$ROOT_DIR" \
    -B "$BUILD_DIR" \
    -D CMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -D CMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
    -D BARRIER_BUILD_INSTALLER=ON \
    -D BARRIER_BUILD_TESTS="$BUILD_TESTS" \
    -D CMAKE_POLICY_VERSION_MINIMUM=3.5 \
    ${B_CMAKE_FLAGS:-}

printf "Building Barrier...\n"
"$CMAKE_BIN" --build "$BUILD_DIR" --config "$BUILD_TYPE" --parallel "$BUILD_JOBS"

printf "Build output directory: %s\n" "$BUILD_DIR"

if [ "$INSTALL_APP" -eq 1 ]; then
    install_barrier "$BUILD_DIR" "$INSTALL_PREFIX"
    printf "Installed Barrier under: %s\n" "$INSTALL_PREFIX"
else
    printf "Skipping install because --no-install was provided\n"
fi
