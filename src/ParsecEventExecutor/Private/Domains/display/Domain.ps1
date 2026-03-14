function Get-ParsecDisplayDomainObservedState {
    [CmdletBinding()]
    param()

    return Invoke-ParsecDisplayAdapter -Method 'GetObservedState'
}

function Get-ParsecDisplayDomainCatalogDocumentPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $stateRoot = Initialize-ParsecStateRoot -StateRoot $StateRoot
    return Join-Path -Path $stateRoot -ChildPath 'display-catalog.json'
}

function Get-ParsecDisplayDomainCatalogDocument {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $path = Get-ParsecDisplayDomainCatalogDocumentPath -StateRoot $StateRoot
    $document = Read-ParsecStateDocument -Path $path -ExpectedDocumentType 'display-catalog'
    if ($null -eq $document) {
        return [ordered]@{
            entries = @()
            updated_at = [DateTimeOffset]::UtcNow.ToString('o')
        }
    }

    if ($document -is [System.Collections.IDictionary] -and $document.Contains('payload')) {
        return ConvertTo-ParsecPlainObject -InputObject $document.payload
    }

    return ConvertTo-ParsecPlainObject -InputObject $document
}

function Save-ParsecDisplayDomainCatalogDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $CatalogDocument,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $CatalogDocument.updated_at = [DateTimeOffset]::UtcNow.ToString('o')
    $path = Get-ParsecDisplayDomainCatalogDocumentPath -StateRoot $StateRoot
    Write-ParsecStateDocument -Path $path -DocumentType 'display-catalog' -Payload $CatalogDocument | Out-Null
    return $path
}

function Get-ParsecDisplayDomainIdentityRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    if ($Monitor.Contains('identity') -and $Monitor.identity -is [System.Collections.IDictionary]) {
        return ConvertTo-ParsecPlainObject -InputObject $Monitor.identity
    }

    if ($Monitor.Contains('monitor_device_path') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.monitor_device_path)) {
        return [ordered]@{
            scheme = 'monitor_device_path'
            monitor_device_path = [string] $Monitor.monitor_device_path
            source_name = if ($Monitor.Contains('source_name')) { [string] $Monitor.source_name } else { $null }
        }
    }

    return [ordered]@{
        scheme = 'device_name'
        device_name = if ($Monitor.Contains('device_name')) { [string] $Monitor.device_name } else { $null }
    }
}

function Get-ParsecDisplayDomainIdentityKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    $identity = Get-ParsecDisplayDomainIdentityRecord -Monitor $Monitor
    switch ([string] $identity.scheme) {
        'adapter_id+target_id' {
            return "adapter_id+target_id:{0}:{1}" -f [string] $identity.adapter_id, [string] $identity.target_id
        }
        'monitor_device_path' {
            return "monitor_device_path:{0}" -f [string] $identity.monitor_device_path
        }
        default {
            return "device_name:{0}" -f [string] $identity.device_name
        }
    }
}

function Test-ParsecDisplayDomainCatalogValueEqual {
    [CmdletBinding()]
    param(
        [Parameter()]
        $Left,

        [Parameter()]
        $Right
    )

    if ($null -eq $Left -and $null -eq $Right) {
        return $true
    }

    if ($null -eq $Left -or $null -eq $Right) {
        return $false
    }

    $leftJson = ConvertTo-ParsecPlainObject -InputObject $Left | ConvertTo-Json -Depth 100 -Compress
    $rightJson = ConvertTo-ParsecPlainObject -InputObject $Right | ConvertTo-Json -Depth 100 -Compress
    return $leftJson -ceq $rightJson
}

function Find-ParsecDisplayDomainCatalogEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable] $Entries,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    $identity = Get-ParsecDisplayDomainIdentityRecord -Monitor $Monitor
    $identityKey = Get-ParsecDisplayDomainIdentityKey -Monitor $Monitor
    $monitorDeviceName = if ($Monitor.Contains('device_name')) { [string] $Monitor.device_name } else { $null }
    $monitorDevicePath = if ($identity.Contains('monitor_device_path')) { [string] $identity.monitor_device_path } else { $null }
    $monitorAdapterId = if ($identity.Contains('adapter_id')) { [string] $identity.adapter_id } else { $null }
    $monitorTargetId = if ($identity.Contains('target_id')) { [string] $identity.target_id } else { $null }

    $exactMatch = $Entries | Where-Object { $_.identity_key -eq $identityKey } | Select-Object -First 1
    if ($null -ne $exactMatch) {
        return $exactMatch
    }

    foreach ($entry in @($Entries)) {
        $entryIdentity = if ($entry.Contains('identity') -and $entry.identity -is [System.Collections.IDictionary]) {
            ConvertTo-ParsecPlainObject -InputObject $entry.identity
        }
        else {
            @{}
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorDevicePath) -and
            $entryIdentity.Contains('monitor_device_path') -and
            [string] $entryIdentity.monitor_device_path -eq $monitorDevicePath
        ) {
            return $entry
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorAdapterId) -and
            -not [string]::IsNullOrWhiteSpace($monitorTargetId) -and
            $entryIdentity.Contains('adapter_id') -and
            $entryIdentity.Contains('target_id') -and
            [string] $entryIdentity.adapter_id -eq $monitorAdapterId -and
            [string] $entryIdentity.target_id -eq $monitorTargetId
        ) {
            return $entry
        }

        if (
            -not [string]::IsNullOrWhiteSpace($monitorDeviceName) -and (
                ($entryIdentity.Contains('device_name') -and [string] $entryIdentity.device_name -eq $monitorDeviceName) -or
                ($entry.Contains('device_name') -and [string] $entry.device_name -eq $monitorDeviceName)
            )
        ) {
            return $entry
        }
    }

    return $null
}

function Sync-ParsecDisplayDomainCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $catalog = Get-ParsecDisplayDomainCatalogDocument -StateRoot $StateRoot
    $entries = @()
    foreach ($entry in @($catalog.entries)) {
        $entries += , (ConvertTo-ParsecPlainObject -InputObject $entry)
    }

    $changed = $false
    $highestScreenId = 0
    $timestamp = [DateTimeOffset]::UtcNow.ToString('o')
    foreach ($entry in @($entries)) {
        if ($entry.screen_id -gt $highestScreenId) {
            $highestScreenId = [int] $entry.screen_id
        }
    }

    foreach ($monitor in @($ObservedState.monitors)) {
        $identity = Get-ParsecDisplayDomainIdentityRecord -Monitor $monitor
        $identityKey = Get-ParsecDisplayDomainIdentityKey -Monitor $monitor
        $entry = Find-ParsecDisplayDomainCatalogEntry -Entries $entries -Monitor $monitor
        if ($null -eq $entry) {
            $highestScreenId++
            $entry = [ordered]@{
                screen_id = [int] $highestScreenId
                identity_key = $identityKey
                identity = $identity
                first_seen_at = $timestamp
                last_seen_at = $timestamp
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
            }
            $entries += , $entry
            $changed = $true
        }
        else {
            $candidateValues = [ordered]@{
                identity_key = $identityKey
                identity = $identity
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
            }

            $entryChanged = $false
            foreach ($key in @($candidateValues.Keys)) {
                $currentValue = if ($entry.Contains($key)) { $entry[$key] } else { $null }
                if (-not (Test-ParsecDisplayDomainCatalogValueEqual -Left $currentValue -Right $candidateValues[$key])) {
                    $entry[$key] = $candidateValues[$key]
                    $entryChanged = $true
                }
            }

            if ($entryChanged) {
                $entry.last_seen_at = $timestamp
                $changed = $true
            }
        }
    }

    $result = [ordered]@{
        entries = @($entries)
        updated_at = if ($changed) { $timestamp } elseif ($catalog.Contains('updated_at')) { [string] $catalog.updated_at } else { $timestamp }
    }

    if ($changed) {
        Save-ParsecDisplayDomainCatalogDocument -CatalogDocument $result -StateRoot $StateRoot | Out-Null
    }

    return $result
}

