[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    throw 'Run companion tests in Windows PowerShell 5.1 (powershell.exe).'
}
Import-Module Pester -MinimumVersion 3.4 -MaximumVersion 3.4.99 -ErrorAction Stop
$result = Invoke-Pester -Script (Join-Path $PSScriptRoot 'tests') -PassThru
if ($result.FailedCount -gt 0) { throw "$($result.FailedCount) companion tests failed." }
