$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Executor state entrypoints' {
    It 'returns verify-only state without mutating recipes' {
        $stateRoot = Join-Path $TestDrive 'verify-only'
        $result = Start-ParsecExecutor -EventName VerifyOnly -StateRoot $stateRoot -Confirm:$false

        $result.event_name | Should -Be 'VerifyOnly'
        $result.state.transition_phase | Should -Be 'Idle'
    }

    It 'routes SwitchToMobile to the placeholder recipe and preserves the approval gate' {
        $stateRoot = Join-Path $TestDrive 'switch-mobile'
        $result = Start-ParsecExecutor -EventName SwitchToMobile -StateRoot $stateRoot -Confirm:$false

        $result.recipe_name | Should -Be 'enter-mobile'
        $result.terminal_status | Should -Be 'Failed'
        $result.step_results[0].execution_result.Errors | Should -Contain 'ApprovalRequired'
    }
}
