[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[$timestamp][$Level] $Message"
}

function Resolve-ConfigReference {
    [CmdletBinding()]
    param(
        [string]$ScriptRoot = '',

        [string]$ConfigPath = '',

        [string]$Profile = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        if (-not (Test-Path -LiteralPath $ConfigPath)) {
            throw "配置文件不存在: $ConfigPath"
        }

        return (Resolve-Path -LiteralPath $ConfigPath).Path
    }

    $baseDirectory = if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
        Get-Location | Select-Object -ExpandProperty Path
    } else {
        Resolve-AbsolutePath -Path '..' -BaseDirectory $ScriptRoot
    }

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        $candidates += Join-Path -Path $baseDirectory -ChildPath ("config.{0}.local.json" -f $Profile)
        $candidates += Join-Path -Path $baseDirectory -ChildPath ("config.{0}.json" -f $Profile)
    } else {
        $candidates += Join-Path -Path $baseDirectory -ChildPath 'config.local.json'
        $candidates += Join-Path -Path $baseDirectory -ChildPath 'config.json'
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $message = if (-not [string]::IsNullOrWhiteSpace($Profile)) {
        "未找到 profile 对应的配置文件: $Profile。候选路径: $($candidates -join '; ')"
    } else {
        "未找到默认配置文件。候选路径: $($candidates -join '; ')"
    }
    throw $message
}

function Read-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "配置文件不存在: $ConfigPath"
    }

    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    $visited = @()
    $configData = Read-ConfigHashtable -ConfigPath $resolvedConfigPath -Visited $visited
    return Convert-ConfigDataToObject -InputObject $configData
}

function Read-ConfigHashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath,

        [string[]]$Visited = @()
    )

    $resolvedConfigPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    if ($Visited -contains $resolvedConfigPath) {
        throw "检测到循环配置继承: $resolvedConfigPath"
    }
    $nextVisited = @($Visited + $resolvedConfigPath)

    $configDirectory = Split-Path -Path $resolvedConfigPath -Parent
    $currentConfig = Get-Content -LiteralPath $resolvedConfigPath -Raw | ConvertFrom-Json -AsHashtable -Depth 100

    $mergedConfig = @{}
    $extendsValues = @()
    if ($currentConfig.ContainsKey('$extends')) {
        $extendsValues = @($currentConfig['$extends'])
        $currentConfig.Remove('$extends')
    }

    foreach ($extendsValue in $extendsValues) {
        if ([string]::IsNullOrWhiteSpace([string]$extendsValue)) {
            continue
        }

        $baseConfigPath = Resolve-AbsolutePath -Path ([string]$extendsValue) -BaseDirectory $configDirectory
        if (-not (Test-Path -LiteralPath $baseConfigPath)) {
            throw "继承的配置文件不存在: $baseConfigPath"
        }

        $baseConfig = Read-ConfigHashtable -ConfigPath $baseConfigPath -Visited $nextVisited
        $mergedConfig = Merge-ConfigData -Base $mergedConfig -Override $baseConfig
    }

    $mergedConfig = Merge-ConfigData -Base $mergedConfig -Override $currentConfig
    return $mergedConfig
}

function Merge-ConfigData {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Base,

        [AllowNull()]
        [object]$Override
    )

    if ($null -eq $Base) {
        return Copy-ConfigData -InputObject $Override
    }

    if ($null -eq $Override) {
        return Copy-ConfigData -InputObject $Base
    }

    if (($Base -is [System.Collections.IDictionary]) -and ($Override -is [System.Collections.IDictionary])) {
        $result = @{}
        foreach ($key in $Base.Keys) {
            $result[$key] = Copy-ConfigData -InputObject $Base[$key]
        }
        foreach ($key in $Override.Keys) {
            if ($result.ContainsKey($key)) {
                $result[$key] = Merge-ConfigData -Base $result[$key] -Override $Override[$key]
            } else {
                $result[$key] = Copy-ConfigData -InputObject $Override[$key]
            }
        }
        return $result
    }

    if (($Base -is [System.Collections.IList]) -and ($Override -is [System.Collections.IList])) {
        return @(foreach ($item in $Override) { Copy-ConfigData -InputObject $item })
    }

    return Copy-ConfigData -InputObject $Override
}

