function Test-ParsecProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $storedProfile = Read-ParsecProfileDocument -Name $Name -StateRoot $StateRoot
    return Invoke-ParsecIngredientVerify -Name 'profile.apply' -Arguments @{ profile_name = $Name } -ExecutionResult (New-ParsecResult -Status 'Succeeded' -Outputs @{ profile = $storedProfile }) -StateRoot $StateRoot -RunState @{}
}
