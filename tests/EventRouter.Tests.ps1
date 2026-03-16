$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Invoke-ParsecEventRouter' {
        BeforeAll {
            $patterns = [ordered]@{
                connect = '\]\s+(.+#\d+)\s+connected\.\s*$'
                disconnect = '\]\s+(.+#\d+)\s+disconnected\.\s*$'
            }

            $script:router = New-ParsecEventRouter -Patterns $patterns
        }

        It 'detects a connect event and extracts the username' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[I 2026-03-09 22:03:47] wgergely#12571953 connected.'

            $result | Should -Not -BeNullOrEmpty
            $result.event_type | Should -Be 'connect'
            $result.username | Should -Be 'wgergely#12571953'
        }

        It 'detects a disconnect event and extracts the username' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[I 2026-03-09 22:11:36] wgergely#12571953 disconnected.'

            $result | Should -Not -BeNullOrEmpty
            $result.event_type | Should -Be 'disconnect'
            $result.username | Should -Be 'wgergely#12571953'
        }

        It 'returns null for a non-matching line' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[D 2026-03-09 22:03:50] encoder = nvidia'

            $result | Should -BeNullOrEmpty
        }

        It 'returns null for IPC connect lines (not user connections)' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[D 2026-03-09 17:46:56] IPC AS Client Connected.'

            $result | Should -BeNullOrEmpty
        }

        It 'returns null for FPS status lines' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[D 2026-03-09 22:04:00] [0] FPS:20.1/0, L:6.0/17.5, B:0.7/4.9, N:0/2/0'

            $result | Should -BeNullOrEmpty
        }

        It 'returns null for virtual tablet disconnect lines' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[I 2026-03-09 22:11:36] Virtual tablet removed due to client disconnect'

            $result | Should -BeNullOrEmpty
        }

        It 'handles usernames with various formats' {
            $result = Invoke-ParsecEventRouter -Router $router -Line '[I 2026-03-14 10:00:00] test-user_123#99 connected.'

            $result | Should -Not -BeNullOrEmpty
            $result.username | Should -Be 'test-user_123#99'
        }
    }
}
