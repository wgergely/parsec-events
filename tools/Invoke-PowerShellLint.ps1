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

    if (@($CandidatePath).Count -gt 0) {
        return @(
            $CandidatePath |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
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

$issues = @(
    foreach ($target in $targets) {
        Invoke-ScriptAnalyzer -Path $target -Settings $settingsPath
    }
)

if ($issues.Count -eq 0) {
    exit 0
}

[Console]::Error.WriteLine('PowerShell lint failures:')
foreach ($issue in $issues | Sort-Object ScriptPath, Line, Column, RuleName) {
    $relativePath = if ($issue.ScriptPath) {
        [System.IO.Path]::GetRelativePath($repoRoot, $issue.ScriptPath)
    }
    else {
        '<unknown>'
    }

    [Console]::Error.WriteLine(
        '{0}:{1}:{2} [{3}/{4}] {5}' -f
        $relativePath,
        $issue.Line,
        $issue.Column,
        $issue.Severity,
        $issue.RuleName,
        $issue.Message
    )
}

exit 1
