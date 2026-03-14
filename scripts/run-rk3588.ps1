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
    Stop-RemoteProgram -ProgramConfig $programConfig
} catch {
    Write-Host "Stop command returned non-zero, continue."
}
Start-Sleep -Seconds 2
Start-RemoteProgramDetached -ProgramName $Program -ProgramConfig $programConfig
Start-Sleep -Seconds 3
$processStatus = @(Get-RemoteProcessStatus -ProgramConfig $programConfig)
if ($processStatus.Count -eq 0) {
    Write-Host "Remote process not found after start."
} else {
    $processStatus | ForEach-Object { Write-Host $_ }
}
