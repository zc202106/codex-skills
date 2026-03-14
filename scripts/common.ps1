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

function Invoke-ExternalProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 20,
        [switch]$AllowNonZeroExit
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            try {
                $process.Kill()
            } catch {
            }
            throw "Command timed out after ${TimeoutSeconds}s: $FilePath $($Arguments -join ' ')"
        }

        $stdoutLines = if (Test-Path $stdoutPath) { @(Get-Content $stdoutPath) } else { @() }
        $stderrLines = if (Test-Path $stderrPath) { @(Get-Content $stderrPath) } else { @() }
        $outputLines = @($stdoutLines + $stderrLines)

        if (-not $AllowNonZeroExit -and $process.ExitCode -ne 0) {
            $details = if ($outputLines.Count -gt 0) { "`n$($outputLines -join "`n")" } else { "" }
            throw "Command failed with exit code $($process.ExitCode): $FilePath $($Arguments -join ' ')$details"
        }

        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output = $outputLines
        }
    } finally {
        Remove-Item $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function ConvertTo-PosixSingleQuotedString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    return "'" + ($Value -replace "'", "'`"`'`"`'") + "'"
}

function Join-PosixCommandArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    return (($Arguments | ForEach-Object { ConvertTo-PosixSingleQuotedString -Value $_ }) -join " ")
}

function Get-RemoteProcessName {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    if ($ProgramConfig.ContainsKey("remoteBinaryPath") -and $ProgramConfig["remoteBinaryPath"]) {
        return [System.IO.Path]::GetFileName([string]$ProgramConfig["remoteBinaryPath"])
    }

    if ($ProgramConfig.ContainsKey("buildTarget") -and $ProgramConfig["buildTarget"]) {
        return [string]$ProgramConfig["buildTarget"]
    }

    throw "Failed to resolve remote process name from program config."
}

function Test-WslSshPass {
    $result = Invoke-ExternalProcess -FilePath "wsl.exe" -Arguments @("bash", "-lc", "command -v sshpass >/dev/null 2>&1") -TimeoutSeconds 5 -AllowNonZeroExit
    return ($result.ExitCode -eq 0)
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
    $quotedCommand = '"' + ($Command -replace '"', '\"') + '"'
    [void](Invoke-ExternalProcess -FilePath "wsl.exe" -Arguments @("bash", "-lc", $quotedCommand) -TimeoutSeconds 1200)
}

function Invoke-RemoteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $board = Get-BoardConfig
    $plink = Get-Command plink -ErrorAction SilentlyContinue
    if ($plink) {
        $result = Invoke-ExternalProcess -FilePath $plink.Source -Arguments @("-batch", "-pw", $board.password, "$($board.user)@$($board.host)", $Command) -TimeoutSeconds 20
        return $result.Output
    }

    if (Test-WslSshPass) {
        $escapedPassword = ConvertTo-PosixSingleQuotedString -Value $board.password
        $bashCommand = Join-PosixCommandArguments -Arguments @(
            "sshpass", "-e", "ssh", "-T",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=8",
            "-o", "ServerAliveInterval=5",
            "-o", "ServerAliveCountMax=1",
            "$($board.user)@$($board.host)",
            $Command
        )
        $quotedCommand = '"' + (("SSHPASS=$escapedPassword $bashCommand") -replace '"', '\"') + '"'
        $result = Invoke-ExternalProcess -FilePath "wsl.exe" -Arguments @("bash", "-lc", $quotedCommand) -TimeoutSeconds 20
        return $result.Output
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
        [void](Invoke-ExternalProcess -FilePath $pscp.Source -Arguments @("-batch", "-pw", $board.password, $LocalPath, "$($board.user)@$($board.host):$RemotePath") -TimeoutSeconds 60)
        return
    }

    if (Test-WslSshPass) {
        $localWslPath = Convert-WindowsPathToWsl -Path $LocalPath
        $escapedPassword = ConvertTo-PosixSingleQuotedString -Value $board.password
        $bashCommand = Join-PosixCommandArguments -Arguments @(
            "sshpass", "-e", "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=8",
            $localWslPath,
            "$($board.user)@$($board.host):$RemotePath"
        )
        $quotedCommand = '"' + (("SSHPASS=$escapedPassword $bashCommand") -replace '"', '\"') + '"'
        [void](Invoke-ExternalProcess -FilePath "wsl.exe" -Arguments @("bash", "-lc", $quotedCommand) -TimeoutSeconds 60)
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
    $firstLine = $output | Select-Object -First 1
    if ($null -eq $firstLine) {
        return ""
    }
    return ([string]$firstLine).Trim()
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
        [void](Invoke-ExternalProcess -FilePath $pscp.Source -Arguments @("-batch", "-pw", $board.password, "$($board.user)@$($board.host):$RemotePath", $LocalDirectory) -TimeoutSeconds 60)
        return
    }

    if (Test-WslSshPass) {
        $localWslDir = Convert-WindowsPathToWsl -Path $LocalDirectory
        $escapedPassword = ConvertTo-PosixSingleQuotedString -Value $board.password
        $bashCommand = Join-PosixCommandArguments -Arguments @(
            "sshpass", "-e", "scp",
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "LogLevel=ERROR",
            "-o", "ConnectTimeout=8",
            "$($board.user)@$($board.host):$RemotePath",
            $localWslDir
        )
        $quotedCommand = '"' + (("SSHPASS=$escapedPassword $bashCommand") -replace '"', '\"') + '"'
        [void](Invoke-ExternalProcess -FilePath "wsl.exe" -Arguments @("bash", "-lc", $quotedCommand) -TimeoutSeconds 60)
        return
    }

    throw "No file copy tool available."
}

function Stop-RemoteProgram {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    if (-not $ProgramConfig.ContainsKey("remoteStopCommand") -or -not $ProgramConfig["remoteStopCommand"]) {
        return
    }

    Invoke-RemoteCommand -Command $ProgramConfig["remoteStopCommand"]
}

function Start-RemoteProgramDetached {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProgramName,
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    $startCommand = [string]$ProgramConfig["remoteStartCommand"]
    if (-not $startCommand) {
        throw "Missing remoteStartCommand for $ProgramName"
    }

    $normalizedCommand = [regex]::Replace($startCommand.Trim(), "\s*&\s*$", "")
    $remoteLogPath = "/tmp/{0}-codex-start.log" -f $ProgramName
    $detachedCommand = "nohup sh -lc {0} </dev/null >{1} 2>&1 &" -f (ConvertTo-PosixSingleQuotedString -Value $normalizedCommand), $remoteLogPath
    Invoke-RemoteCommand -Command $detachedCommand
}

function Get-RemoteProcessStatus {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    $processName = Get-RemoteProcessName -ProgramConfig $ProgramConfig
    return Invoke-RemoteCommand -Command "ps -ef | grep -F $processName | grep -v grep || true"
}
