param(
    [Parameter(Mandatory = $true)]
    [string]$Program,
    [int]$WaitSeconds = 6,
    [switch]$Clean
)

. (Join-Path $PSScriptRoot "common.ps1")

function Invoke-StepScript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    & $ScriptPath @Arguments
}

Invoke-StepScript -ScriptPath (Join-Path $PSScriptRoot "build-rk3588.ps1") -Arguments @{
    Program = $Program
    Clean = $Clean
}

Invoke-StepScript -ScriptPath (Join-Path $PSScriptRoot "deploy-rk3588.ps1") -Arguments @{
    Program = $Program
}

Invoke-StepScript -ScriptPath (Join-Path $PSScriptRoot "run-rk3588.ps1") -Arguments @{
    Program = $Program
}

Start-Sleep -Seconds $WaitSeconds
& (Join-Path $PSScriptRoot "pull-full-log-rk3588.ps1") -Program $Program
