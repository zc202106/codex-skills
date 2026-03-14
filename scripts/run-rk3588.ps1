param(
    [Parameter(Mandatory = $true)]
    [string]$Program
)

. (Join-Path $PSScriptRoot "common.ps1")

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$programConfig = Get-ProgramConfig -Name $Program

try {
    Invoke-RemoteCommand -Command $programConfig["remoteStopCommand"]
} catch {
    Write-Host "Stop command returned non-zero, continue."
}
Start-Sleep -Seconds 2
Invoke-RemoteCommand -Command $programConfig["remoteStartCommand"]