function Resolve-ParsecDisplayDomainMonitorByScreenId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter(Mandatory)]
        [int] $ScreenId,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $catalog = Sync-ParsecDisplayDomainCatalog -ObservedState $ObservedState -StateRoot $StateRoot
    $entry = $catalog.entries | Where-Object { [int] $_.screen_id -eq $ScreenId } | Select-Object -First 1
    if ($null -eq $entry) {
        return $null
    }

    foreach ($monitor in @($ObservedState.monitors)) {
        if ((Get-ParsecDisplayDomainIdentityKey -Monitor $monitor) -eq $entry.identity_key) {
            return $monitor
        }
    }

    return $null
}

function Get-ParsecDisplayDomainMonitorLabel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Monitor
    )

    if ($Monitor.Contains('friendly_name') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.friendly_name)) {
        return [string] $Monitor.friendly_name
    }

    if ($Monitor.Contains('monitor_device_path') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.monitor_device_path)) {
        return [string] $Monitor.monitor_device_path
    }

    if ($Monitor.Contains('source_name') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.source_name)) {
        return [string] $Monitor.source_name
    }

    if ($Monitor.Contains('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $Monitor.device_name)) {
        return [string] $Monitor.device_name
    }

    return '<unknown-monitor>'
}

function Resolve-ParsecDisplayDomainObservedMonitor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TargetMonitor
    )

    $identity = Get-ParsecDisplayDomainIdentityRecord -Monitor $TargetMonitor
    $identityKey = Get-ParsecDisplayDomainIdentityKey -Monitor $TargetMonitor
    $observedMonitors = @($ObservedState.monitors)
    $observedPaths = if ($ObservedState.Contains('topology') -and $ObservedState.topology -is [System.Collections.IDictionary] -and $ObservedState.topology.Contains('paths')) {
        @($ObservedState.topology.paths)
    }
    else {
        @()
    }

    foreach ($monitor in $observedMonitors) {
        if ((Get-ParsecDisplayDomainIdentityKey -Monitor $monitor) -eq $identityKey) {
            return $monitor
        }
    }

    $monitorDevicePath = if ($identity.Contains('monitor_device_path')) { [string] $identity.monitor_device_path } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($monitorDevicePath)) {
        $match = $observedMonitors | Where-Object {
            $_.Contains('monitor_device_path') -and
            [string] $_.monitor_device_path -eq $monitorDevicePath
        } | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    $adapterId = if ($identity.Contains('adapter_id')) { [string] $identity.adapter_id } else { $null }
    $targetId = if ($identity.Contains('target_id')) { [string] $identity.target_id } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($adapterId) -and -not [string]::IsNullOrWhiteSpace($targetId)) {
        $match = $observedMonitors | Where-Object {
            [string] $_.adapter_id -eq $adapterId -and [string] $_.target_id -eq $targetId
        } | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }

        $matchingPaths = @(
            $observedPaths | Where-Object {
                [string] $_.adapter_id -eq $adapterId -and [string] $_.target_id -eq $targetId
            }
        )
        if ($matchingPaths.Count -gt 0) {
            $path = @($matchingPaths | Where-Object { $_.is_active } | Select-Object -First 1)[0]
            if ($null -eq $path) {
                $path = @($matchingPaths | Where-Object { $_.target_available } | Select-Object -First 1)[0]
            }
            if ($null -eq $path) {
                $path = @($matchingPaths | Select-Object -First 1)[0]
            }

            if ($null -ne $path) {
                $pathSourceName = if ($path.PSObject.Properties.Name -contains 'source_name') { [string] $path.source_name } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($pathSourceName)) {
                    $match = $observedMonitors | Where-Object {
                        [string] $_.source_name -eq $pathSourceName -or [string] $_.device_name -eq $pathSourceName
                    } | Select-Object -First 1
                    if ($null -ne $match) {
                        return $match
                    }
                }

                return [ordered]@{
                    device_name = $pathSourceName
                    source_name = $pathSourceName
                    friendly_name = if ($path.PSObject.Properties.Name -contains 'friendly_name') { [string] $path.friendly_name } else { $null }
                    monitor_device_path = if ($path.PSObject.Properties.Name -contains 'monitor_device_path') { [string] $path.monitor_device_path } else { $null }
                    adapter_id = if ($path.PSObject.Properties.Name -contains 'adapter_id') { [string] $path.adapter_id } else { $null }
                    source_id = if ($path.PSObject.Properties.Name -contains 'source_id') { $path.source_id } else { $null }
                    target_id = if ($path.PSObject.Properties.Name -contains 'target_id') { $path.target_id } else { $null }
                    enabled = if ($path.PSObject.Properties.Name -contains 'is_active') { [bool] $path.is_active } else { $false }
                    target_available = if ($path.PSObject.Properties.Name -contains 'target_available') { [bool] $path.target_available } else { $false }
                }
            }
        }
    }

    $sourceName = if ($identity.Contains('source_name')) { [string] $identity.source_name } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($sourceName)) {
        $match = $observedMonitors | Where-Object {
            [string] $_.source_name -eq $sourceName -or [string] $_.device_name -eq $sourceName
        } | Select-Object -First 1
        if ($null -ne $match) {
            return $match
        }
    }

    $deviceName = if ($TargetMonitor.Contains('device_name')) { [string] $TargetMonitor.device_name } else { $null }
    if (-not [string]::IsNullOrWhiteSpace($deviceName)) {
        return $observedMonitors | Where-Object { [string] $_.device_name -eq $deviceName } | Select-Object -First 1
    }

    return $null
}

