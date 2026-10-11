# MSI Runtime Xbox Companion module for Windows PowerShell 5.1.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:ThermalHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private\Invoke-MsiModeElevated.ps1'
$script:LosslessScalingStopHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private\Stop-LosslessScalingElevated.ps1'
$script:SettingsDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'MSIRuntimeXboxCompanion'
$script:SettingsPath = Join-Path -Path $script:SettingsDirectory -ChildPath 'Settings.json'


function Get-DefaultXboxCompanionSetting {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        DefaultThermalProfile         = 'Balanced'
        UseCoolerBoost = $false
        UseLosslessScaling             = $true
        CloseLosslessScalingAfterGame  = $true
        LosslessScalingPathOverride    = ''
        GameStartTimeoutSeconds        = 300
        PollIntervalSeconds            = 2
        GameOverrides                  = [pscustomobject]@{}
    }
}

function Write-XboxCompanionSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
        New-Item -Path $script:SettingsDirectory -ItemType Directory -Force | Out-Null
    }

    $temporaryPath = Join-Path -Path $script:SettingsDirectory -ChildPath ("Settings.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path -Path $script:SettingsDirectory -ChildPath ("Settings.{0}.bak" -f [guid]::NewGuid().ToString('N'))
    try {
        $Setting | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        if (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $script:SettingsPath, $backupPath)
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $script:SettingsPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-NormalizedXboxCompanionSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if (-not $Setting.PSObject.Properties['UseCoolerBoost']) { $Setting | Add-Member -NotePropertyName UseCoolerBoost -NotePropertyValue $false }

    $validProfiles = @('EcoSilent', 'Balanced', 'ExtremePerformance')
    if ([string]$Setting.DefaultThermalProfile -notin $validProfiles) {
        throw 'DefaultThermalProfile must be EcoSilent, Balanced, or ExtremePerformance.'
    }

    foreach ($booleanName in @('UseCoolerBoost', 'UseLosslessScaling', 'CloseLosslessScalingAfterGame')) {
        $value = $Setting.$booleanName
        if ($value -is [bool]) { continue }
        $parsedBoolean = $false
        if ($value -is [string] -and [bool]::TryParse($value, [ref]$parsedBoolean)) {
            $Setting.$booleanName = $parsedBoolean
            continue
        }
        throw ("{0} must be true or false." -f $booleanName)
    }

    foreach ($range in @(
        @{ Name = 'GameStartTimeoutSeconds'; Minimum = 30; Maximum = 3600 },
        @{ Name = 'PollIntervalSeconds'; Minimum = 1; Maximum = 30 }
    )) {
        $parsedInteger = 0
        if (-not [int]::TryParse([string]$Setting.($range.Name), [ref]$parsedInteger) -or
            $parsedInteger -lt $range.Minimum -or $parsedInteger -gt $range.Maximum) {
            throw ("{0} must be an integer from {1} through {2}." -f $range.Name, $range.Minimum, $range.Maximum)
        }
        $Setting.($range.Name) = $parsedInteger
    }

    $Setting.LosslessScalingPathOverride = [string]$Setting.LosslessScalingPathOverride
    if ($null -eq $Setting.GameOverrides) {
        $Setting.GameOverrides = [pscustomobject]@{}
    }
    elseif ($Setting.GameOverrides -is [string] -or $Setting.GameOverrides -is [System.Array] -or
        $Setting.GameOverrides.GetType().IsValueType) {
        throw 'GameOverrides must be a JSON object.'
    }

    foreach ($property in @($Setting.GameOverrides.PSObject.Properties)) {
        $override = $property.Value
        if ($null -eq $override -or $override -is [string] -or $override -is [System.Array] -or
            $override.GetType().IsValueType) {
            throw ("GameOverrides.{0} must be a JSON object." -f $property.Name)
        }
        if ($override.PSObject.Properties['ThermalProfile'] -and
            [string]$override.ThermalProfile -notin $validProfiles) {
            throw ("GameOverrides.{0}.ThermalProfile must be EcoSilent, Balanced, or ExtremePerformance." -f $property.Name)
        }
        if ($override.PSObject.Properties['UseLosslessScaling']) {
            $overrideBoolean = $override.UseLosslessScaling
            if ($overrideBoolean -isnot [bool]) {
                $parsedOverrideBoolean = $false
                if ($overrideBoolean -is [string] -and [bool]::TryParse($overrideBoolean, [ref]$parsedOverrideBoolean)) {
                    $override.UseLosslessScaling = $parsedOverrideBoolean
                }
                else {
                    throw ("GameOverrides.{0}.UseLosslessScaling must be true or false." -f $property.Name)
                }
            }
        }
        if ($override.PSObject.Properties['UseCoolerBoost']) {
            $overrideBoolean = $override.UseCoolerBoost
            if ($overrideBoolean -isnot [bool]) {
                $parsedOverrideBoolean = $false
                if ($overrideBoolean -is [string] -and [bool]::TryParse($overrideBoolean, [ref]$parsedOverrideBoolean)) {
                    $override.UseCoolerBoost = $parsedOverrideBoolean
                }
                else {
                    throw ("GameOverrides.{0}.UseCoolerBoost must be true or false." -f $property.Name)
                }
            }
        }
        if ($override.PSObject.Properties['ProcessName']) {
            $normalizedProcessNames = [string[]]@(
                $override.ProcessName |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            if (@($normalizedProcessNames).Count -gt 0) {
                $override.ProcessName = $normalizedProcessNames
            }
            else {
                $override.PSObject.Properties.Remove('ProcessName')
            }
        }
        if (-not $override.PSObject.Properties['ThermalProfile'] -and
            -not $override.PSObject.Properties['UseCoolerBoost'] -and
            -not $override.PSObject.Properties['UseLosslessScaling'] -and
            -not $override.PSObject.Properties['ProcessName']) {
            throw ("GameOverrides.{0} must contain ThermalProfile, UseLosslessScaling, or ProcessName." -f $property.Name)
        }
    }

    return $Setting
}

function Get-XboxCompanionSetting {
    <#
    .SYNOPSIS
        Gets persistent Xbox companion settings.
    #>
    [CmdletBinding()]
    param()

    $defaults = Get-DefaultXboxCompanionSetting
    if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) {
        Write-XboxCompanionSetting -Setting $defaults
        return $defaults
    }

    try {
        $setting = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop

        foreach ($defaultProperty in $defaults.PSObject.Properties) {
            if (-not $setting.PSObject.Properties[$defaultProperty.Name]) {
                $setting | Add-Member -MemberType NoteProperty -Name $defaultProperty.Name -Value $defaultProperty.Value
            }
        }

        return ConvertTo-NormalizedXboxCompanionSetting -Setting $setting
    }
    catch {
        throw ("Unable to read Xbox companion settings at '{0}': {1}" -f $script:SettingsPath, $_.Exception.Message)
    }
}

function Set-XboxCompanionSetting {
    <#
    .SYNOPSIS
        Changes persistent Xbox companion settings.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('EcoSilent', 'Balanced', 'ExtremePerformance')]
        [string]$DefaultThermalProfile,
        [bool]$UseCoolerBoost,
        [bool]$UseLosslessScaling,
        [bool]$CloseLosslessScalingAfterGame,
        [string]$LosslessScalingPathOverride,
        [ValidateRange(30, 3600)]
        [int]$GameStartTimeoutSeconds,
        [ValidateRange(1, 30)]
        [int]$PollIntervalSeconds
    )

    $setting = Get-XboxCompanionSetting
    foreach ($propertyName in @('DefaultThermalProfile', 'UseCoolerBoost', 'UseLosslessScaling', 'CloseLosslessScalingAfterGame', 'LosslessScalingPathOverride', 'GameStartTimeoutSeconds', 'PollIntervalSeconds')) {
        if ($PSBoundParameters.ContainsKey($propertyName)) {
            $setting.$propertyName = $PSBoundParameters[$propertyName]
        }
    }
    Write-XboxCompanionSetting -Setting $setting
    Get-XboxCompanionSetting
}

function Get-XboxGameProfile {
    <#
    .SYNOPSIS
        Gets saved per-game Xbox profiles.

    .DESCRIPTION
        Returns saved thermal and process-name overrides from Settings.json.
        Supply an App ID to return one profile.
    #>
    [CmdletBinding()]
    param([string]$AppId)

    $setting = Get-XboxCompanionSetting
    $profiles = @(
        foreach ($property in @($setting.GameOverrides.PSObject.Properties)) {
            $value = $property.Value
            $profileProcessNames = [string[]]@()
            if ($value.PSObject.Properties['ProcessName']) {
                $profileProcessNames = [string[]]@($value.ProcessName)
            }
            [pscustomobject]@{
                AppId          = [string]$property.Name
                ThermalProfile      = if ($value.PSObject.Properties['ThermalProfile']) { [string]$value.ThermalProfile } else { $null }
                UseLosslessScaling  = if ($value.PSObject.Properties['UseLosslessScaling']) { [bool]$value.UseLosslessScaling } else { $null }
                UseCoolerBoost  = if ($value.PSObject.Properties['UseCoolerBoost']) { [bool]$value.UseCoolerBoost } else { $null }
                ProcessName          = $profileProcessNames
            }
        }
    )
    if ($AppId) { $profiles = @($profiles | Where-Object AppId -EQ $AppId) }
    $profiles | Sort-Object AppId
}

