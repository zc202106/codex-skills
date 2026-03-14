param(
    [Parameter(Mandatory = $true)]
    [string]$Program
)

. (Join-Path $PSScriptRoot "common.ps1")

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$repoRoot = Get-RepoRoot
$programConfig = Get-ProgramConfig -Name $Program
$localBinaryPath = Join-Path $repoRoot $programConfig["binaryRelativePath"]

if (-not (Test-Path $localBinaryPath)) {
    throw "Build artifact not found: $localBinaryPath"
}

Invoke-RemoteCommand -Command "test -d $($programConfig["remoteWorkDir"]) || mkdir -p $($programConfig["remoteWorkDir"]) || true"
Copy-FileToBoard -LocalPath $localBinaryPath -RemotePath $programConfig["remoteBinaryPath"]
Invoke-RemoteCommand -Command "chmod +x $($programConfig["remoteBinaryPath"])"
