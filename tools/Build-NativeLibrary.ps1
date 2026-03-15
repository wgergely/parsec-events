[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$projectPath = Join-Path -Path $repoRoot -ChildPath 'src/ParsecEventExecutor.Native/ParsecEventExecutor.Native.csproj'
$moduleRoot = Join-Path -Path $repoRoot -ChildPath 'src/ParsecEventExecutor'

if (-not (Test-Path -LiteralPath $projectPath)) {
    throw "Project file not found: $projectPath"
}

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    throw 'dotnet SDK is not installed or not on PATH.'
}

Write-Verbose "Building ParsecEventExecutor.Native..."
& dotnet build $projectPath -c Release --nologo -v quiet
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build failed with exit code $LASTEXITCODE."
}

$framework = Get-ChildItem -Path (Join-Path (Split-Path $projectPath) 'bin/Release') -Directory | Select-Object -First 1
$dllSource = Join-Path -Path $framework.FullName -ChildPath 'ParsecEventExecutor.Native.dll'
$dllTarget = Join-Path -Path $moduleRoot -ChildPath 'ParsecEventExecutor.Native.dll'

if (-not (Test-Path -LiteralPath $dllSource)) {
    throw "Build output not found: $dllSource"
}

Copy-Item -LiteralPath $dllSource -Destination $dllTarget -Force
Write-Verbose "Copied to $dllTarget"