function Set-XboxGameProfile {
    <#
    .SYNOPSIS
        Creates or updates a saved profile for one Xbox game.

    .DESCRIPTION
        Stores a per-game thermal profile and optional process-name overrides. Only
        explicitly supplied properties are changed, so adding a process override does
        not replace an existing thermal profile.

    .PARAMETER AppId
        Stable Xbox package-family AppId to configure.

    .PARAMETER ThermalProfile
        Saved thermal profile: EcoSilent, Balanced, or ExtremePerformance.

    .PARAMETER ProcessName
        Optional process filename(s) used when the manifest LaunchExecutable is only a
        bootstrapper or otherwise unsuitable for session detection. Names may be supplied
        with or without the .exe extension.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [ValidateSet('EcoSilent', 'Balanced', 'ExtremePerformance')][string]$ThermalProfile,
        [Nullable[bool]]$UseCoolerBoost,
        [Nullable[bool]]$UseLosslessScaling,
        [string[]]$ProcessName
    )

    if (-not ($PSBoundParameters.ContainsKey('ThermalProfile') -or
        $PSBoundParameters.ContainsKey('UseCoolerBoost') -or
        $PSBoundParameters.ContainsKey('UseLosslessScaling') -or
        $PSBoundParameters.ContainsKey('ProcessName'))) {
        throw 'Specify at least one profile value: ThermalProfile, UseLosslessScaling, or ProcessName.'
    }

    $setting = Get-XboxCompanionSetting
    $existingProperty = $setting.GameOverrides.PSObject.Properties[$AppId]
    $profile = if ($existingProperty) { $existingProperty.Value } else { [pscustomobject]@{} }

    if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
        if ($profile.PSObject.Properties['ThermalProfile']) { $profile.ThermalProfile = $ThermalProfile }
        else { $profile | Add-Member -MemberType NoteProperty -Name ThermalProfile -Value $ThermalProfile }
    }
    if ($PSBoundParameters.ContainsKey('UseLosslessScaling')) {
        if ($profile.PSObject.Properties['UseLosslessScaling']) { $profile.UseLosslessScaling = [bool]$UseLosslessScaling }
        else { $profile | Add-Member -MemberType NoteProperty -Name UseLosslessScaling -Value ([bool]$UseLosslessScaling) }
    }
    if ($PSBoundParameters.ContainsKey('UseCoolerBoost')) {
        if ($profile.PSObject.Properties['UseCoolerBoost']) { $profile.UseCoolerBoost = [bool]$UseCoolerBoost }
        else { $profile | Add-Member -MemberType NoteProperty -Name UseCoolerBoost -Value ([bool]$UseCoolerBoost) }
    }
    if ($PSBoundParameters.ContainsKey('ProcessName')) {
        $normalizedProcessNames = [string[]]@(
            $ProcessName |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if (@($normalizedProcessNames).Count -gt 0) {
            if ($profile.PSObject.Properties['ProcessName']) { $profile.ProcessName = $normalizedProcessNames }
            else { $profile | Add-Member -MemberType NoteProperty -Name ProcessName -Value $normalizedProcessNames }
        }
        elseif ($profile.PSObject.Properties['ProcessName']) {
            $profile.PSObject.Properties.Remove('ProcessName')
        }
    }

    if (-not $profile.PSObject.Properties['ThermalProfile'] -and
        -not $profile.PSObject.Properties['UseCoolerBoost'] -and
        -not $profile.PSObject.Properties['UseLosslessScaling'] -and
        -not $profile.PSObject.Properties['ProcessName']) {
        throw 'A saved game profile must contain ThermalProfile, UseLosslessScaling, or at least one ProcessName.'
    }

    if ($existingProperty) { $setting.GameOverrides.$AppId = $profile }
    else { $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name $AppId -Value $profile }

    Write-XboxCompanionSetting -Setting $setting
    Get-XboxGameProfile -AppId $AppId
}

function Remove-XboxGameProfile {
    <#
    .SYNOPSIS
        Removes a saved per-game Xbox thermal profile.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$AppId)

    $setting = Get-XboxCompanionSetting
    if (-not $setting.GameOverrides.PSObject.Properties[$AppId]) { return }
    if ($PSCmdlet.ShouldProcess("Xbox App ID $AppId", 'Remove saved game profile')) {
        $setting.GameOverrides.PSObject.Properties.Remove($AppId)
        Write-XboxCompanionSetting -Setting $setting
    }
}

function Get-ResolvedXboxThermalProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Game,
        [string]$ExplicitThermalProfile,
        [bool]$HasExplicitThermalProfile
    )

    if ($HasExplicitThermalProfile) {
        return [pscustomobject]@{ ThermalProfile = $ExplicitThermalProfile; Source = 'Explicit' }
    }

    $setting = Get-XboxCompanionSetting
    $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$Game.AppId]
    if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) {
        return [pscustomobject]@{ ThermalProfile = [string]$overrideProperty.Value.ThermalProfile; Source = 'Game' }
    }

    [pscustomobject]@{ ThermalProfile = [string]$setting.DefaultThermalProfile; Source = 'Global' }
}

function Get-XboxObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        $DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($property -and $null -ne $property.Value) { return $property.Value }
    return $DefaultValue
}

function Get-XboxPackageFamilyName {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PackageFullName)

    if ($PackageFullName -notmatch '^(?<Name>.+)_(?<Version>\d+\.\d+\.\d+\.\d+)_[^_]+_[^_]*_(?<PublisherId>[^_]+)$') {
        throw "Xbox package full name has an unsupported format: $PackageFullName"
    }

    [pscustomobject]@{
        IdentityName      = [string]$Matches.Name
        PackageVersion   = [version]$Matches.Version
        PublisherId      = [string]$Matches.PublisherId
        PackageFamilyName = '{0}_{1}' -f $Matches.Name, $Matches.PublisherId
    }
}

function ConvertFrom-XboxGameRegistration {
    <#
    .SYNOPSIS
        Converts one Gaming Services registration into an installed-game object.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Registration,
        [switch]$IncludeMissingInstallPath
    )

    $packageFullName = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'PackageFullName' -DefaultValue '')
    $installPath = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'InstallPath' -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($packageFullName) -or [string]::IsNullOrWhiteSpace($installPath)) { return }

    if (-not $IncludeMissingInstallPath -and -not (Test-Path -LiteralPath $installPath -PathType Container)) { return }

    $identity = Get-XboxPackageFamilyName -PackageFullName $packageFullName
    $executables = @(
        @(Get-XboxObjectPropertyValue -InputObject $Registration -Name 'Executables' -DefaultValue @()) |
            Where-Object {
                $isDevOnly = [string](Get-XboxObjectPropertyValue -InputObject $_ -Name 'IsDevOnly' -DefaultValue '0')
                $targetDeviceFamily = [string](Get-XboxObjectPropertyValue -InputObject $_ -Name 'TargetDeviceFamily' -DefaultValue 'PC')
                $isDevOnly -notin @('1', 'True', 'true') -and $targetDeviceFamily -ieq 'PC'
            }
    )
    if ($executables.Count -eq 0) { return }

    [string[]]$launchExecutables = @(
        $executables |
            ForEach-Object { [string](Get-XboxObjectPropertyValue -InputObject $_ -Name 'Name' -DefaultValue '') } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )
    if ($launchExecutables.Count -eq 0) { return }

    [string[]]$launchPaths = @($launchExecutables | ForEach-Object { Join-Path -Path $installPath -ChildPath $_ })
    $launcherPath = Join-Path -Path $installPath -ChildPath 'GameLaunchHelper.exe'
    if (-not $IncludeMissingInstallPath -and -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) { return }

    $applicationId = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'ApplicationId' -DefaultValue '')
    $displayName = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'DisplayName' -DefaultValue $identity.IdentityName)
    if ([string]::IsNullOrWhiteSpace($displayName)) { $displayName = $identity.IdentityName }

    $aumid = $null
    if (-not [string]::IsNullOrWhiteSpace($applicationId)) {
        $aumid = '{0}!{1}' -f $identity.PackageFamilyName, $applicationId
    }

    [pscustomobject]@{
        Name               = $displayName
        AppId              = $identity.PackageFamilyName
        PackageFamilyName  = $identity.PackageFamilyName
        PackageFullName    = $packageFullName
        PackageVersion     = $identity.PackageVersion
        IdentityName       = $identity.IdentityName
        PublisherId        = $identity.PublisherId
        StoreId            = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'StoreId' -DefaultValue '')
        TitleId            = Get-XboxObjectPropertyValue -InputObject $Registration -Name 'TitleId'
        MSAAppId           = [string](Get-XboxObjectPropertyValue -InputObject $Registration -Name 'MSAAppId' -DefaultValue '')
        RequiresXboxLive   = Get-XboxObjectPropertyValue -InputObject $Registration -Name 'RequiresXboxLive'
        ApplicationId      = $applicationId
        AUMID              = $aumid
        InstallPath        = $installPath
        LauncherPath       = $launcherPath
        LaunchExecutable   = $launchExecutables[0]
        LaunchExecutables  = $launchExecutables
        LaunchPath         = $launchPaths[0]
        LaunchPaths        = $launchPaths
        Manifest           = Join-Path -Path $installPath -ChildPath 'MicrosoftGame.config'
        AppxManifest       = Join-Path -Path $installPath -ChildPath 'AppxManifest.xml'
    }
}

