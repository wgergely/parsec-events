Context 'nvidia.add-custom-resolution' {
    It 'adds a custom resolution through the NVIDIA adapter' {
        $apply = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'apply' -Arguments @{
            width = 2000
            height = 1125
        } -RunState @{}

        $verify = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'verify' -Arguments @{
            width = 2000
            height = 1125
        } -RunState @{}

        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.display_id | Should -Be 101
        $apply.Outputs.already_present | Should -BeFalse
        $apply.Outputs.topology_restore.Status | Should -Be 'Succeeded'
        $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
        $script:IngredientObservedState.monitors[0].bounds.x | Should -Be 0
        $verify.Status | Should -Be 'Succeeded'
        $verify.Outputs.supported_mode_present | Should -BeTrue
    }

    It 'reports capability unavailable when the NVIDIA adapter is absent' {
        $script:IngredientNvidiaAvailable = $false

        $apply = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'apply' -Arguments @{
            width = 2000
            height = 3000
        } -RunState @{}

        $apply.Status | Should -Be 'Failed'
        $apply.Errors | Should -Contain 'CapabilityUnavailable'
    }

    It 'fails early when the requested orientation does not match the monitor orientation' {
        $apply = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'apply' -Arguments @{
            width = 1125
            height = 2000
        } -RunState @{}

        $apply.Status | Should -Be 'Failed'
        $apply.Errors | Should -Contain 'OrientationMismatch'
    }
}
