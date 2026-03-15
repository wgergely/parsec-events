$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'New-ParsecWatcherDispatcher' {
        It 'creates a dispatcher with correct initial state' {
            $dispatcher = New-ParsecWatcherDispatcher -StateRoot $TestDrive

            $dispatcher.state_root | Should -Be $TestDrive
            $dispatcher.is_busy | Should -BeFalse
            $dispatcher.queue.Count | Should -Be 0
            $dispatcher.last_result | Should -BeNullOrEmpty
            $dispatcher.last_error | Should -BeNullOrEmpty
        }
    }

    Describe 'Invoke-ParsecWatcherDispatch' {
        It 'dispatches a recipe and records result metadata' {
            $stateRoot = Join-Path $TestDrive "dispatch-$(New-Guid)"
            Initialize-ParsecStateRoot -StateRoot $stateRoot | Out-Null

            $dispatcher = New-ParsecWatcherDispatcher -StateRoot $stateRoot

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-dispatch-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $recipeContent = @'
name = "dispatch-test"

[[steps]]
id = "noop-step"
ingredient = "display.snapshot"
operation = "capture"
depends_on = []
verify = false
compensation_policy = "none"

[steps.arguments]
snapshot_name = "dispatch-test-snapshot"
'@
                $recipePath = Join-Path $tempDir 'dispatch-test.toml'
                Set-Content -LiteralPath $recipePath -Value $recipeContent -NoNewline

                $recipe = Get-ParsecRecipe -NameOrPath $recipePath

                $result = Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username 'test#1234' -EventType 'connect'

                $result.status | Should -Be 'Dispatched'
                $result.terminal_status | Should -Not -BeNullOrEmpty
                $dispatcher.is_busy | Should -BeFalse
                $dispatcher.last_result | Should -Not -BeNullOrEmpty
                $dispatcher.last_result.recipe_name | Should -Be 'dispatch-test'
                $dispatcher.last_result.username | Should -Be 'test#1234'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'queues a second dispatch while the first is running' {
            $dispatcher = New-ParsecWatcherDispatcher -StateRoot $TestDrive
            $dispatcher.is_busy = $true

            $recipe = [ordered]@{
                name = 'queued-recipe'
                path = 'test.toml'
            }

            $result = Invoke-ParsecWatcherDispatch -Dispatcher $dispatcher -Recipe $recipe -Username 'test#1234' -EventType 'connect'

            $result.status | Should -Be 'Queued'
            $dispatcher.queue.Count | Should -Be 1
        }
    }

    Describe 'Invoke-ParsecWatcherDrainQueue' {
        It 'drains queued recipes in order' {
            $stateRoot = Join-Path $TestDrive "drain-$(New-Guid)"
            Initialize-ParsecStateRoot -StateRoot $stateRoot | Out-Null

            $dispatcher = New-ParsecWatcherDispatcher -StateRoot $stateRoot

            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-drain-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $recipeContent = @'
name = "drain-test"

[[steps]]
id = "noop-step"
ingredient = "display.snapshot"
operation = "capture"
depends_on = []
verify = false
compensation_policy = "none"

[steps.arguments]
snapshot_name = "drain-test-snapshot"
'@
                $recipePath = Join-Path $tempDir 'drain-test.toml'
                Set-Content -LiteralPath $recipePath -Value $recipeContent -NoNewline

                $dispatcher.queue.Enqueue([ordered]@{
                        recipe_name = 'drain-test'
                        recipe_path = $recipePath
                        username = 'drain#1'
                        event_type = 'connect'
                        queued_at = [DateTimeOffset]::UtcNow.ToString('o')
                    })

                $results = @(Invoke-ParsecWatcherDrainQueue -Dispatcher $dispatcher)

                $results.Count | Should -BeGreaterOrEqual 1
                $dispatcher.queue.Count | Should -Be 0
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}