function Copy-ConfigData {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $copy = @{}
        foreach ($key in $InputObject.Keys) {
            $copy[$key] = Copy-ConfigData -InputObject $InputObject[$key]
        }
        return $copy
    }

    if (($InputObject -is [System.Collections.IList]) -and -not ($InputObject -is [string])) {
        return @(foreach ($item in $InputObject) { Copy-ConfigData -InputObject $item })
    }

    return $InputObject
}

function Convert-ConfigDataToObject {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = Convert-ConfigDataToObject -InputObject $InputObject[$key]
        }
        return [pscustomobject]$result
    }

    if (($InputObject -is [System.Collections.IList]) -and -not ($InputObject -is [string])) {
        return @(foreach ($item in $InputObject) { Convert-ConfigDataToObject -InputObject $item })
    }

    return $InputObject
}

function Ensure-Directory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    return (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-ProjectRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    if (Test-Path -LiteralPath $ProjectPath -PathType Container) {
        return (Resolve-Path -LiteralPath $ProjectPath).Path
    }

    return Split-Path -Path (Resolve-Path -LiteralPath $ProjectPath).Path -Parent
}

function Get-OptionalPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [AllowNull()]
        [object]$DefaultValue = $null
    )

    if ($null -eq $InputObject) {
        return $DefaultValue
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }

        return $DefaultValue
    }

    if ($InputObject.PSObject.Properties.Name -contains $Name) {
        return $InputObject.$Name
    }

    return $DefaultValue
}

function Resolve-ExistingPath {
    [CmdletBinding()]
    param(
        [string[]]$Candidates = @()
    )

    foreach ($candidate in @($Candidates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    return $null
}

function Resolve-RuntimeLaunchConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $runtime = $Config.runtime
    $project = $Config.project

    $configuredExecutablePath = [string](Get-OptionalPropertyValue -InputObject $runtime -Name 'executablePath' -DefaultValue '')
    $executableName = [string](Get-OptionalPropertyValue -InputObject $runtime -Name 'executableName' -DefaultValue '')

    $searchDirectories = @()
    $configuredSearchDirectories = @(Get-OptionalPropertyValue -InputObject $runtime -Name 'searchDirectories' -DefaultValue @())
    foreach ($directory in $configuredSearchDirectories + @($project.outputDirectory, $project.buildDirectory, $runtime.workingDirectory)) {
        if (-not [string]::IsNullOrWhiteSpace($directory)) {
            $searchDirectories += [string]$directory
        }
    }
    $searchDirectories = @($searchDirectories | Select-Object -Unique)

    $candidatePaths = @()
    if (-not [string]::IsNullOrWhiteSpace($configuredExecutablePath)) {
        $candidatePaths += $configuredExecutablePath
    }
    if (-not [string]::IsNullOrWhiteSpace($executableName)) {
        foreach ($directory in $searchDirectories) {
            $candidatePaths += Join-Path -Path $directory -ChildPath $executableName
        }
    }

    $resolvedExecutablePath = Resolve-ExistingPath -Candidates $candidatePaths

    if (-not $resolvedExecutablePath -and -not [string]::IsNullOrWhiteSpace($executableName)) {
        foreach ($directory in $searchDirectories) {
            if ([string]::IsNullOrWhiteSpace($directory) -or -not (Test-Path -LiteralPath $directory -PathType Container)) {
                continue
            }

            $match = Get-ChildItem -LiteralPath $directory -Filter $executableName -File -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1 -ExpandProperty FullName
            if ($match) {
                $resolvedExecutablePath = (Resolve-Path -LiteralPath $match).Path
                break
            }
        }
    }

    if (-not $resolvedExecutablePath) {
        $candidateText = if ($candidatePaths.Count -gt 0) {
            $candidatePaths -join '; '
        } else {
            '未提供 executablePath / executableName'
        }
        throw "运行目标不存在。候选路径: $candidateText"
    }

    $configuredWorkingDirectory = [string](Get-OptionalPropertyValue -InputObject $runtime -Name 'workingDirectory' -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($configuredWorkingDirectory) -and -not (Test-Path -LiteralPath $configuredWorkingDirectory -PathType Container)) {
        Write-Log -Level WARN -Message "workingDirectory 不存在，回退到 exe 目录: $configuredWorkingDirectory"
        $configuredWorkingDirectory = ''
    }

    $resolvedWorkingDirectory = if (-not [string]::IsNullOrWhiteSpace($configuredWorkingDirectory)) {
        (Resolve-Path -LiteralPath $configuredWorkingDirectory).Path
    } else {
        Split-Path -Path $resolvedExecutablePath -Parent
    }

    $arguments = @()
    foreach ($argument in @(Get-OptionalPropertyValue -InputObject $runtime -Name 'arguments' -DefaultValue @())) {
        if ($null -ne $argument) {
            $arguments += [string]$argument
        }
    }

    return [pscustomobject]@{
        ExecutablePath = $resolvedExecutablePath
        WorkingDirectory = $resolvedWorkingDirectory
        Arguments = $arguments
        SearchDirectories = $searchDirectories
        ConfiguredExecutablePath = $configuredExecutablePath
        ExecutableName = $executableName
    }
}

function Resolve-AbsolutePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string]$BaseDirectory = ''
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    if ([string]::IsNullOrWhiteSpace($BaseDirectory)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path -Path $BaseDirectory -ChildPath $Path))
}