function Get-XboxGameRegistration {
    [CmdletBinding()]
    param(
        [string]$GameConfigPath = 'HKLM:\SOFTWARE\Microsoft\GamingServices\GameConfig',
        [string]$PackageRepositoryPath = 'HKLM:\SOFTWARE\Microsoft\GamingServices\PackageRepository\Root'
    )

    if (-not (Test-Path -LiteralPath $GameConfigPath -PathType Container)) { return }
    if (-not (Test-Path -LiteralPath $PackageRepositoryPath -PathType Container)) { return }

    $rootByPackage = @{}
    foreach ($rootKey in @(Get-ChildItem -LiteralPath $PackageRepositoryPath -Recurse -ErrorAction SilentlyContinue)) {
        $rootProperties = Get-ItemProperty -LiteralPath $rootKey.PSPath -ErrorAction SilentlyContinue
        if (-not $rootProperties) { continue }
        $packageName = [string](Get-XboxObjectPropertyValue -InputObject $rootProperties -Name 'Package' -DefaultValue '')
        $root = [string](Get-XboxObjectPropertyValue -InputObject $rootProperties -Name 'Root' -DefaultValue '')
        if ([string]::IsNullOrWhiteSpace($packageName) -or [string]::IsNullOrWhiteSpace($root)) { continue }
        $rootByPackage[$packageName] = ($root -replace '^\\\\\?\\', '').TrimEnd('\')
    }

    foreach ($gameKey in @(Get-ChildItem -LiteralPath $GameConfigPath -ErrorAction SilentlyContinue)) {
        $packageFullName = [string]$gameKey.PSChildName
        if (-not $rootByPackage.ContainsKey($packageFullName)) { continue }

        $values = Get-ItemProperty -LiteralPath $gameKey.PSPath -ErrorAction SilentlyContinue
        if (-not $values) { continue }

        $executablePath = Join-Path -Path $gameKey.PSPath -ChildPath 'Executable'
        $executables = @(
            if (Test-Path -LiteralPath $executablePath -PathType Container) {
                foreach ($executableKey in @(Get-ChildItem -LiteralPath $executablePath -ErrorAction SilentlyContinue | Sort-Object PSChildName)) {
                    Get-ItemProperty -LiteralPath $executableKey.PSPath -ErrorAction SilentlyContinue
                }
            }
        )
        if ($executables.Count -eq 0) { continue }

        $displayName = [string](Get-XboxObjectPropertyValue -InputObject $values -Name 'Name' -DefaultValue '')
        $shellVisualsPath = Join-Path -Path $gameKey.PSPath -ChildPath 'ShellVisuals'
        if (Test-Path -LiteralPath $shellVisualsPath -PathType Container) {
            $shellVisuals = Get-ItemProperty -LiteralPath $shellVisualsPath -ErrorAction SilentlyContinue
            if ($shellVisuals) {
                $displayName = [string](Get-XboxObjectPropertyValue -InputObject $shellVisuals -Name 'DefaultDisplayName' -DefaultValue $displayName)
            }
        }

        $installPath = [string]$rootByPackage[$packageFullName]
        $applicationId = ''
        $appxManifestPath = Join-Path -Path $installPath -ChildPath 'AppxManifest.xml'
        if (Test-Path -LiteralPath $appxManifestPath -PathType Leaf) {
            try {
                [xml]$appxManifest = Get-Content -LiteralPath $appxManifestPath -Raw -ErrorAction Stop
                $application = @($appxManifest.Package.Applications.Application | Where-Object {
                    [System.IO.Path]::GetFileName([string]$_.Executable) -ieq 'GameLaunchHelper.exe'
                } | Select-Object -First 1)
                if ($application.Count -gt 0) { $applicationId = [string]$application[0].Id }
            }
            catch {
                Write-Verbose ("Unable to read Xbox app manifest '{0}': {1}" -f $appxManifestPath, $_.Exception.Message)
            }
        }

        [pscustomobject]@{
            PackageFullName  = $packageFullName
            InstallPath      = $installPath
            DisplayName      = $displayName
            StoreId          = Get-XboxObjectPropertyValue -InputObject $values -Name 'StoreId' -DefaultValue ''
            TitleId          = Get-XboxObjectPropertyValue -InputObject $values -Name 'TitleId'
            MSAAppId         = Get-XboxObjectPropertyValue -InputObject $values -Name 'MSAAppId' -DefaultValue ''
            RequiresXboxLive = Get-XboxObjectPropertyValue -InputObject $values -Name 'RequiresXboxLive'
            ApplicationId    = $applicationId
            Executables      = $executables
        }
    }
}

function Get-XboxInstalledGame {
    <#
    .SYNOPSIS
        Gets games currently installed through Xbox or Microsoft Store.

    .DESCRIPTION
        Reads Gaming Services registration and package-repository records, then
        resolves each title's signed GameLaunchHelper and real session executable.

    .PARAMETER Name
        Filters results using a case-insensitive wildcard match against the game name.

    .PARAMETER AppId
        Filters results to one stable package-family identifier.

    .PARAMETER IncludeMissingInstallPath
        Includes manifest records whose InstallLocation no longer exists.

    .OUTPUTS
        PSCustomObject for each installed Xbox game.

    .EXAMPLE
        Get-XboxInstalledGame

    .EXAMPLE
        Get-XboxInstalledGame -Name 'Alan Wake'

    .EXAMPLE
        Get-XboxInstalledGame -AppId 'Fortnite'
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$AppId,
        [switch]$IncludeMissingInstallPath
    )

    $games = @(
        Get-XboxGameRegistration |
            ForEach-Object { ConvertFrom-XboxGameRegistration -Registration $_ -IncludeMissingInstallPath:$IncludeMissingInstallPath }
    )

    # Package family is stable across version updates. Prefer the newest usable
    # registration if Gaming Services temporarily retains more than one version.
    $games = @(
        $games |
            Group-Object AppId |
            ForEach-Object {
                $_.Group |
                    Sort-Object @{ Expression = { if (Test-Path -LiteralPath $_.LauncherPath -PathType Leaf) { 0 } else { 1 } } }, @{ Expression = 'PackageVersion'; Descending = $true } |
                    Select-Object -First 1
            }
    )

    if ($AppId) { $games = $games | Where-Object AppId -EQ $AppId }
    if ($Name) { $games = $games | Where-Object Name -Like "*$Name*" }

    $games | Sort-Object Name, AppId
}

function Get-XboxLosslessScalingFilter {
    <#
    .SYNOPSIS
        Gets executable filenames suitable for Lossless Scaling Xbox profiles.

    .DESCRIPTION
        Resolves exactly one installed Xbox game and converts its executable
        records from the Gaming Services registry into filename-only Lossless
        Scaling filters. No access to the protected game executable is required.

        Some packages register more than one executable. Each is returned as a
        separate object, with IsPrimary identifying the first executable selected
        by Gaming Services discovery.

    .PARAMETER Name
        Selects one installed Xbox game by display name. Wildcards are supported;
        the result must resolve to exactly one title.

    .PARAMETER AppId
        Selects one installed Xbox game by stable package-family identifier.

    .PARAMETER Game
        An installed-game object returned by Get-XboxInstalledGame.

    .PARAMETER PrimaryOnly
        Returns only the primary registered executable.

    .EXAMPLE
        Get-XboxLosslessScalingFilter -Name 'Palworld'

    .EXAMPLE
        Get-XboxLosslessScalingFilter -AppId 'Publisher.Game_abcdefghijklm' -PrimaryOnly
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [psobject]$Game,

        [switch]$PrimaryOnly
    )

    process {
        [object[]]$games = @(
            if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
                $Game
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
                Get-XboxInstalledGame -AppId $AppId
            }
            else {
                Get-XboxInstalledGame -Name $Name
            }
        )

        if (@($games).Count -eq 0) {
            throw 'No installed Xbox game matched the requested selection.'
        }
        if (@($games).Count -gt 1) {
            $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
            throw ("The selection matched more than one Xbox game: {0}. Use -AppId or a more specific -Name." -f $matchedNames)
        }

        $resolvedGame = $games[0]
        $source = 'GamingServicesRegistry'
        [object[]]$registeredExecutables = @()
        $savedProfile = Get-XboxGameProfile -AppId ([string]$resolvedGame.AppId) | Select-Object -First 1
        if ($savedProfile -and @($savedProfile.ProcessName).Count -gt 0) {
            $registeredExecutables = @($savedProfile.ProcessName)
            $source = 'GameProfileOverride'
        }
        elseif ($resolvedGame.PSObject.Properties['LaunchExecutables']) {
            $registeredExecutables = @($resolvedGame.LaunchExecutables)
        }
        elseif ($resolvedGame.PSObject.Properties['LaunchExecutable']) {
            $registeredExecutables = @($resolvedGame.LaunchExecutable)
        }

        [string[]]$executableNames = @(
            $registeredExecutables |
                ForEach-Object { [System.IO.Path]::GetFileName([string]$_) } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
                Select-Object -Unique
        )
        if ($executableNames.Count -eq 0) {
            throw ("Xbox game '{0}' does not have a registered executable suitable for Lossless Scaling." -f $resolvedGame.Name)
        }

        if ($PrimaryOnly) {
            $executableNames = [string[]]@($executableNames | Select-Object -First 1)
        }

        for ($index = 0; $index -lt $executableNames.Count; $index++) {
            [pscustomobject]@{
                GameName       = [string]$resolvedGame.Name
                AppId          = [string]$resolvedGame.AppId
                ExecutableName = [string]$executableNames[$index]
                IsPrimary      = ($index -eq 0)
                Source         = $source
            }
        }
    }
}

