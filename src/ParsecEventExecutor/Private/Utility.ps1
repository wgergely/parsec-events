function Get-ParsecModuleRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return $PSScriptRoot | Split-Path -Parent
}

function Get-ParsecRepositoryRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return (Get-ParsecModuleRoot | Split-Path -Parent | Split-Path -Parent)
}

function Get-ParsecDefaultStateRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    return Join-Path -Path $localAppData -ChildPath 'ParsecEventExecutor'
}

function Initialize-ParsecStateRoot {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    foreach ($relative in @('.', 'snapshots', 'runs', 'logs', 'events', 'ingredient-invocations', 'ingredient-tokens')) {
        $path = if ($relative -eq '.') { $StateRoot } else { Join-Path -Path $StateRoot -ChildPath $relative }
        if (-not (Test-Path -LiteralPath $path)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
        }
    }

    return $StateRoot
}

function ConvertTo-ParsecPlainObject {
    [CmdletBinding()]
    [OutputType([object])]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    [OutputType([System.Object[]])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    $baseObject = if ($InputObject -is [psobject] -and $null -ne $InputObject.PSObject) {
        $InputObject.PSObject.BaseObject
    }
    else {
        $InputObject
    }

    if (
        $baseObject -is [string] -or
        $baseObject -is [char] -or
        $baseObject -is [bool] -or
        $baseObject -is [byte] -or
        $baseObject -is [sbyte] -or
        $baseObject -is [int16] -or
        $baseObject -is [uint16] -or
        $baseObject -is [int32] -or
        $baseObject -is [uint32] -or
        $baseObject -is [int64] -or
        $baseObject -is [uint64] -or
        $baseObject -is [single] -or
        $baseObject -is [double] -or
        $baseObject -is [decimal] -or
        $baseObject -is [datetime] -or
        $baseObject -is [datetimeoffset] -or
        $baseObject -is [timespan] -or
        $baseObject -is [guid] -or
        $baseObject -is [uri]
    ) {
        return $baseObject
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

        return , @($values)
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

function Get-ParsecModuleVariableValue {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Name
    )

    $rootModule = Get-Module -Name 'ParsecEventExecutor'
    $module = if ($null -ne $rootModule) { $rootModule } else { $ExecutionContext.SessionState.Module }
    if ($null -ne $module) {
        $moduleValue = & $module {
            param($VariableName)
            $variable = Get-Variable -Name $VariableName -Scope Script -ErrorAction SilentlyContinue
            if ($null -eq $variable) {
                return $null
            }

            return $variable.Value
        } $Name
        if ($null -ne $moduleValue) {
            return $moduleValue
        }

        $globalVariable = Get-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
        if ($null -ne $globalVariable) {
            return $globalVariable.Value
        }

        return $null
    }

    $variable = Get-Variable -Name $Name -Scope Script -ErrorAction SilentlyContinue
    if ($null -eq $variable) {
        $globalVariable = Get-Variable -Name $Name -Scope Global -ErrorAction SilentlyContinue
        if ($null -eq $globalVariable) {
            return $null
        }

        return $globalVariable.Value
    }

    return $variable.Value
}

function Set-ParsecModuleVariableValue {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        $Value
    )

    if (-not $PSCmdlet.ShouldProcess("Module variable '$Name'", 'Set value')) {
        return $Value
    }

    $rootModule = Get-Module -Name 'ParsecEventExecutor'
    $module = if ($null -ne $rootModule) { $rootModule } else { $ExecutionContext.SessionState.Module }
    if ($null -ne $module) {
        & $module {
            param($VariableName, $VariableValue)
            Set-Variable -Name $VariableName -Scope Script -Value $VariableValue -Force
        } $Name $Value | Out-Null
        Set-Variable -Name $Name -Scope Global -Value $Value -Force
        return $Value
    }

    Set-Variable -Name $Name -Scope Script -Value $Value -Force
    Set-Variable -Name $Name -Scope Global -Value $Value -Force
    return $Value
}

function Read-ParsecJsonFile {
    [CmdletBinding()]
    [OutputType([object])]
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
    [OutputType([string])]
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
    $fileName = Split-Path -Path $Path -Leaf
    $tempPath = Join-Path -Path $directory -ChildPath ('.{0}.{1}.tmp' -f $fileName, [guid]::NewGuid().Guid)
    $backupPath = Join-Path -Path $directory -ChildPath ('.{0}.bak' -f $fileName)
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($tempPath, $json, $utf8NoBom)

    if (Test-Path -LiteralPath $Path) {
        [System.IO.File]::Replace($tempPath, $Path, $backupPath, $true)
        if (Test-Path -LiteralPath $backupPath) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        [System.IO.File]::Move($tempPath, $Path)
    }

    return $Path
}

function New-ParsecStateEnvelope {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $DocumentType,

        [Parameter(Mandatory)]
        $Payload
    )

    return [ordered]@{
        schema_version = 1
        document_type = $DocumentType
        written_at = [DateTimeOffset]::UtcNow.ToString('o')
        payload = ConvertTo-ParsecPlainObject -InputObject $Payload
    }
}

