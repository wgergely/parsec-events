function New-ParsecEventRouter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Patterns
    )

    $compiledPatterns = [ordered]@{}
    foreach ($key in @('connect', 'disconnect')) {
        if ($Patterns.Contains($key)) {
            $compiledPatterns[$key] = [regex]::new($Patterns[$key])
        }
    }

    return [ordered]@{
        patterns = $compiledPatterns
    }
}

function Invoke-ParsecEventRouter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Router,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    foreach ($eventType in @('connect', 'disconnect')) {
        if (-not $Router.patterns.Contains($eventType)) {
            continue
        }

        $match = $Router.patterns[$eventType].Match($Line)
        if ($match.Success -and $match.Groups.Count -ge 2) {
            return [ordered]@{
                event_type = $eventType
                username = $match.Groups[1].Value
                raw_line = $Line
                matched_at = [DateTimeOffset]::UtcNow.ToString('o')
            }
        }
    }

    return $null
}