function Get-XboxProcessSnapshot {
    <#
    .SYNOPSIS
        Captures a lightweight Win32_Process snapshot.

    .DESCRIPTION
        Returns process identity, parent PID, executable path, command line, and
        creation time for launch tracing. Access to ExecutablePath or CommandLine
        can be denied for individual processes; those fields are left blank.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | ForEach-Object {
        $creationDate = $null
        if ($_.CreationDate) {
            try { $creationDate = [Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationDate) }
            catch { $creationDate = $null }
        }

        [pscustomobject]@{
            ProcessName     = [string]$_.Name
            ProcessId       = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            ExecutablePath  = [string]$_.ExecutablePath
            CommandLine     = [string]$_.CommandLine
            CreationTime    = $creationDate
        }
    }
}

function Test-XboxProcessIdentity {
    <#
    .SYNOPSIS
        Tests whether a PID still represents the originally detected process.

    .DESCRIPTION
        Windows can recycle a departed game's PID immediately. Session monitoring
        must validate the executable name and, when available, the original start
        time instead of treating any process with the same PID as the game.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$ProcessId,
        [Parameter(Mandatory)][string]$ProcessName,
        [long]$StartTimeUtcTicks = 0
    )

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $process) { return $false }

    $expectedProcessName = [System.IO.Path]::GetFileNameWithoutExtension($ProcessName)
    if ([string]$process.ProcessName -ine $expectedProcessName) { return $false }

    if ($StartTimeUtcTicks -gt 0) {
        try {
            if ([long]$process.StartTime.ToUniversalTime().Ticks -ne $StartTimeUtcTicks) {
                return $false
            }
        }
        catch {
            # If Windows temporarily denies StartTime, the matching PID and name
            # are safer to keep monitoring than to restore the thermal mode early.
        }
    }

    return $true
}

function Get-XboxCompanionSteamLibraryPath {
    [CmdletBinding()]
    param()

    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($registryPath in @('HKCU:\Software\Valve\Steam','HKLM:\Software\WOW6432Node\Valve\Steam','HKLM:\Software\Valve\Steam')) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $properties) { continue }
        foreach ($propertyName in @('SteamPath','InstallPath')) {
            $property = $properties.PSObject.Properties[$propertyName]
            if ($property -and (Test-Path -LiteralPath ([string]$property.Value) -PathType Container)) {
                $steamRoots.Add([string]$property.Value)
            }
        }
    }
    foreach ($defaultRoot in @((Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Steam'),(Join-Path -Path $env:ProgramFiles -ChildPath 'Steam'))) {
        if (Test-Path -LiteralPath $defaultRoot -PathType Container) { $steamRoots.Add($defaultRoot) }
    }
    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in ($steamRoots | Select-Object -Unique)) {
        $libraries.Add($steamRoot)
        $libraryFile = Join-Path -Path $steamRoot -ChildPath 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        foreach ($line in (Get-Content -LiteralPath $libraryFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*"path"\s+"(?<Path>.+)"\s*$') {
                $path = $Matches.Path -replace '\\\\','\'
                if (Test-Path -LiteralPath $path -PathType Container) { $libraries.Add($path) }
            }
        }
    }
    $libraries | Select-Object -Unique
}

function Get-XboxLosslessScalingPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if ($Setting.LosslessScalingPathOverride) {
        if (Test-Path -LiteralPath $Setting.LosslessScalingPathOverride -PathType Leaf) { return $Setting.LosslessScalingPathOverride }
        throw "The Lossless Scaling override does not exist: $($Setting.LosslessScalingPathOverride)"
    }
    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090'
    )) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($properties.DisplayIcon) {
            $path = ($properties.DisplayIcon -replace ',\d+$','').Trim('"')
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
    foreach ($library in (Get-XboxCompanionSteamLibraryPath)) {
        foreach ($fileName in @('LosslessScaling.exe','Lossless Scaling.exe')) {
            $candidate = Join-Path -Path $library -ChildPath "steamapps\common\Lossless Scaling\$fileName"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

function Get-XboxLosslessScalingProcess {
    [CmdletBinding()]
    param()

    $processes = @()
    foreach ($process in @(Get-Process -Name 'LosslessScaling' -ErrorAction SilentlyContinue)) {
        try {
            $processes += [pscustomobject]@{
                Id                    = [int]$process.Id
                ProcessName           = [string]$process.ProcessName
                StartTimeUtcTicks     = [long]$process.StartTime.ToUniversalTime().Ticks
            }
        }
        catch {
            Write-Warning ("Could not inspect Lossless Scaling PID {0}: {1}" -f $process.Id, $_.Exception.Message)
        }
    }
    @($processes)
}

function Start-XboxLosslessScaling {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$ExistingProcessIds,
        [ValidateRange(1, 60)][int]$DetectionTimeoutSeconds = 30
    )

    Start-Process -FilePath $Path -ArgumentList '-StartMinimized' -ErrorAction Stop | Out-Null
    $deadline = (Get-Date).AddSeconds($DetectionTimeoutSeconds)

    do {
        [object[]]$startedProcesses = @(
            Get-XboxLosslessScalingProcess |
                Where-Object { -not $ExistingProcessIds.ContainsKey([int]$_.Id) }
        )
        if (@($startedProcesses).Count -gt 0) {
            return $startedProcesses
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    throw "Lossless Scaling was started, but its application process was not detected within $DetectionTimeoutSeconds seconds."
}

function Stop-XboxLosslessScalingProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object[]]$ProcessRecord)

    foreach ($record in @($ProcessRecord)) {
        $processId = [int]$record.Id
        $expectedStartTimeUtcTicks = [long]$record.StartTimeUtcTicks
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($null -eq $process) { continue }

        try {
            $identityMatches = (
                [string]$process.ProcessName -ieq 'LosslessScaling' -and
                [long]$process.StartTime.ToUniversalTime().Ticks -eq $expectedStartTimeUtcTicks
            )
        }
        catch {
            Write-Warning ("Could not validate Lossless Scaling PID {0}; it will not be closed: {1}" -f $processId, $_.Exception.Message)
            continue
        }

        if (-not $identityMatches) {
            Write-Warning ("PID {0} no longer identifies the Lossless Scaling instance started by this session; it will not be closed." -f $processId)
            continue
        }

        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 250
        }
        catch {
            # StartAsAdmin prevents the unelevated companion from stopping the real
            # application process. The helper repeats the identity checks as admin.
        }

        if ($null -eq (Get-Process -Id $processId -ErrorAction SilentlyContinue)) { continue }

        if (-not (Test-Path -LiteralPath $script:LosslessScalingStopHelperPath -PathType Leaf)) {
            throw "Lossless Scaling cleanup helper was not found: $script:LosslessScalingStopHelperPath"
        }

        $helperProcess = Start-Process -FilePath $script:WindowsPowerShellPath -Verb RunAs -ArgumentList @(
            '-NoProfile',
            '-ExecutionPolicy', 'Bypass',
            '-File', ('"{0}"' -f $script:LosslessScalingStopHelperPath),
            '-ProcessId', ([string]$processId),
            '-StartTimeUtcTicks', ([string]$expectedStartTimeUtcTicks)
        ) -WindowStyle Hidden -Wait -PassThru

        if ($helperProcess.ExitCode -ne 0) {
            throw "The elevated Lossless Scaling cleanup helper failed for PID $processId. Exit code: $($helperProcess.ExitCode)"
        }
    }
}

function Set-ElevatedXboxMsiMode {
    <#
    .SYNOPSIS
        Applies one MSI controller mode from an elevated helper process.

    .DESCRIPTION
        Only the thermal-mode write is elevated. Xbox, Gaming Services, and the game
        continue to run in the original user context. This function is private to
        the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('EcoSilent', 'Balanced', 'ExtremePerformance')]
        [string]$Mode,
        [switch]$EnableCoolerBoost,
        [switch]$RestoreCoolerBoost,
        [string]$SessionStatePath
    )

    if (-not (Test-Path -LiteralPath $script:WindowsPowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell 5.1 was not found: $script:WindowsPowerShellPath"
    }

    if (-not (Test-Path -LiteralPath $script:ThermalHelperPath -PathType Leaf)) {
        throw "Thermal helper was not found: $script:ThermalHelperPath"
    }

    Write-Output ("Requesting {0} thermal mode..." -f $Mode)
    $helperArguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $script:ThermalHelperPath),'-Mode',$Mode)
    if ($EnableCoolerBoost) { $helperArguments += '-EnableCoolerBoost' }
    if ($RestoreCoolerBoost) { $helperArguments += '-RestoreCoolerBoost' }
    if ($SessionStatePath) { $helperArguments += @('-SessionStatePath',('"{0}"' -f $SessionStatePath)) }
    $process = Start-Process -FilePath $script:WindowsPowerShellPath -Verb RunAs -ArgumentList $helperArguments -WindowStyle Hidden -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "The elevated thermal helper failed to set $Mode mode. Exit code: $($process.ExitCode)"
    }
}

