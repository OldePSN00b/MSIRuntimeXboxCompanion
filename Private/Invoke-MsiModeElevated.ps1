<#
.SYNOPSIS
    Applies a session mode with optional Cooler Boost in an elevated controller helper.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('EcoSilent','Balanced','ExtremePerformance')][string]$Mode,
    [switch]$EnableCoolerBoost,
    [switch]$RestoreCoolerBoost,
    [string]$SessionStatePath
)
$ErrorActionPreference = 'Stop'
try {
    if ($EnableCoolerBoost -and $RestoreCoolerBoost) { throw 'Cannot enable and restore simultaneously.' }
    if ($EnableCoolerBoost -or $RestoreCoolerBoost) {
        if ([string]::IsNullOrWhiteSpace($SessionStatePath)) { throw 'A session state path is required.' }
        $fullPath = [IO.Path]::GetFullPath($SessionStatePath)
        $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
        if (-not $fullPath.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($fullPath) -notlike 'MSIRuntime-Boost-*.json') {
            throw 'Session state must use an MSI Runtime file in the user temporary folder.'
        }
    }
    $repositoryRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
    $runtimeManifest = Join-Path -Path $repositoryRoot -ChildPath 'MSIRuntime\MSIRuntime.psd1'
    if (Test-Path -LiteralPath $runtimeManifest -PathType Leaf) {
        Import-Module -Name $runtimeManifest -Force -ErrorAction Stop
    } else {
        Import-Module -Name MSIRuntime -Force -ErrorAction Stop
    }
    $modeArguments = @{ Mode=$Mode; Confirm=$false; ErrorAction='Stop' }
    if ($EnableCoolerBoost) {
        $previous = Get-MsiCoolerBoost -ErrorAction Stop
        [pscustomobject]@{ CoolerBoost=[bool]$previous } | ConvertTo-Json | Set-Content -LiteralPath $fullPath -Encoding UTF8
        $modeArguments.CoolerBoost = 'On'
    } elseif ($RestoreCoolerBoost) {
        $previous = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
        if ($previous.CoolerBoost -isnot [bool]) { throw 'Invalid Cooler Boost session state.' }
        $modeArguments.CoolerBoost = if ($previous.CoolerBoost) { 'On' } else { 'Off' }
    }
    $result = Set-MsiMode @modeArguments
    if ($null -eq $result -or -not $result.RegisterVerified -or $result.RequestedMode -ne $Mode) {
        throw "MSIRuntime did not verify the requested $Mode controller mode."
    }
    if ($modeArguments.ContainsKey('CoolerBoost') -and $result.CoolerBoost -ne ($modeArguments.CoolerBoost -eq 'On')) { throw 'Cooler Boost was not verified.' }
    if ($RestoreCoolerBoost) { Remove-Item -LiteralPath $fullPath -Force }
    Write-Output "MSI controller mode set to $Mode."
} catch {
    Write-Error ("Failed to apply MSI session settings: {0}" -f $_.Exception.Message) -ErrorAction Continue
    exit 1
}
