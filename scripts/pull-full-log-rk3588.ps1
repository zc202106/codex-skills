param(
    [Parameter(Mandatory = $true)]
    [string]$Program,
    [string]$OutputDir
)

. (Join-Path $PSScriptRoot "common.ps1")

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$config = Get-AutomationConfig
$programConfig = Get-ProgramConfig -Name $Program
$repoRoot = Get-RepoRoot

if (-not $OutputDir) {
    $OutputDir = Join-Path $repoRoot $config["repo"]["fullLogLocalDir"]
}

$logPath = Get-LatestRemoteLogPath -LogGlob $programConfig["remoteLogGlob"]
if (-not $logPath) {
    throw "No remote log matched: $($programConfig["remoteLogGlob"])"
}

Copy-RemoteFileToLocal -RemotePath $logPath -LocalDirectory $OutputDir
$localFilePath = Join-Path $OutputDir ([System.IO.Path]::GetFileName($logPath))
Write-Output "REMOTE_LOG:$logPath"
Write-Output "LOCAL_LOG:$localFilePath"
