function New-ParsecSessionTracker {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int] $DefaultGracePeriodMs = 10000
    )

    return [ordered]@{
        active_sessions = [ordered]@{}
        default_grace_period_ms = $DefaultGracePeriodMs
        pending_disconnects = [ordered]@{}
    }
}

function Register-ParsecSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tracker,

        [Parameter(Mandatory)]
        [string] $Username
    )

    if ($Tracker.pending_disconnects.Contains($Username)) {
        $Tracker.pending_disconnects.Remove($Username)
        $Tracker.active_sessions[$Username] = [ordered]@{
            connected_at = [DateTimeOffset]::UtcNow.ToString('o')
        }

        return [ordered]@{
            action = 'reconnect_within_grace'
            username = $Username
            message = "User '$Username' reconnected within grace period. Disconnect cancelled."
        }
    }

    if ($Tracker.active_sessions.Contains($Username)) {
        $Tracker.active_sessions[$Username] = [ordered]@{
            connected_at = [DateTimeOffset]::UtcNow.ToString('o')
        }

        return [ordered]@{
            action = 'duplicate_connect'
            username = $Username
            message = "User '$Username' sent duplicate connect. Treated as reconnection."
        }
    }

    $isFirstSession = $Tracker.active_sessions.Count -eq 0

    $Tracker.active_sessions[$Username] = [ordered]@{
        connected_at = [DateTimeOffset]::UtcNow.ToString('o')
    }

    if ($isFirstSession) {
        return [ordered]@{
            action = 'dispatch_connect'
            username = $Username
            message = "First connection from '$Username'. Dispatch connect recipe."
        }
    }

    return [ordered]@{
        action = 'additional_connect'
        username = $Username
        message = "Additional connection from '$Username' while session active. First connection wins."
    }
}

function Unregister-ParsecSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tracker,

        [Parameter(Mandatory)]
        [string] $Username,

        [Parameter()]
        [int] $GracePeriodMs = -1
    )

    if (-not $Tracker.active_sessions.Contains($Username)) {
        return [ordered]@{
            action = 'orphan_disconnect'
            username = $Username
            message = "Disconnect from unknown session '$Username'. Ignored."
        }
    }

    $Tracker.active_sessions.Remove($Username)

    $gracePeriod = if ($GracePeriodMs -ge 0) { $GracePeriodMs } else { $Tracker.default_grace_period_ms }

    if ($Tracker.active_sessions.Count -gt 0) {
        return [ordered]@{
            action = 'other_sessions_active'
            username = $Username
            remaining_count = $Tracker.active_sessions.Count
            message = "User '$Username' disconnected but $($Tracker.active_sessions.Count) session(s) remain active."
        }
    }

    $Tracker.pending_disconnects[$Username] = [ordered]@{
        disconnected_at = [DateTimeOffset]::UtcNow.ToString('o')
        grace_period_ms = $gracePeriod
        grace_expires_at = [DateTimeOffset]::UtcNow.AddMilliseconds($gracePeriod).ToString('o')
    }

    return [ordered]@{
        action = 'grace_period_started'
        username = $Username
        grace_period_ms = $gracePeriod
        message = "Last session disconnected. Grace period ($gracePeriod ms) started for '$Username'."
    }
}

function Get-ParsecExpiredDisconnects {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tracker
    )

    $expired = @()
    $now = [DateTimeOffset]::UtcNow

    foreach ($username in @($Tracker.pending_disconnects.Keys)) {
        $pending = $Tracker.pending_disconnects[$username]
        $expiresAt = [DateTimeOffset]::ParseExact($pending.grace_expires_at, 'o', [System.Globalization.CultureInfo]::InvariantCulture)

        if ($now -ge $expiresAt) {
            $expired += [ordered]@{
                action = 'dispatch_disconnect'
                username = $username
                message = "Grace period expired for '$username'. Dispatch disconnect recipe."
            }

            $Tracker.pending_disconnects.Remove($username)
        }
    }

    return $expired
}

function Get-ParsecSessionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Tracker
    )

    return [ordered]@{
        active_session_count = $Tracker.active_sessions.Count
        active_usernames = @($Tracker.active_sessions.Keys)
        pending_disconnect_count = $Tracker.pending_disconnects.Count
        pending_usernames = @($Tracker.pending_disconnects.Keys)
        has_active_sessions = $Tracker.active_sessions.Count -gt 0
    }
}
