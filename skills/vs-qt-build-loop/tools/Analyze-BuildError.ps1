[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "日志文件不存在: $LogPath"
}

$content = Get-Content -LiteralPath $LogPath -Raw
$ruleMatches = @()

foreach ($rule in $config.repair.errorRules) {
    if ([string]::IsNullOrWhiteSpace($rule.pattern)) {
        continue
    }

    if ($content -match $rule.pattern) {
        $ruleMatches += [pscustomobject]@{
            Id = $rule.id
            Category = $rule.category
            Pattern = $rule.pattern
            AutoFix = $rule.autoFix
            CanAutoFix = -not [string]::IsNullOrWhiteSpace($rule.autoFix)
            Confidence = 'medium'
        }
    }
}

if ($ruleMatches.Count -eq 0) {
    [pscustomobject]@{
        ErrorCategory = 'unknown'
        Confidence = 'low'
        SuggestedFixes = @('需要人工分析日志，建议补充更详细日志或检查工程配置。')
        CanAutoFix = $false
        Matches = @()
    }
    return
}

$primary = $ruleMatches[0]
[pscustomobject]@{
    ErrorCategory = $primary.Category
    Confidence = $primary.Confidence
    SuggestedFixes = @($ruleMatches | ForEach-Object { $_.AutoFix } | Where-Object { $_ } | Select-Object -Unique)
    CanAutoFix = @($ruleMatches | Where-Object { $_.CanAutoFix }).Count -gt 0
    Matches = $ruleMatches
}
