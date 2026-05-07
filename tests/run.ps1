# Run the offline test suite.
# Usage:  .\tests\run.ps1            (quiet)
#         .\tests\run.ps1 -v         (verbose)
#
# Auto-locates lua.exe in common install paths so you don't need it on PATH.

param([switch]$v)

$ErrorActionPreference = "Stop"

$candidates = @(
    "lua.exe",
    "luajit.exe",
    "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe",
    "$env:ProgramFiles\Lua\bin\lua.exe",
    "${env:ProgramFiles(x86)}\Lua\bin\lua.exe"
)

$lua = $null
foreach ($c in $candidates) {
    $cmd = Get-Command $c -ErrorAction SilentlyContinue
    if ($cmd) { $lua = $cmd.Source; break }
    if (Test-Path $c) { $lua = $c; break }
}

if (-not $lua) {
    Write-Host "Lua interpreter not found. Install with: winget install DEVCOM.Lua" -ForegroundColor Red
    exit 2
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Push-Location $root
try {
    if ($v) {
        & $lua "tests\run.lua" "-v"
    } else {
        & $lua "tests\run.lua"
    }
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