function Start-XboxRegisteredGame {
    <#
    .SYNOPSIS
        Starts an Xbox title through Microsoft's signed Game Launch Helper.

    .DESCRIPTION
        GameLaunchHelper preserves Gaming Services identity, licensing, cloud-save,
        and update behavior. The real game executable is never started directly.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Game)

    $launcherPath = [string]$Game.LauncherPath
    $installPath = [string]$Game.InstallPath
    if ([string]::IsNullOrWhiteSpace($launcherPath) -or
        -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw ("Xbox game '{0}' does not have a usable GameLaunchHelper: {1}" -f $Game.Name, $launcherPath)
    }
    if ([string]::IsNullOrWhiteSpace($installPath) -or
        -not (Test-Path -LiteralPath $installPath -PathType Container)) {
        throw ("Xbox game '{0}' does not have a usable install path: {1}" -f $Game.Name, $installPath)
    }

    $signature = Get-AuthenticodeSignature -LiteralPath $launcherPath -ErrorAction Stop
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        throw ("Xbox GameLaunchHelper signature is not valid for '{0}': {1}" -f $Game.Name, $signature.Status)
    }
    if (-not $signature.SignerCertificate -or
        [string]$signature.SignerCertificate.Subject -notlike 'CN=Microsoft Corporation,*') {
        throw ("Xbox GameLaunchHelper for '{0}' is not signed by Microsoft Corporation." -f $Game.Name)
    }

    Start-Process -FilePath $launcherPath -WorkingDirectory $installPath -PassThru -ErrorAction Stop
}

function Trace-XboxGameLaunch {
    <#
    .SYNOPSIS
        Launches one Xbox title and reports processes created by the launch.

    .DESCRIPTION
        Diagnostic command for learning Xbox launch behavior before session tracking
        is implemented. The command resolves exactly one installed Xbox game, takes
        a process snapshot, starts its signed GameLaunchHelper, then samples new
        processes during an observation window.

        No MSI thermal settings are changed.

        New processes are returned once, with simple hints showing whether the
        process matches the manifest LaunchExecutable or is descended from a process
        created during this trace.

    .PARAMETER Name
        Selects an installed Xbox game by display name. Wildcards are supported by
        Get-XboxInstalledGame. The result must resolve to exactly one title.

    .PARAMETER AppId
        Selects one installed Xbox game by its stable package-family identifier.

    .PARAMETER ObservationSeconds
        Number of seconds to observe for new processes after launch. Default: 20.

    .PARAMETER PollIntervalMilliseconds
        Delay between process snapshots. Default: 500 milliseconds.

    .PARAMETER PassThruGame
        Emits the resolved game object before process-trace results.

    .OUTPUTS
        PSCustomObject records describing processes first seen after launch.

    .EXAMPLE
        Trace-XboxGameLaunch -Name 'Fogpiercer'

    .EXAMPLE
        Trace-XboxGameLaunch -AppId 'HoodedHorse.Fogpiercer_znaey1dw2bdpr' -ObservationSeconds 30
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [ValidateRange(1, 300)]
        [int]$ObservationSeconds = 20,

        [ValidateRange(100, 5000)]
        [int]$PollIntervalMilliseconds = 500,

        [switch]$PassThruGame
    )

    [object[]]$games = @(
        if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
            Get-XboxInstalledGame -AppId $AppId
        }
        else {
            Get-XboxInstalledGame -Name $Name
        }
    )

    if (@($games).Count -eq 0) {
        throw 'No installed Xbox game matched the requested selection.'
    }

    if (@($games).Count -gt 1) {
        $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
        throw ("The selection matched more than one Xbox game: {0}. Use -AppId or a more specific -Name." -f $matchedNames)
    }

    $game = $games[0]
    if ([string]::IsNullOrWhiteSpace([string]$game.LauncherPath)) {
        throw ("Xbox game '{0}' does not have a GameLaunchHelper path." -f $game.Name)
    }

    $launchExecutableName = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$game.LaunchExecutable)) {
        $launchExecutableName = [System.IO.Path]::GetFileName([string]$game.LaunchExecutable)
    }

    Write-Output ("Tracing Xbox launch for: {0}" -f $game.Name)
    Write-Output ("Game Launch Helper: {0}" -f $game.LauncherPath)
    Write-Output ("Observation window: {0} seconds" -f $ObservationSeconds)
    Write-Output 'No MSI thermal settings will be changed.'

    $before = @(Get-XboxProcessSnapshot)
    $knownProcessIds = @{}
    foreach ($process in $before) {
        $knownProcessIds[[int]$process.ProcessId] = $true
    }

    if ($PassThruGame) {
        $game
    }

    $launcherProcess = Start-XboxRegisteredGame -Game $game
    $traceStart = Get-Date
    $deadline = $traceStart.AddSeconds($ObservationSeconds)
    $createdProcessIds = @{}

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $PollIntervalMilliseconds

        $snapshot = @(Get-XboxProcessSnapshot)
        foreach ($process in $snapshot) {
            $processId = [int]$process.ProcessId
            if ($knownProcessIds.ContainsKey($processId)) { continue }

            $knownProcessIds[$processId] = $true
            $createdProcessIds[$processId] = $true

            $matchType = 'NewProcess'
            if (-not [string]::IsNullOrWhiteSpace($launchExecutableName) -and
                [string]$process.ProcessName -ieq $launchExecutableName) {
                $matchType = 'ManifestLaunchExecutable'
            }
            elseif ($createdProcessIds.ContainsKey([int]$process.ParentProcessId)) {
                $matchType = 'ChildOfNewProcess'
            }

            [pscustomobject]@{
                GameName          = $game.Name
                AppId             = $game.AppId
                MatchType         = $matchType
                ProcessName       = $process.ProcessName
                ProcessId         = $process.ProcessId
                ParentProcessId   = $process.ParentProcessId
                LauncherProcessId = $launcherProcess.Id
                ExecutablePath    = $process.ExecutablePath
                CommandLine       = $process.CommandLine
                CreationTime      = $process.CreationTime
                SecondsAfterLaunch = [math]::Round(((Get-Date) - $traceStart).TotalSeconds, 2)
            }
        }
    }
}


