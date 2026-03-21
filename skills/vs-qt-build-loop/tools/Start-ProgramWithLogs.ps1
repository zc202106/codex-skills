[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
$runtime = $config.runtime

if (-not $runtime.enabled) {
    return [pscustomobject]@{
        Enabled = $false
        Started = $false
        LogPath = $null
        ExitCode = $null
        WasKilled = $false
        TimedOut = $false
        Repro = $null
    }
}

$runtimeLaunch = Resolve-RuntimeLaunchConfig -Config $config

Ensure-Directory -Path (Split-Path -Path $LogPath -Parent) | Out-Null
$stderrLogPath = '{0}.stderr.log' -f $LogPath

$argumentList = @($runtimeLaunch.Arguments)
$argumentLine = if ($argumentList.Count -gt 0) {
    ($argumentList | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
    }) -join ' '
} else {
    ''
}

Write-Log -Message "启动程序: $($runtimeLaunch.ExecutablePath) $argumentLine"
$process = Start-Process -FilePath $runtimeLaunch.ExecutablePath `
    -ArgumentList $argumentLine `
    -WorkingDirectory $runtimeLaunch.WorkingDirectory `
    -RedirectStandardOutput $LogPath `
    -RedirectStandardError $stderrLogPath `
    -PassThru

$reproResult = $null
if ($config.repro.enabled) {
    $reproSummaryPath = '{0}.repro.json' -f $LogPath
    try {
        $reproResult = & "$PSScriptRoot\Invoke-ReproScenario.ps1" `
            -ConfigPath $ConfigPath `
            -OutputPath $reproSummaryPath `
            -ProcessId $process.Id
    } catch {
        $reproResult = [pscustomobject]@{
            Enabled = $true
            Mode = $config.repro.mode
            ScenarioName = $config.repro.scenarioName
            Executed = $false
            Success = $false
            ProcessId = $process.Id
            Steps = @()
            Note = "复现场景执行异常: $($_.Exception.Message)"
        }
        Save-JsonFile -Path $reproSummaryPath -InputObject $reproResult
        Write-Log -Level WARN -Message $reproResult.Note
    }
    if (Test-Path -LiteralPath $reproSummaryPath) {
        Copy-Item -LiteralPath $reproSummaryPath -Destination ('{0}.ui-automation.json' -f $LogPath) -Force
    }
}

$startupTimeout = [int]$runtime.startupTimeoutSeconds
$captureDuration = [int]$runtime.captureDurationSeconds
$timedOut = $false
$wasKilled = $false

# 轮询等待程序启动，最多等 startupTimeout 秒，进程提前退出则不再等待
$startDeadline = (Get-Date).AddSeconds($startupTimeout)
while (-not $process.HasExited -and (Get-Date) -lt $startDeadline) {
    Start-Sleep -Milliseconds 500
}

# 启动阶段结束后，再等 captureDuration 秒抓取日志
if (-not $process.HasExited -and $runtime.stopAfterCapture) {
    Start-Sleep -Seconds $captureDuration
}

if (-not $process.HasExited -and $runtime.stopAfterCapture) {
    $process.Kill()
    $timedOut = $true
    $wasKilled = $true
}

$process.WaitForExit()

if (Test-Path -LiteralPath $stderrLogPath) {
    $stderrContent = Get-Content -LiteralPath $stderrLogPath -Raw
    if (-not [string]::IsNullOrWhiteSpace($stderrContent)) {
        [System.IO.File]::AppendAllText($LogPath, "`r`n[stderr]`r`n$stderrContent", [System.Text.UTF8Encoding]::new($false))
    }
    Remove-Item -LiteralPath $stderrLogPath -Force -ErrorAction SilentlyContinue
}

[pscustomobject]@{
    Enabled = $true
    Started = $true
    LogPath = $LogPath
    ExitCode = $process.ExitCode
    WasKilled = $wasKilled
    TimedOut = $timedOut
    ExecutablePath = $runtimeLaunch.ExecutablePath
    WorkingDirectory = $runtimeLaunch.WorkingDirectory
    SearchDirectories = $runtimeLaunch.SearchDirectories
    Repro = $reproResult
}
