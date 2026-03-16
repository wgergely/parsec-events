$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Read-ParsecLogTailLines' {
        It 'reads the last N lines from a log file' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-tail-test-$(New-Guid).txt"

            try {
                $lines = @(
                    '[D 2026-03-14 10:00:00] line 1',
                    '[D 2026-03-14 10:00:01] line 2',
                    '[I 2026-03-14 10:00:02] wgergely#12571953 connected.',
                    '[D 2026-03-14 10:00:03] line 4',
                    '[I 2026-03-14 10:00:04] wgergely#12571953 disconnected.'
                )
                Set-Content -LiteralPath $tempFile -Value ($lines -join "`n")

                $result = Read-ParsecLogTailLines -LogPath $tempFile -TailCount 3
                $result.Count | Should -Be 3
                $result[0] | Should -BeLike '*connected*'
                $result[2] | Should -BeLike '*disconnected*'
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'returns all lines when file has fewer than TailCount lines' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-tail-test-$(New-Guid).txt"

            try {
                Set-Content -LiteralPath $tempFile -Value "[D 2026-03-14 10:00:00] single line"

                $result = @(Read-ParsecLogTailLines -LogPath $tempFile -TailCount 100)
                $result.Count | Should -Be 1
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'returns empty array when file does not exist' {
            $result = @(Read-ParsecLogTailLines -LogPath 'C:\nonexistent\log.txt' -TailCount 10)
            $result.Count | Should -Be 0
        }
    }

    Describe 'New-ParsecLogTailer' {
        It 'creates a tailer object with correct properties' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-tailer-test-$(New-Guid).txt"
            New-Item -ItemType File -Path $tempFile -Force | Out-Null

            try {
                $tailer = New-ParsecLogTailer -LogPath $tempFile -PollIntervalMs 500

                $tailer.log_path | Should -Be $tempFile
                $tailer.poll_interval_ms | Should -Be 500
                $tailer.last_position | Should -Be 0
                $tailer.is_running | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'throws when log file does not exist' {
            { New-ParsecLogTailer -LogPath 'C:\nonexistent\log.txt' } | Should -Throw '*not found*'
        }
    }

    Describe 'Start/Stop-ParsecLogTailer lifecycle' {
        It 'starts and stops the tailer without errors' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-tailer-lifecycle-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
            $tempFile = Join-Path $tempDir 'log.txt'
            Set-Content -LiteralPath $tempFile -Value '[D 2026-03-14 10:00:00] init'

            try {
                $tailer = New-ParsecLogTailer -LogPath $tempFile

                Start-ParsecLogTailer -Tailer $tailer -SkipExisting
                $tailer.is_running | Should -BeTrue

                Stop-ParsecLogTailer -Tailer $tailer
                $tailer.is_running | Should -BeFalse
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
