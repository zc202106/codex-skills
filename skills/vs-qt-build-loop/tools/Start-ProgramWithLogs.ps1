[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

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
    }
}

if (-not (Test-Path -LiteralPath $runtime.executablePath)) {
    throw "运行目标不存在: $($runtime.executablePath)"
}

Ensure-Directory -Path (Split-Path -Path $LogPath -Parent) | Out-Null
$stderrLogPath = '{0}.stderr.log' -f $LogPath

$argumentList = @($runtime.arguments)
$argumentLine = if ($argumentList.Count -gt 0) {
    ($argumentList | ForEach-Object {
        if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
    }) -join ' '
} else {
    ''
}

Write-Log -Message "启动程序: $($runtime.executablePath) $argumentLine"
$process = Start-Process -FilePath $runtime.executablePath `
    -ArgumentList $argumentLine `
    -WorkingDirectory $runtime.workingDirectory `
    -RedirectStandardOutput $LogPath `
    -RedirectStandardError $stderrLogPath `
    -PassThru

$uiAutomationResult = $null
if ($config.repro.enabled -and $config.repro.mode -eq 'ui-automation') {
    $uiAutomationSummaryPath = '{0}.ui-automation.json' -f $LogPath
    $uiAutomationResult = & "$PSScriptRoot\Invoke-UiAutomationScenario.ps1" `
        -ConfigPath $ConfigPath `
        -OutputPath $uiAutomationSummaryPath `
        -ProcessId $process.Id
}

$startupTimeout = [int]$runtime.startupTimeoutSeconds
$captureDuration = [int]$runtime.captureDurationSeconds
$timedOut = $false
$wasKilled = $false

Start-Sleep -Seconds $startupTimeout
if (-not $process.HasExited -and $runtime.stopAfterCapture) {
    Start-Sleep -Seconds $captureDuration
}

if (-not $process.HasExited -and $runtime.stopAfterCapture) {
    $process.Kill()
    $process.WaitForExit()
    $timedOut = $true
    $wasKilled = $true
}

if (-not $process.HasExited) {
    $process.WaitForExit()
}

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
    ExecutablePath = $runtime.executablePath
    WorkingDirectory = $runtime.workingDirectory
    UiAutomation = $uiAutomationResult
}
