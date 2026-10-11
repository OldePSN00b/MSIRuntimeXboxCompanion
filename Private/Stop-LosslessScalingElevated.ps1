<#
.SYNOPSIS
    Stops one verified Lossless Scaling process from an elevated PowerShell process.

.DESCRIPTION
    Private helper for MSIRuntimeXboxCompanion. Both PID and original start
    time must match, preventing PID reuse from terminating an unrelated process.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProcessId,

    [Parameter(Mandatory)]
    [long]$StartTimeUtcTicks
)

$ErrorActionPreference = 'Stop'

try {
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    if ([string]$process.ProcessName -ine 'LosslessScaling') {
        throw "PID $ProcessId is '$($process.ProcessName)', not LosslessScaling."
    }
    if ([long]$process.StartTime.ToUniversalTime().Ticks -ne $StartTimeUtcTicks) {
        throw "PID $ProcessId has been reused since the companion started Lossless Scaling."
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction Stop
}
catch {
    Write-Error ("Failed to stop the verified Lossless Scaling process: {0}" -f $_.Exception.Message)
    exit 1
}
