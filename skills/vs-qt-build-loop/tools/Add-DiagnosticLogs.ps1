[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$IssueText,

    [string[]]$CandidateFiles = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$config = Read-Config -ConfigPath $ConfigPath
$uiDiagnostics = $config.uiDiagnostics

$selectedFiles = @($CandidateFiles)
if ($selectedFiles.Count -eq 0) {
    foreach ($rule in $uiDiagnostics.keywordRules) {
        $matched = $false
        foreach ($keyword in $rule.keywords) {
            if ($IssueText -match [regex]::Escape($keyword)) {
                $matched = $true
                break
            }
        }

        if ($matched) {
            $selectedFiles += @($rule.preferredFiles)
        }
    }
}

$selectedFiles = $selectedFiles | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

[pscustomobject]@{
    Enabled = [bool]$uiDiagnostics.enabled
    MarkerPrefix = $uiDiagnostics.markerPrefix
    LogFunction = $uiDiagnostics.logFunction
    IssueText = $IssueText
    SuggestedFiles = $selectedFiles
    SuggestedPoints = @(
        '事件入口',
        '状态变量变化',
        '条件分支',
        '信号/槽调用',
        '界面刷新结果'
    )
    Note = '该脚本负责输出候选诊断位置，主代理应根据实际问题把日志插入到对应代码位置。'
}
