function Save-ParsecProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Capture Parsec profile')) {
        return
    }

    $result = Invoke-ParsecIngredientExecute -Name 'profile.snapshot' -Arguments @{ profile_name = $Name; approved = $true } -StateRoot $StateRoot -RunState @{}
    if (-not (Test-ParsecSuccessfulStatus -Status $result.Status)) {
        $exception = New-Object System.InvalidOperationException("Unable to capture profile '$Name': $($result.Message)")
        $errorRecord = New-Object System.Management.Automation.ErrorRecord($exception, 'ProfileCaptureFailed', [System.Management.Automation.ErrorCategory]::InvalidOperation, $Name)
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    return $result.Outputs.profile
}

Set-Alias -Name Capture-ParsecProfile -Value Save-ParsecProfile -Scope Script
