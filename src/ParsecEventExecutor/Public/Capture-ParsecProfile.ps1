function Save-ParsecSnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Capture Parsec snapshot')) {
        return
    }

    $result = Invoke-ParsecCoreIngredientOperation -Name 'display.snapshot' -Operation 'capture' -Arguments @{ snapshot_name = $Name } -StateRoot $StateRoot -RunState @{}
    if (-not (Test-ParsecSuccessfulStatus -Status $result.Status)) {
        $exception = New-Object System.InvalidOperationException("Unable to capture snapshot '$Name': $($result.Message)")
        $errorRecord = New-Object System.Management.Automation.ErrorRecord($exception, 'SnapshotCaptureFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Name)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $result.Outputs.snapshot
}

function Save-ParsecProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Save-ParsecSnapshot -Name $Name -StateRoot $StateRoot -Confirm:$false
}

Set-Alias -Name Capture-ParsecSnapshot -Value Save-ParsecSnapshot -Scope Script
Set-Alias -Name Capture-ParsecProfile -Value Save-ParsecProfile -Scope Script
