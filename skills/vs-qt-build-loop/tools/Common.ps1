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

function Read-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )

    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        throw "配置文件不存在: $ConfigPath"
    }

    return Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -Depth 20
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
