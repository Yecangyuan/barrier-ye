# GitHub Actions Release Workflows Design

## Goal

Add GitHub Actions automation that:

- verifies Barrier builds on Windows, macOS, and Linux for normal development work
- builds distributable release packages for the same three platforms on version tags
- uploads the built packages to the matching GitHub Release as release assets

## Trigger Model

### CI workflow

- File: `.github/workflows/ci.yml`
- Triggers:
  - `push` on branches only
  - `pull_request`
- Purpose:
  - compile the project on all three platforms
  - fail fast on platform-specific build regressions
  - avoid publishing artifacts or releases during day-to-day development

### Release workflow

- File: `.github/workflows/release.yml`
- Trigger:
  - `push` on tags matching `v*`
- Purpose:
  - build release-mode packages for Windows, macOS, and Linux
  - upload each platform package as a workflow artifact
  - aggregate those artifacts in a final publish job
  - create or update the GitHub Release for the tag and upload the assets

## Packaging Strategy

### Windows

- Reuse the existing repository build path:
  - `azure-pipelines/download_install_qt.ps1`
  - `azure-pipelines/download_install_bonjour_sdk_like.ps1`
  - `clean_build.bat`
  - `build_installer.bat`
- Output package:
  - Inno Setup installer `.exe`

### macOS

- Reuse the existing repository build path:
  - `clean_build.sh`
  - `dist/macos/bundle/build_dist.sh.in`
- Output package:
  - `.dmg` created by `macdeployqt`

### Linux

- Reuse the existing Unix build path:
  - `clean_build.sh`
  - `cmake/Package.cmake`
- Output package:
  - CPack-generated `.tar.bz2`
- Reason:
  - the repository already contains CPack configuration for Unix
  - it is less risky than inventing a new Linux installer format in the same change

## Release Publication

- Each platform build job uploads its package with `actions/upload-artifact@v4`.
- A final `publish-release` job downloads all release artifacts with `actions/download-artifact@v5`.
- The publish job uses `gh release view/create/upload` with `GH_TOKEN=${{ github.token }}`.
- Release creation behavior:
  - if the release does not exist, create it with generated notes
  - if the release already exists, upload or replace assets with `--clobber`

## Required Build Compatibility Fixes

### Windows runner compatibility

- `clean_build.bat` currently only recognizes VS 2017 and VS 2019 generator names.
- GitHub-hosted `windows-2022` runners require VS 2022 support.
- Fix:
  - detect `VisualStudioVersion=17.0`
  - use CMake generator `Visual Studio 17 2022`
  - make VS 2022 the fallback generator

### Inno Setup path compatibility

- `build_installer.bat` currently hardcodes `C:\Program Files (x86)\Inno Setup 5`.
- Modern GitHub runners commonly install Inno Setup 6.
- Fix:
  - prefer an existing `INNO_ROOT` override
  - otherwise auto-detect Inno Setup 6, then 5

### macOS OpenSSL compatibility

- the Darwin OpenSSL lookup in `CMakeLists.txt` only checks a subset of Homebrew paths
- GitHub macOS runners can expose OpenSSL via `openssl@3` paths
- Fix:
  - extend the Homebrew detection logic to accept `openssl`, `openssl@3`, and `openssl@1.1`

## Permissions

- default workflow permission: `contents: read`
- release publish job permission: `contents: write`
- no extra repository permissions should be granted

## Verification

- validate workflow YAML with `actionlint`
- syntax-check touched shell scripts with `bash -n`
- syntax-check touched PowerShell/CMD-compatible logic where feasible
- inspect the resulting artifact paths referenced by the workflows against the repository build scripts
