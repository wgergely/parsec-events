@{
    RootModule        = 'ParsecEventExecutor.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '2eff4ae6-539f-47f6-bf7d-3d42d9d219ec'
    Author            = 'OpenAI Codex'
    CompanyName       = 'OpenAI'
    Copyright         = '(c) OpenAI. All rights reserved.'
    Description       = 'Mission-focused recipe executor for Parsec desktop/mobile transitions.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Invoke-ParsecIngredient',
        'Invoke-ParsecRecipe',
        'Get-ParsecDisplay',
        'Get-ParsecRecipe',
        'Get-ParsecIngredient',
        'Save-ParsecSnapshot',
        'Test-ParsecSnapshot',
        'Save-ParsecProfile',
        'Test-ParsecProfile',
        'Get-ParsecExecutorState',
        'Repair-ParsecExecutorState',
        'Start-ParsecExecutor'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('Capture-ParsecSnapshot', 'Capture-ParsecProfile')
    PrivateData       = @{
        PSData = @{
            Tags       = @('parsec', 'powershell', 'recipes', 'windows')
            ProjectUri = 'https://example.invalid/parsec-event-executor'
        }
    }
}