function Resolve-ParsecDisplayDomainTargetDeviceName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $ObservedState,

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TargetMonitor
    )

    $resolvedMonitor = Resolve-ParsecDisplayDomainObservedMonitor -ObservedState $ObservedState -TargetMonitor $TargetMonitor
    if ($null -eq $resolvedMonitor) {
        return $null
    }

    if ($resolvedMonitor -is [System.Collections.IDictionary]) {
        if ($resolvedMonitor.Contains('device_name') -and -not [string]::IsNullOrWhiteSpace([string] $resolvedMonitor.device_name)) {
            return [string] $resolvedMonitor.device_name
        }

        if ($resolvedMonitor.Contains('source_name') -and -not [string]::IsNullOrWhiteSpace([string] $resolvedMonitor.source_name)) {
            return [string] $resolvedMonitor.source_name
        }
    }
    else {
        if ($resolvedMonitor.PSObject.Properties.Name -contains 'device_name' -and -not [string]::IsNullOrWhiteSpace([string] $resolvedMonitor.device_name)) {
            return [string] $resolvedMonitor.device_name
        }

        if ($resolvedMonitor.PSObject.Properties.Name -contains 'source_name' -and -not [string]::IsNullOrWhiteSpace([string] $resolvedMonitor.source_name)) {
            return [string] $resolvedMonitor.source_name
        }
    }

    return $null
}

function Invoke-ParsecDisplayDomainCaptureTarget {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    return [ordered]@{
        observed = $observed
        target_monitor = $targetMonitor
    }
}

function Invoke-ParsecDisplayDomainCaptureMonitorState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Domain,

        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $capture = Invoke-ParsecDisplayDomainCaptureTarget -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $capture.target_monitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $capture.observed -Errors @('MonitorNotFound')
    }

    return Get-ParsecDisplayCaptureResult -ObservedState $capture.observed -DeviceName ([string] $capture.target_monitor.device_name) -Domain $Domain
}

function Invoke-ParsecDisplayDomainApplyResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
    $supportedModeCount = @($supportedModes).Count
    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $matchingMode = @(
        $supportedModes | Where-Object {
            [int] $_.width -eq $requestedWidth -and
            [int] $_.height -eq $requestedHeight
        } | Select-Object -First 1
    )

    if ($matchingMode.Count -eq 0) {
        return New-ParsecResult -Status 'Failed' -Message "Resolution ${requestedWidth}x${requestedHeight} is not available on '$deviceName'." -Requested $Arguments -Outputs @{
            device_name = $deviceName
            width = $requestedWidth
            height = $requestedHeight
            supported_mode_count = $supportedModeCount
            supported_modes_sample = @($supportedModes | Select-Object -First 10)
        } -Errors @('UnsupportedResolution')
    }

    $result = Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
    $result.Requested = [ordered]@{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
    $result.Outputs = [ordered]@{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
        supported_mode_count = $supportedModeCount
        supported_modes_sample = @($supportedModes | Select-Object -First 10)
    }
    return $result
}

function Invoke-ParsecDisplayDomainWaitResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
    }

    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $observedWidth = if ($monitor.Contains('bounds')) { [int] $monitor.bounds.width } else { $null }
    $observedHeight = if ($monitor.Contains('bounds')) { [int] $monitor.bounds.height } else { $null }
    if ($observedWidth -ne $requestedWidth -or $observedHeight -ne $requestedHeight) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution is still settling." -Observed $monitor -Outputs @{
            device_name = $deviceName
            width = $requestedWidth
            height = $requestedHeight
            observed_width = $observedWidth
            observed_height = $observedHeight
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution is ready.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    }
}

function Invoke-ParsecDisplayDomainVerifyResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
    }

    if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
        $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor -Outputs @{
            device_name = $deviceName
            width = [int] $Arguments.width
            height = [int] $Arguments.height
            supported_mode_count = @($supportedModes).Count
            supported_modes_sample = @($supportedModes | Select-Object -First 10)
        } -Errors @('ResolutionDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor resolution matches.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        width = [int] $Arguments.width
        height = [int] $Arguments.height
    }
}

function Invoke-ParsecDisplayDomainResetResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetResolution' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        width = [int] $capturedMonitor.bounds.width
        height = [int] $capturedMonitor.bounds.height
    }
}

function Invoke-ParsecDisplayDomainApplyEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot),

        [Parameter()]
        [System.Collections.IDictionary] $RunState = @{}
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $supportedModes = @(Get-ParsecSupportedDisplayModes -DeviceName $deviceName)
    $requestedWidth = [int] $Arguments.width
    $requestedHeight = [int] $Arguments.height
    $requestedOrientation = if ($Arguments.Contains('orientation')) { [string] $Arguments.orientation } else { $null }
    $matchingMode = @($supportedModes | Where-Object {
            $_.width -eq $requestedWidth -and
            $_.height -eq $requestedHeight -and
            ($null -eq $requestedOrientation -or $_.orientation -eq $requestedOrientation)
        } | Select-Object -First 1)

    $resolutionResult = Invoke-ParsecDisplayDomainApplyResolution -Arguments @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
    } -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolutionResult.Status)) {
        return $resolutionResult
    }

    if ($requestedOrientation) {
        $orientationResult = Invoke-ParsecDisplayDomainApplyOrientation -Arguments @{
            device_name = $deviceName
            orientation = $requestedOrientation
        } -StateRoot $StateRoot
        if (-not (Test-ParsecSuccessfulStatus -Status $orientationResult.Status)) {
            return $orientationResult
        }
    }

    return New-ParsecResult -Status 'Succeeded' -Message "Ensured resolution ${requestedWidth}x${requestedHeight} on '$deviceName'." -Requested $Arguments -Outputs @{
        device_name = $deviceName
        width = $requestedWidth
        height = $requestedHeight
        orientation = $requestedOrientation
        mode_preexisting = ($matchingMode.Count -gt 0)
        supported_mode_count = @($supportedModes).Count
        supported_modes_sample = @($supportedModes | Select-Object -First 10)
    }
}

function Invoke-ParsecDisplayDomainVerifyEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $observed = Get-ParsecDisplayDomainObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed
    }

    if ($monitor.bounds.width -ne [int] $Arguments.width -or $monitor.bounds.height -ne [int] $Arguments.height) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' resolution mismatch." -Observed $monitor
    }

    if ($Arguments.Contains('orientation') -and $monitor.orientation -ne [string] $Arguments.orientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation mismatch." -Observed $monitor
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Ensured resolution matches.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetEnsureResolution {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('bounds')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured ensured-resolution state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayDomainResetResolution -Arguments @{ captured_state = $capturedMonitor } -ExecutionResult $ExecutionResult
}

function Invoke-ParsecDisplayDomainApplyOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $result = Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    $result.Requested = [ordered]@{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    $result.Outputs = [ordered]@{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
    return $result
}

function Invoke-ParsecDisplayDomainWaitOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found during readiness probe." -Observed $observed -Errors @('MonitorNotFound')
    }

    $expectedOrientation = [string] $Arguments.orientation
    if ([string] $monitor.orientation -ne $expectedOrientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation is still settling." -Observed $monitor -Outputs @{
            device_name = $deviceName
            orientation = $expectedOrientation
            observed_orientation = [string] $monitor.orientation
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation is ready.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        orientation = $expectedOrientation
    }
}

function Invoke-ParsecDisplayDomainVerifyOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $deviceName = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $deviceName
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' not found." -Observed $observed -Errors @('MonitorNotFound')
    }

    if ([string] $monitor.orientation -ne [string] $Arguments.orientation) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$deviceName' orientation mismatch." -Observed $monitor -Outputs @{
            device_name = $deviceName
            orientation = [string] $Arguments.orientation
        } -Errors @('OrientationDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor orientation matches.' -Observed $monitor -Outputs @{
        device_name = $deviceName
        orientation = [string] $Arguments.orientation
    }
}

