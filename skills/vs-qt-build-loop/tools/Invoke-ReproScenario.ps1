[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [int]$ProcessId = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
$repro = $config.repro

if (-not $repro.enabled) {
    $result = [pscustomobject]@{
        Enabled = $false
        Mode = $null
        ScenarioName = $null
        Executed = $false
        Success = $false
        ProcessId = $ProcessId
        Steps = @()
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

$steps = @()
foreach ($step in @($repro.steps)) {
    $steps += [pscustomobject]@{
        type = $step.type
        description = [string](Get-OptionalPropertyValue -InputObject $step -Name 'description' -DefaultValue '')
        seconds = Get-OptionalPropertyValue -InputObject $step -Name 'seconds' -DefaultValue $null
        enabled = [bool](Get-OptionalPropertyValue -InputObject $step -Name 'enabled' -DefaultValue $true)
    }
}

if ($repro.mode -ne 'ui-automation') {
    $result = [pscustomobject]@{
        Enabled = $true
        Mode = $repro.mode
        ScenarioName = $repro.scenarioName
        Executed = $false
        Success = $false
        ProcessId = $ProcessId
        Steps = $steps
        Note = '当前模式为 manual-assisted，仅输出步骤，不执行自动化。'
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

if ($ProcessId -le 0) {
    $result = [pscustomobject]@{
        Enabled = $true
        Mode = $repro.mode
        ScenarioName = $repro.scenarioName
        Executed = $false
        Success = $false
        ProcessId = $ProcessId
        Steps = $steps
        Note = '缺少 ProcessId，无法执行自动化复现。'
    }
    Save-JsonFile -Path $OutputPath -InputObject $result
    return $result
}

$uiAutomationResult = & "$PSScriptRoot\Invoke-UiAutomationScenario.ps1" `
    -ConfigPath $ConfigPath `
    -OutputPath $OutputPath `
    -ProcessId $ProcessId

$result = [pscustomobject]@{
    Enabled = $true
    Mode = $repro.mode
    ScenarioName = $repro.scenarioName
    Executed = [bool]$uiAutomationResult.Executed
    Success = [bool]$uiAutomationResult.Success
    ProcessId = $ProcessId
    Steps = $steps
    ActionSource = $uiAutomationResult.ActionSource
    Actions = $uiAutomationResult.Actions
    StoppedOnFailure = $uiAutomationResult.StoppedOnFailure
}

Save-JsonFile -Path $OutputPath -InputObject $result
$result
