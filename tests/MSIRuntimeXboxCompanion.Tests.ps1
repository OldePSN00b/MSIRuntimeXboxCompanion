$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\MSIRuntimeXboxCompanion.psd1'
Import-Module -Name $modulePath -Force

Describe 'Module contract' {
    It 'exports exactly the commands declared by the manifest' {
        $manifest = Test-ModuleManifest -Path $modulePath
        $actual = @(Get-Command -Module MSIRuntimeXboxCompanion -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $expected = @($manifest.ExportedFunctions.Keys | Sort-Object)

        @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count | Should Be 0
    }

    It 'uses approved verbs for every exported command' {
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $unapproved = @(
            Get-Command -Module MSIRuntimeXboxCompanion -CommandType Function |
                Where-Object { ($_.Name -split '-')[0] -notin $approvedVerbs }
        )

        $unapproved.Count | Should Be 0
    }

    It 'exports only the normalized Xbox command families and its diagnostic trace' {
        $actual = @(Get-Command -Module MSIRuntimeXboxCompanion -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $expected = @(
            'Get-XboxCompanionSetting',
            'Get-XboxGameProfile',
            'Get-XboxInstalledGame',
            'Get-XboxLosslessScalingFilter',
            'Remove-XboxGameProfile',
            'Set-XboxCompanionSetting',
            'Set-XboxGameProfile',
            'Start-XboxCompanion',
            'Start-XboxGameSession',
            'Trace-XboxGameLaunch'
        ) | Sort-Object

        @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count | Should Be 0
    }

    It 'exposes the shared launcher session parameter sets' {
        $command = Get-Command Start-XboxGameSession
        @($command.ParameterSets.Name | Sort-Object) -join ',' | Should Be 'ByAppId,ByName,ByObject'
        $pipelineAttributes = @(
            $command.Parameters['Game'].Attributes |
                Where-Object {
                    $_ -is [System.Management.Automation.ParameterAttribute] -and
                    $_.ValueFromPipeline
                }
        )
        $pipelineAttributes.Count | Should Be 1
    }
}

Describe 'Lossless Scaling filter discovery' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'returns filename-only filters from Gaming Services executable records' {
            Mock Get-XboxGameProfile { @() }
            Mock Get-XboxInstalledGame {
                [pscustomobject]@{
                    Name = 'Palworld'
                    AppId = 'Pocketpair.Palworld_example'
                    LaunchExecutable = 'Pal\Binaries\WinGDK\Palworld-WinGDK-Shipping.exe'
                    LaunchExecutables = @(
                        'Pal\Binaries\WinGDK\Palworld-WinGDK-Shipping.exe',
                        'Tools\PalworldLauncher.exe'
                    )
                }
            }

            $result = @(Get-XboxLosslessScalingFilter -Name 'Palworld')

            $result.Count | Should Be 2
            $result[0].ExecutableName | Should Be 'Palworld-WinGDK-Shipping.exe'
            $result[0].IsPrimary | Should Be $true
            $result[0].Source | Should Be 'GamingServicesRegistry'
            $result[1].ExecutableName | Should Be 'PalworldLauncher.exe'
            $result[1].IsPrimary | Should Be $false
        }

        It 'can return only the primary registered executable' {
            Mock Get-XboxGameProfile { @() }
            $game = [pscustomobject]@{
                Name = 'Example'
                AppId = 'Example.Game_abc123'
                LaunchExecutable = 'Primary.exe'
                LaunchExecutables = @('Primary.exe', 'Secondary.exe')
            }

            $result = @(Get-XboxLosslessScalingFilter -Game $game -PrimaryOnly)

            $result.Count | Should Be 1
            $result[0].ExecutableName | Should Be 'Primary.exe'
        }

        It 'prefers a traced game-profile override over a registered bootstrapper' {
            Mock Get-XboxInstalledGame {
                [pscustomobject]@{
                    Name = 'Like a Dragon: Pirate Yakuza in Hawaii'
                    AppId = 'SEGA.Example'
                    LaunchExecutable = 'runtime\media\startup.exe'
                    LaunchExecutables = @('runtime\media\startup.exe')
                }
            }
            Mock Get-XboxGameProfile {
                [pscustomobject]@{
                    AppId = 'SEGA.Example'
                    ProcessName = @('likeadragonpirates.exe')
                }
            }

            $result = @(Get-XboxLosslessScalingFilter -Name 'Like a Dragon')

            $result.Count | Should Be 1
            $result[0].ExecutableName | Should Be 'likeadragonpirates.exe'
            $result[0].Source | Should Be 'GameProfileOverride'
        }

        It 'rejects an ambiguous display-name match' {
            Mock Get-XboxInstalledGame {
                @(
                    [pscustomobject]@{ Name = 'Example One'; AppId = 'One'; LaunchExecutables = @('One.exe') },
                    [pscustomobject]@{ Name = 'Example Two'; AppId = 'Two'; LaunchExecutables = @('Two.exe') }
                )
            }

            { Get-XboxLosslessScalingFilter -Name 'Example' } | Should Throw
        }
    }
}

