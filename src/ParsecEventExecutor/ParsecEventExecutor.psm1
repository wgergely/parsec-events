Set-StrictMode -Version Latest

$privateRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Private'
$publicRoot = Join-Path -Path $PSScriptRoot -ChildPath 'Public'

Get-ChildItem -Path $privateRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

Get-ChildItem -Path $publicRoot -Filter '*.ps1' -File | Sort-Object Name | ForEach-Object {
    . $_.FullName
}

if (-not (Get-Variable -Name ParsecIngredientRegistry -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParsecIngredientRegistry = @{}
}

if (-not (Get-Variable -Name ParsecStatusSuccessSet -Scope Script -ErrorAction SilentlyContinue)) {
    $script:ParsecStatusSuccessSet = @('Succeeded', 'SucceededWithDrift', 'Compensated')
}

Initialize-ParsecIngredientRegistry
