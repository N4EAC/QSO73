param([string]$MsysRoot = 'C:\msys64')
$ErrorActionPreference = 'Stop'
$bash = Join-Path $MsysRoot 'usr\bin\bash.exe'
if (-not (Test-Path $bash)) { throw "MSYS2 not found at $MsysRoot. Install MSYS2 and its MinGW64 tools; see README.md." }
$oldSystem=$env:MSYSTEM; $oldSource=$env:QSO73_BUILD_SOURCE; $oldInvoke=$env:CHERE_INVOKING
try {
    $env:MSYSTEM='MINGW64'; $env:CHERE_INVOKING='1'; $env:QSO73_BUILD_SOURCE=$PSScriptRoot
    & $bash -lc 'set -e; cd "$(cygpath -u "$QSO73_BUILD_SOURCE")"; for tool in g++ gcc windres make zip unzip sha256sum; do command -v "$tool" >/dev/null || { echo "Missing $tool: install make zip unzip mingw-w64-x86_64-gcc in MinGW64"; exit 1; }; done; CXX=g++ CC=gcc WINDRES=windres ./build.sh'
    if ($LASTEXITCODE -ne 0) { throw "Windows build failed (exit $LASTEXITCODE). See compiler output above." }
    Write-Host "Share $(Join-Path $PSScriptRoot 'dist\QSO73-0.4.7-windows-x64-test3.zip')"
} finally {
    $env:MSYSTEM=$oldSystem; $env:QSO73_BUILD_SOURCE=$oldSource; $env:CHERE_INVOKING=$oldInvoke
}
