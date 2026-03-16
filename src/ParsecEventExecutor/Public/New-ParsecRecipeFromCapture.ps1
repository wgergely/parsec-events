function New-ParsecRecipeFromCapture {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '')]
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter()]
        [ValidateSet('connect', 'disconnect')]
        [string] $EventType = 'connect',

        [Parameter()]
        [string] $Username,

        [Parameter()]
        [string] $Description
    )

    # Single call to get the full observed state (display topology, scaling, theme)
    $observed = & (Get-Module ParsecEventExecutor) { Get-ParsecDisplayDomainObservedState }
    $primaryMonitor = $observed.monitors | Where-Object { $_.is_primary } | Select-Object -First 1
    if (-not $primaryMonitor) {
        $primaryMonitor = $observed.monitors | Select-Object -First 1
    }

    # Build recipe lines
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("name = `"$Name`"")

    $desc = if ($Description) { $Description } else { "Captured recipe for $EventType event." }
    $lines.Add("description = `"$desc`"")
    $lines.Add("event_type = `"$EventType`"")

    if ($Username) {
        $lines.Add("username = `"$Username`"")
    }

    $lines.Add('')

    # Capture snapshot step (only for connect recipes)
    if ($EventType -eq 'connect') {
        $lines.Add('[[steps]]')
        $lines.Add('id = "capture-pre-connect-snapshot"')
        $lines.Add('ingredient = "display.snapshot"')
        $lines.Add('operation = "capture"')
        $lines.Add('depends_on = []')
        $lines.Add('verify = true')
        $lines.Add('compensation_policy = "none"')
        $lines.Add('')
        $lines.Add('[steps.arguments]')
        $lines.Add('snapshot_name = "pre-connect"')
        $lines.Add('')
    }

    $stepIndex = 0
    $lastStepId = if ($EventType -eq 'connect') { 'capture-pre-connect-snapshot' } else { $null }

    # Helper to emit a recipe step block
    $addStep = {
        param([string] $Id, [string] $Ingredient, [hashtable] $Arguments)
        $lines.Add('[[steps]]')
        $lines.Add("id = `"$Id`"")
        $lines.Add("ingredient = `"$Ingredient`"")
        $lines.Add('operation = "apply"')
        $dep = if ($lastStepId) { "[`"$lastStepId`"]" } else { '[]' }
        $lines.Add("depends_on = $dep")
        $lines.Add('verify = true')
        $lines.Add('compensation_policy = "explicit"')
        $lines.Add('')
        $lines.Add('[steps.arguments]')
        foreach ($k in $Arguments.Keys) {
            $v = $Arguments[$k]
            if ($v -is [string]) { $lines.Add("$k = `"$v`"") }
            else { $lines.Add("$k = $v") }
        }
        $lines.Add('')
        $script:lastStepId = $Id
        $script:stepIndex++
    }

    # Resolution step from primary monitor
    if ($primaryMonitor) {
        $width = $primaryMonitor.bounds.width
        $height = $primaryMonitor.bounds.height
        $orientation = $primaryMonitor.orientation

        if ($width -and $height) {
            $stepArgs = [ordered]@{ width = $width; height = $height }
            if ($orientation -and $orientation -ne 'Landscape') {
                $stepArgs.orientation = $orientation
            }
            & $addStep 'set-resolution' 'display.ensure-resolution' $stepArgs
        }
    }

    # UI scaling step
    if ($observed.scaling -and $observed.scaling.ui_scale_percent) {
        & $addStep 'set-ui-scaling' 'display.set-scaling' @{ ui_scale_percent = $observed.scaling.ui_scale_percent }
    }

    # Text scaling step
    if ($observed.font_scaling -and $observed.font_scaling.text_scale_percent) {
        & $addStep 'set-text-scaling' 'display.set-textscale' @{ text_scale_percent = $observed.font_scaling.text_scale_percent }
    }

    # Theme step
    if ($observed.theme -and $observed.theme.app_mode) {
        & $addStep 'set-theme' 'system.set-theme' @{ mode = $observed.theme.app_mode }
    }

    $tomlContent = $lines -join "`n"

    # Write to recipes directory
    $recipesDir = Join-Path (Get-ParsecRepositoryRoot) 'recipes'
    if (-not (Test-Path -LiteralPath $recipesDir)) {
        New-Item -ItemType Directory -Path $recipesDir -Force | Out-Null
    }

    $recipePath = Join-Path $recipesDir "$Name.toml"
    Set-Content -LiteralPath $recipePath -Value $tomlContent -Encoding UTF8 -NoNewline

    return [ordered]@{
        name = $Name
        event_type = $EventType
        path = $recipePath
        steps = $stepIndex
        captured_at = [DateTimeOffset]::UtcNow.ToString('o')
    }
}
