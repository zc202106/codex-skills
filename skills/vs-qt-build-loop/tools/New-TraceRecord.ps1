[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TraceRoot,

    [Parameter(Mandatory = $true)]
    [int]$Attempt,

    [string[]]$FilesBefore = @(),

    [string]$Summary = '初始化追溯目录'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

Ensure-Directory -Path $TraceRoot | Out-Null

$traceDirectoryName = '{0}-{1:00}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $Attempt
$traceDirectory = Join-Path -Path $TraceRoot -ChildPath $traceDirectoryName
$beforeDirectory = Join-Path -Path $traceDirectory -ChildPath 'before'
$afterDirectory = Join-Path -Path $traceDirectory -ChildPath 'after'
$logsDirectory = Join-Path -Path $traceDirectory -ChildPath 'logs'

Ensure-Directory -Path $beforeDirectory | Out-Null
Ensure-Directory -Path $afterDirectory | Out-Null
Ensure-Directory -Path $logsDirectory | Out-Null

foreach ($file in $FilesBefore) {
    if (-not (Test-Path -LiteralPath $file)) {
        continue
    }

    $target = Join-Path -Path $beforeDirectory -ChildPath ([System.IO.Path]::GetFileName($file))
    Copy-Item -LiteralPath $file -Destination $target -Force
}

$context = @{
    attempt = $Attempt
    createdAt = (Get-Date).ToString('s')
    filesBefore = $FilesBefore
}

Save-JsonFile -Path (Join-Path -Path $traceDirectory -ChildPath 'context.json') -InputObject $context
[System.IO.File]::WriteAllText((Join-Path -Path $traceDirectory -ChildPath 'change-summary.md'), "# 变更摘要`r`n`r`n$Summary`r`n", [System.Text.UTF8Encoding]::new($false))

[pscustomobject]@{
    TraceDirectory = $traceDirectory
    BeforeDirectory = $beforeDirectory
    AfterDirectory = $afterDirectory
    LogsDirectory = $logsDirectory
}