function Start-XboxGameSession {
    <#
    .SYNOPSIS
        Launches and monitors one installed Xbox title.

    .DESCRIPTION
        Resolves exactly one installed Xbox game, snapshots any already-running
        instances of the registered executables, starts the signed GameLaunchHelper,
        and waits for a new matching process to appear.

        A newly detected process must remain alive for StabilitySeconds before it
        becomes the session process. Xbox launcher helpers, overlays,
        and unrelated processes are never adopted as the game session.

        Before launch, an optional EcoSilent, Balanced, or ExtremePerformance thermal profile
        is applied through a small elevated helper. Xbox and the game remain
        unelevated. After the session process is established, the command waits for
        that PID to exit and restores Balanced when a non-Balanced profile was
        applied. The completed session is returned as a summary object.

    .PARAMETER Name
        Selects an installed Xbox game by display name. Wildcards are supported by
        Get-XboxInstalledGame. The result must resolve to exactly one title.

    .PARAMETER Game
        An installed-game object returned by Get-XboxInstalledGame.

    .PARAMETER AppId
        Selects one installed Xbox game by its stable package-family identifier.

    .PARAMETER ThermalProfile
        Optional thermal profile override for this launch: EcoSilent, Balanced, or ExtremePerformance.
        TDProfile is provided as a shorter alias. When omitted, a saved per-game
        profile is used, then the global default, then Balanced.

    .PARAMETER ProcessName
        Optional one-session process filename override. When omitted, a saved per-game
        ProcessName override is used; otherwise the manifest LaunchExecutable is used.

    .PARAMETER LaunchTimeoutSeconds
        Maximum time to wait for a new game process after invoking Xbox.
        When omitted, uses the persisted GameStartTimeoutSeconds setting.

    .PARAMETER PollIntervalMilliseconds
        Optional one-session delay between process checks. When omitted, uses
        the persisted PollIntervalSeconds setting.

    .PARAMETER StabilitySeconds
        Time a candidate game PID must remain alive before launch is accepted.
        Default: 2 seconds.

    .OUTPUTS
        PSCustomObject describing the completed Xbox game session.

    .EXAMPLE
        Start-XboxGameSession -Name 'Fogpiercer' -ThermalProfile ExtremePerformance

    .EXAMPLE
        Start-XboxGameSession -AppId 'HoodedHorse.Fogpiercer_znaey1dw2bdpr' -LaunchTimeoutSeconds 90
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByObject')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByObject', ValueFromPipeline)]
        [psobject]$Game,

        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Alias('TDProfile')]
        [ValidateSet('EcoSilent', 'Balanced', 'ExtremePerformance')]
        [string]$ThermalProfile,

        [string[]]$ProcessName,

        [Nullable[bool]]$UseCoolerBoost,
        [Nullable[bool]]$UseLosslessScaling,

        [ValidateRange(5, 3600)]
        [int]$LaunchTimeoutSeconds,

        [ValidateRange(100, 5000)]
        [int]$PollIntervalMilliseconds,

        [ValidateRange(0, 10)]
        [int]$StabilitySeconds = 2
    )

    process {
        [object[]]$games = @(
            if ($PSCmdlet.ParameterSetName -eq 'ByObject') {
                $Game
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
                Get-XboxInstalledGame -AppId $AppId
            }
            else {
                Get-XboxInstalledGame -Name $Name
            }
        )

    if (@($games).Count -eq 0) {
        throw 'No installed Xbox game matched the requested selection.'
    }

    if (@($games).Count -gt 1) {
        $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
        throw ("The selection matched more than one Xbox game: {0}. Use -AppId or a more specific -Name." -f $matchedNames)
    }

    $game = $games[0]
    if ([string]::IsNullOrWhiteSpace([string]$game.LauncherPath)) {
        throw ("Xbox game '{0}' does not have a GameLaunchHelper path." -f $game.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$game.LaunchExecutable)) {
        throw ("Xbox game '{0}' does not define LaunchExecutable in its manifest." -f $game.Name)
    }

    [string[]]$manifestExecutableNames = @(
        if ($game.PSObject.Properties['LaunchExecutables']) {
            @($game.LaunchExecutables) | ForEach-Object { [System.IO.Path]::GetFileName([string]$_) }
        }
        else {
            [System.IO.Path]::GetFileName([string]$game.LaunchExecutable)
        }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($manifestExecutableNames.Count -eq 0) {
        throw ("Xbox game '{0}' has an invalid LaunchExecutable value: {1}" -f $game.Name, $game.LaunchExecutable)
    }

    $setting = Get-XboxCompanionSetting
    $effectiveLaunchTimeoutSeconds = if ($PSBoundParameters.ContainsKey('LaunchTimeoutSeconds')) { $LaunchTimeoutSeconds } else { [int]$setting.GameStartTimeoutSeconds }
    $effectivePollIntervalMilliseconds = if ($PSBoundParameters.ContainsKey('PollIntervalMilliseconds')) { $PollIntervalMilliseconds } else { [int]$setting.PollIntervalSeconds * 1000 }
    $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$game.AppId]
    $hasExplicitProcessName = $PSBoundParameters.ContainsKey('ProcessName')
    [string[]]$resolvedProcessNames = @(
        if ($hasExplicitProcessName) {
            $ProcessName
        }
        elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ProcessName'] -and $overrideProperty.Value.ProcessName) {
            $overrideProperty.Value.ProcessName
        }
        else {
            $manifestExecutableNames
        }
    ) | ForEach-Object {
        $name = [System.IO.Path]::GetFileName([string]$_)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            if ([System.IO.Path]::GetExtension($name)) { $name } else { "$name.exe" }
        }
    }
    $resolvedProcessNames = [string[]]@($resolvedProcessNames | Select-Object -Unique)
    if (@($resolvedProcessNames).Count -eq 0) {
        throw ("Xbox game '{0}' does not have a usable session process name." -f $game.Name)
    }
    $processNameSource = if ($hasExplicitProcessName) { 'Explicit' } elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ProcessName'] -and $overrideProperty.Value.ProcessName) { 'Game' } else { 'Manifest' }

    $hasExplicitThermalProfile = $PSBoundParameters.ContainsKey('ThermalProfile')
    $resolvedProfile = Get-ResolvedXboxThermalProfile -Game $game -ExplicitThermalProfile $ThermalProfile -HasExplicitThermalProfile $hasExplicitThermalProfile
    $effectiveThermalProfile = [string]$resolvedProfile.ThermalProfile
    $thermalProfileSource = [string]$resolvedProfile.Source

    $hasExplicitLosslessScaling = $PSBoundParameters.ContainsKey('UseLosslessScaling')
    if ($hasExplicitLosslessScaling) {
        $effectiveUseLosslessScaling = [bool]$UseLosslessScaling
        $losslessScalingSource = 'Explicit'
    }
    elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) {
        $effectiveUseLosslessScaling = [bool]$overrideProperty.Value.UseLosslessScaling
        $losslessScalingSource = 'Game'
    }
    else {
        $effectiveUseLosslessScaling = [bool]$setting.UseLosslessScaling
        $losslessScalingSource = 'Global'
    }

    # Capture only existing instances of the expected manifest executable. A process
    # that existed before this command can never become this launch session's anchor.
    $existingProcessIds = @{}
    foreach ($process in @(Get-XboxProcessSnapshot)) {
        if (@($resolvedProcessNames | Where-Object { [string]$process.ProcessName -ieq $_ }).Count -gt 0) {
            $existingProcessIds[[int]$process.ProcessId] = $true
        }
    }

    Write-Output ("Thermal profile for this session: {0} ({1})" -f $effectiveThermalProfile, $thermalProfileSource)
    Write-Output ("Lossless Scaling for this session: {0} ({1})" -f $(if ($effectiveUseLosslessScaling) { 'On' } else { 'Off' }), $losslessScalingSource)
    Write-Output ("Launching Xbox game: {0}" -f $game.Name)
    Write-Output ("Session process: {0} ({1})" -f ($resolvedProcessNames -join ", "), $processNameSource)
    Write-Output ("Launch timeout: {0} seconds" -f $effectiveLaunchTimeoutSeconds)

    $sessionUseCoolerBoost = if ($PSBoundParameters.ContainsKey('UseCoolerBoost')) { [bool]$UseCoolerBoost }
        elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseCoolerBoost']) { [bool]$overrideProperty.Value.UseCoolerBoost }
        elseif ($setting.PSObject.Properties['UseCoolerBoost']) { [bool]$setting.UseCoolerBoost } else { $false }
    $boostStatePath = $null
    if ($sessionUseCoolerBoost) { $boostStatePath = Join-Path ([IO.Path]::GetTempPath()) ('MSIRuntime-Boost-' + [guid]::NewGuid().ToString('N') + '.json') }
    $thermalModeChanged = $false
    $losslessScalingWasRunning = $false
    [object[]]$losslessScalingStartedProcesses = @()
    $sessionResult = $null

    try {
        Write-Output ("Cooler Boost for this session: {0}" -f $(if ($sessionUseCoolerBoost) { 'On' } else { 'Unchanged' }))
        if ($sessionUseCoolerBoost) { Set-ElevatedXboxMsiMode -Mode $effectiveThermalProfile -EnableCoolerBoost -SessionStatePath $boostStatePath }
        else { Set-ElevatedXboxMsiMode -Mode $effectiveThermalProfile }
        $thermalModeChanged = ($effectiveThermalProfile -ne 'Balanced' -or $sessionUseCoolerBoost)

        if ($effectiveUseLosslessScaling) {
            [object[]]$existingLosslessScalingProcesses = @(Get-XboxLosslessScalingProcess)
            $losslessScalingWasRunning = @($existingLosslessScalingProcesses).Count -gt 0
            if (-not $losslessScalingWasRunning) {
                $losslessScalingPath = Get-XboxLosslessScalingPath -Setting $setting
                if (-not $losslessScalingPath) { throw 'Lossless Scaling could not be located.' }
                Write-Output ("Starting Lossless Scaling: {0}" -f $losslessScalingPath)
                $existingLosslessScalingProcessIds = @{}
                foreach ($process in $existingLosslessScalingProcesses) {
                    $existingLosslessScalingProcessIds[[int]$process.Id] = $true
                }
                $losslessScalingStartedProcesses = @(Start-XboxLosslessScaling -Path $losslessScalingPath -ExistingProcessIds $existingLosslessScalingProcessIds)
            }
            else {
                Write-Output 'Lossless Scaling is already running.'
            }
        }
        else {
            Write-Output 'Lossless Scaling is disabled for this launch.'
        }

        $launchRequestedAt = Get-Date
        $launcherProcess = Start-XboxRegisteredGame -Game $game

        $deadline = $launchRequestedAt.AddSeconds($effectiveLaunchTimeoutSeconds)
        $rejectedCandidateIds = @{}
        $sessionProcess = $null

        while ((Get-Date) -lt $deadline -and $null -eq $sessionProcess) {
            Start-Sleep -Milliseconds $effectivePollIntervalMilliseconds

            $candidates = @(
                Get-XboxProcessSnapshot |
                    Where-Object {
                        [string]$_.ProcessName -in $resolvedProcessNames -and
                        -not $existingProcessIds.ContainsKey([int]$_.ProcessId) -and
                        -not $rejectedCandidateIds.ContainsKey([int]$_.ProcessId)
                    }
            )

            foreach ($candidate in $candidates) {
                $candidateId = [int]$candidate.ProcessId

                if ($StabilitySeconds -gt 0) {
                    Start-Sleep -Seconds $StabilitySeconds
                    $stillRunning = Get-Process -Id $candidateId -ErrorAction SilentlyContinue
                    if ($null -eq $stillRunning) {
                        $rejectedCandidateIds[$candidateId] = $true
                        continue
                    }
                }

                $sessionProcess = $candidate
                break
            }
        }

        if ($null -eq $sessionProcess) {
            throw ("Xbox accepted the launch request for '{0}', but no new session process ({1}) was detected within {2} seconds. The game may be updating, installing prerequisites, waiting for user interaction, or require a ProcessName override." -f $game.Name, ($resolvedProcessNames -join ', '), $effectiveLaunchTimeoutSeconds)
        }

        $sessionProcessId = [int]$sessionProcess.ProcessId
        $sessionProcessStartTimeUtcTicks = 0
        $detectedProcess = Get-Process -Id $sessionProcessId -ErrorAction SilentlyContinue
        if ($null -ne $detectedProcess) {
            try {
                $sessionProcessStartTimeUtcTicks = [long]$detectedProcess.StartTime.ToUniversalTime().Ticks
            }
            catch {
                $sessionProcessStartTimeUtcTicks = 0
            }
        }
        $sessionStartedAt = Get-Date
        $secondsToDetect = [math]::Round(($sessionStartedAt - $launchRequestedAt).TotalSeconds, 2)

        Write-Output ("Game session detected: {0} (PID {1}) after {2} seconds." -f $sessionProcess.ProcessName, $sessionProcessId, $secondsToDetect)
        Write-Output 'Monitoring game session. Close the game normally to complete this command.'

        while (Test-XboxProcessIdentity -ProcessId $sessionProcessId -ProcessName $sessionProcess.ProcessName -StartTimeUtcTicks $sessionProcessStartTimeUtcTicks) {
            Start-Sleep -Milliseconds $effectivePollIntervalMilliseconds
        }

        $processAtSessionEnd = Get-Process -Id $sessionProcessId -ErrorAction SilentlyContinue
        if ($null -ne $processAtSessionEnd) {
            Write-Output ("The original game PID {0} was reused by '{1}'; treating the game session as ended." -f $sessionProcessId, $processAtSessionEnd.ProcessName)
        }

        $sessionEndedAt = Get-Date
        $duration = $sessionEndedAt - $sessionStartedAt
        Write-Output ("Game session ended: {0} (PID {1})." -f $sessionProcess.ProcessName, $sessionProcessId)

        $sessionResult = [pscustomobject]@{
            GameName             = $game.Name
            AppId                = $game.AppId
            ThermalProfile       = $effectiveThermalProfile
            ThermalProfileSource = $thermalProfileSource
            UseLosslessScaling   = $effectiveUseLosslessScaling
            LosslessScalingSource = $losslessScalingSource
            ProcessName          = $sessionProcess.ProcessName
            ProcessNameSource    = $processNameSource
            ProcessId            = $sessionProcessId
            ExecutablePath       = $sessionProcess.ExecutablePath
            LauncherPath         = $game.LauncherPath
            LauncherProcessId    = $launcherProcess.Id
            AUMID                = $game.AUMID
            LaunchRequestedAt    = $launchRequestedAt
            SessionStartedAt     = $sessionStartedAt
            SessionEndedAt       = $sessionEndedAt
            SecondsToDetection   = $secondsToDetect
            Duration             = $duration
            DurationSeconds      = [math]::Round($duration.TotalSeconds, 2)
            LaunchTimeoutSeconds = $effectiveLaunchTimeoutSeconds
            StabilitySeconds     = $StabilitySeconds
        }
    }
    finally {
        if ($effectiveUseLosslessScaling -and $setting.CloseLosslessScalingAfterGame -and @($losslessScalingStartedProcesses).Count -gt 0 -and -not $losslessScalingWasRunning) {
            Write-Output 'Closing Lossless Scaling...'
            try {
                Stop-XboxLosslessScalingProcess -ProcessRecord $losslessScalingStartedProcesses
            }
            catch {
                Write-Warning ("Failed to close the Lossless Scaling instance started by this session: {0}" -f $_.Exception.Message)
            }
        }
        if ($thermalModeChanged) {
            try {
                if ($sessionUseCoolerBoost) { Set-ElevatedXboxMsiMode -Mode Balanced -RestoreCoolerBoost -SessionStatePath $boostStatePath }
            else { Set-ElevatedXboxMsiMode -Mode Balanced }
                Write-Output 'Balanced thermal mode restored.'
            }
            catch {
                Write-Warning ("Failed to restore Balanced mode: {0}" -f $_.Exception.Message)
            }
        }
    }

        if ($null -ne $sessionResult) {
            $sessionResult
        }
    }
}

