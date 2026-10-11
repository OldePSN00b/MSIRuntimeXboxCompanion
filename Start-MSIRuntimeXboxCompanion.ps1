<#
.SYNOPSIS
    Starts the MSI Runtime Xbox Companion interactively or launches one Xbox game directly.

.DESCRIPTION
    With no game selection parameters, opens the interactive Xbox companion menu.
    With -AppId or -Name, launches the selected Xbox game through the normal Xbox
    session flow. -ThermalProfile can override the resolved thermal profile for that
    session only; otherwise saved per-game and global settings are used.

    Xbox remains responsible for the game's launch behavior and arguments.

.PARAMETER AppId
    Stable Xbox package-family AppId to launch directly.

.PARAMETER Name
    Installed Xbox game name to resolve for direct launch. Wildcards are supported;
    the selection must resolve to exactly one installed title.

.PARAMETER ThermalProfile
    Optional one-session thermal override: EcoSilent, Balanced, or ExtremePerformance.

.EXAMPLE
    .\Start-MSIRuntimeXboxCompanion.ps1

.EXAMPLE
    .\Start-MSIRuntimeXboxCompanion.ps1 -AppId 'HoodedHorse.Fogpiercer_znaey1dw2bdpr'

.EXAMPLE
    .\Start-MSIRuntimeXboxCompanion.ps1 -Name 'Fogpiercer' -ThermalProfile ExtremePerformance
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
    [string]$AppId,

    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [string]$Name,

    [Parameter(ParameterSetName = 'ByAppId')]
    [Parameter(ParameterSetName = 'ByName')]
    [Alias('TDProfile')]
    [ValidateSet('EcoSilent', 'Balanced', 'ExtremePerformance')]
    [string]$ThermalProfile
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'MSIRuntimeXboxCompanion.psd1'
Import-Module -Name $modulePath -Force

if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    Start-XboxCompanion
    return
}

$sessionParameters = @{}
if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
    $sessionParameters.ThermalProfile = $ThermalProfile
}

if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
    Start-XboxGameSession -AppId $AppId @sessionParameters
}
else {
    Start-XboxGameSession -Name $Name @sessionParameters
}
