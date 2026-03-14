param(
    [Parameter(Mandatory = $true)]
    [string]$Program,
    [int]$WaitSeconds = 6,
    [int]$TailLines = 200,
    [switch]$Clean
)

. (Join-Path $PSScriptRoot "common.ps1")

& (Join-Path $PSScriptRoot "build-rk3588.ps1") -Program $Program -Clean:$Clean
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot "deploy-rk3588.ps1") -Program $Program
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

& (Join-Path $PSScriptRoot "run-rk3588.ps1") -Program $Program
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Start-Sleep -Seconds $WaitSeconds
& (Join-Path $PSScriptRoot "fetch-log-rk3588.ps1") -Program $Program -TailLines $TailLines