function Select-XboxThermalProfile {
    [CmdletBinding()]
    param(
        [string]$Title = 'Select thermal profile',
        [switch]$AllowInherit
    )

    while ($true) {
        Write-Host ''
        Write-Host $Title
        Write-Host '  [1] EcoSilent'
        Write-Host '  [2] Balanced'
        Write-Host '  [3] ExtremePerformance'
        if ($AllowInherit) {
            Write-Host '  [4] Inherit global default (remove game override)'
        }
        Write-Host '  [B] Back'
        $selection = [string](Read-Host 'Selection')

        switch ($selection.Trim().ToUpperInvariant()) {
            '1' { return 'EcoSilent' }
            '2' { return 'Balanced' }
            '3' { return 'ExtremePerformance' }
            '4' { if ($AllowInherit) { return '__INHERIT__' } }
            'B' { return $null }
        }

        Write-Host 'Invalid selection.'
    }
}

function Get-XboxInteractiveLibrary {
    [CmdletBinding()]
    param()

    $setting = Get-XboxCompanionSetting
    $games = @(Get-XboxInstalledGame)
    @(
        foreach ($game in $games) {
            $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$game.AppId]
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) {
                $profile = [string]$overrideProperty.Value.ThermalProfile
                $thermalSource = 'Game'
            }
            else {
                $profile = [string]$setting.DefaultThermalProfile
                $thermalSource = 'Global'
            }
            $useLosslessScaling = if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { [bool]$overrideProperty.Value.UseLosslessScaling } else { [bool]$setting.UseLosslessScaling }
            $losslessScalingSource = if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { 'Game' } else { 'Global' }

            [pscustomobject]@{
                Name                 = [string]$game.Name
                AppId                = [string]$game.AppId
                EffectiveProfile     = $profile
                ProfileSource        = $thermalSource
                UseLosslessScaling   = $useLosslessScaling
                LosslessScalingSource = $losslessScalingSource
                LaunchExecutable     = [string]$game.LaunchExecutable
            }
        }
    ) | Sort-Object Name
}