Describe 'Settings validation' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'normalizes Boolean strings and numeric values from legacy settings' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.UseLosslessScaling = 'false'
            $setting.GameStartTimeoutSeconds = '600'
            $setting.PollIntervalSeconds = '3'

            $result = ConvertTo-NormalizedXboxCompanionSetting -Setting $setting

            $result.UseLosslessScaling | Should Be $false
            $result.GameStartTimeoutSeconds | Should Be 600
            $result.PollIntervalSeconds | Should Be 3
        }

        It 'rejects invalid Boolean values instead of coercing them to true' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.UseLosslessScaling = 'not-a-boolean'

            { ConvertTo-NormalizedXboxCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects invalid timeout ranges' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.GameStartTimeoutSeconds = 0

            { ConvertTo-NormalizedXboxCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects malformed game override collections' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.GameOverrides = 'invalid'

            { ConvertTo-NormalizedXboxCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects a persisted profile whose process override is empty' {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.GameOverrides | Add-Member NoteProperty 'ExampleGame' ([pscustomobject]@{ ProcessName = @() })

            { ConvertTo-NormalizedXboxCompanionSetting -Setting $setting } | Should Throw
        }
    }
}

Describe 'Settings persistence' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'atomically replaces an existing settings file under Windows PowerShell 5.1' {
            $originalDirectory = $script:SettingsDirectory
            $originalPath = $script:SettingsPath
            $testDirectory = Join-Path -Path $TestDrive -ChildPath 'Settings'
            $script:SettingsDirectory = $testDirectory
            $script:SettingsPath = Join-Path -Path $testDirectory -ChildPath 'Settings.json'

            try {
                $setting = Get-DefaultXboxCompanionSetting
                Write-XboxCompanionSetting -Setting $setting
                $setting.DefaultThermalProfile = 'ExtremePerformance'
                Write-XboxCompanionSetting -Setting $setting

                $saved = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
                $saved.DefaultThermalProfile | Should Be 'ExtremePerformance'
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.tmp').Count | Should Be 0
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.bak').Count | Should Be 0
            }
            finally {
                $script:SettingsDirectory = $originalDirectory
                $script:SettingsPath = $originalPath
            }
        }
    }
}

Describe 'Saved game profiles' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'rejects an empty saved profile' {
            { Set-XboxGameProfile -AppId 'ExampleGame' } | Should Throw
        }

        It 'rejects an empty process override as a new profile' {
            Mock Get-XboxCompanionSetting { Get-DefaultXboxCompanionSetting }

            { Set-XboxGameProfile -AppId 'ExampleGame' -ProcessName @() } | Should Throw
        }

        It 'keeps a single process override as a collection' {
            Mock Get-XboxCompanionSetting {
                $setting = Get-DefaultXboxCompanionSetting
                $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name 'ExampleGame' -Value ([pscustomobject]@{
                    ProcessName = @('ExampleGame')
                })
                $setting
            }

            $profile = Get-XboxGameProfile -AppId 'ExampleGame'

            @($profile.ProcessName).Count | Should Be 1
            $profile.ProcessName[0] | Should Be 'ExampleGame'
        }
    }
}

