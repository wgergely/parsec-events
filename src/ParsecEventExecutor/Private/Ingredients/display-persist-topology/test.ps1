Context 'display.persist-topology' {
    It 'captures and restores topology without touching theme or scaling' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'display.persist-topology' -Operation 'capture' -Arguments @{
            snapshot_name = 'topology-fixture'
        } -StateRoot $TestDrive -RunState @{}

        $script:IngredientObservedState.monitors[0].bounds.x = 320
        $script:IngredientObservedState.monitors[0].bounds.y = 180
        $script:IngredientObservedState.monitors[0].bounds.width = 1280
        $script:IngredientObservedState.monitors[0].bounds.height = 720
        $script:IngredientObservedState.monitors[0].display.width = 1280
        $script:IngredientObservedState.monitors[0].display.height = 720
        $script:IngredientObservedState.monitors[0].orientation = 'Portrait'

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'display.persist-topology' -Operation 'reset' -Arguments @{
            snapshot_name = 'topology-fixture'
        } -StateRoot $TestDrive -RunState @{}

        $verify = Invoke-ParsecCoreIngredientOperation -Name 'display.persist-topology' -Operation 'verify' -Arguments @{
            snapshot_name = 'topology-fixture'
        } -StateRoot $TestDrive -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $reset.Status | Should -Be 'Succeeded'
        $verify.Status | Should -Be 'Succeeded'
        $script:IngredientObservedState.monitors[0].bounds.x | Should -Be 0
        $script:IngredientObservedState.monitors[0].bounds.y | Should -Be 0
        $script:IngredientObservedState.monitors[0].bounds.width | Should -Be 1920
        $script:IngredientObservedState.monitors[0].orientation | Should -Be 'Landscape'
    }
}