function Start-XboxCompanion {
    <#
    .SYNOPSIS
        Opens the interactive Xbox Companion menu.
    #>
    [CmdletBinding()]
    param()

    [object[]]$games = @(Get-XboxInstalledGame)
    if (@($games).Count -eq 0) { throw 'No installed Xbox games were found.' }

    while ($true) {
        Clear-Host
        Write-Host '=== MSI Runtime Xbox Companion ==='
        Write-Host 'Type part of a game name to filter, A for all games, L for a Lossless Scaling executable, R to refresh, S for settings, or Q to quit.'
        $choice = Read-Host 'Selection'

        if ($choice -match '^(?i)q$') { return }
        if ($choice -match '^(?i)l$') {
            Clear-Host
            Write-Host '=== Lossless Scaling Executable Lookup ==='
            $filter = Read-Host 'Enter part of the game name'
            [object[]]$filterGames = @($games | Where-Object Name -Like "*$filter*")
            if (@($filterGames).Count -eq 0) {
                Read-Host 'No matching games. Press Enter to return' | Out-Null
                continue
            }

            for ($index = 0; $index -lt @($filterGames).Count; $index++) {
                Write-Host ('[{0}] {1} (App ID {2})' -f ($index + 1), $filterGames[$index].Name, $filterGames[$index].AppId)
            }

            $selectedNumber = 0
            $value = Read-Host 'Game number'
            if (-not [int]::TryParse($value, [ref]$selectedNumber) -or
                $selectedNumber -lt 1 -or $selectedNumber -gt @($filterGames).Count) {
                Write-Host 'Invalid selection.'
                Start-Sleep -Seconds 1
                continue
            }

            $selectedGame = $filterGames[$selectedNumber - 1]
            [object[]]$losslessScalingFilters = @(Get-XboxLosslessScalingFilter -Game $selectedGame)

            Write-Host ''
            Write-Host ('Lossless Scaling executable filter for {0}:' -f $selectedGame.Name)
            foreach ($losslessScalingFilter in $losslessScalingFilters) {
                $primaryLabel = if ($losslessScalingFilter.IsPrimary) { ' [Primary]' } else { '' }
                Write-Host ('  {0}{1}' -f $losslessScalingFilter.ExecutableName, $primaryLabel)
            }
            Write-Host ''
            Write-Host 'Type the filename only into the Lossless Scaling application/filter field.'
            Write-Host 'Do not browse into the protected Xbox game folder or select AppxManifest.xml.'
            Read-Host 'Press Enter to return' | Out-Null
            continue
        }
        if ($choice -match '^(?i)r$') {
            $games = @(Get-XboxInstalledGame)
            Write-Host ("Xbox library refreshed. {0} installed game(s) found." -f @($games).Count)
            Start-Sleep -Seconds 1
            continue
        }
        if ($choice -match '^(?i)s$') {
            $returnToMain = $false
            while (-not $returnToMain) {
                $setting = Get-XboxCompanionSetting
                Clear-Host
                Write-Host '=== Xbox Companion Settings ==='
                Write-Host "[1] Default thermal profile: $($setting.DefaultThermalProfile)"
                Write-Host "[2] Lossless Scaling enabled: $($setting.UseLosslessScaling)"
                Write-Host '[3] Configure a game profile'
                Write-Host '[4] View saved game profiles'
                Write-Host '[5] Remove a game profile'
                Write-Host '[6] Return'
                Write-Host ("[7] Cooler Boost with thermal sessions: {0}" -f $(if ($setting.UseCoolerBoost) { 'On' } else { 'Off' }))
                $settingsChoice = Read-Host 'Selection'

                switch ($settingsChoice) {
                    '7' { Set-XboxCompanionSetting -UseCoolerBoost (-not [bool]$setting.UseCoolerBoost) | Out-Null }
                    '1' {
                        Write-Host '[1] EcoSilent  [2] Balanced  [3] ExtremePerformance'
                        $profileChoice = Read-Host 'Default thermal profile'
                        $profile = switch ($profileChoice) { '1' {'EcoSilent'} '2' {'Balanced'} '3' {'ExtremePerformance'} default {$null} }
                        if ($profile) { Set-XboxCompanionSetting -DefaultThermalProfile $profile | Out-Null }
                    }
                    '2' { Set-XboxCompanionSetting -UseLosslessScaling (-not [bool]$setting.UseLosslessScaling) | Out-Null }
                    '3' {
                        $filter = Read-Host 'Enter part of the game name'
                        [object[]]$profileGames = @(Get-XboxInstalledGame -Name $filter)
                        if (@($profileGames).Count -eq 0) { Read-Host 'No matching games. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt @($profileGames).Count; $i++) { Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$profileGames[$i].Name,$profileGames[$i].AppId) }
                        $selection = 0
                        $value = Read-Host 'Game number'
                        if (-not [int]::TryParse($value,[ref]$selection) -or $selection -lt 1 -or $selection -gt @($profileGames).Count) { continue }
                        $selectedGame = $profileGames[$selection-1]
                        Write-Host '[1] EcoSilent  [2] Balanced  [3] ExtremePerformance'
                        $thermalChoice = Read-Host 'Thermal profile'
                        $thermal = switch ($thermalChoice) { '1' {'EcoSilent'} '2' {'Balanced'} '3' {'ExtremePerformance'} default {$null} }
                        if (-not $thermal) { continue }
                        $boostChoice = Read-Host 'Enable Cooler Boost with this thermal profile? (Y/N)'
                        $gameBoost = $boostChoice -match '^(?i)y$'
                        $lsChoice = Read-Host 'Use Lossless Scaling for this game? (Y/N)'
                        $gameLs = $lsChoice -match '^(?i)y$'
                        Set-XboxGameProfile -AppId $selectedGame.AppId -ThermalProfile $thermal -UseLosslessScaling $gameLs -UseCoolerBoost $gameBoost | Out-Null
                    }
                    '4' {
                        [object[]]$profiles = @(Get-XboxGameProfile)
                        if (@($profiles).Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        Clear-Host
                        Write-Host '=== Saved Xbox Game Profiles ==='
                        foreach ($profile in $profiles) {
                            $game = Get-XboxInstalledGame -AppId $profile.AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            Write-Host ('{0} (App ID {1})' -f $name,$profile.AppId)
                            Write-Host ('  Thermal profile: {0}' -f $(if ($profile.ThermalProfile) { $profile.ThermalProfile } else { '(inherits global default)' }))
                            $lsText = if ($null -eq $profile.UseLosslessScaling) { '(inherits global default)' } elseif ($profile.UseLosslessScaling) { 'On' } else { 'Off' }
                            $boostText = if (-not $profile.PSObject.Properties['UseCoolerBoost'] -or $null -eq $profile.UseCoolerBoost) { '(inherits global default)' } elseif ($profile.UseCoolerBoost) { 'On for session' } else { 'Unchanged' }
                            Write-Host ('  Cooler Boost: {0}' -f $boostText)
                            Write-Host ('  Lossless Scaling: {0}' -f $lsText)
                            if (@($profile.ProcessName).Count -gt 0) {
                                Write-Host ('  Process override: {0}' -f ($profile.ProcessName -join ', '))
                            }
                            Write-Host ''
                        }
                        Read-Host 'Press Enter to return' | Out-Null
                    }
                    '5' {
                        [object[]]$profiles = @(Get-XboxGameProfile)
                        if (@($profiles).Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt @($profiles).Count; $i++) {
                            $game = Get-XboxInstalledGame -AppId $profiles[$i].AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$name,$profiles[$i].AppId)
                        }
                        $selection = 0
                        $value = Read-Host 'Profile number to remove'
                        if ([int]::TryParse($value,[ref]$selection) -and $selection -ge 1 -and $selection -le @($profiles).Count) {
                            Remove-XboxGameProfile -AppId $profiles[$selection-1].AppId -Confirm:$false
                        }
                    }
                    '6' { $returnToMain = $true }
                }
            }
            continue
        }

        [object[]]$matches = @(if ($choice -match '^(?i)a$' -or [string]::IsNullOrWhiteSpace($choice)) { $games } else { $games | Where-Object Name -Like "*$choice*" })
        if (@($matches).Count -eq 0) { Write-Host 'No matching games found.'; Read-Host 'Press Enter to continue' | Out-Null; continue }

        $setting = Get-XboxCompanionSetting
        for ($index=0; $index -lt @($matches).Count; $index++) {
            $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$matches[$index].AppId]
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) { $thermalProfile = [string]$overrideProperty.Value.ThermalProfile; $thermalSource = 'Game' } else { $thermalProfile = [string]$setting.DefaultThermalProfile; $thermalSource = 'Global' }
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { $useLs = [bool]$overrideProperty.Value.UseLosslessScaling; $lsSource = 'Game' } else { $useLs = [bool]$setting.UseLosslessScaling; $lsSource = 'Global' }
            $sourceText = if ($thermalSource -eq 'Game' -and $lsSource -eq 'Game') { 'Saved profile' } elseif ($thermalSource -eq 'Global' -and $lsSource -eq 'Global') { 'Global defaults' } else { 'Mixed sources' }
            $lsText = if ($useLs) { 'On' } else { 'Off' }
            Write-Host ('[{0}] {1} (App ID {2}) [Thermal: {3} | Lossless Scaling: {4} | {5}]' -f ($index+1),$matches[$index].Name,$matches[$index].AppId,$thermalProfile,$lsText,$sourceText)
        }

        $number = Read-Host 'Enter game number or press Enter to search again'
        if ([string]::IsNullOrWhiteSpace($number)) { continue }
        $selectedNumber = 0
        if (-not [int]::TryParse($number,[ref]$selectedNumber) -or $selectedNumber -lt 1 -or $selectedNumber -gt @($matches).Count) { Write-Host 'Invalid selection.'; Start-Sleep 1; continue }

        $selectedGame = $matches[$selectedNumber-1]
        $selectedProfile = Get-ResolvedXboxThermalProfile -Game $selectedGame -HasExplicitThermalProfile $false
        $selectedOverride = $setting.GameOverrides.PSObject.Properties[[string]$selectedGame.AppId]
        if ($selectedOverride -and $selectedOverride.Value.PSObject.Properties['UseLosslessScaling']) { $selectedUseLs = [bool]$selectedOverride.Value.UseLosslessScaling; $selectedLsSource = 'Game' } else { $selectedUseLs = [bool]$setting.UseLosslessScaling; $selectedLsSource = 'Global' }
        $selectedLsText = if ($selectedUseLs) { 'On' } else { 'Off' }
        Write-Host ''
        Write-Host ('Selected profile for {0}:' -f $selectedGame.Name)
        Write-Host ('  Thermal profile: {0} ({1})' -f $selectedProfile.ThermalProfile,$selectedProfile.Source)
        $boostOverride = $setting.GameOverrides.PSObject.Properties[[string]$selectedGame.AppId]
        $selectedBoost = if ($boostOverride -and $boostOverride.Value.PSObject.Properties['UseCoolerBoost']) { [bool]$boostOverride.Value.UseCoolerBoost } else { [bool]$setting.UseCoolerBoost }
        Write-Host ('  Cooler Boost: {0}' -f $(if ($selectedBoost) { 'On for session' } else { 'Unchanged' }))
        Write-Host ('  Lossless Scaling: {0} ({1})' -f $selectedLsText,$selectedLsSource)
        Write-Host ''
        $cancelSession = $false
        while ($true) {
            $sessionAction = Read-Host 'B: toggle Cooler Boost for this session | Enter: launch | Q: cancel'
            if ([string]::IsNullOrWhiteSpace($sessionAction)) { break }
            if ($sessionAction -match '^(?i)q$') { $cancelSession = $true; break }
            if ($sessionAction -match '^(?i)b$') {
                $selectedBoost = -not $selectedBoost
                Write-Host ('  Cooler Boost: {0}' -f $(if ($selectedBoost) { 'On for session' } else { 'Unchanged' }))
            } else { Write-Host 'Choose B, Enter, or Q.' }
        }
        if ($cancelSession) { continue }
        Start-XboxGameSession -AppId $selectedGame.AppId -UseCoolerBoost $selectedBoost
        Read-Host 'Press Enter to return to the launcher' | Out-Null
    }
}

Export-ModuleMember -Function @(
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