Describe 'Gaming Services discovery' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'derives a stable package family from a versioned package full name' {
            $identity = Get-XboxPackageFamilyName -PackageFullName 'Example_Publisher.Game_1.2.3.4_x64__abc123'

            $identity.IdentityName | Should Be 'Example_Publisher.Game'
            $identity.PackageVersion.ToString() | Should Be '1.2.3.4'
            $identity.PackageFamilyName | Should Be 'Example_Publisher.Game_abc123'
        }

        It 'converts a registration into a launchable game without using the game executable as launcher' {
            $installPath = Join-Path -Path $TestDrive -ChildPath 'Example Game'
            New-Item -Path $installPath -ItemType Directory | Out-Null
            New-Item -Path (Join-Path -Path $installPath -ChildPath 'GameLaunchHelper.exe') -ItemType File | Out-Null

            $registration = [pscustomobject]@{
                PackageFullName  = 'Example.Game_1.2.3.4_x64__abc123'
                InstallPath      = $installPath
                DisplayName      = 'Example Game'
                StoreId          = '9EXAMPLE1234'
                TitleId          = 123
                MSAAppId         = 'example-msa-id'
                RequiresXboxLive = 1
                ApplicationId    = 'Game'
                Executables      = @([pscustomobject]@{
                    Name = 'Binaries\ExampleGame.exe'
                    TargetDeviceFamily = 'PC'
                    IsDevOnly = 0
                })
            }

            $game = ConvertFrom-XboxGameRegistration -Registration $registration

            $game.AppId | Should Be 'Example.Game_abc123'
            $game.AUMID | Should Be 'Example.Game_abc123!Game'
            $game.LaunchExecutable | Should Be 'Binaries\ExampleGame.exe'
            $game.LauncherPath | Should Be (Join-Path -Path $installPath -ChildPath 'GameLaunchHelper.exe')
            $game.LauncherPath | Should Not Be $game.LaunchPath
        }

        It 'retains multiple registered session executables' {
            $installPath = Join-Path -Path $TestDrive -ChildPath 'Multi Game'
            New-Item -Path $installPath -ItemType Directory | Out-Null
            New-Item -Path (Join-Path -Path $installPath -ChildPath 'GameLaunchHelper.exe') -ItemType File | Out-Null
            $registration = [pscustomobject]@{
                PackageFullName = 'Example.MultiGame_2.0.0.0_x64__abc123'
                InstallPath = $installPath
                DisplayName = 'Multi Game'
                ApplicationId = 'Game'
                Executables = @(
                    [pscustomobject]@{ Name = 'Launcher.exe'; TargetDeviceFamily = 'PC'; IsDevOnly = 0 },
                    [pscustomobject]@{ Name = 'Game.exe'; TargetDeviceFamily = 'PC'; IsDevOnly = 0 },
                    [pscustomobject]@{ Name = 'Debug.exe'; TargetDeviceFamily = 'PC'; IsDevOnly = 1 }
                )
            }

            $game = ConvertFrom-XboxGameRegistration -Registration $registration

            @($game.LaunchExecutables).Count | Should Be 2
            $game.LaunchExecutables -contains 'Launcher.exe' | Should Be $true
            $game.LaunchExecutables -contains 'Game.exe' | Should Be $true
            $game.LaunchExecutables -contains 'Debug.exe' | Should Be $false
        }
    }
}

Describe 'Xbox launch behavior' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'launches the Microsoft-signed helper from the game install directory' {
            $game = [pscustomobject]@{
                Name = 'Example Game'
                InstallPath = 'C:\Xbox Games\Example'
                LauncherPath = 'C:\Xbox Games\Example\GameLaunchHelper.exe'
            }
            Mock Test-Path { $true }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::Valid
                    SignerCertificate = [pscustomobject]@{ Subject = 'CN=Microsoft Corporation, O=Microsoft Corporation, C=US' }
                }
            }
            Mock Start-Process { [pscustomobject]@{ Id = 42 } }

            $result = Start-XboxRegisteredGame -Game $game

            $result.Id | Should Be 42
            Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
                $FilePath -eq $game.LauncherPath -and
                $WorkingDirectory -eq $game.InstallPath -and
                $PassThru
            }
        }

        It 'rejects a helper without a valid signature' {
            $game = [pscustomobject]@{
                Name = 'Example Game'
                InstallPath = 'C:\Xbox Games\Example'
                LauncherPath = 'C:\Xbox Games\Example\GameLaunchHelper.exe'
            }
            Mock Test-Path { $true }
            Mock Get-AuthenticodeSignature {
                [pscustomobject]@{
                    Status = [System.Management.Automation.SignatureStatus]::HashMismatch
                    SignerCertificate = $null
                }
            }
            Mock Start-Process { }

            { Start-XboxRegisteredGame -Game $game } | Should Throw
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }
    }
}

