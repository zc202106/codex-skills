[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$config = Read-Config -ConfigPath $ConfigPath
$repro = $config.repro

if (-not $repro.enabled) {
    $result = [pscustomobject]@{
        Enabled = $false
        Mode = $null
        ScenarioName = $null
        Steps = @()
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

$steps = @()
foreach ($step in $repro.steps) {
    $steps += [pscustomobject]@{
        type = $step.type
        description = $step.description
        seconds = if ($step.PSObject.Properties.Name -contains 'seconds') { $step.seconds } else { $null }
    }
}

$result = [pscustomobject]@{
    Enabled = $true
    Mode = $repro.mode
    ScenarioName = $repro.scenarioName
    Steps = $steps
    Note = '当前为复现步骤框架；如需真实 GUI 自动操作，可继续扩展为 UIAutomation / WinAppDriver / AutoHotkey。'
}

Save-JsonFile -Path $OutputPath -InputObject $result
$result
