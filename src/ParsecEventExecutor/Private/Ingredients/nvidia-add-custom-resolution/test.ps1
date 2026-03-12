Context 'nvidia.add-custom-resolution' {
    It 'adds a custom resolution through the NVIDIA adapter' {
        $apply = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'apply' -Arguments @{
            width = 2000
            height = 3000
        } -RunState @{}

        $verify = Invoke-ParsecIngredientOperation -Name 'nvidia.add-custom-resolution' -Operation 'verify' -Arguments @{
            width = 2000
            height = 3000
        } -RunState @{}

        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.display_id | Should -Be 101
        $apply.Outputs.already_present | Should -BeFalse
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
}