Describe 'Xbox session process identity' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'keeps monitoring the original process identity' {
            $startTime = [datetime]::new(2026, 9, 30, 13, 0, 0, [DateTimeKind]::Utc)
            Mock Get-Process {
                [pscustomobject]@{
                    Id = 400
                    ProcessName = 'startup'
                    StartTime = $startTime
                }
            }

            Test-XboxProcessIdentity -ProcessId 400 -ProcessName 'startup.exe' -StartTimeUtcTicks $startTime.Ticks | Should Be $true
        }

        It 'ends monitoring when Windows reuses the PID for another process' {
            $startTime = [datetime]::new(2026, 9, 30, 13, 0, 0, [DateTimeKind]::Utc)
            Mock Get-Process {
                [pscustomobject]@{
                    Id = 400
                    ProcessName = 'svchost'
                    StartTime = $startTime.AddMinutes(1)
                }
            }

            Test-XboxProcessIdentity -ProcessId 400 -ProcessName 'startup.exe' -StartTimeUtcTicks $startTime.Ticks | Should Be $false
        }

        It 'ends monitoring when the same executable name has a different start time' {
            $startTime = [datetime]::new(2026, 9, 30, 13, 0, 0, [DateTimeKind]::Utc)
            Mock Get-Process {
                [pscustomobject]@{
                    Id = 400
                    ProcessName = 'startup'
                    StartTime = $startTime.AddMinutes(1)
                }
            }

            Test-XboxProcessIdentity -ProcessId 400 -ProcessName 'startup.exe' -StartTimeUtcTicks $startTime.Ticks | Should Be $false
        }

        It 'ends monitoring when the original PID no longer exists' {
            Mock Get-Process { $null }

            Test-XboxProcessIdentity -ProcessId 400 -ProcessName 'startup.exe' -StartTimeUtcTicks 123 | Should Be $false
        }
    }
}

Describe 'Interactive settings actions' {
    InModuleScope MSIRuntimeXboxCompanion {
        function New-TestXboxSetting {
            $setting = Get-DefaultXboxCompanionSetting
            $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name 'ExampleGame' -Value ([pscustomobject]@{
                ThermalProfile = 'ExtremePerformance'
            })
            $setting
        }

        It 'uses option 4 to view profiles without removing one' {
            $script:answers = @('s', '4', '', '6', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-XboxInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }
            Mock Get-XboxCompanionSetting { New-TestXboxSetting }
            Mock Get-XboxGameProfile { [pscustomobject]@{ AppId = 'ExampleGame'; ThermalProfile = 'ExtremePerformance'; UseLosslessScaling = $null; ProcessName = @() } }
            Mock Remove-XboxGameProfile { }

            Start-XboxCompanion

            Assert-MockCalled Remove-XboxGameProfile -Times 0 -Exactly
        }

        It 'uses option 5 to remove the selected profile' {
            $script:answers = @('s', '5', '1', '6', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-XboxInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }
            Mock Get-XboxCompanionSetting { New-TestXboxSetting }
            Mock Get-XboxGameProfile { [pscustomobject]@{ AppId = 'ExampleGame'; ThermalProfile = 'ExtremePerformance'; UseLosslessScaling = $null; ProcessName = @() } }
            Mock Remove-XboxGameProfile { }

            Start-XboxCompanion

            Assert-MockCalled Remove-XboxGameProfile -Times 1 -Exactly -ParameterFilter { $AppId -eq 'ExampleGame' }
        }

        It 'uses L to show the Lossless Scaling executable for a selected game' {
            $script:answers = @('l', 'example', '1', '', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-XboxInstalledGame {
                [pscustomobject]@{
                    Name = 'Example'
                    AppId = 'ExampleGame'
                    LaunchExecutable = 'Example.exe'
                    LaunchExecutables = @('Example.exe')
                }
            }
            Mock Get-XboxLosslessScalingFilter {
                [pscustomobject]@{
                    GameName = 'Example'
                    AppId = 'ExampleGame'
                    ExecutableName = 'Example.exe'
                    IsPrimary = $true
                    Source = 'GamingServicesRegistry'
                }
            }

            Start-XboxCompanion

            Assert-MockCalled Get-XboxLosslessScalingFilter -Times 1 -Exactly -Scope It -ParameterFilter {
                $Game.AppId -eq 'ExampleGame'
            }
        }

        It 'rescans the Xbox library when R is selected' {
            $script:answers = @('r', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Start-Sleep { }
            Mock Get-XboxInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }

            Start-XboxCompanion

            Assert-MockCalled Get-XboxInstalledGame -Times 2 -Exactly -Scope It
        }
    }
}

Describe 'Thermal helper launch behavior' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'hides the elevated PowerShell console and disables profile loading' {
            Mock Test-Path { $true }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

            Set-ElevatedXboxMsiMode -Mode ExtremePerformance

            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and
                $WindowStyle -eq 'Hidden' -and
                $Wait -and
                $PassThru -and
                $ArgumentList -contains '-NoProfile'
            }
        }
    }
}

