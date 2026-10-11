# MSI Runtime Xbox Companion

Windows PowerShell 5.1 companion for MSIRuntime, adapted from the matching
Legion Go Runtime companion. Discovers installed Xbox games, resolves
global defaults and per-game or one-session overrides, applies an MSI controller
mode, launches through the platform, monitors the session, and restores Balanced
after non-Balanced sessions.

## Setup

Keep this repository alongside `MSIRuntime` in your GitHub folder, or install
MSIRuntime on Windows PowerShell 5.1's `PSModulePath`. The elevated helper prefers
the sibling `MSIRuntime/MSIRuntime.psd1` manifest. Writes require the runtime's
verified EC firmware `17K5IMS1.107`.

Run the companion from an **unelevated Windows PowerShell 5.1** session so the
launcher and games retain their normal user context. Only the short-lived
controller helper requests elevation. Windows may show UAC prompts before
launch and during restoration.

```powershell
.\Start-MSIRuntimeXboxCompanion.ps1
.\Start-MSIRuntimeXboxCompanion.ps1 -Name 'Game title' -ThermalProfile ExtremePerformance

Import-Module .\MSIRuntimeXboxCompanion.psd1 -Force
Get-XboxInstalledGame
Set-XboxCompanionSetting -DefaultThermalProfile Balanced -UseLosslessScaling $false
Set-XboxGameProfile -AppId 'GAME_ID' -ThermalProfile EcoSilent
Start-XboxGameSession -AppId 'GAME_ID' -ThermalProfile ExtremePerformance
```

Use `Get-Help Start-XboxGameSession -Full` for platform selection and process
override parameters. No arguments on the wrapper open the interactive menu;
`-AppId` or `-Name` launches directly.

## Profiles and settings

Supported `-ThermalProfile` values are `EcoSilent`, `Balanced`, and
`ExtremePerformance`; `-TDProfile` remains an alias. Precedence is explicit
session override, saved game profile, then global default. Balanced is the default
and is explicitly applied before launch, rather than assuming the controller is
already Balanced.

Settings are stored independently at
`%LOCALAPPDATA%\MSIRuntimeXboxCompanion\Settings.json`.
Legion companion settings are not imported. Saved profiles also support Lossless
Scaling preferences and process-name overrides.

Cooler Boost is preserved unless requested through the session option. These profiles apply the verified MSI registers;
they do not select MSI Center's highlighted tile or implement Smart Auto.
Cleanup returns to Balanced after a successfully applied non-Balanced profile,
including launch errors and timeouts. Restoration failures produce a warning;
select the desired mode in MSI Center if recovery fails.

## Platform integration

Reads Gaming Services registrations and package metadata; launches the registered Microsoft-signed GameLaunchHelper. Trace-XboxGameLaunch remains available for process diagnostics.
Inherited process monitoring excludes pre-existing matching processes. Optional
Lossless Scaling starts only when requested and cleanup targets only the instance
started by the companion. The companion does not configure scaling profiles
inside Lossless Scaling.

## Validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Run-Tests.ps1
```

Uses the bundled Pester 3.4. Tests simulate launcher/controller operations and use
temporary settings. Hardware mode changes, UAC, real game launches, and Lossless
Scaling need separate testing on the MSI machine.

The original MIT license is retained in [LICENSE](LICENSE).

## Cooler Boost sessions (0.2.0)

Use Settings option 7 to toggle Cooler Boost alongside the current default thermal
profile. Configure a game profile to save a separate Cooler Boost preference.
The setting is independent of EcoSilent, Balanced, or ExtremePerformance.

```powershell
Set-XboxCompanionSetting -UseCoolerBoost $true
Set-XboxGameProfile -AppId 'GAME_ID' -UseCoolerBoost $true
Start-XboxGameSession -AppId 'GAME_ID' -ThermalProfile ExtremePerformance -UseCoolerBoost $true
```

Precedence: explicit session argument, per-game preference, global default.
Existing settings default to false and preserve manually enabled Cooler Boost.
Enabled sessions save the prior boost state through the elevated MSI helper and
restore it with Balanced when the session ends or a later launch step fails.
Only the controller helper is elevated. Games and launchers remain unelevated.
Temporary session state is removed after successful restoration. If restoration
fails, select the desired mode and Cooler Boost state in MSI Center.

After selecting a game, press **B** to toggle Cooler Boost for that session, then **Enter** to launch. This keeps the selected thermal profile and does not alter saved defaults. Press **Q** to cancel.
