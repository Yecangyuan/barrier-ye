#!/usr/bin/env pwsh
# Requires PowerShell 5.1 or newer
# Build and install Barrier on Windows

[CmdletBinding()]
param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string] $Configuration = "Release",

    [ValidateSet("x64", "Win32", "ARM64")]
    [string] $Platform = "x64",

    [string] $BuildDir = "build-windows",
    [string] $InstallDir = "C:\Program Files\Barrier",
    [string] $Generator = "Visual Studio 17 2022",
    [string] $QtDir = "",
    [string] $OpenSSLRoot = "",
    [int] $Jobs = 0,

    [switch] $NoGui,
    [switch] $NoTests,
    [switch] $WithTests,
    [switch] $BuildInstaller,
    [switch] $NoInstall,
    [switch] $Clean,
    [switch] $Help
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    @"
Usage: build_install_windows.ps1 [options]

Build Barrier on Windows and optionally install binaries or build an installer.

Options:
  -Configuration <Debug|Release|RelWithDebInfo|MinSizeRel>
                       Build configuration (default: Release)
  -Platform <x64|Win32|ARM64>
                       Target platform (default: x64)
  -BuildDir <path>     CMake build directory (default: build-windows)
  -InstallDir <path>   Directory to copy binaries (default: 'C:\Program Files\Barrier')
  -Generator <name>    CMake generator (default: 'Visual Studio 17 2022')
  -QtDir <path>        Path to Qt5 installation, e.g. C:\Qt\5.15.2\msvc2019_64
  -OpenSSLRoot <path>  Path to OpenSSL, e.g. C:\Program Files\OpenSSL-Win64
  -Jobs <n>            Number of parallel build jobs (default: auto-detect)
  -NoGui               Build without the GUI
  -NoTests             Skip building tests
  -WithTests           Build and run tests
  -BuildInstaller      Build the Inno Setup installer after compiling
  -NoInstall           Build only, do not copy binaries to InstallDir
  -Clean               Remove the build directory before configuring
  -Help                Show this help
"@ | Write-Host
}

function Get-RepoRoot {
    return $PSScriptRoot
}

function Test-CommandExists {
    param([string] $Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Find-VisualStudio {
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio with C++ CMake tools, or run from a Developer PowerShell."
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installPath) {
        throw "No Visual Studio installation with C++ tools was found."
    }

    return $installPath
}

function Enter-VsDevShell {
    if ($env:VSCMD_VER) {
        Write-Host "Using existing Visual Studio developer environment $env:VSCMD_VER"
        return
    }

    $installPath = Find-VisualStudio
    $devShell = Join-Path $installPath "Common7\Tools\Launch-VsDevShell.ps1"
    if (!(Test-Path $devShell)) {
        throw "Launch-VsDevShell.ps1 not found under $installPath"
    }

    $devArch = switch ($Platform) {
        "x64" { "amd64" }
        "Win32" { "x86" }
        "ARM64" { "arm64" }
    }

    Write-Host "Entering Visual Studio developer shell: $installPath"
    & $devShell -Arch $devArch -HostArch amd64 | Out-Null
}

function Get-DefaultQtDir {
    $candidates = @(
        "C:\Qt\5.15.2\msvc2019_64",
        "C:\Qt\5.15.2\msvc2019",
        "C:\Qt\5.15.0\msvc2019_64",
        "C:\Qt\5.12.12\msvc2017_64",
        "C:\Qt\5.12.12\msvc2017"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "bin\qmake.exe")) {
            return $candidate
        }
    }

    return $null
}

function Get-DefaultOpenSSLRoot {
    $candidates = @(
        "C:\Program Files\OpenSSL-Win64",
        "C:\Program Files\OpenSSL",
        "C:\OpenSSL-Win64",
        "C:\OpenSSL",
        "C:\Program Files (x86)\OpenSSL-Win32",
        "C:\Program Files (x86)\OpenSSL"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "include\openssl\ssl.h")) {
            return $candidate
        }
    }

    return $null
}

function Get-CmakePathArgs {
    $args = @()

    if (!$QtDir) {
        $QtDir = Get-DefaultQtDir
        if ($QtDir) {
            Write-Host "Detected Qt5 at: $QtDir"
        }
    }

    if ($QtDir) {
        $qtCmake = Join-Path $QtDir "lib\cmake\Qt5"
        if (Test-Path $qtCmake) {
            $args += "-DQt5_DIR=$qtCmake"
        }
        else {
            $args += "-DCMAKE_PREFIX_PATH=$QtDir"
        }
    }

    if (!$OpenSSLRoot) {
        $OpenSSLRoot = Get-DefaultOpenSSLRoot
        if ($OpenSSLRoot) {
            Write-Host "Detected OpenSSL at: $OpenSSLRoot"
        }
    }

    if ($OpenSSLRoot) {
        $args += "-DOPENSSL_ROOT_DIR=$OpenSSLRoot"
    }

    return $args
}

