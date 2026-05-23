[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [string]$Profile = '',

    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$ManifestPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\Common.ps1"

$ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
$config = Read-Config -ConfigPath $ConfigPath
if (-not $config.translations.enabled) {
    Write-Log -Message 'translation update disabled, skip.'
    return [pscustomobject]@{
        Updated = $false
        TsFiles = @()
        QmFiles = @()
        ManifestPath = $null
    }
}

$translationConfig = $config.translations
$searchRoot = if ([string]::IsNullOrWhiteSpace($translationConfig.tsSearchRoot)) { $ProjectRoot } else { $translationConfig.tsSearchRoot }
$tsFiles = @()
foreach ($pattern in $translationConfig.tsPatterns) {
    $tsFiles += Get-ChildItem -Path $searchRoot -Filter $pattern -File -Recurse
}
$tsFiles = $tsFiles | Sort-Object FullName -Unique

if ($tsFiles.Count -eq 0) {
    Write-Log -Level WARN -Message "no ts files found under: $searchRoot"
}

foreach ($target in $translationConfig.lupdateTargets) {
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Log -Level WARN -Message "lupdate target missing, skip: $target"
        continue
    }

    $lupdateCommand = 'call "{0}" {1} && "{2}" "{3}"' -f `
        $config.environment.vcVarsAll, `
        $config.environment.vcArch, `
        $config.environment.lupdatePath, `
        $target
    & cmd.exe /c $lupdateCommand | Out-Host
}

$qmFiles = @()
$copyTargets = @($translationConfig.copyTargets)
if ($OutputDirectory) {
    $copyTargets += $OutputDirectory
}
$copyTargets = $copyTargets | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

Ensure-Directory -Path $translationConfig.qmOutputDirectory | Out-Null

foreach ($tsFile in $tsFiles) {
    $qmFileName = [System.IO.Path]::GetFileNameWithoutExtension($tsFile.Name) + '.qm'
    $qmPath = Join-Path -Path $translationConfig.qmOutputDirectory -ChildPath $qmFileName
    & $config.environment.lreleasePath $tsFile.FullName -qm $qmPath | Out-Host
    $qmFiles += $qmPath

    foreach ($target in $copyTargets) {
        Ensure-Directory -Path $target | Out-Null
        $destinationPath = Join-Path -Path $target -ChildPath $qmFileName
        if ([System.StringComparer]::OrdinalIgnoreCase.Equals($qmPath, $destinationPath)) {
            continue
        }

        Copy-Item -LiteralPath $qmPath -Destination $destinationPath -Force
    }
}

$manifest = [pscustomobject]@{
    generatedAt = (Get-Date).ToString('s')
    tsFiles = @($tsFiles | ForEach-Object { $_.FullName })
    qmFiles = $qmFiles
    copyTargets = $copyTargets
}

if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
    $ManifestPath = Join-Path -Path $OutputDirectory -ChildPath $config.report.qmManifestFileName
}

Save-JsonFile -Path $ManifestPath -InputObject $manifest

[pscustomobject]@{
    Updated = $true
    TsFiles = @($tsFiles | ForEach-Object { $_.FullName })
    QmFiles = $qmFiles
    ManifestPath = $ManifestPath
}
