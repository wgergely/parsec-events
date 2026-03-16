$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

InModuleScope ParsecEventExecutor {
    Describe 'Read-ParsecWatcherConfig' {
        It 'loads the default parsec-watcher.toml from the repository root' {
            $config = Read-ParsecWatcherConfig

            $config.watcher.parsec_log_path | Should -Be 'auto'
            $config.watcher.apply_delay_ms | Should -Be 3000
            $config.watcher.grace_period_ms | Should -Be 10000
            $config.watcher.poll_interval_ms | Should -Be 1000
            $config.patterns.connect | Should -Not -BeNullOrEmpty
            $config.patterns.disconnect | Should -Not -BeNullOrEmpty
            $config.path | Should -Not -BeNullOrEmpty
        }

        It 'loads a custom config file from a specified path' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-watcher-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $configContent = @'
[watcher]
parsec_log_path = "C:\custom\log.txt"
apply_delay_ms = 5000
grace_period_ms = 30000
poll_interval_ms = 2000

[patterns]
connect = '\]\s+(\w+)\s+connected\.'
disconnect = '\]\s+(\w+)\s+disconnected\.'
'@
                $configPath = Join-Path $tempDir 'custom-watcher.toml'
                Set-Content -LiteralPath $configPath -Value $configContent -NoNewline

                $config = Read-ParsecWatcherConfig -ConfigPath $configPath

                $config.watcher.parsec_log_path | Should -Be 'C:\custom\log.txt'
                $config.watcher.apply_delay_ms | Should -Be 5000
                $config.watcher.grace_period_ms | Should -Be 30000
                $config.watcher.poll_interval_ms | Should -Be 2000
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'applies defaults for missing watcher fields' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-watcher-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $configContent = @'
[watcher]
apply_delay_ms = 5000
'@
                $configPath = Join-Path $tempDir 'minimal-watcher.toml'
                Set-Content -LiteralPath $configPath -Value $configContent -NoNewline

                $config = Read-ParsecWatcherConfig -ConfigPath $configPath

                $config.watcher.parsec_log_path | Should -Be 'auto'
                $config.watcher.apply_delay_ms | Should -Be 5000
                $config.watcher.grace_period_ms | Should -Be 10000
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'throws on invalid regex pattern' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-watcher-test-$(New-Guid)"
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

            try {
                $configContent = @'
[patterns]
connect = '[\invalid'
'@
                $configPath = Join-Path $tempDir 'bad-regex.toml'
                Set-Content -LiteralPath $configPath -Value $configContent -NoNewline

                { Read-ParsecWatcherConfig -ConfigPath $configPath } | Should -Throw '*not a valid regex*'
            }
            finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'throws when config file does not exist' {
            { Read-ParsecWatcherConfig -ConfigPath 'C:\nonexistent\watcher.toml' } | Should -Throw '*not found*'
        }
    }

    Describe 'Resolve-ParsecLogPath' {
        It 'finds the per-machine Parsec log file on this system' {
            $perMachine = Join-Path -Path ([Environment]::GetFolderPath('CommonApplicationData')) -ChildPath 'Parsec\log.txt'

            if (Test-Path -LiteralPath $perMachine) {
                $result = Resolve-ParsecLogPath -ConfiguredPath 'auto'
                $result | Should -Be $perMachine
            }
            else {
                Set-ItResult -Skipped -Because 'Parsec is not installed on this machine'
            }
        }

        It 'returns the explicit path when configured' {
            $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-log-test-$(New-Guid).txt"
            New-Item -ItemType File -Path $tempFile -Force | Out-Null

            try {
                $result = Resolve-ParsecLogPath -ConfiguredPath $tempFile
                $result | Should -Be $tempFile
            }
            finally {
                Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
            }
        }

        It 'throws when explicit path does not exist' {
            { Resolve-ParsecLogPath -ConfiguredPath 'C:\nonexistent\log.txt' } | Should -Throw '*does not exist*'
        }
    }

    Describe 'Find-ParsecMatchingRecipe' {
        BeforeAll {
            $script:connectRecipe = [ordered]@{
                name = 'dev-connect'
                event_type = 'connect'
                username = $null
                grace_period_ms = $null
            }

            $script:disconnectRecipe = [ordered]@{
                name = 'dev-disconnect'
                event_type = 'disconnect'
                username = $null
                grace_period_ms = $null
            }

            $script:phoneOnlyRecipe = [ordered]@{
                name = 'dev-connect-phone'
                event_type = 'connect'
                username = 'phone#1234'
                grace_period_ms = 5000
            }

            $script:laptopRecipe = [ordered]@{
                name = 'enter-laptop'
                event_type = 'connect'
                username = 'laptop#5678'
                grace_period_ms = 30000
            }
        }

        Context 'with unfiltered recipes (no username)' {
            It 'matches the connect recipe for a connect event' {
                $result = Find-ParsecMatchingRecipe -Username 'anyone#9999' -EventType 'connect' -Recipes @($connectRecipe, $disconnectRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-connect'
            }

            It 'matches the disconnect recipe for a disconnect event' {
                $result = Find-ParsecMatchingRecipe -Username 'anyone#9999' -EventType 'disconnect' -Recipes @($connectRecipe, $disconnectRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-disconnect'
            }

            It 'returns null when no recipe matches the event type' {
                $result = Find-ParsecMatchingRecipe -Username 'anyone#9999' -EventType 'disconnect' -Recipes @($connectRecipe)

                $result | Should -BeNullOrEmpty
            }
        }

        Context 'with username-filtered recipes' {
            It 'matches the phone recipe for the phone user' {
                $result = Find-ParsecMatchingRecipe -Username 'phone#1234' -EventType 'connect' -Recipes @($phoneOnlyRecipe, $laptopRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-connect-phone'
            }

            It 'matches the laptop recipe for the laptop user' {
                $result = Find-ParsecMatchingRecipe -Username 'laptop#5678' -EventType 'connect' -Recipes @($phoneOnlyRecipe, $laptopRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'enter-laptop'
            }

            It 'returns null for an unrecognized user when all recipes have username filters' {
                $result = Find-ParsecMatchingRecipe -Username 'unknown#0000' -EventType 'connect' -Recipes @($phoneOnlyRecipe, $laptopRecipe)

                $result | Should -BeNullOrEmpty
            }
        }

        Context 'with mixed filtered and unfiltered recipes' {
            It 'prefers a username-specific recipe over an unfiltered one' {
                $result = Find-ParsecMatchingRecipe -Username 'phone#1234' -EventType 'connect' -Recipes @($connectRecipe, $phoneOnlyRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-connect-phone'
            }

            It 'falls back to unfiltered recipe for unknown users' {
                $result = Find-ParsecMatchingRecipe -Username 'unknown#0000' -EventType 'connect' -Recipes @($connectRecipe, $phoneOnlyRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-connect'
            }
        }

        Context 'disconnect event matching' {
            It 'matches disconnect recipe when event type is disconnect' {
                $result = Find-ParsecMatchingRecipe -Username 'anyone#9999' -EventType 'disconnect' -Recipes @($connectRecipe, $disconnectRecipe)

                $result | Should -Not -BeNullOrEmpty
                $result.name | Should -Be 'dev-disconnect'
            }

            It 'returns null when no recipe matches disconnect event type' {
                $result = Find-ParsecMatchingRecipe -Username 'anyone#9999' -EventType 'disconnect' -Recipes @($connectRecipe)

                $result | Should -BeNullOrEmpty
            }
        }
    }

    Describe 'Get-ParsecRecipeGracePeriod' {
        It 'returns recipe-specific grace period when set' {
            $recipe = [ordered]@{ grace_period_ms = 5000 }
            Get-ParsecRecipeGracePeriod -Recipe $recipe -DefaultGracePeriodMs 10000 | Should -Be 5000
        }

        It 'returns default when recipe has no grace_period_ms' {
            $recipe = [ordered]@{ name = 'test' }
            Get-ParsecRecipeGracePeriod -Recipe $recipe -DefaultGracePeriodMs 10000 | Should -Be 10000
        }

        It 'returns default when recipe grace_period_ms is null' {
            $recipe = [ordered]@{ grace_period_ms = $null }
            Get-ParsecRecipeGracePeriod -Recipe $recipe -DefaultGracePeriodMs 15000 | Should -Be 15000
        }
    }
}

Describe 'Recipe schema extension' {
    It 'parses username field from recipe TOML' {
        $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "parsec-recipe-test-$(New-Guid)"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        try {
            $recipeContent = @'
name = "test-username-recipe"
description = "Recipe with username filter"
event_type = "connect"
username = "phone#1234"
grace_period_ms = 5000

[[steps]]
id = "test-step"
ingredient = "display.snapshot"
operation = "capture"

[steps.arguments]
snapshot_name = "test"
'@
            $recipePath = Join-Path $tempDir 'username-recipe.toml'
            Set-Content -LiteralPath $recipePath -Value $recipeContent -NoNewline

            $recipe = Get-ParsecRecipe -NameOrPath $recipePath

            $recipe.username | Should -Be 'phone#1234'
            $recipe.grace_period_ms | Should -Be 5000
            $recipe.event_type | Should -Be 'connect'
        }
        finally {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns null for username and grace_period_ms when not specified in TOML' {
        $connectPath = Join-Path $PSScriptRoot 'fixtures\recipes\dev-connect.toml'
        $recipe = Get-ParsecRecipe -NameOrPath $connectPath

        $recipe.username | Should -BeNullOrEmpty
        $recipe.grace_period_ms | Should -BeNullOrEmpty
    }
}
