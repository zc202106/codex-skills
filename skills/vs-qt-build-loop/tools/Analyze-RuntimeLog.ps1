[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath,

    [int]$ExitCode = 0,

    [bool]$TimedOut = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$config = Read-Config -ConfigPath $ConfigPath
$runtime = $config.runtime

if (-not (Test-Path -LiteralPath $LogPath)) {
    throw "运行日志不存在: $LogPath"
}

$content = Get-Content -LiteralPath $LogPath -Raw
$ruleMatches = @()

foreach ($rule in $runtime.errorRules) {
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

if ($TimedOut -and -not $runtime.treatAliveAfterCaptureAsSuccess) {
    $ruleMatches += [pscustomobject]@{
        Id = 'runtime-timeout'
        Category = 'runtime-timeout'
        Pattern = ''
        AutoFix = ''
        CanAutoFix = $false
        Confidence = 'medium'
    }
}

if ($ruleMatches.Count -eq 0 -and ($ExitCode -eq 0 -or ($TimedOut -and $runtime.treatAliveAfterCaptureAsSuccess))) {
    return [pscustomobject]@{
        RuntimeSuccess = $true
        ErrorCategory = $null
        Confidence = 'high'
        SuggestedFixes = @()
        CanAutoFix = $false
        Matches = @()
    }
}

$primary = if ($ruleMatches.Count -gt 0) { $ruleMatches[0] } else { $null }
[pscustomobject]@{
    RuntimeSuccess = $false
    ErrorCategory = if ($primary) { $primary.Category } else { 'runtime-nonzero-exit' }
    Confidence = if ($primary) { $primary.Confidence } else { 'medium' }
    SuggestedFixes = @($ruleMatches | ForEach-Object { $_.AutoFix } | Where-Object { $_ } | Select-Object -Unique)
    CanAutoFix = @($ruleMatches | Where-Object { $_.CanAutoFix }).Count -gt 0
    Matches = $ruleMatches
}
