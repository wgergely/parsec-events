function Invoke-ParsecIngredient {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [Alias('Ingredient')]
        [string] $Name,

        [Parameter()]
        [ValidateSet('apply', 'capture', 'verify', 'reset')]
        [string] $Operation = 'apply',

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $TokenId,

        [Parameter()]
        [bool] $Verify = $true,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $definition = Get-ParsecIngredientDefinition -Name $Name
    $target = if ($Operation -eq 'reset' -and -not [string]::IsNullOrWhiteSpace($TokenId)) {
        "{0} ({1})" -f $definition.Name, $TokenId
    }
    else {
        $definition.Name
    }

    if (-not $PSCmdlet.ShouldProcess($target, "Invoke ingredient operation '$Operation'")) {
        return
    }

    return Invoke-ParsecIngredientCommandInternal -Name $Name -Operation $Operation -Arguments $Arguments -TokenId $TokenId -Verify $Verify -StateRoot $StateRoot
}
