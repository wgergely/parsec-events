$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'New-ParsecSessionTracker' {
        It 'creates a tracker with empty sessions' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 5000

            $tracker.active_sessions.Count | Should -Be 0
            $tracker.pending_disconnects.Count | Should -Be 0
            $tracker.default_grace_period_ms | Should -Be 5000
        }
    }

    Describe 'Register-ParsecSession' {
        It 'dispatches connect recipe on first connection' {
            $tracker = New-ParsecSessionTracker

            $result = Register-ParsecSession -Tracker $tracker -Username 'phone#1234'

            $result.action | Should -Be 'dispatch_connect'
            $result.username | Should -Be 'phone#1234'
            $tracker.active_sessions.Count | Should -Be 1
        }

        It 'returns additional_connect for second user while first is active' {
            $tracker = New-ParsecSessionTracker
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $result = Register-ParsecSession -Tracker $tracker -Username 'laptop#5678'

            $result.action | Should -Be 'additional_connect'
            $tracker.active_sessions.Count | Should -Be 2
        }

        It 'returns duplicate_connect when same user connects twice' {
            $tracker = New-ParsecSessionTracker
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $result = Register-ParsecSession -Tracker $tracker -Username 'phone#1234'

            $result.action | Should -Be 'duplicate_connect'
            $tracker.active_sessions.Count | Should -Be 1
        }

        It 'cancels pending disconnect on reconnect within grace period' {
            $tracker = New-ParsecSessionTracker
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null
            Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $tracker.pending_disconnects.Count | Should -Be 1

            $result = Register-ParsecSession -Tracker $tracker -Username 'phone#1234'

            $result.action | Should -Be 'reconnect_within_grace'
            $tracker.pending_disconnects.Count | Should -Be 0
            $tracker.active_sessions.Count | Should -Be 1
        }
    }

    Describe 'Unregister-ParsecSession' {
        It 'starts grace period when last session disconnects' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 5000
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $result = Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234'

            $result.action | Should -Be 'grace_period_started'
            $result.grace_period_ms | Should -Be 5000
            $tracker.active_sessions.Count | Should -Be 0
            $tracker.pending_disconnects.Count | Should -Be 1
        }

        It 'does not start grace period when other sessions remain' {
            $tracker = New-ParsecSessionTracker
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null
            Register-ParsecSession -Tracker $tracker -Username 'laptop#5678' | Out-Null

            $result = Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234'

            $result.action | Should -Be 'other_sessions_active'
            $result.remaining_count | Should -Be 1
            $tracker.pending_disconnects.Count | Should -Be 0
        }

        It 'returns orphan_disconnect for unknown sessions' {
            $tracker = New-ParsecSessionTracker

            $result = Unregister-ParsecSession -Tracker $tracker -Username 'unknown#0000'

            $result.action | Should -Be 'orphan_disconnect'
        }

        It 'uses per-recipe grace period when provided' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 10000
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $result = Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234' -GracePeriodMs 2000

            $result.grace_period_ms | Should -Be 2000
        }
    }

    Describe 'Get-ParsecExpiredDisconnects' {
        It 'returns expired disconnects' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 0
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null
            Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234' -GracePeriodMs 0 | Out-Null

            Start-Sleep -Milliseconds 50

            $expired = @(Get-ParsecExpiredDisconnects -Tracker $tracker)

            $expired.Count | Should -Be 1
            $expired[0].action | Should -Be 'dispatch_disconnect'
            $expired[0].username | Should -Be 'phone#1234'
            $tracker.pending_disconnects.Count | Should -Be 0
        }

        It 'does not return non-expired disconnects' {
            $tracker = New-ParsecSessionTracker -DefaultGracePeriodMs 60000
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null
            Unregister-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $expired = @(Get-ParsecExpiredDisconnects -Tracker $tracker)

            $expired.Count | Should -Be 0
            $tracker.pending_disconnects.Count | Should -Be 1
        }
    }

    Describe 'Get-ParsecSessionState' {
        It 'returns session summary' {
            $tracker = New-ParsecSessionTracker
            Register-ParsecSession -Tracker $tracker -Username 'phone#1234' | Out-Null

            $state = Get-ParsecSessionState -Tracker $tracker

            $state.active_session_count | Should -Be 1
            $state.active_usernames | Should -Contain 'phone#1234'
            $state.has_active_sessions | Should -BeTrue
            $state.pending_disconnect_count | Should -Be 0
        }
    }
}
