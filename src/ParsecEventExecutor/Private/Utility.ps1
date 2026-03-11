function Get-ParsecModuleRoot {
    [CmdletBinding()]
    param()

    return $PSScriptRoot | Split-Path -Parent
}

function Get-ParsecRepositoryRoot {
    [CmdletBinding()]
    param()

    return (Get-ParsecModuleRoot | Split-Path -Parent | Split-Path -Parent)
}

function Get-ParsecDefaultStateRoot {
    [CmdletBinding()]
    param()

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    return Join-Path -Path $localAppData -ChildPath 'ParsecEventExecutor'
}

function Initialize-ParsecStateRoot {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    foreach ($relative in @('.', 'profiles', 'runs', 'logs', 'events')) {
        $path = if ($relative -eq '.') { $StateRoot } else { Join-Path -Path $StateRoot -ChildPath $relative }
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    return $StateRoot
}

function ConvertTo-ParsecPlainObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $output = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $output[$key] = ConvertTo-ParsecPlainObject -InputObject $InputObject[$key]
        }

        return $output
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $values = foreach ($item in $InputObject) {
            ConvertTo-ParsecPlainObject -InputObject $item
        }

        return @($values)
    }

    if ($InputObject -is [psobject] -and $null -ne $InputObject.PSObject -and @($InputObject.PSObject.Properties).Count -gt 0) {
        $output = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            if ($property.Name -eq 'PSPath' -or $property.Name -eq 'PSParentPath' -or $property.Name -eq 'PSChildName' -or $property.Name -eq 'PSDrive' -or $property.Name -eq 'PSProvider') {
                continue
            }

            $output[$property.Name] = ConvertTo-ParsecPlainObject -InputObject $property.Value
        }

        return $output
    }

    return $InputObject
}

function Read-ParsecJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 100
}

function Write-ParsecJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        $InputObject
    )

    $directory = Split-Path -Path $Path -Parent
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $plain = ConvertTo-ParsecPlainObject -InputObject $InputObject
    $json = $plain | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
    return $Path
}

function New-ParsecResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Status,

        [Parameter()]
        [string] $Message,

        [Parameter()]
        [hashtable] $Requested = @{},

        [Parameter()]
        [hashtable] $Observed = @{},

        [Parameter()]
        [hashtable] $Outputs = @{},

        [Parameter()]
        [string[]] $Warnings = @(),

        [Parameter()]
        [string[]] $Errors = @(),

        [Parameter()]
        [bool] $CanCompensate = $false
    )

    return [pscustomobject]@{
        PSTypeName    = 'ParsecEventExecutor.Result'
        Status        = $Status
        Message       = $Message
        Requested     = ConvertTo-ParsecPlainObject -InputObject $Requested
        Observed      = ConvertTo-ParsecPlainObject -InputObject $Observed
        Outputs       = ConvertTo-ParsecPlainObject -InputObject $Outputs
        Warnings      = @($Warnings)
        Errors        = @($Errors)
        CanCompensate = $CanCompensate
        Timestamp     = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Test-ParsecSuccessfulStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Status
    )

    return $script:ParsecStatusSuccessSet -contains $Status
}

function New-ParsecRunIdentifier {
    [CmdletBinding()]
    param()

    return [guid]::NewGuid().Guid
}

function Resolve-ParsecRecipePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $NameOrPath
    )

    if (Test-Path -LiteralPath $NameOrPath) {
        return (Resolve-Path -LiteralPath $NameOrPath).Path
    }

    $repoRoot = Get-ParsecRepositoryRoot
    $candidate = Join-Path -Path $repoRoot -ChildPath ("recipes/{0}.toml" -f $NameOrPath)
    if (Test-Path -LiteralPath $candidate) {
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    throw "Recipe '$NameOrPath' could not be found."
}

function Get-ParsecProfileDocumentPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath ("profiles/{0}.json" -f $Name)
}

function Resolve-ParsecProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateCandidate = Get-ParsecProfileDocumentPath -Name $Name -StateRoot $StateRoot
    if (Test-Path -LiteralPath $stateCandidate) {
        return $stateCandidate
    }

    $repoCandidate = Join-Path -Path (Get-ParsecRepositoryRoot) -ChildPath ("profiles/{0}.json" -f $Name)
    if (Test-Path -LiteralPath $repoCandidate) {
        return (Resolve-Path -LiteralPath $repoCandidate).Path
    }

    throw "Profile '$Name' could not be found."
}