function Test-PathUnderDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$DirectoryPath
    )

    $fullPath = Resolve-AbsolutePath -Path $Path
    $fullDirectoryPath = Resolve-AbsolutePath -Path $DirectoryPath
    if ([string]::IsNullOrWhiteSpace($fullDirectoryPath)) {
        return $false
    }

    if (-not $fullDirectoryPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
        $fullDirectoryPath = '{0}{1}' -f $fullDirectoryPath, [System.IO.Path]::DirectorySeparatorChar
    }

    return $fullPath.StartsWith($fullDirectoryPath, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-FileNameMatchesPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [string[]]$Patterns = @()
    )

    foreach ($pattern in @($Patterns)) {
        if (-not [string]::IsNullOrWhiteSpace($pattern) -and ($FileName -like $pattern)) {
            return $true
        }
    }

    return $false
}

function Resolve-ProjectConfigGuard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$Target
    )

    $guardConfig = Get-OptionalPropertyValue -InputObject $Config -Name 'projectGuard' -DefaultValue $null
    $enabled = [bool](Get-OptionalPropertyValue -InputObject $guardConfig -Name 'enabled' -DefaultValue $true)

    $includePatterns = @(
        Get-OptionalPropertyValue -InputObject $guardConfig -Name 'includePatterns' -DefaultValue @(
            '*.sln',
            '*.vcxproj',
            '*.vcxproj.filters',
            '*.props',
            '*.targets',
            '*.pro',
            '*.pri'
        )
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    $roots = @(
        Get-OptionalPropertyValue -InputObject $guardConfig -Name 'roots' -DefaultValue @($Target.ProjectRoot)
    )

    $resolvedRoots = @()
    foreach ($root in $roots) {
        if ([string]::IsNullOrWhiteSpace($root)) {
            continue
        }

        $resolvedRoot = Resolve-AbsolutePath -Path $root -BaseDirectory $Target.ProjectRoot
        if (Test-Path -LiteralPath $resolvedRoot) {
            $resolvedRoots += $resolvedRoot
        }
    }
    $resolvedRoots = @($resolvedRoots | Select-Object -Unique)

    $excludeDirectories = @(
        Get-OptionalPropertyValue -InputObject $guardConfig -Name 'excludeDirectories' -DefaultValue @('.git', '.vs')
    ) + @($Target.BuildDirectory, $Target.OutputDirectory, $Target.TraceRoot)

    $resolvedExcludeDirectories = @()
    foreach ($directory in $excludeDirectories) {
        if ([string]::IsNullOrWhiteSpace($directory)) {
            continue
        }

        $resolvedDirectory = Resolve-AbsolutePath -Path $directory -BaseDirectory $Target.ProjectRoot
        $resolvedExcludeDirectories += $resolvedDirectory
    }
    $resolvedExcludeDirectories = @($resolvedExcludeDirectories | Select-Object -Unique)

    return [pscustomobject]@{
        Enabled = $enabled
        Roots = $resolvedRoots
        IncludePatterns = $includePatterns
        ExcludeDirectories = $resolvedExcludeDirectories
    }
}

