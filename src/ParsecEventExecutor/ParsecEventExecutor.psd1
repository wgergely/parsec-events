@{
    RootModule = 'ParsecEventExecutor.psm1'
    ModuleVersion = '0.1.0'
    GUID = '2eff4ae6-539f-47f6-bf7d-3d42d9d219ec'
    Author = 'OpenAI Codex'
    CompanyName = 'OpenAI'
    Copyright = '(c) OpenAI. All rights reserved.'
    Description = 'Recipe executor for Parsec connection events with display configuration management.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-ParsecIngredient',
        'Invoke-ParsecRecipe',
        'Get-ParsecDisplay',
        'Get-ParsecDisplayAudit',
        'Get-ParsecRecipe',
        'Get-ParsecIngredient',
        'Save-ParsecSnapshot',
        'Test-ParsecSnapshot',
        'Save-ParsecProfile',
        'Test-ParsecProfile',
        'Get-ParsecExecutorState',
        'Repair-ParsecExecutorState',
        'Start-ParsecExecutor',
        'Start-ParsecWatcher',
        'Stop-ParsecWatcher',
        'Register-ParsecWatcherTask',
        'Unregister-ParsecWatcherTask',
        'Set-ParsecDefaultProfile',
        'Get-ParsecDefaultProfile',
        'New-ParsecRecipeFromCapture'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @('Capture-ParsecSnapshot', 'Capture-ParsecProfile')
    PrivateData = @{
        PSData = @{
            Tags = @('parsec', 'powershell', 'recipes', 'windows')
            ProjectUri = 'https://example.invalid/parsec-event-executor'
        }
    }
}