function Test-ParsecStateEnvelope {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        $Document
    )

    return $Document -is [System.Collections.IDictionary] -and $Document.Contains('document_type') -and $Document.Contains('payload')
}

function Read-ParsecStateDocument {
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter()]
        [string] $ExpectedDocumentType
    )

    $document = Read-ParsecJsonFile -Path $Path
    if ($null -eq $document) {
        return $null
    }

    $plain = ConvertTo-ParsecPlainObject -InputObject $document
    if (-not (Test-ParsecStateEnvelope -Document $plain)) {
        return $plain
    }

    if ($ExpectedDocumentType -and $plain.document_type -ne $ExpectedDocumentType) {
        throw "State document '$Path' has type '$($plain.document_type)' but expected '$ExpectedDocumentType'."
    }

    return [ordered]@{
        envelope = $plain
        payload = ConvertTo-ParsecPlainObject -InputObject $plain.payload
    }
}

function Write-ParsecStateDocument {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $DocumentType,

        [Parameter(Mandatory)]
        $Payload
    )

    $envelope = New-ParsecStateEnvelope -DocumentType $DocumentType -Payload $Payload
    Write-ParsecJsonFile -Path $Path -InputObject $envelope | Out-Null
    return $Path
}

function Write-ParsecEventRecord {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $EventType,

        [Parameter(Mandatory)]
        [hashtable] $Payload,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    if (-not (Get-Variable -Name ParsecEventSequence -Scope Script -ErrorAction SilentlyContinue)) {
        $script:ParsecEventSequence = 0
    }

    $script:ParsecEventSequence++
    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyyMMddTHHmmssfffffffZ')
    $path = Join-Path -Path $stateRoot -ChildPath ("events/{0}-{1:D8}-{2}.json" -f $timestamp, [int] $script:ParsecEventSequence, [guid]::NewGuid().Guid)
    Write-ParsecStateDocument -Path $path -DocumentType $EventType -Payload $Payload | Out-Null
    return $path
}

function New-ParsecResult {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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
        PSTypeName = 'ParsecEventExecutor.Result'
        Status = $Status
        Message = $Message
        Requested = ConvertTo-ParsecPlainObject -InputObject $Requested
        Observed = ConvertTo-ParsecPlainObject -InputObject $Observed
        Outputs = ConvertTo-ParsecPlainObject -InputObject $Outputs
        Warnings = @($Warnings)
        Errors = @($Errors)
        CanCompensate = $CanCompensate
        Timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    }
}

function Test-ParsecSuccessfulStatus {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '')]
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $Status
    )

    $successSet = $script:ParsecStatusSuccessSet
    if ($null -eq $successSet -or @($successSet).Count -eq 0) {
        $successSet = @('Succeeded', 'SucceededWithDrift', 'Compensated')
    }

    return @($successSet) -contains $Status
}

function New-ParsecRunIdentifier {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([string])]
    param()

    return [guid]::NewGuid().Guid
}

function Resolve-ParsecRecipePath {
    [CmdletBinding()]
    [OutputType([string])]
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

function Get-ParsecSnapshotDocumentPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath ("snapshots/{0}.json" -f $Name)
}

function Resolve-ParsecSnapshotPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateCandidate = Get-ParsecSnapshotDocumentPath -Name $Name -StateRoot $StateRoot
    if (Test-Path -LiteralPath $stateCandidate) {
        return $stateCandidate
    }

    throw "Snapshot '$Name' could not be found."
}

function Get-ParsecProfileDocumentPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Get-ParsecSnapshotDocumentPath -Name $Name -StateRoot $StateRoot
}

function Resolve-ParsecProfilePath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    return Resolve-ParsecSnapshotPath -Name $Name -StateRoot $StateRoot
}
