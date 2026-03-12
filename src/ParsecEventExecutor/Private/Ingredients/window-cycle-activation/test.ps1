Context 'window.cycle-activation' {
    It 'captures the current foreground window and restores it after cycling' {
        $capture = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'capture' -Arguments @{} -RunState @{}
        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state.foreground_window.handle | Should -Be 101
        @($capture.Outputs.windows).handle | Should -Be @(101, 102)

        $apply = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'apply' -Arguments @{ dwell_ms = 0; max_cycles = 4 } -RunState @{}
        $apply.Status | Should -Be 'Succeeded'
        $apply.Observed.loop_returned | Should -BeTrue
        $script:IngredientWindowForegroundHandle | Should -Be 101
        $script:IngredientWindowActivationLog | Should -Be @(102, 101)
    }

    It 'filters helper windows out of the Alt-Tab candidate set' {
        $script:IngredientWindows += @(
            [ordered]@{
                handle = [int64] 104
                owner_handle = [int64] 0
                process_id = 1004
                process_name = 'ApplicationFrameHost'
                title = 'Hosted App'
                class_name = 'ApplicationFrameWindow'
                is_visible = $true
                is_minimized = $false
                is_cloaked = $false
                is_shell_window = $false
                extended_style = 0
                width = 1280
                height = 720
            },
            [ordered]@{
                handle = [int64] 105
                owner_handle = [int64] 0
                process_id = 1005
                process_name = 'TextInputHost'
                title = 'Windows Input Experience'
                class_name = 'Windows.UI.Core.CoreWindow'
                is_visible = $true
                is_minimized = $false
                is_cloaked = $false
                is_shell_window = $false
                extended_style = 0
                width = 600
                height = 500
            },
            [ordered]@{
                handle = [int64] 106
                owner_handle = [int64] 0
                process_id = 1006
                process_name = 'TinyUtility'
                title = 'Overlay'
                class_name = 'OverlayWindow'
                is_visible = $true
                is_minimized = $false
                is_cloaked = $false
                is_shell_window = $false
                extended_style = 0
                width = 32
                height = 32
            }
        )

        $capture = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'capture' -Arguments @{} -RunState @{}

        @($capture.Outputs.windows).handle | Should -Be @(101, 102)
    }

    It 'fails verification when the original foreground window is not restored' {
        $capture = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'capture' -Arguments @{} -RunState @{}
        $script:IngredientWindowForegroundHandle = 102

        $verify = Invoke-ParsecIngredientOperation -Name 'window.cycle-activation' -Operation 'verify' -Arguments @{} -ExecutionResult $capture -RunState @{}
        $verify.Status | Should -Be 'Failed'
        $verify.Errors | Should -Contain 'ForegroundWindowDrift'
    }
}
