$modulePath = Join-Path $PSScriptRoot '..\MSIRuntimeXboxCompanion.psd1'
Import-Module $modulePath -Force

Describe 'MSI controller profiles and session recovery' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'uses an independent MSI settings directory' {
            (Split-Path $script:SettingsDirectory -Leaf) | Should Be 'MSIRuntimeXboxCompanion'
        }

        It 'accepts all MSI modes and rejects Legion profile names' {
            foreach ($mode in @('EcoSilent', 'Balanced', 'ExtremePerformance')) {
                $setting = Get-DefaultXboxCompanionSetting
                $setting.DefaultThermalProfile = $mode
                (ConvertTo-NormalizedXboxCompanionSetting -Setting $setting).DefaultThermalProfile | Should Be $mode
            }
            foreach ($mode in @('Quiet', 'Performance')) {
                $setting = Get-DefaultXboxCompanionSetting
                $setting.DefaultThermalProfile = $mode
                { ConvertTo-NormalizedXboxCompanionSetting -Setting $setting } | Should Throw
            }
        }

        It 'applies Balanced before launching a Balanced session' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' }
            Assert-MockCalled Start-XboxRegisteredGame -Times 1 -Exactly -Scope It
        }

        It 'restores Balanced after a failed ExtremePerformance launch' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }
            { Start-XboxGameSession -Game $script:testGame -ThermalProfile ExtremePerformance -UseLosslessScaling $false } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'ExtremePerformance' }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' }
            Assert-MockCalled Start-XboxRegisteredGame -Times 1 -Exactly -Scope It
        }

        It 'uses a saved ECO profile and restores Balanced after failure' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }
            $script:testSetting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ ThermalProfile = 'EcoSilent' })
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'EcoSilent' }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' }
        }

        It 'prefers an explicit mode over a saved game mode' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }
            $script:testSetting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ ThermalProfile = 'EcoSilent' })
            { Start-XboxGameSession -Game $script:testGame -ThermalProfile ExtremePerformance -UseLosslessScaling $false } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'ExtremePerformance' }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 0 -Exactly -Scope It -ParameterFilter { $Mode -eq 'EcoSilent' }
        }

        It 'does not launch a game when the controller helper fails' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }
            Mock Set-ElevatedXboxMsiMode { throw 'Simulated controller failure.' }
            { Start-XboxGameSession -Game $script:testGame -ThermalProfile ExtremePerformance -UseLosslessScaling $false } | Should Throw
            Assert-MockCalled Start-XboxRegisteredGame -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 0 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' }
        }
    }
}

Describe 'MSI helper process failure' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'propagates a failed elevated helper exit status' {
            Mock Test-Path { $true }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 1 } }
            { Set-ElevatedXboxMsiMode -Mode ExtremePerformance } | Should Throw
        }
    }
}

Describe 'MSI runtime helper integration' {
    Import-Module (Join-Path $PSScriptRoot '..\..\MSIRuntime\MSIRuntime.psd1') -Force
    It 'imports the sibling runtime and preserves Cooler Boost for each MSI mode' {
        Mock Import-Module { }
        Mock Test-Path { $true }
        Mock Set-MsiMode { [pscustomobject]@{ RegisterVerified = $true; RequestedMode = $Mode } }
        foreach ($mode in @('EcoSilent', 'Balanced', 'ExtremePerformance')) {
            & (Join-Path $PSScriptRoot '..\Private\Invoke-MsiModeElevated.ps1') -Mode $mode | Out-Null
        }
        Assert-MockCalled Import-Module -Times 3 -Exactly -Scope It -ParameterFilter { $Name -like '*MSIRuntime\MSIRuntime.psd1' }
        Assert-MockCalled Set-MsiMode -Times 3 -Exactly -Scope It -ParameterFilter { [string]::IsNullOrEmpty($CoolerBoost) }
    }

    It 'falls back to the installed runtime when the sibling is absent' {
        Mock Import-Module { }
        Mock Test-Path { $false }
        Mock Set-MsiMode { [pscustomobject]@{ RegisterVerified = $true; RequestedMode = $Mode } }
        & (Join-Path $PSScriptRoot '..\Private\Invoke-MsiModeElevated.ps1') -Mode Balanced | Out-Null
        Assert-MockCalled Import-Module -Times 1 -Exactly -Scope It -ParameterFilter { $Name -eq 'MSIRuntime' }
    }
}

