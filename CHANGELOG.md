# Changelog

## 0.1.0 — 2026-10-11

- Adapted the Legion Go Runtime Xbox companion for MSIRuntime.
- Added MSI profile values, independent settings, and a sibling runtime lookup.
- Apply Balanced explicitly before Balanced sessions; preserve Cooler Boost.
- Retained platform discovery, session monitoring, and Lossless Scaling support.
- Added MSI-specific validation alongside the inherited regression suite.

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