function Invoke-ParsecDisplayDomainResetOrientation {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('orientation') -or $capturedMonitor.orientation -eq 'Unknown') {
        return New-ParsecResult -Status 'Failed' -Message 'Captured orientation state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        orientation = [string] $capturedMonitor.orientation
    }
}

function Invoke-ParsecDisplayDomainCapturePrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $primary = @($observed.monitors) | Where-Object { $_.is_primary } | Select-Object -First 1
    $outputs = [ordered]@{ captured_state = [ordered]@{ primary_monitor = $primary } }
    if ($Arguments.Contains('device_name')) {
        $outputs.captured_state.requested_monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured primary monitor state.' -Observed $outputs.captured_state -Outputs $outputs
}

function Invoke-ParsecDisplayDomainApplyPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found."
    }
    if (-not [bool] $monitor.is_primary) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' is not primary." -Observed $monitor
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor is primary.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetPrimary {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult -Preference 'primary'
    if ($null -eq $capturedMonitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured primary-monitor state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
    }
}

function Invoke-ParsecDisplayDomainCaptureEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    return Get-ParsecDisplayCaptureResult -ObservedState $observed -DeviceName $Arguments.device_name -Domain 'display enabled-state'
}

function Invoke-ParsecDisplayDomainApplyEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
    if ($null -eq $monitor) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found."
    }
    if ([bool] $monitor.enabled -ne [bool] $Arguments.enabled) {
        return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' enabled state mismatch." -Observed $monitor
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Monitor enabled state matches.' -Observed $monitor
}

function Invoke-ParsecDisplayDomainResetEnabled {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedMonitor = Get-ParsecDisplayResetMonitorState -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedMonitor -or -not $capturedMonitor.Contains('enabled')) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured enabled-state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments @{
        device_name = [string] $capturedMonitor.device_name
        enabled = [bool] $capturedMonitor.enabled
        bounds = if ($capturedMonitor.Contains('bounds')) { $capturedMonitor.bounds } else { $null }
    }
}

function Invoke-ParsecDisplayDomainCaptureActiveDisplays {
    [CmdletBinding()]
    param()

    $observed = Get-ParsecDisplayDomainObservedState
    $capturedState = Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $observed
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured active display topology.' -Observed $observed -Outputs @{
        captured_state = $capturedState
    }
}

function Invoke-ParsecDisplayDomainApplyActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $resolution = Resolve-ParsecActiveDisplayTargetState -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if (-not (Test-ParsecSuccessfulStatus -Status $resolution.Status)) {
        return $resolution
    }

    $targetState = ConvertTo-ParsecPlainObject -InputObject $resolution.Outputs.target_state
    $result = Invoke-ParsecDisplayDomainTopologyReset -TopologyState $targetState -SnapshotName 'set-activedisplays'
    $result.Requested = [ordered]@{
        screen_ids = @($resolution.Outputs.requested_screen_ids)
    }
    $result.Outputs = [ordered]@{
        target_state = $targetState
        requested_screen_ids = @($resolution.Outputs.requested_screen_ids)
        requested_device_names = @($resolution.Outputs.requested_device_names)
        primary_device_name = [string] $resolution.Outputs.primary_device_name
        topology_restore = if ($result.Outputs.Contains('actions')) {
            [ordered]@{
                snapshot_name = [string] $result.Outputs.snapshot_name
                actions = @($result.Outputs.actions)
            }
        } else { $null }
    }
    if (Test-ParsecSuccessfulStatus -Status $result.Status) {
        $result.Message = 'Applied active display topology.'
    }

    return $result
}

function Invoke-ParsecDisplayDomainWaitActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
    if ($targetState -isnot [System.Collections.IDictionary]) {
        return $targetState
    }

    $observed = Get-ParsecDisplayDomainObservedState
    $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
    if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
        return New-ParsecResult -Status 'Failed' -Message 'Display topology is still settling.' -Observed $observed -Outputs @{
            mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
            target_state = $targetState
        } -Errors @('ReadinessPending')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Display topology is ready.' -Observed $observed -Outputs @{
        target_state = $targetState
    }
}

function Invoke-ParsecDisplayDomainVerifyActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult,

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $targetState = Resolve-ParsecActiveDisplayTargetStateForOperation -ExecutionResult $ExecutionResult -Arguments $Arguments -StateRoot $StateRoot
    if ($targetState -isnot [System.Collections.IDictionary]) {
        return $targetState
    }

    $observed = Get-ParsecDisplayDomainObservedState
    $comparison = Compare-ParsecActiveDisplaySelectionState -TargetState $targetState -ObservedState $observed
    if (-not (Test-ParsecSuccessfulStatus -Status $comparison.Status)) {
        return New-ParsecResult -Status 'Failed' -Message 'Observed display topology does not match the requested active-display set.' -Observed $observed -Outputs @{
            mismatches = if ($comparison.Outputs.Contains('mismatches')) { @($comparison.Outputs.mismatches) } else { @() }
            target_state = $targetState
        } -Errors @('ActiveDisplayDrift')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed display topology matches the requested active-display set.' -Observed $observed -Outputs @{
        target_state = $targetState
    }
}

function Invoke-ParsecDisplayDomainResetActiveDisplays {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -eq $capturedState) {
        return New-ParsecResult -Status 'Failed' -Message 'Captured topology state does not include a resettable value.' -Errors @('MissingCapturedState')
    }

    return Invoke-ParsecDisplayDomainTopologyReset -TopologyState $capturedState -SnapshotName 'set-activedisplays-reset'
}

function Invoke-ParsecDisplayDomainCaptureScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    if ($Arguments.Contains('device_name')) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
        if ($null -eq $monitor) {
            return New-ParsecResult -Status 'Failed' -Message "Monitor '$($Arguments.device_name)' not found." -Observed $observed -Errors @('MonitorNotFound')
        }
        $scalePercent = if ($monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $monitor.display.scale_percent } else { $null }
        $effectiveDpiX = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_x')) { $monitor.display.effective_dpi_x } else { $null }
        $effectiveDpiY = if ($monitor.Contains('display') -and $monitor.display.Contains('effective_dpi_y')) { $monitor.display.effective_dpi_y } else { $null }
        $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $observed.font_scaling.text_scale_percent } else { $null }
        return New-ParsecResult -Status 'Succeeded' -Message "Captured display scaling state for '$($Arguments.device_name)'." -Observed @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } -Outputs @{ captured_state = @{ device_name = $monitor.device_name; scale_percent = $scalePercent; effective_dpi_x = $effectiveDpiX; effective_dpi_y = $effectiveDpiY; text_scale_percent = $textScalePercent } }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Captured display scaling state.' -Observed @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling } -Outputs @{ captured_state = @{ scaling = $observed.scaling; font_scaling = $observed.font_scaling; ui_scale_percent = $observed.scaling.ui_scale_percent; text_scale_percent = $observed.font_scaling.text_scale_percent } }
}

function Invoke-ParsecDisplayDomainApplyScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments $Arguments
}

function Invoke-ParsecDisplayDomainVerifyScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{}
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $currentValue = $null
    $expectedValue = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('ui_scale_percent')) { [int] $Arguments.ui_scale_percent } elseif ($Arguments.Contains('scale_percent')) { [int] $Arguments.scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { $null }
    if ($Arguments.Contains('device_name')) {
        $monitor = Get-ParsecObservedMonitor -ObservedState $observed -DeviceName $Arguments.device_name
        if ($null -ne $monitor -and $monitor.Contains('display') -and $monitor.display.Contains('scale_percent')) { $currentValue = $monitor.display.scale_percent }
    } elseif ($Arguments.Contains('text_scale_percent') -and $observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { $currentValue = $observed.font_scaling.text_scale_percent } elseif (($Arguments.Contains('ui_scale_percent') -or $Arguments.Contains('scale_percent') -or $Arguments.Contains('value')) -and $observed.scaling.Contains('ui_scale_percent')) { $currentValue = $observed.scaling.ui_scale_percent } elseif ($observed.scaling.Contains('text_scale_percent')) { $currentValue = $observed.scaling.text_scale_percent }
    if ($null -eq $currentValue -or $null -eq $expectedValue -or $currentValue -ne $expectedValue) {
        return New-ParsecResult -Status 'Failed' -Message 'Display scaling mismatch.' -Observed $observed.scaling
    }
    return New-ParsecResult -Status 'Succeeded' -Message 'Display scaling matches.' -Observed $observed.scaling
}

function Invoke-ParsecDisplayDomainResetScaling {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    $capturedState = if ($Arguments.Contains('captured_state') -and $Arguments.captured_state -is [System.Collections.IDictionary]) { ConvertTo-ParsecPlainObject -InputObject $Arguments.captured_state } elseif ($null -ne $ExecutionResult -and $ExecutionResult.Outputs.captured_state) { ConvertTo-ParsecPlainObject -InputObject $ExecutionResult.Outputs.captured_state } else { $null }
    if ($null -ne $capturedState -and $capturedState.Contains('text_scale_percent')) {
        return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ text_scale_percent = [int] $capturedState.text_scale_percent }
    }
    if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) {
        return Invoke-ParsecDisplayAdapter -Method 'SetScaling' -Arguments @{ ui_scale_percent = [int] $capturedState.ui_scale_percent }
    }
    return New-ParsecResult -Status 'Failed' -Message 'Captured scaling state does not include a resettable text scaling value.' -Errors @('CapabilityUnavailable')
}

function Resolve-ParsecDisplayDomainUiScaleExpectedValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        $ExecutionResult
    )

    if ($null -ne $ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('ui_scale_percent')) { return [int] $ExecutionResult.Outputs.ui_scale_percent }
    if ($Arguments.Contains('ui_scale_percent')) { return [int] $Arguments.ui_scale_percent }
    if ($Arguments.Contains('scale_percent')) { return [int] $Arguments.scale_percent }
    if ($Arguments.Contains('value')) { return [int] $Arguments.value }
    $capturedState = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult
    if ($null -ne $capturedState -and $capturedState.Contains('ui_scale_percent')) { return [int] $capturedState.ui_scale_percent }
    throw 'UI scale operation requires ui_scale_percent, scale_percent, or value.'
}

function Invoke-ParsecDisplayDomainCaptureTextScale {
    [CmdletBinding()]
    param()

    $observed = Get-ParsecDisplayDomainObservedState
    $textScalePercent = if ($observed.Contains('font_scaling') -and $observed.font_scaling.Contains('text_scale_percent')) { [int] $observed.font_scaling.text_scale_percent } else { $null }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured text scaling state.' -Observed @{ text_scale_percent = $textScalePercent } -Outputs @{ captured_state = @{ text_scale_percent = $textScalePercent } }
}

function Invoke-ParsecDisplayDomainCaptureUiScale {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $Arguments = @{},

        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $targetMonitor = Resolve-ParsecDisplayTargetMonitor -ObservedState $observed -Arguments $Arguments -StateRoot $StateRoot
    if ($null -eq $targetMonitor) {
        return New-ParsecResult -Status 'Failed' -Message 'Target monitor could not be resolved.' -Observed $observed -Errors @('MonitorNotFound')
    }
    $uiScalePercent = if ($targetMonitor.display -is [System.Collections.IDictionary] -and $targetMonitor.display.Contains('scale_percent')) { [int] $targetMonitor.display.scale_percent } else { $null }
    return New-ParsecResult -Status 'Succeeded' -Message 'Captured UI scaling state.' -Observed @{ device_name = [string] $targetMonitor.device_name; ui_scale_percent = $uiScalePercent } -Outputs @{ captured_state = @{ device_name = [string] $targetMonitor.device_name; ui_scale_percent = $uiScalePercent } }
}

function Get-ParsecDisplayDomainInventory {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $StateRoot = (Get-ParsecDefaultStateRoot)
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $catalog = Sync-ParsecDisplayDomainCatalog -ObservedState $observed -StateRoot $StateRoot
    return @(
        foreach ($monitor in @($observed.monitors)) {
            $identityKey = Get-ParsecDisplayDomainIdentityKey -Monitor $monitor
            $catalogEntry = $catalog.entries | Where-Object { $_.identity_key -eq $identityKey } | Select-Object -First 1
            [pscustomobject]@{
                screen_id = if ($null -ne $catalogEntry) { [int] $catalogEntry.screen_id } else { $null }
                device_name = if ($monitor.Contains('device_name')) { [string] $monitor.device_name } else { $null }
                source_name = if ($monitor.Contains('source_name')) { [string] $monitor.source_name } else { $null }
                friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
                is_primary = if ($monitor.Contains('is_primary')) { [bool] $monitor.is_primary } else { $false }
                enabled = if ($monitor.Contains('enabled')) { [bool] $monitor.enabled } else { $false }
                orientation = if ($monitor.Contains('orientation')) { [string] $monitor.orientation } else { $null }
                bounds = if ($monitor.Contains('bounds')) { ConvertTo-ParsecPlainObject -InputObject $monitor.bounds } else { $null }
                working_area = if ($monitor.Contains('working_area')) { ConvertTo-ParsecPlainObject -InputObject $monitor.working_area } else { $null }
                display = if ($monitor.Contains('display')) { ConvertTo-ParsecPlainObject -InputObject $monitor.display } else { $null }
                identity = Get-ParsecDisplayDomainIdentityRecord -Monitor $monitor
                identity_key = $identityKey
                monitor_backend = if ($observed.Contains('display_backend')) { [string] $observed.display_backend } else { $null }
            }
        }
    )
}

