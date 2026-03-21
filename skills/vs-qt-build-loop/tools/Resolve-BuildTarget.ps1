[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$ProjectPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
$resolvedProjectPath = (Resolve-Path -LiteralPath $ProjectPath).Path

$solutionPath = $null
$proPath = $null

switch ([System.IO.Path]::GetExtension($resolvedProjectPath).ToLowerInvariant()) {
    '.sln' { $solutionPath = $resolvedProjectPath }
    '.pro' { $proPath = $resolvedProjectPath }
    default {
        if (Test-Path -LiteralPath $resolvedProjectPath -PathType Container) {
            $solutionPath = Get-ChildItem -LiteralPath $resolvedProjectPath -Filter *.sln -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
            if (-not $solutionPath) {
                $proPath = Get-ChildItem -LiteralPath $resolvedProjectPath -Filter *.pro -File -Recurse | Select-Object -First 1 -ExpandProperty FullName
            }
        }
    }
}

if (-not $solutionPath -and -not $proPath) {
    throw "未找到可识别的 .sln 或 .pro: $ProjectPath"
}

$buildMode = if ($solutionPath) { 'msbuild' } else { 'qmake' }
$anchorPath = if ($solutionPath) { $solutionPath } else { $proPath }
$projectRoot = Split-Path -Path $anchorPath -Parent
$traceRoot = Join-Path -Path $projectRoot -ChildPath $config.trace.directoryName

[pscustomobject]@{
    BuildMode = $buildMode
    SolutionPath = $solutionPath
    ProPath = $proPath
    ProjectRoot = $projectRoot
    BuildDirectory = $config.project.buildDirectory
    OutputDirectory = $config.project.outputDirectory
    TraceRoot = $traceRoot
}
