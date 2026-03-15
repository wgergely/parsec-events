Context 'sound.set-playback-device' {
    It 'captures the current default playback device' {
        $capture = Invoke-ParsecCoreIngredientOperation -Name 'sound.set-playback-device' -Operation 'capture' -Arguments @{} -RunState @{}

        $capture.Status | Should -Be 'Succeeded'
        $capture.Outputs.captured_state | Should -Not -BeNullOrEmpty
        $capture.Outputs.captured_state.has_device | Should -Be $true
        $capture.Outputs.captured_state.device_id | Should -Be 'speaker-001'
    }

    It 'applies a playback device change and verifies the result' {
        $apply = Invoke-ParsecCoreIngredientOperation -Name 'sound.set-playback-device' -Operation 'apply' -Arguments @{
            device_id = 'hdmi-002'
            device_name = 'HDMI Audio'
        } -RunState @{}

        $apply.Status | Should -Be 'Succeeded'
        $script:IngredientSoundDefaultDevice.id | Should -Be 'hdmi-002'

        $verify = Invoke-ParsecCoreIngredientOperation -Name 'sound.set-playback-device' -Operation 'verify' -Arguments @{
            device_id = 'hdmi-002'
        } -Prior $apply -RunState @{}

        $verify.Status | Should -Be 'Succeeded'
    }

    It 'resets the playback device to the captured state' {
        $script:IngredientSoundDefaultDevice = [ordered]@{
            id = 'hdmi-002'
            name = 'HDMI Audio'
            is_default = $true
            type = 'Playback'
            status = 'Active'
        }

        $reset = Invoke-ParsecCoreIngredientOperation -Name 'sound.set-playback-device' -Operation 'reset' -Arguments @{
            captured_state = @{
                has_device = $true
                device_id = 'speaker-001'
                device_name = 'Speakers'
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
        $script:IngredientSoundDefaultDevice.id | Should -Be 'speaker-001'
    }

    It 'handles reset when no device was originally captured' {
        $reset = Invoke-ParsecCoreIngredientOperation -Name 'sound.set-playback-device' -Operation 'reset' -Arguments @{
            captured_state = @{
                has_device = $false
            }
        } -RunState @{}

        $reset.Status | Should -Be 'Succeeded'
    }
}