function Get-ParsecDisplayDomainTopologyCaptureState {
    [CmdletBinding()]
    param(
        [Parameter()]
        [System.Collections.IDictionary] $ObservedState = $(Get-ParsecDisplayDomainObservedState)
    )

    $monitors = foreach ($monitor in @($ObservedState.monitors)) {
        [ordered]@{
            device_name = [string] $monitor.device_name
            source_name = if ($monitor.Contains('source_name')) { [string] $monitor.source_name } else { $null }
            friendly_name = if ($monitor.Contains('friendly_name')) { [string] $monitor.friendly_name } else { $null }
            monitor_device_path = if ($monitor.Contains('monitor_device_path')) { [string] $monitor.monitor_device_path } else { $null }
            adapter_device_path = if ($monitor.Contains('adapter_device_path')) { [string] $monitor.adapter_device_path } else { $null }
            adapter_id = if ($monitor.Contains('adapter_id')) { [string] $monitor.adapter_id } else { $null }
            source_id = if ($monitor.Contains('source_id')) { [int] $monitor.source_id } else { $null }
            target_id = if ($monitor.Contains('target_id')) { [int] $monitor.target_id } else { $null }
            is_primary = [bool] $monitor.is_primary
            enabled = [bool] $monitor.enabled
            target_available = if ($monitor.Contains('target_available')) { [bool] $monitor.target_available } else { $null }
            bounds = if ($monitor.Contains('bounds')) { ConvertTo-ParsecPlainObject -InputObject $monitor.bounds } else { $null }
            orientation = if ($monitor.Contains('orientation')) { [string] $monitor.orientation } else { $null }
            identity = if ($monitor.Contains('identity')) { ConvertTo-ParsecPlainObject -InputObject $monitor.identity } else { $null }
            topology = if ($monitor.Contains('topology')) { ConvertTo-ParsecPlainObject -InputObject $monitor.topology } else { $null }
            display = if ($monitor.Contains('display')) {
                [ordered]@{
                    width = $monitor.display.width
                    height = $monitor.display.height
                    bits_per_pel = $monitor.display.bits_per_pel
                    refresh_rate_hz = $monitor.display.refresh_rate_hz
                }
            }
            else { $null }
        }
    }

    return [ordered]@{
        captured_at = if ($ObservedState.Contains('captured_at')) { [string] $ObservedState.captured_at } else { [DateTimeOffset]::UtcNow.ToString('o') }
        computer_name = if ($ObservedState.Contains('computer_name')) { [string] $ObservedState.computer_name } else { $env:COMPUTERNAME }
        display_backend = if ($ObservedState.Contains('display_backend')) { [string] $ObservedState.display_backend } else { $null }
        monitor_identity = if ($ObservedState.Contains('monitor_identity')) { [string] $ObservedState.monitor_identity } else { $null }
        monitors = @($monitors)
        topology = if ($ObservedState.Contains('topology')) { ConvertTo-ParsecPlainObject -InputObject $ObservedState.topology } else { [ordered]@{ query_mode = 'Unknown'; path_count = 0; paths = @() } }
    }
}

function Invoke-ParsecDisplayDomainTopologyReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $TopologyState,

        [Parameter()]
        [string] $SnapshotName = ''
    )

    $observed = Get-ParsecDisplayDomainObservedState
    $actions = New-Object System.Collections.Generic.List[object]
    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) { [bool] $monitor.target_available } else { $true }
        if (-not $isEnabled -and -not $targetAvailable) { continue }
        $deviceName = Resolve-ParsecDisplayDomainTargetDeviceName -ObservedState $observed -TargetMonitor $monitor
        if ([string]::IsNullOrWhiteSpace($deviceName)) {
            $actions.Add((New-ParsecResult -Status 'Failed' -Message ("Could not resolve an active display source for '{0}'." -f (Get-ParsecDisplayDomainMonitorLabel -Monitor $monitor)) -Requested @{ target_monitor = ConvertTo-ParsecPlainObject -InputObject $monitor } -Errors @('MonitorNotFound', 'TopologyTargetUnresolved')))
            continue
        }

        $enableArguments = @{
            device_name = $deviceName
            enabled = $isEnabled
        }
        if ($monitor.Contains('bounds') -and $monitor.bounds -is [System.Collections.IDictionary]) {
            $enableArguments.bounds = ConvertTo-ParsecPlainObject -InputObject $monitor.bounds
        }

        $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetEnabled' -Arguments $enableArguments))
    }

    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) { [bool] $monitor.target_available } else { $true }
        if ($isEnabled -and $targetAvailable -and $monitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $monitor.orientation) -and $monitor.orientation -ne 'Unknown') {
            $deviceName = Resolve-ParsecDisplayDomainTargetDeviceName -ObservedState $observed -TargetMonitor $monitor
            if ([string]::IsNullOrWhiteSpace($deviceName)) {
                $actions.Add((New-ParsecResult -Status 'Failed' -Message ("Could not resolve an active display source for '{0}'." -f (Get-ParsecDisplayDomainMonitorLabel -Monitor $monitor)) -Requested @{ target_monitor = ConvertTo-ParsecPlainObject -InputObject $monitor } -Errors @('MonitorNotFound', 'TopologyTargetUnresolved')))
                continue
            }
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetOrientation' -Arguments @{
                        device_name = $deviceName
                        orientation = [string] $monitor.orientation
                    }))
        }
    }

    foreach ($monitor in @($TopologyState.monitors)) {
        $isEnabled = [bool] $monitor.enabled
        $targetAvailable = if ($monitor.Contains('target_available') -and $null -ne $monitor.target_available) { [bool] $monitor.target_available } else { $true }
        if ($isEnabled -and $targetAvailable -and $monitor.Contains('is_primary') -and [bool] $monitor.is_primary) {
            $deviceName = Resolve-ParsecDisplayDomainTargetDeviceName -ObservedState $observed -TargetMonitor $monitor
            if ([string]::IsNullOrWhiteSpace($deviceName)) {
                $actions.Add((New-ParsecResult -Status 'Failed' -Message ("Could not resolve an active display source for '{0}'." -f (Get-ParsecDisplayDomainMonitorLabel -Monitor $monitor)) -Requested @{ target_monitor = ConvertTo-ParsecPlainObject -InputObject $monitor } -Errors @('MonitorNotFound', 'TopologyTargetUnresolved')))
                continue
            }
            $actions.Add((Invoke-ParsecDisplayAdapter -Method 'SetPrimary' -Arguments @{
                        device_name = $deviceName
                    }))
        }
    }

    $actionResults = @($actions | Where-Object { $null -ne $_ } | ForEach-Object { $_ })
    if ($actionResults.Count -ne $actions.Count) {
        return New-ParsecResult -Status 'Failed' -Message 'Display topology restore produced an incomplete action result set.' -Outputs @{ snapshot_name = $SnapshotName; actions = $actionResults } -Errors @('ResetFailed')
    }

    $failures = @($actionResults | Where-Object { -not (Test-ParsecSuccessfulStatus -Status $_.Status) })
    if ($failures.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message $failures[0].Message -Outputs @{ snapshot_name = $SnapshotName; actions = $actionResults } -Errors @('ResetFailed')
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Display topology restored.' -Outputs @{ snapshot_name = $SnapshotName; actions = $actionResults }
}