Describe 'Lossless Scaling lifecycle' {
    InModuleScope MSIRuntimeXboxCompanion {
        It 'returns only the application process created after the launch snapshot' {
            $script:snapshotNumber = 0
            Mock Start-Process { }
            Mock Start-Sleep { }
            Mock Get-XboxLosslessScalingProcess {
                $script:snapshotNumber++
                if ($script:snapshotNumber -eq 1) {
                    [pscustomobject]@{ Id = 100; ProcessName = 'LosslessScaling'; StartTimeUtcTicks = 10 }
                }
                else {
                    @(
                        [pscustomobject]@{ Id = 100; ProcessName = 'LosslessScaling'; StartTimeUtcTicks = 10 },
                        [pscustomobject]@{ Id = 200; ProcessName = 'LosslessScaling'; StartTimeUtcTicks = 20 }
                    )
                }
            }

            $existing = @{ 100 = $true }
            $result = @(Start-XboxLosslessScaling -Path 'C:\LosslessScaling.exe' -ExistingProcessIds $existing -DetectionTimeoutSeconds 1)

            $result.Count | Should Be 1
            $result[0].Id | Should Be 200
            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $FilePath -eq 'C:\LosslessScaling.exe' -and $ArgumentList -contains '-StartMinimized'
            }
        }

        It 'does not stop a reused PID whose start time no longer matches' {
            $current = [pscustomobject]@{
                Id = 200
                ProcessName = 'LosslessScaling'
                StartTime = [datetime]::new(2026, 9, 30, 12, 0, 0, [DateTimeKind]::Utc)
            }
            Mock Get-Process { $current }
            Mock Stop-Process { }
            Mock Start-Process { }
            Mock Write-Warning { }

            Stop-XboxLosslessScalingProcess -ProcessRecord @(
                [pscustomobject]@{ Id = 200; StartTimeUtcTicks = 1 }
            )

            Assert-MockCalled Stop-Process -Times 0 -Exactly -Scope It
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        }

        It 'uses the elevated helper when an owned instance cannot be stopped normally' {
            $startTime = [datetime]::new(2026, 9, 30, 12, 0, 0, [DateTimeKind]::Utc)
            $script:getProcessCount = 0
            Mock Get-Process {
                $script:getProcessCount++
                [pscustomobject]@{ Id = 200; ProcessName = 'LosslessScaling'; StartTime = $startTime }
            }
            Mock Stop-Process { throw 'Access denied' }
            Mock Test-Path { $true }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

            Stop-XboxLosslessScalingProcess -ProcessRecord @(
                [pscustomobject]@{ Id = 200; StartTimeUtcTicks = $startTime.Ticks }
            )

            Assert-MockCalled Start-Process -Times 1 -Exactly -Scope It -ParameterFilter {
                $Verb -eq 'RunAs' -and $Wait -and $PassThru -and
                $ArgumentList -contains '-ProcessId' -and
                $ArgumentList -contains '200'
            }
        }
    }
}
