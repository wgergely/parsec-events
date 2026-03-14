Context 'display.ensure-resolution' {
    It 'captures and resolves ensured resolution state' {
        $script:IngredientSupportedModes = @(
            [ordered]@{ width = 1920; height = 1080; refresh_rate_hz = 60; bits_per_pel = 32; orientation = 'Landscape' },
            [ordered]@{ width = 2000; height = 3000; refresh_rate_hz = 60; bits_per_pel = 32; orientation = 'Portrait' }
        )

        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.ensure-resolution' -Operation 'capture' -Arguments @{} -RunState @{}
        $apply = Invoke-ParsecCoreIngredientOperation -Name 'display.ensure-resolution' -Operation 'apply' -Arguments @{
            width = 2000
            height = 3000
            orientation = 'Portrait'
        } -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $apply.Status | Should -Be 'Succeeded'
        $apply.Outputs.mode_preexisting | Should -BeTrue
    }
}