function Compare-ParsecDisplayDomainTopologyState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TargetState,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($targetMonitor in @($TargetState.monitors)) {
        $label = Get-ParsecDisplayDomainMonitorLabel -Monitor $targetMonitor
        $observedMonitor = Resolve-ParsecDisplayDomainObservedMonitor -ObservedState $ObservedState -TargetMonitor $targetMonitor
        if ($null -eq $observedMonitor) { $mismatches.Add("Monitor '$label' not found."); continue }
        if ([bool] $targetMonitor.enabled -ne [bool] $observedMonitor.enabled) { $mismatches.Add("Monitor '$label' enabled state mismatch.") }
        if ([bool] $targetMonitor.is_primary -ne [bool] $observedMonitor.is_primary) { $mismatches.Add("Monitor '$label' primary state mismatch.") }
        if ($targetMonitor.Contains('bounds') -and $targetMonitor.bounds -is [System.Collections.IDictionary]) {
            if ($targetMonitor.bounds.x -ne $observedMonitor.bounds.x -or $targetMonitor.bounds.y -ne $observedMonitor.bounds.y) { $mismatches.Add("Monitor '$label' position mismatch.") }
            if ($targetMonitor.bounds.width -ne $observedMonitor.bounds.width -or $targetMonitor.bounds.height -ne $observedMonitor.bounds.height) { $mismatches.Add("Monitor '$label' resolution mismatch.") }
        }
        if ($targetMonitor.Contains('orientation') -and -not [string]::IsNullOrWhiteSpace([string] $targetMonitor.orientation) -and $targetMonitor.orientation -ne 'Unknown' -and $targetMonitor.orientation -ne $observedMonitor.orientation) { $mismatches.Add("Monitor '$label' orientation mismatch.") }
    }

    if ($mismatches.Count -gt 0) {
        return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{ mismatches = @($mismatches) }
    }

    return New-ParsecResult -Status 'Succeeded' -Message 'Observed topology matches the target topology.' -Observed $ObservedState -Outputs @{ target_state = $TargetState }
}

function Compare-ParsecDisplayDomainState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $TargetState,

        [Parameter(Mandatory)]
        [hashtable] $ObservedState
    )

    $mismatches = New-Object System.Collections.Generic.List[string]
    foreach ($targetMonitor in @($TargetState.monitors)) {
        $label = Get-ParsecDisplayDomainMonitorLabel -Monitor $targetMonitor
        $observedMonitor = Resolve-ParsecDisplayDomainObservedMonitor -ObservedState $ObservedState -TargetMonitor $targetMonitor
        if ($null -eq $observedMonitor) { $mismatches.Add("Monitor '$label' not found."); continue }
        if ($targetMonitor.Contains('enabled') -and [bool] $targetMonitor.enabled -ne [bool] $observedMonitor.enabled) { $mismatches.Add("Monitor '$label' enabled state mismatch.") }
        if ($targetMonitor.Contains('is_primary') -and [bool] $targetMonitor.is_primary -ne [bool] $observedMonitor.is_primary) { $mismatches.Add("Monitor '$label' primary state mismatch.") }
        if ($targetMonitor.Contains('bounds')) { if ($targetMonitor.bounds.width -ne $observedMonitor.bounds.width -or $targetMonitor.bounds.height -ne $observedMonitor.bounds.height) { $mismatches.Add("Monitor '$label' resolution mismatch.") } }
        if ($targetMonitor.Contains('orientation') -and $targetMonitor.orientation -ne 'Unknown' -and $targetMonitor.orientation -ne $observedMonitor.orientation) { $mismatches.Add("Monitor '$label' orientation mismatch.") }
    }
    if ($TargetState.Contains('scaling') -and $TargetState.scaling.Contains('value')) { if (-not $ObservedState.Contains('scaling') -or $ObservedState.scaling.value -ne $TargetState.scaling.value) { $mismatches.Add('Display scaling mismatch.') } }
    if ($TargetState.Contains('font_scaling') -and $TargetState.font_scaling.Contains('text_scale_percent')) { if (-not $ObservedState.Contains('font_scaling') -or $ObservedState.font_scaling.text_scale_percent -ne $TargetState.font_scaling.text_scale_percent) { $mismatches.Add('Font scaling mismatch.') } }
    if ($TargetState.Contains('theme')) {
        if (-not $ObservedState.Contains('theme')) { $mismatches.Add('Theme state is missing.') }
        else {
            if ($TargetState.theme.Contains('app_mode') -and $ObservedState.theme.app_mode -ne $TargetState.theme.app_mode) { $mismatches.Add('Application theme mismatch.') }
            if ($TargetState.theme.Contains('system_mode') -and $ObservedState.theme.system_mode -ne $TargetState.theme.system_mode) { $mismatches.Add('System theme mismatch.') }
        }
    }
    if ($TargetState.Contains('wallpaper')) {
        if (-not $ObservedState.Contains('wallpaper')) {
            $mismatches.Add('Wallpaper state is missing.')
        }
        else {
            if ($TargetState.wallpaper.Contains('path') -and $ObservedState.wallpaper.path -ne $TargetState.wallpaper.path) { $mismatches.Add('Wallpaper path mismatch.') }
            if ($TargetState.wallpaper.Contains('wallpaper_style') -and $ObservedState.wallpaper.wallpaper_style -ne $TargetState.wallpaper.wallpaper_style) { $mismatches.Add('Wallpaper style mismatch.') }
            if ($TargetState.wallpaper.Contains('tile_wallpaper') -and $ObservedState.wallpaper.tile_wallpaper -ne $TargetState.wallpaper.tile_wallpaper) { $mismatches.Add('Wallpaper tiling mismatch.') }
            if ($TargetState.wallpaper.Contains('background_color') -and $ObservedState.wallpaper.background_color -ne $TargetState.wallpaper.background_color) { $mismatches.Add('Wallpaper background color mismatch.') }
        }
    }
    if ($mismatches.Count -gt 0) { return New-ParsecResult -Status 'Failed' -Message ($mismatches -join ' ') -Observed $ObservedState -Outputs @{ mismatches = @($mismatches) } }
    return New-ParsecResult -Status 'Succeeded' -Message 'Observed state matches the target state.' -Observed $ObservedState -Outputs @{ target_state = $TargetState }
}

function Invoke-ParsecDisplayDomainApplyTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $v = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $r = Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{ text_scale_percent = $v }; $r.Requested = [ordered]@{ text_scale_percent = $v }; $r.Outputs = [ordered]@{ text_scale_percent = $v }; return $r }
function Invoke-ParsecDisplayDomainWaitTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $e = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $o = Get-ParsecDisplayDomainObservedState; $c = if ($o.Contains('font_scaling') -and $o.font_scaling.Contains('text_scale_percent')) { [int] $o.font_scaling.text_scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'Text scale is still settling.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e; observed_text_scale_percent = $c } -Errors @('ReadinessPending') }; return New-ParsecResult -Status 'Succeeded' -Message 'Text scale is ready.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e } }
function Invoke-ParsecDisplayDomainVerifyTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $e = if ($Arguments.Contains('text_scale_percent')) { [int] $Arguments.text_scale_percent } elseif ($Arguments.Contains('value')) { [int] $Arguments.value } else { [int] (Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult).text_scale_percent }; $o = Get-ParsecDisplayDomainObservedState; $c = if ($o.Contains('font_scaling') -and $o.font_scaling.Contains('text_scale_percent')) { [int] $o.font_scaling.text_scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'Text scale mismatch.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e; observed_text_scale_percent = $c } -Errors @('TextScaleDrift') }; return New-ParsecResult -Status 'Succeeded' -Message 'Text scale matches.' -Observed $o.font_scaling -Outputs @{ text_scale_percent = $e } }
function Invoke-ParsecDisplayDomainResetTextScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $s = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult; if ($null -eq $s -or -not $s.Contains('text_scale_percent')) { return New-ParsecResult -Status 'Failed' -Message 'Captured text scaling state does not include a resettable value.' -Errors @('MissingCapturedState') }; return Invoke-ParsecPersonalizationAdapter -Method 'SetTextScale' -Arguments @{ text_scale_percent = [int] $s.text_scale_percent } }

function Invoke-ParsecDisplayDomainApplyUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $u = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $r = Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{ device_name = $d; ui_scale_percent = $u }; $a = if ($r.Outputs -and $r.Outputs.Contains('ui_scale_percent')) { [int] $r.Outputs.ui_scale_percent } else { $u }; $r.Requested = [ordered]@{ device_name = $d; ui_scale_percent = $u }; $r.Outputs = [ordered]@{ device_name = $d; ui_scale_percent = $a; requires_signout = if ($r.Outputs -and $r.Outputs.Contains('requires_signout')) { [bool] $r.Outputs.requires_signout } else { $false } }; return $r }
function Invoke-ParsecDisplayDomainWaitUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $e = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $o = Get-ParsecDisplayDomainObservedState; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $m = Get-ParsecObservedMonitor -ObservedState $o -DeviceName $d; if ($null -eq $m) { return New-ParsecResult -Status 'Failed' -Message \"Monitor '$d' not found during readiness probe.\" -Observed $o -Errors @('MonitorNotFound') }; $c = if ($m.display -is [System.Collections.IDictionary] -and $m.display.Contains('scale_percent')) { [int] $m.display.scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'UI scale is still settling.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; observed_ui_scale_percent = $c; requires_signout = $false } -Errors @('ReadinessPending') }; return New-ParsecResult -Status 'Succeeded' -Message 'UI scale is ready.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false } } }
function Invoke-ParsecDisplayDomainVerifyUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot)) $e = Resolve-ParsecDisplayDomainUiScaleExpectedValue -Arguments $Arguments -ExecutionResult $ExecutionResult; $o = Get-ParsecDisplayDomainObservedState; $d = Resolve-ParsecDisplayTargetDeviceName -Arguments $Arguments -StateRoot $StateRoot; $m = Get-ParsecObservedMonitor -ObservedState $o -DeviceName $d; if ($null -eq $m) { return New-ParsecResult -Status 'Failed' -Message \"Monitor '$d' not found.\" -Observed $o -Errors @('MonitorNotFound') }; $c = if ($m.display -is [System.Collections.IDictionary] -and $m.display.Contains('scale_percent')) { [int] $m.display.scale_percent } else { $null }; if ($c -ne $e) { return New-ParsecResult -Status 'Failed' -Message 'UI scale mismatch.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; observed_ui_scale_percent = $c; requires_signout = $false } -Errors @('UiScaleDrift') }; return New-ParsecResult -Status 'Succeeded' -Message 'UI scale matches.' -Observed $m -Outputs @{ device_name = $d; ui_scale_percent = $e; requires_signout = if ($ExecutionResult -and $ExecutionResult.Outputs -and $ExecutionResult.Outputs.Contains('requires_signout')) { [bool] $ExecutionResult.Outputs.requires_signout } else { $false } } }
function Invoke-ParsecDisplayDomainResetUiScale { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()] $ExecutionResult) $s = Get-ParsecCapturedStateFromResult -Arguments $Arguments -ExecutionResult $ExecutionResult; if ($null -eq $s -or -not $s.Contains('ui_scale_percent')) { return New-ParsecResult -Status 'Failed' -Message 'Captured UI scaling state does not include a resettable value.' -Errors @('MissingCapturedState') }; return Invoke-ParsecPersonalizationAdapter -Method 'SetUiScale' -Arguments @{ device_name = if ($s.Contains('device_name')) { [string] $s.device_name } else { $null }; ui_scale_percent = [int] $s.ui_scale_percent } }

function Invoke-ParsecDisplayDomainCaptureSnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) return Invoke-ParsecSnapshotDomainCapture -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState }
function Invoke-ParsecDisplayDomainResetSnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $RunState.active_snapshot = $t.snapshot_name; return Invoke-ParsecSnapshotDomainReset -SnapshotDocument $t.snapshot }
function Invoke-ParsecDisplayDomainVerifySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $o = Get-ParsecDisplayDomainObservedState; $v = Compare-ParsecDisplayDomainState -TargetState $t.snapshot.display -ObservedState $o; $v.Outputs.snapshot_name = $t.snapshot_name; return $v }

function Invoke-ParsecDisplayDomainCaptureTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $n = Resolve-ParsecSnapshotDomainName -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState -UseDefaultCaptureName; $o = Get-ParsecDisplayDomainObservedState; $t = Get-ParsecDisplayDomainTopologyCaptureState -ObservedState $o; $s = [ordered]@{ schema_version = 1; name = $n; source = 'capture'; captured_at = [DateTimeOffset]::UtcNow.ToString('o'); display = $t }; $p = Save-ParsecSnapshotDocument -Name $n -SnapshotDocument $s -StateRoot $StateRoot; $RunState.active_snapshot = $n; return New-ParsecResult -Status 'Succeeded' -Message \"Captured topology snapshot '$n'.\" -Observed $t -Outputs @{ snapshot_name = $n; snapshot = $s; captured_state = $t; path = $p } }
function Invoke-ParsecDisplayDomainResetTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $RunState.active_snapshot = $t.snapshot_name; return Invoke-ParsecDisplayDomainTopologyReset -TopologyState $t.snapshot.display -SnapshotName $t.snapshot_name }
function Invoke-ParsecDisplayDomainVerifyTopologySnapshot { [CmdletBinding()] param([Parameter()][System.Collections.IDictionary] $Arguments = @{}, [Parameter()][string] $StateRoot = (Get-ParsecDefaultStateRoot), [Parameter()][System.Collections.IDictionary] $RunState = @{}) $t = Get-ParsecSnapshotDomainTarget -Arguments $Arguments -StateRoot $StateRoot -RunState $RunState; $o = Get-ParsecDisplayDomainObservedState; $v = Compare-ParsecDisplayDomainTopologyState -TargetState $t.snapshot.display -ObservedState $o; $v.Outputs.snapshot_name = $t.snapshot_name; return $v }
