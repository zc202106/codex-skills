Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$script:AutomationConfig = $null

function Get-RepoRoot {
    (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

function Get-ConfigPath {
    Join-Path $PSScriptRoot "automation-config.json"
}

function Get-LocalConfigPath {
    Join-Path $PSScriptRoot "automation-config.local.json"
}

function ConvertTo-Hashtable {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($null -eq $InputObject) {
        return $null
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[$key] = ConvertTo-Hashtable -InputObject $InputObject[$key]
        }
        return $result
    }

    if ($InputObject -is [psobject]) {
        $properties = @($InputObject.PSObject.Properties)
        if ($properties.Count -gt 0) {
            $result = @{}
            foreach ($property in $properties) {
                $result[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            return $result
        }
    }

    if (($InputObject -is [System.Collections.IEnumerable]) -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-Hashtable -InputObject $item)
        }
        return $items
    }

    return $InputObject
}

function Merge-Hashtable {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Base,
        [Parameter(Mandatory = $true)]
        [hashtable]$Override
    )

    foreach ($key in $Override.Keys) {
        if ($Base.ContainsKey($key) -and $Base[$key] -is [hashtable] -and $Override[$key] -is [hashtable]) {
            Merge-Hashtable -Base $Base[$key] -Override $Override[$key]
            continue
        }

        $Base[$key] = $Override[$key]
    }

    return $Base
}

function Read-ConfigFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "Config file not found: $Path"
    }

    $content = Get-Content $Path -Raw
    $jsonObject = ConvertFrom-Json $content
    return ConvertTo-Hashtable -InputObject $jsonObject
}

function Get-AutomationConfig {
    if ($script:AutomationConfig) {
        return $script:AutomationConfig
    }

    $config = Read-ConfigFile -Path (Get-ConfigPath)
    $localConfigPath = Get-LocalConfigPath
    if (Test-Path $localConfigPath) {
        $localConfig = Read-ConfigFile -Path $localConfigPath
        [void](Merge-Hashtable -Base $config -Override $localConfig)
    }

    $script:AutomationConfig = $config
    return $script:AutomationConfig
}

function Get-WslProjectPath {
    $config = Get-AutomationConfig
    $path = $config["repo"]["wslProjectPath"]
    if (-not $path) {
        throw "Missing repo.wslProjectPath. Set it in scripts/automation-config.local.json."
    }
    return $path
}

function Get-ToolchainConfig {
    $config = Get-AutomationConfig
    $toolchain = $config["toolchain"]
    $requiredKeys = @("wslDistro", "cCompiler", "cxxCompiler", "cmake")
    foreach ($key in $requiredKeys) {
        if (-not $toolchain[$key]) {
            throw "Missing toolchain.$key. Set it in scripts/automation-config.local.json."
        }
    }
    return $toolchain
}

function Get-BoardConfig {
    $config = Get-AutomationConfig
    $remote = $config["remote"]
    $requiredKeys = @("host", "user", "password")
    foreach ($key in $requiredKeys) {
        if (-not $remote[$key]) {
            throw "Missing remote.$key. Set it in scripts/automation-config.local.json."
        }
    }
    return $remote
}

function Get-ProgramNames {
    $config = Get-AutomationConfig
    return [string[]]$config["programs"].Keys
}

function Get-ProgramConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $config = Get-AutomationConfig
    if (-not $config["programs"].ContainsKey($Name)) {
        throw "Unknown program: $Name"
    }

    return $config["programs"][$Name]
}

function Test-WslSshPass {
    & wsl bash -c "command -v sshpass >/dev/null 2>&1"
    return ($LASTEXITCODE -eq 0)
}

function Convert-WindowsPathToWsl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $resolvedPath = (Resolve-Path $Path).Path
    $normalizedPath = $resolvedPath -replace "\\", "/"
    if ($normalizedPath -notmatch "^([A-Za-z]):/(.*)$") {
        throw "Failed to convert Windows path to WSL path: $resolvedPath"
    }

    $drive = $matches[1].ToLower()
    $rest = $matches[2]
    return "/mnt/$drive/$rest"
}

function Invoke-WslCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    Write-Host "WSL command:"
    Write-Host $Command
    & wsl bash -c $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL command failed."
    }
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $board = Get-BoardConfig
    $plink = Get-Command plink -ErrorAction SilentlyContinue
    if ($plink) {
        & $plink.Source -batch -pw $board.password "$($board.user)@$($board.host)" $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Remote command failed: $Command"
        }
        return
    }

    if (Test-WslSshPass) {
        & wsl sshpass -p $board.password ssh -o StrictHostKeyChecking=no "$($board.user)@$($board.host)" $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Remote command failed: $Command"
        }
        return
    }

    throw "No remote execution tool available."
}

function Copy-FileToBoard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalPath,
        [Parameter(Mandatory = $true)]
        [string]$RemotePath
    )

    $board = Get-BoardConfig
    $pscp = Get-Command pscp -ErrorAction SilentlyContinue
    if ($pscp) {
        & $pscp.Source -batch -pw $board.password $LocalPath "$($board.user)@$($board.host):$RemotePath"
        if ($LASTEXITCODE -ne 0) {
            throw "Upload failed: $LocalPath -> $RemotePath"
        }
        return
    }

    if (Test-WslSshPass) {
        $localWslPath = Convert-WindowsPathToWsl -Path $LocalPath
        & wsl sshpass -p $board.password scp -o StrictHostKeyChecking=no $localWslPath "$($board.user)@$($board.host):$RemotePath"
        if ($LASTEXITCODE -ne 0) {
            throw "Upload failed: $LocalPath -> $RemotePath"
        }
        return
    }

    throw "No file copy tool available."
}

function Get-LatestRemoteLogPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogGlob
    )

    $command = "ls -t $LogGlob 2>/dev/null | head -n 1"
    $output = Invoke-RemoteCommand -Command $command
    return ($output | Select-Object -First 1).Trim()
}

function Get-LatestRemoteLogContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogGlob,
        [int]$TailLines = 200
    )

    $safeTailLines = [Math]::Max(1, $TailLines)
    $logPath = Get-LatestRemoteLogPath -LogGlob $LogGlob
    if (-not $logPath) {
        return "__LOG_FILE__:NOT_FOUND"
    }

    $command = "echo __LOG_FILE__:$logPath && tail -n $safeTailLines $logPath"
    return Invoke-RemoteCommand -Command $command
}

function Copy-RemoteFileToLocal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemotePath,
        [Parameter(Mandatory = $true)]
        [string]$LocalDirectory
    )

    if (-not (Test-Path $LocalDirectory)) {
        New-Item -ItemType Directory -Force $LocalDirectory | Out-Null
    }

    $board = Get-BoardConfig
    $pscp = Get-Command pscp -ErrorAction SilentlyContinue
    if ($pscp) {
        & $pscp.Source -batch -pw $board.password "$($board.user)@$($board.host):$RemotePath" $LocalDirectory
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed: $RemotePath -> $LocalDirectory"
        }
        return
    }

    if (Test-WslSshPass) {
        $localWslDir = Convert-WindowsPathToWsl -Path $LocalDirectory
        & wsl sshpass -p $board.password scp -o StrictHostKeyChecking=no "$($board.user)@$($board.host):$RemotePath" $localWslDir
        if ($LASTEXITCODE -ne 0) {
            throw "Download failed: $RemotePath -> $LocalDirectory"
        }
        return
    }

    throw "No file copy tool available."
}
