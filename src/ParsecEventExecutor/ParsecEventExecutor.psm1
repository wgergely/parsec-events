Set-StrictMode -Version Latest

$privateRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

$privateLoadOrder = @(
    'Utility.ps1',
    'Toml.ps1',
    'State.ps1',
    'NvidiaInterop.ps1',
    'IngredientRuntime.ps1',
    'IngredientInvocation.ps1',
    'Execution.ps1'
)

foreach ($privateFile in $privateLoadOrder) {
    . (Join-Path -Path $privateRoot -ChildPath $privateFile)
}

$coreRoot = Join-Path -Path $privateRoot -ChildPath 'Core'
if (Test-Path -LiteralPath $coreRoot) {
    . (Join-Path -Path $coreRoot -ChildPath 'Bootstrap.ps1')
    foreach ($coreFile in @(Get-ParsecCoreLoadOrder)) {
        . (Join-Path -Path $coreRoot -ChildPath $coreFile)
    }
    . (Join-Path -Path $coreRoot -ChildPath 'Compat.ps1')
}

Get-ChildItem -Path $publicRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

if (-not (Get-Variable -Name ParsecIngredientRegistry -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParsecIngredientRegistry = @{}
}

if (-not (Get-Variable -Name ParsecIngredientAliasRegistry -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParsecIngredientAliasRegistry = @{}
}

if (-not (Get-Variable -Name ParsecStatusSuccessSet -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParsecStatusSuccessSet = @('Succeeded', 'SucceededWithDrift', 'Compensated')
}

Initialize-ParsecIngredientRegistry