function Get-ProjectConfigSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Guard
    )

    $files = @{}

    foreach ($root in @($Guard.Roots)) {
        if ([string]::IsNullOrWhiteSpace($root) -or -not (Test-Path -LiteralPath $root)) {
            continue
        }

        $item = Get-Item -LiteralPath $root
        if ($item.PSIsContainer) {
            foreach ($pattern in @($Guard.IncludePatterns)) {
                $matches = Get-ChildItem -LiteralPath $root -Filter $pattern -File -Recurse -ErrorAction SilentlyContinue
                foreach ($match in $matches) {
                    $fullName = [System.IO.Path]::GetFullPath($match.FullName)
                    $isExcluded = $false
                    foreach ($excludeDirectory in @($Guard.ExcludeDirectories)) {
                        if (Test-PathUnderDirectory -Path $fullName -DirectoryPath $excludeDirectory) {
                            $isExcluded = $true
                            break
                        }
                    }

                    if (-not $isExcluded) {
                        $files[$fullName] = $fullName
                    }
                }
            }
        } elseif (Test-FileNameMatchesPattern -FileName $item.Name -Patterns $Guard.IncludePatterns) {
            $fullName = [System.IO.Path]::GetFullPath($item.FullName)
            $files[$fullName] = $fullName
        }
    }

    $snapshot = @()
    foreach ($path in @($files.Keys | Sort-Object)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }

        $fileInfo = Get-Item -LiteralPath $path
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        $snapshot += [pscustomobject]@{
            Path = $path
            Hash = $hash
            Length = [int64]$fileInfo.Length
            LastWriteTimeUtc = $fileInfo.LastWriteTimeUtc.ToString('o')
        }
    }

    return $snapshot
}

function Compare-ProjectConfigSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Before,

        [Parameter(Mandatory = $true)]
        [object[]]$After
    )

    $beforeMap = @{}
    foreach ($item in @($Before)) {
        $beforeMap[$item.Path] = $item
    }

    $afterMap = @{}
    foreach ($item in @($After)) {
        $afterMap[$item.Path] = $item
    }

    $changes = @()
    $allPaths = @($beforeMap.Keys + $afterMap.Keys | Sort-Object -Unique)
    foreach ($path in $allPaths) {
        $beforeItem = if ($beforeMap.ContainsKey($path)) { $beforeMap[$path] } else { $null }
        $afterItem = if ($afterMap.ContainsKey($path)) { $afterMap[$path] } else { $null }

        if ($null -eq $beforeItem) {
            $changes += [pscustomobject]@{
                Path = $path
                ChangeType = 'created'
                BeforeHash = $null
                AfterHash = $afterItem.Hash
            }
            continue
        }

        if ($null -eq $afterItem) {
            $changes += [pscustomobject]@{
                Path = $path
                ChangeType = 'deleted'
                BeforeHash = $beforeItem.Hash
                AfterHash = $null
            }
            continue
        }

        if ($beforeItem.Hash -ne $afterItem.Hash) {
            $changes += [pscustomobject]@{
                Path = $path
                ChangeType = 'modified'
                BeforeHash = $beforeItem.Hash
                AfterHash = $afterItem.Hash
            }
        }
    }

    return $changes
}

function Save-JsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$InputObject
    )

    $directory = Split-Path -Path $Path -Parent
    if ($directory) {
        Ensure-Directory -Path $directory | Out-Null
    }

    $json = $InputObject | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Copy-IfExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source)) {
        return $false
    }

    $parent = Split-Path -Path $Destination -Parent
    if ($parent) {
        Ensure-Directory -Path $parent | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    return $true
}

function Invoke-LoggedProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    Ensure-Directory -Path (Split-Path -Path $LogPath -Parent) | Out-Null
    $errorLogPath = '{0}.stderr.log' -f $LogPath

    $argumentLine = if ($Arguments.Count -gt 0) {
        ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
        }) -join ' '
    } else {
        ''
    }

    Write-Log -Message "执行命令: $FilePath $argumentLine"

    Push-Location -LiteralPath $WorkingDirectory
    try {
        & $FilePath @Arguments 1> $LogPath 2> $errorLogPath
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    Write-Log -Message "命令结束，退出码: $exitCode"

    if (Test-Path -LiteralPath $errorLogPath) {
        $stderrContent = Get-Content -LiteralPath $errorLogPath -Raw
        if (-not [string]::IsNullOrWhiteSpace($stderrContent)) {
            [System.IO.File]::AppendAllText($LogPath, "`r`n[stderr]`r`n$stderrContent", [System.Text.UTF8Encoding]::new($false))
        }

        try {
            Remove-Item -LiteralPath $errorLogPath -Force -ErrorAction Stop
        } catch {
            Write-Log -Level WARN -Message "清理 stderr 临时日志失败，保留文件: $errorLogPath"
        }
    }

    return @{
        ExitCode = $exitCode
        LogPath = $LogPath
        Command = "$FilePath $argumentLine".Trim()
    }
}
