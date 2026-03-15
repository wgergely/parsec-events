[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$formatterPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-PowerShellFormatter.ps1'
$lintPath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-PowerShellLint.ps1'

function Resolve-GitPath {
    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($gitCommand) {
        return $gitCommand.Source
    }

    $programFiles = [Environment]::GetFolderPath('ProgramFiles')
    $programFilesX86 = [Environment]::GetFolderPath('ProgramFilesX86')
    $userProfile = [Environment]::GetFolderPath('UserProfile')
    $candidatePath = @(
        if (-not [string]::IsNullOrWhiteSpace($programFiles)) {
            Join-Path -Path $programFiles -ChildPath 'Git\cmd\git.exe'
        }
        if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
            Join-Path -Path $programFilesX86 -ChildPath 'Git\cmd\git.exe'
        }
        if (-not [string]::IsNullOrWhiteSpace($userProfile)) {
            Join-Path -Path $userProfile -ChildPath 'scoop\apps\git\current\cmd\git.exe'
        }
    )

    foreach ($candidate in $candidatePath) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
    }

    throw 'git.exe was not found. Install Git or add it to PATH before committing.'
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory)]
        [string]$GitExecutable,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GitExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $repoRoot

    foreach ($argument in $ArgumentList) {
        $null = $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    if ($process.ExitCode -ne 0) {
        $message = if ([string]::IsNullOrWhiteSpace($stderr)) {
            "git exited with code $($process.ExitCode)."
        }
        else {
            $stderr.Trim()
        }

        throw $message
    }

    return @(
        $stdout -split '\r?\n' |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-ScriptExitCode {
    if (Test-Path -LiteralPath Variable:\LASTEXITCODE) {
        return [int] $LASTEXITCODE
    }

    return 0
}

$buildScript = Join-Path -Path $PSScriptRoot -ChildPath 'Build-NativeLibrary.ps1'
if (Test-Path -LiteralPath $buildScript) {
    & $buildScript
    if ((Get-ScriptExitCode) -ne 0) {
        exit (Get-ScriptExitCode)
    }
}

$gitPath = Resolve-GitPath
$stagedFiles = @(
    Invoke-GitCapture -GitExecutable $gitPath -ArgumentList @(
        '-C',
        $repoRoot,
        'diff',
        '--cached',
        '--name-only',
        '--diff-filter=ACMR',
        '--',
        '*.ps1',
        '*.psm1',
        '*.psd1'
    )
)

if ($stagedFiles.Count -eq 0) {
    exit 0
}

& $formatterPath @stagedFiles
if ((Get-ScriptExitCode) -ne 0) {
    exit (Get-ScriptExitCode)
}

& $lintPath @stagedFiles
if ((Get-ScriptExitCode) -ne 0) {
    exit (Get-ScriptExitCode)
}
