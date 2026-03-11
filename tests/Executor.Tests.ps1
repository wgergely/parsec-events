$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Invoke-ParsecRecipe' {
    It 'executes a successful command recipe and writes runtime state' {
        $stateRoot = Join-Path $TestDrive 'state-success'
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\command-success.toml'

        $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

        $result.terminal_status | Should -Be 'Succeeded'
        $result.step_results[0].status | Should -Be 'Succeeded'
        (Test-Path (Join-Path $stateRoot 'executor-state.json')) | Should -BeTrue
    }

    It 'blocks dependent steps after a failure' {
        $stateRoot = Join-Path $TestDrive 'state-failure'
        $recipePath = Join-Path $PSScriptRoot 'fixtures\recipes\failure-blocks.toml'

        $result = Invoke-ParsecRecipe -NameOrPath $recipePath -StateRoot $stateRoot -Confirm:$false

        $result.terminal_status | Should -Be 'Failed'
        $result.step_results[0].status | Should -Be 'Failed'
        $result.step_results[1].status | Should -Be 'Blocked'
    }
}
