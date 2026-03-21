[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
$environment = $config.environment

$requiredFiles = @(
    $environment.vcVarsAll,
    $environment.msbuildPath,
    $environment.qmakePath,
    $environment.lupdatePath,
    $environment.lreleasePath
)

foreach ($file in $requiredFiles) {
    if (-not [string]::IsNullOrWhiteSpace($file) -and -not (Test-Path -LiteralPath $file)) {
        throw "关键工具不存在: $file"
    }
}

if (-not [string]::IsNullOrWhiteSpace($environment.jomPath) -and -not (Test-Path -LiteralPath $environment.jomPath)) {
    Write-Log -Level WARN -Message "未找到 jom，可按需改用 nmake 或补齐路径: $($environment.jomPath)"
}

$qtBin = Join-Path -Path $environment.qtRoot -ChildPath 'bin'
if (-not (Test-Path -LiteralPath $qtBin)) {
    throw "Qt bin 目录不存在: $qtBin"
}

$env:Path = "$qtBin;$env:Path"
$env:QTDIR = $environment.qtRoot
$env:Qt5_DIR = $environment.qtRoot

$result = @{
    vcVarsAll = $environment.vcVarsAll
    vcArch = $environment.vcArch
    qtRoot = $environment.qtRoot
    msbuildPath = $environment.msbuildPath
    qmakePath = $environment.qmakePath
    jomPath = $environment.jomPath
    lupdatePath = $environment.lupdatePath
    lreleasePath = $environment.lreleasePath
    pathInjected = $qtBin
    note = 'PowerShell 无法直接持久注入 vcvarsall.bat 的完整环境；实际构建脚本会通过 cmd /c call vcvarsall.bat && command 的方式执行。'
  }

$result