function Get-BuildJobs {
    if ($Jobs -gt 0) {
        return $Jobs
    }

    $cpuCount = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    if ($cpuCount -gt 0) {
        return $cpuCount
    }

    return 4
}

function Install-Binaries {
    param(
        [string] $SourceDir,
        [string] $DestinationDir
    )

    if (!(Test-Path $SourceDir)) {
        throw "Build output directory not found: $SourceDir"
    }

    if (Test-Path $DestinationDir) {
        Remove-Item -Recurse -Force $DestinationDir
    }

    New-Item -ItemType Directory -Path $DestinationDir | Out-Null
    Copy-Item -Path "$SourceDir\*" -Destination $DestinationDir -Recurse -Force

    Write-Host "Installed Barrier binaries to: $DestinationDir"
}

function Build-Installer {
    param(
        [string] $BuildDirectory,
        [string] $Configuration
    )

    $innoRoots = @(
        "C:\Program Files (x86)\Inno Setup 6",
        "C:\Program Files (x86)\Inno Setup 5",
        "C:\Program Files\Inno Setup 6"
    )

    $innoRoot = $null
    foreach ($candidate in $innoRoots) {
        if (Test-Path (Join-Path $candidate "ISCC.exe")) {
            $innoRoot = $candidate
            break
        }
    }

    if (!$innoRoot) {
        throw "Inno Setup not found. Install Inno Setup 5 or 6 to build the installer."
    }

    $issFile = Join-Path $BuildDirectory "installer-inno\barrier.iss"
    if (!(Test-Path $issFile)) {
        throw "Installer script not found: $issFile. Configure with -BARRIER_BUILD_INSTALLER=ON."
    }

    Write-Host "Building installer with Inno Setup..."
    & "$innoRoot\ISCC.exe" /Qp "$issFile"
    if ($LASTEXITCODE -ne 0) {
        throw "Inno Setup build failed with exit code $LASTEXITCODE"
    }

    Write-Host "Installer output: $BuildDirectory\installer-inno\bin"
}

function Invoke-Tests {
    param(
        [string] $BuildDirectory,
        [string] $Configuration
    )

    Write-Host "Running tests..."
    & ctest --test-dir $BuildDirectory -C $Configuration --output-on-failure
    if ($LASTEXITCODE -ne 0) {
        throw "Tests failed with exit code $LASTEXITCODE"
    }
}

# --- Main ---

if ($Help) {
    Show-Usage
    exit 0
}

if ($env:OS -ne "Windows_NT") {
    Write-Error "This script only supports Windows."
    exit 1
}

if (!(Test-CommandExists "git")) {
    Write-Error "Missing required command: git"
    exit 1
}

$repoRoot = Get-RepoRoot
Set-Location $repoRoot

Enter-VsDevShell

if (!(Test-CommandExists "cmake")) {
    Write-Error "Missing required command: cmake"
    exit 1
}

$cmake = Get-Command cmake
Write-Host "Using CMake: $($cmake.Source)"

$pathArgs = Get-CmakePathArgs
$buildJobs = Get-BuildJobs
$buildGui = if ($NoGui) { "OFF" } else { "ON" }
$buildTests = if ($NoTests) { "OFF" } else { "ON" }
$buildInstallerOption = if ($BuildInstaller) { "ON" } else { "OFF" }

if ($Clean -and (Test-Path $BuildDir)) {
    Write-Host "Cleaning build directory: $BuildDir"
    Remove-Item -Recurse -Force $BuildDir
}

Write-Host "Configuring Barrier ($Configuration $Platform)..."
$configureArgs = @(
    "-S", $repoRoot,
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", $Platform,
    "-DCMAKE_BUILD_TYPE=$Configuration",
    "-DBARRIER_BUILD_GUI=$buildGui",
    "-DBARRIER_BUILD_TESTS=$buildTests",
    "-DBARRIER_BUILD_INSTALLER=$buildInstallerOption"
) + $pathArgs

& cmake @configureArgs
if ($LASTEXITCODE -ne 0) {
    throw "CMake configuration failed with exit code $LASTEXITCODE"
}

Write-Host "Building Barrier..."
$targets = @("barrierc", "barriers")
if (!$NoGui) {
    $targets += "barrier"
}
if (!$NoTests) {
    $targets += "unittests"
}

foreach ($target in $targets) {
    Write-Host "Building target $target..."
    & cmake --build $BuildDir --config $Configuration --target $target --parallel $buildJobs
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for target $target with exit code $LASTEXITCODE"
    }
}

if ($WithTests -and !$NoTests) {
    Invoke-Tests -BuildDirectory $BuildDir -Configuration $Configuration
}

if ($BuildInstaller) {
    Build-Installer -BuildDirectory $BuildDir -Configuration $Configuration
}

$binaryDir = Join-Path $BuildDir "bin\$Configuration"
Write-Host ""
Write-Host "Build complete."
Write-Host "Binaries: $binaryDir"

if (!$NoInstall) {
    Install-Binaries -SourceDir $binaryDir -DestinationDir $InstallDir
}
else {
    Write-Host "Skipping install because -NoInstall was provided."
}
