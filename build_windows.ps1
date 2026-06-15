param(
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string] $Configuration = "Release",

    [ValidateSet("x64", "Win32", "ARM64")]
    [string] $Platform = "x64",

    [string] $BuildDir = "build-windows",
    [string] $Generator = "Visual Studio 17 2022",
    [string] $QtDir = "",
    [string] $OpenSSLRoot = "",

    [switch] $NoGui,
    [switch] $NoTests,
    [switch] $BuildInstaller,
    [switch] $RunTests
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
    return $PSScriptRoot
}

function Enter-VsDevShell {
    if ($env:VSCMD_VER) {
        Write-Host "Using existing Visual Studio developer environment $env:VSCMD_VER"
        return
    }

    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (!(Test-Path $vswhere)) {
        throw "vswhere.exe not found. Install Visual Studio with C++ CMake tools, or run from a Developer PowerShell."
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (!$installPath) {
        throw "No Visual Studio installation with C++ tools was found."
    }

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

function Add-CmakePathArgs {
    $args = @()

    if ($QtDir) {
        $qtCmake = Join-Path $QtDir "lib\cmake\Qt5"
        if (Test-Path $qtCmake) {
            $args += "-DQt5_DIR=$qtCmake"
        }
        else {
            $args += "-DCMAKE_PREFIX_PATH=$QtDir"
        }
    }

    if ($OpenSSLRoot) {
        $args += "-DOPENSSL_ROOT_DIR=$OpenSSLRoot"
    }

    return $args
}

$repoRoot = Resolve-RepoRoot
Set-Location $repoRoot

Enter-VsDevShell

$cmake = Get-Command cmake -ErrorAction Stop
Write-Host "Using CMake: $($cmake.Source)"

$buildGui = if ($NoGui) { "OFF" } else { "ON" }
$buildTests = if ($NoTests) { "OFF" } else { "ON" }
$buildInstallerOption = if ($BuildInstaller) { "ON" } else { "OFF" }
$pathArgs = Add-CmakePathArgs

$configureArgs = @(
    "-S", ".",
    "-B", $BuildDir,
    "-G", $Generator,
    "-A", $Platform,
    "-DBARRIER_BUILD_GUI=$buildGui",
    "-DBARRIER_BUILD_TESTS=$buildTests",
    "-DBARRIER_BUILD_INSTALLER=$buildInstallerOption"
) + $pathArgs

Write-Host "Configuring Barrier..."
& cmake @configureArgs

$targets = @("barrierc", "barriers")
if (!$NoGui) {
    $targets += "barrier"
}
if (!$NoTests) {
    $targets += "unittests"
}

foreach ($target in $targets) {
    Write-Host "Building target $target ($Configuration)..."
    & cmake --build $BuildDir --config $Configuration --target $target --parallel
}

if ($RunTests -and !$NoTests) {
    Write-Host "Running tests..."
    & ctest --test-dir $BuildDir -C $Configuration --output-on-failure
}

if ($BuildInstaller) {
    Write-Host "Building installer..."
    & .\build_installer.bat
}

Write-Host ""
Write-Host "Build complete."
Write-Host "Binaries: $BuildDir\bin\$Configuration"
if ($BuildInstaller) {
    Write-Host "Installer output: $BuildDir\installer-inno\bin"
}
