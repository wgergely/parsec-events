[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$settingsPath = Join-Path -Path $repoRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
$extensions = @('.ps1', '.psd1', '.psm1')

function Resolve-PowerShellFile {
    param(
        [Parameter(Mandatory)]
        [string]$Candidate,

        [Parameter(Mandatory)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory)]
        [string[]]$AllowedExtension
    )

    if ([string]::IsNullOrWhiteSpace($Candidate)) {
        return $null
    }

    $resolvedPath = if ([System.IO.Path]::IsPathRooted($Candidate)) {
        $Candidate
    }
    else {
        Join-Path -Path $RepositoryRoot -ChildPath $Candidate
    }

    if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
        return $null
    }

    $item = Get-Item -LiteralPath $resolvedPath
    if ($AllowedExtension -notcontains $item.Extension.ToLowerInvariant()) {
        return $null
    }

    return $item.FullName
}

function Get-TargetFiles {
    param(
        [string[]]$CandidatePath
    )

    if ($CandidatePath.Count -gt 0) {
        return @(
            $CandidatePath |
                ForEach-Object {
                    Resolve-PowerShellFile -Candidate $_ -RepositoryRoot $repoRoot -AllowedExtension $extensions
                } |
                Where-Object { $_ } |
                Sort-Object -Unique
        )
    }

    return @(
        Get-ChildItem -Path $repoRoot -Recurse -File |
            Where-Object {
                $_.FullName -notmatch '[\\/]\.git[\\/]' -and
                $extensions -contains $_.Extension.ToLowerInvariant()
            } |
            Select-Object -ExpandProperty FullName
    )
}

Import-Module PSScriptAnalyzer -ErrorAction Stop

$targets = @(Get-TargetFiles -CandidatePath $Path)
if ($targets.Count -eq 0) {
    exit 0
}

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$changedFiles = [System.Collections.Generic.List[string]]::new()

foreach ($target in $targets) {
    $original = [System.IO.File]::ReadAllText($target)
    $formatted = Invoke-Formatter -ScriptDefinition $original -Settings $settingsPath

    if ($formatted -cne $original) {
        [System.IO.File]::WriteAllText($target, $formatted, $utf8NoBom)
        $changedFiles.Add([System.IO.Path]::GetRelativePath($repoRoot, $target))
    }
}

if ($changedFiles.Count -gt 0) {
    [Console]::Error.WriteLine('PowerShell formatter updated these files:')
    foreach ($changedFile in $changedFiles) {
        [Console]::Error.WriteLine(" - $changedFile")
    }

    [Console]::Error.WriteLine('Review and stage the formatting changes, then run the commit again.')
    exit 1
}
