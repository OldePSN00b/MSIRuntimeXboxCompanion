# MSI Runtime Xbox Companion agent guide

These instructions apply to this repository.

- Support Windows PowerShell 5.1 and Pester 3.4 syntax.
- Preserve platform discovery, native launch behavior, process isolation, and
  Lossless Scaling ownership rules inherited from the Legion companion.
- Keep exported commands and manifest exports synchronized; use approved verbs.
- Keep settings separate under MSIRuntimeXboxCompanion. Do not migrate
  Legion settings or write machine-specific data into the repository.
- Profiles are EcoSilent, Balanced, and ExtremePerformance. Apply every selected
  mode before launch and restore Balanced after successful non-Balanced changes.
- Delegate controller changes to MSIRuntime through the elevated private helper.
  Do not duplicate MSI register writes here or change Cooler Boost implicitly.
- Keep launchers and games unelevated; only controller helpers request elevation.
- Use Write-Host for menu UI and keep data output clean.
- Wrap collections in @() before reading Count. Check strict-mode behavior.
- Update README.md and CHANGELOG.md for user-visible changes.
- Run .\Run-Tests.ps1 in powershell.exe before handoff. Do not access hardware
  during automated tests. Report real-hardware validation separately.