Describe 'Cooler Boost session options' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'adds boost to Balanced and restores it after launch failure' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }

            
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false -UseCoolerBoost $true } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and $EnableCoolerBoost }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $RestoreCoolerBoost -and $Mode -eq 'Balanced' -and $SessionStatePath -like '*MSIRuntime-Boost-*.json' }
        }
        It 'inherits global boost without changing the selected thermal profile' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }

            $script:testSetting.UseCoolerBoost = $true
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false  } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and $EnableCoolerBoost }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $RestoreCoolerBoost -and $Mode -eq 'Balanced' -and $SessionStatePath -like '*MSIRuntime-Boost-*.json' }
        }
        It 'honors a saved false boost override over the global default' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }

            $script:testSetting.UseCoolerBoost = $true
            $script:testSetting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ UseCoolerBoost = $false })
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false  } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and -not $EnableCoolerBoost -and -not $RestoreCoolerBoost }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 0 -Exactly -Scope It -ParameterFilter { $RestoreCoolerBoost -and $Mode -eq 'Balanced' -and $SessionStatePath -like '*MSIRuntime-Boost-*.json' }
        }
        It 'honors an explicit false boost option over the saved true option' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }

            $script:testSetting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ UseCoolerBoost = $true })
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false -UseCoolerBoost $false } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and -not $EnableCoolerBoost -and -not $RestoreCoolerBoost }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 0 -Exactly -Scope It -ParameterFilter { $RestoreCoolerBoost -and $Mode -eq 'Balanced' -and $SessionStatePath -like '*MSIRuntime-Boost-*.json' }
        }
        It 'inherits a boost-only saved profile' {
            Set-StrictMode -Version Latest
            $script:testSetting = Get-DefaultXboxCompanionSetting
            $script:testSetting.UseLosslessScaling = $false
            $script:testGame = [pscustomobject]@{
                Name = 'Example'; AppId = 'ExampleId'; InstallPath = 'C:\Games\Example'
                LaunchUri = 'test://example'; LaunchExecutable = 'Example.exe'
                LaunchExecutables = @('Example.exe'); LauncherPath = 'C:\Games\Example\Launcher.exe'
            }
            Mock Get-XboxCompanionSetting { $script:testSetting }
            Mock Get-XboxProcessSnapshot { }
            Mock Set-ElevatedXboxMsiMode { }
            Mock Start-XboxRegisteredGame { throw 'Simulated launcher failure.' }

            $script:testSetting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ UseCoolerBoost = $true })
            { Start-XboxGameSession -Game $script:testGame -UseLosslessScaling $false  } | Should Throw
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and $EnableCoolerBoost }
            Assert-MockCalled Set-ElevatedXboxMsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $RestoreCoolerBoost -and $Mode -eq 'Balanced' -and $SessionStatePath -like '*MSIRuntime-Boost-*.json' }
        }
        It 'defaults older settings to preserving the current boost state' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.PSObject.Properties.Remove('UseCoolerBoost')
            (ConvertTo-NormalizedXboxCompanionSetting -Setting $setting).UseCoolerBoost | Should Be $false
        }
        It 'normalizes a boost-only saved profile including false' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.GameOverrides | Add-Member NoteProperty 'ExampleId' ([pscustomobject]@{ UseCoolerBoost = 'false' })
            $result = ConvertTo-NormalizedXboxCompanionSetting -Setting $setting
            $result.GameOverrides.ExampleId.UseCoolerBoost | Should Be $false
        }
    }
}

Describe 'Cooler Boost helper state recovery' {
    It 'restores both previously enabled and previously disabled boost states' {
        Mock Import-Module { }

        Mock Set-MsiMode { [pscustomobject]@{ RegisterVerified=$true; RequestedMode=$Mode; CoolerBoost=($CoolerBoost -eq 'On') } }
        $helperPath = Join-Path $PSScriptRoot '..\Private\Invoke-MsiModeElevated.ps1'
        foreach ($prior in @($false, $true)) {
            if ($prior) { Mock Get-MsiCoolerBoost { $true } } else { Mock Get-MsiCoolerBoost { $false } }
            $statePath = Join-Path ([IO.Path]::GetTempPath()) ('MSIRuntime-Boost-' + [guid]::NewGuid().ToString('N') + '.json')
            try {
                & $helperPath -Mode ExtremePerformance -EnableCoolerBoost -SessionStatePath $statePath | Out-Null
                (Get-Content $statePath -Raw | ConvertFrom-Json).CoolerBoost | Should Be $prior
                & $helperPath -Mode Balanced -RestoreCoolerBoost -SessionStatePath $statePath | Out-Null
                (Test-Path $statePath) | Should Be $false
            } finally { if (Test-Path $statePath) { Remove-Item -LiteralPath $statePath -Force } }
        }
        Assert-MockCalled Set-MsiMode -Times 2 -Exactly -Scope It -ParameterFilter { $Mode -eq 'ExtremePerformance' -and $CoolerBoost -eq 'On' }
        Assert-MockCalled Set-MsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and $CoolerBoost -eq 'Off' }
        Assert-MockCalled Set-MsiMode -Times 1 -Exactly -Scope It -ParameterFilter { $Mode -eq 'Balanced' -and $CoolerBoost -eq 'On' }
    }
}

Describe 'Cooler Boost launch menu' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'toggles boost for the selected session without changing its saved thermal profile' {
            $script:menuSetting = Get-DefaultXboxCompanionSetting
            $script:menuSetting.DefaultThermalProfile = 'ExtremePerformance'
            $script:answers = @('a', '1', 'b', '', '', 'q')
            Mock Read-Host {
                if ($script:answers.Count -eq 0) { throw 'Unexpected extra menu prompt' }
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-XboxCompanionSetting { $script:menuSetting }
            Mock Get-XboxInstalledGame { [pscustomobject]@{ Name='Example'; AppId='ExampleId'; InstallPath='C:\Games\Example' } }
            Mock Start-XboxGameSession { }
            Mock Set-XboxCompanionSetting { }
            Mock Set-XboxGameProfile { }
            Start-XboxCompanion
            Assert-MockCalled Start-XboxGameSession -Times 1 -Exactly -Scope It -ParameterFilter { $UseCoolerBoost -eq $true }
            Assert-MockCalled Set-XboxCompanionSetting -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-XboxGameProfile -Times 0 -Exactly -Scope It
            $script:menuSetting.DefaultThermalProfile | Should Be 'ExtremePerformance'
            $script:menuSetting.UseCoolerBoost | Should Be $false
        }
    }
}
