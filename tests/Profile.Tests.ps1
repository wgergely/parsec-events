$modulePath = Join-Path $PSScriptRoot '..\src\ParsecEventExecutor\ParsecEventExecutor.psd1'
Import-Module $modulePath -Force

Describe 'Profile workflow' {
    InModuleScope ParsecEventExecutor {
        BeforeAll {
            $script:ParsecDisplayAdapter = @{
                GetObservedState = {
                    return [ordered]@{
                        captured_at      = [DateTimeOffset]::UtcNow.ToString('o')
                        computer_name    = 'TESTHOST'
                        display_backend  = 'TestAdapter'
                        monitor_identity = 'device_name'
                        monitors         = @(
                            [ordered]@{
                                device_name = '\\.\DISPLAY1'
                                is_primary  = $true
                                enabled     = $true
                                bounds      = [ordered]@{ x = 0; y = 0; width = 1920; height = 1080 }
                                working_area = [ordered]@{ x = 0; y = 0; width = 1920; height = 1040 }
                                orientation = 'Landscape'
                            }
                        )
                        scaling = [ordered]@{ status = 'Unsupported' }
                    }
                }
                SetEnabled = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'enabled' -Requested $Arguments }
                SetPrimary = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'primary' -Requested $Arguments }
                SetResolution = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'resolution' -Requested $Arguments }
                SetOrientation = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'orientation' -Requested $Arguments }
                SetScaling = { param($Arguments) New-ParsecResult -Status 'Succeeded' -Message 'scaling' -Requested $Arguments }
            }
        }

        It 'captures a profile and verifies it against the observed state' {
            $stateRoot = Join-Path $TestDrive 'profile-state'
            $profile = Capture-ParsecProfile -Name 'DESKTOP-CAPTURE' -StateRoot $stateRoot -Confirm:$false
            $verification = Test-ParsecProfile -Name 'DESKTOP-CAPTURE' -StateRoot $stateRoot

            $profile.name | Should -Be 'DESKTOP-CAPTURE'
            $verification.Status | Should -Be 'Succeeded'
        }

        It 'fails closed when a repository placeholder profile is not approved' {
            $stateRoot = Join-Path $TestDrive 'approval-gate'
            $result = Invoke-ParsecIngredientExecute -Name 'profile.apply' -Arguments @{ profile_name = 'MOBILE' } -StateRoot $stateRoot -RunState @{}

            $result.Status | Should -Be 'Failed'
            $result.Errors | Should -Contain 'ApprovalRequired'
        }
    }
}
