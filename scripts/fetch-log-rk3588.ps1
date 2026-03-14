param(
    [Parameter(Mandatory = $true)]
    [string]$Program,
    [int]$TailLines = 200
)

. (Join-Path $PSScriptRoot "common.ps1")

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$programConfig = Get-ProgramConfig -Name $Program
$content = Get-LatestRemoteLogContent -LogGlob $programConfig["remoteLogGlob"] -TailLines $TailLines
$content
