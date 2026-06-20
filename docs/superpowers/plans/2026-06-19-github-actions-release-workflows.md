# GitHub Actions Release Workflows Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add GitHub Actions CI and tag-based release automation that builds Barrier on Windows, macOS, and Linux and publishes platform packages to GitHub Releases.

**Architecture:** Split the automation into a branch/PR CI workflow and a tag-only release workflow. Reuse the repository's current platform-specific build scripts wherever they already encode dependency and packaging behavior, and only patch the small compatibility gaps needed for modern GitHub-hosted runners.

**Tech Stack:** GitHub Actions, CMake, CPack, Homebrew, apt, Chocolatey, Inno Setup, gh CLI

---

### Task 1: Document the approved workflow design

**Files:**
- Create: `docs/superpowers/specs/2026-06-19-github-actions-release-workflows-design.md`
- Create: `docs/superpowers/plans/2026-06-19-github-actions-release-workflows.md`

- [ ] **Step 1: Write the design doc**

```md
Describe the trigger split, platform package formats, release publishing strategy,
and the compatibility fixes required for Windows and macOS runners.
```

- [ ] **Step 2: Review the design doc for scope and ambiguity**

Run: `rtk sed -n '1,220p' docs/superpowers/specs/2026-06-19-github-actions-release-workflows-design.md`
Expected: the document names all workflows, platforms, package outputs, and release behavior with no placeholder markers

- [ ] **Step 3: Write the implementation plan**

```md
Record the repo files to modify, the workflow/job boundaries, and the exact
verification commands for YAML and script syntax.
```

- [ ] **Step 4: Re-read the plan**

Run: `rtk sed -n '1,260p' docs/superpowers/plans/2026-06-19-github-actions-release-workflows.md`
Expected: the plan header is present and each implementation area maps to a concrete file change

### Task 2: Add the CI and release workflows

**Files:**
- Create: `.github/workflows/ci.yml`
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the CI workflow**

```yaml
on:
  push:
    branches: ["**"]
  pull_request:
```

- [ ] **Step 2: Add Windows, macOS, and Linux build jobs**

```yaml
jobs:
  linux:
    runs-on: ubuntu-24.04
  macos:
    runs-on: macos-15
  windows:
    runs-on: windows-2022
```

- [ ] **Step 3: Write the release workflow**

```yaml
on:
  push:
    tags:
      - "v*"
```

- [ ] **Step 4: Add artifact upload and release publish logic**

```yaml
- uses: actions/upload-artifact@v4
- uses: actions/download-artifact@v5
- run: gh release create ...
```

- [ ] **Step 5: Validate workflow structure**

Run: `actionlint .github/workflows/ci.yml .github/workflows/release.yml`
Expected: no diagnostics

### Task 3: Patch the existing build scripts for hosted runner compatibility

**Files:**
- Modify: `clean_build.bat`
- Modify: `build_installer.bat`
- Modify: `CMakeLists.txt`

- [ ] **Step 1: Add VS 2022 detection to `clean_build.bat`**

```bat
if "%VisualStudioVersion%"=="17.0" (
    set cmake_gen=Visual Studio 17 2022
)
```

- [ ] **Step 2: Make `build_installer.bat` detect Inno Setup 6 or 5**

```bat
if not defined INNO_ROOT if exist "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" set INNO_ROOT=C:\Program Files (x86)\Inno Setup 6
if not defined INNO_ROOT if exist "C:\Program Files (x86)\Inno Setup 5\ISCC.exe" set INNO_ROOT=C:\Program Files (x86)\Inno Setup 5
```

- [ ] **Step 3: Expand macOS Homebrew OpenSSL lookup in `CMakeLists.txt`**

```cmake
elseif (BREW_PROGRAM)
    execute_process(COMMAND ${BREW_PROGRAM} --prefix openssl@3 ...)
```

- [ ] **Step 4: Syntax-check the touched scripts**

Run: `bash -n clean_build.sh`
Expected: no output and exit code 0

### Task 4: Verify artifact paths and release packaging commands

**Files:**
- Test: `.github/workflows/ci.yml`
- Test: `.github/workflows/release.yml`
- Test: `dist/macos/bundle/build_dist.sh.in`
- Test: `build_installer.bat`

- [ ] **Step 1: Confirm the workflow upload paths match repo outputs**

Run: `rtk rg -n "upload-artifact|path:|cpack|build_installer|build_dist" .github/workflows build_installer.bat dist/macos/bundle/build_dist.sh.in`
Expected: Windows points to `build/installer-inno/bin`, macOS points to `build/bundle/*.dmg`, Linux points to `build/*.tar.bz2`

- [ ] **Step 2: Review the final diff**

Run: `rtk git diff -- .github/workflows clean_build.bat build_installer.bat CMakeLists.txt docs/superpowers`
Expected: only the planned workflow, compatibility, and documentation changes are present

- [ ] **Step 3: Keep the implementation ready for execution**

```bash
git status --short
```
