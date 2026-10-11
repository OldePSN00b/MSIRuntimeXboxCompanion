@{
    RootModule        = 'MSIRuntimeXboxCompanion.psm1'
    ModuleVersion = '0.2.0'
    GUID = '268807c8-885d-4aa7-9ba8-0093cf7acbfb'
    Author            = '0ldePSN00b'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 0ldePSN00b. All rights reserved.'
    Description       = 'Companion module for MSI Runtime that discovers and launches installed Xbox games with persistent thermal profiles and optional per-game process detection overrides.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-XboxCompanionSetting',
        'Set-XboxCompanionSetting',
        'Get-XboxGameProfile',
        'Set-XboxGameProfile',
        'Remove-XboxGameProfile',
        'Get-XboxInstalledGame',
        'Get-XboxLosslessScalingFilter',
        'Trace-XboxGameLaunch',
        'Start-XboxGameSession',
        'Start-XboxCompanion'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('Xbox', 'GamePass', 'MSI', 'MSIRuntime', 'XboxCompanion', 'Gaming')
            ProjectUri = ''
            ReleaseNotes = 'Initial MSI Runtime adaptation with firmware-gated controller profiles and Balanced cleanup.'
        }
    }
}
