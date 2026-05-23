param(
    [Parameter(Mandatory = $true)]
    [string]$Program
)

. (Join-Path $PSScriptRoot "common.ps1")

function New-LfNormalizedTempFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath
    )

    $tempPath = [System.IO.Path]::GetTempFileName()
    $content = Get-Content -LiteralPath $SourcePath -Raw
    $content = $content -replace "`r`n", "`n"
    $content = $content -replace "`r", "`n"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tempPath, $content, $utf8NoBom)
    return $tempPath
}

function Resolve-LocalBinaryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    $configuredRelativePath = ""
    if ($ProgramConfig.ContainsKey("binaryRelativePath") -and $ProgramConfig["binaryRelativePath"]) {
        $configuredRelativePath = [string]$ProgramConfig["binaryRelativePath"]
        $normalizedRelativePath = $configuredRelativePath -replace "[/\\]", [System.IO.Path]::DirectorySeparatorChar
        $directCandidate = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $normalizedRelativePath))
        try {
            return (Get-Item -LiteralPath $directCandidate -ErrorAction Stop).FullName
        } catch {
        }
    }

    $binaryName = ""
    if ($ProgramConfig.ContainsKey("remoteBinaryPath") -and $ProgramConfig["remoteBinaryPath"]) {
        $binaryName = [System.IO.Path]::GetFileName([string]$ProgramConfig["remoteBinaryPath"])
    }
    if ((-not $binaryName) -and $ProgramConfig.ContainsKey("buildTarget") -and $ProgramConfig["buildTarget"]) {
        $binaryName = [string]$ProgramConfig["buildTarget"]
    }

    $searchRoots = @()
    if ($ProgramConfig.ContainsKey("buildDir") -and $ProgramConfig["buildDir"]) {
        $buildDir = [string]$ProgramConfig["buildDir"]
        $searchRoots += [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $buildDir))
        $searchRoots += [System.IO.Path]::GetFullPath((Join-Path (Join-Path $RepoRoot "SkyNode") $buildDir))
    }

    $searchRoots = @($searchRoots | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
    if ($binaryName -and $searchRoots.Count -gt 0) {
        $matches = @()
        foreach ($searchRoot in $searchRoots) {
            $matches += @(Get-ChildItem -LiteralPath $searchRoot -Recurse -File -Filter $binaryName -ErrorAction SilentlyContinue)
        }
        $uniqueMatches = @($matches | Select-Object -ExpandProperty FullName -Unique)
        if ($uniqueMatches.Count -eq 1) {
            Write-Host "Resolved build artifact by search: $($uniqueMatches[0])"
            return $uniqueMatches[0]
        }
        if ($uniqueMatches.Count -gt 1) {
            throw "Build artifact path ambiguous: binaryName=$binaryName matches=$($uniqueMatches -join '; ')"
        }
    }

    $searchRootsText = if ($searchRoots.Count -gt 0) { $searchRoots -join "; " } else { "(none)" }
    throw "Build artifact not found: configuredPath=$configuredRelativePath binaryName=$binaryName searchRoots=$searchRootsText"
}

function Resolve-LocalRuntimeScriptDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    if (-not $ProgramConfig.ContainsKey("runtimeScriptsRelativeDir") -or -not $ProgramConfig["runtimeScriptsRelativeDir"]) {
        return ""
    }

    $relativePath = [string]$ProgramConfig["runtimeScriptsRelativeDir"]
    $normalizedRelativePath = $relativePath -replace "[/\\]", [System.IO.Path]::DirectorySeparatorChar
    $fullPath = [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $normalizedRelativePath))
    if (-not (Test-Path -LiteralPath $fullPath)) {
        throw "Runtime script directory not found: $fullPath"
    }

    return $fullPath
}

function Sync-RemoteRuntimeScripts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,
        [Parameter(Mandatory = $true)]
        [hashtable]$ProgramConfig
    )

    $localScriptDir = Resolve-LocalRuntimeScriptDirectory -RepoRoot $RepoRoot -ProgramConfig $ProgramConfig
    if (-not $localScriptDir) {
        return
    }

    $remoteWorkDir = [string]$ProgramConfig["remoteWorkDir"]
    $scriptNames = @("start.sh", "stop.sh", "daemon.sh")
    foreach ($scriptName in $scriptNames) {
        $localScriptPath = Join-Path $localScriptDir $scriptName
        if (-not (Test-Path -LiteralPath $localScriptPath)) {
            throw "Runtime script not found: $localScriptPath"
        }

        $remoteScriptPath = "$remoteWorkDir/$scriptName"
        $tempScriptPath = New-LfNormalizedTempFile -SourcePath $localScriptPath
        try {
            Copy-FileToBoard -LocalPath $tempScriptPath -RemotePath $remoteScriptPath
        } finally {
            Remove-Item -LiteralPath $tempScriptPath -Force -ErrorAction SilentlyContinue
        }
    }

    $remoteScriptPaths = $scriptNames | ForEach-Object { "$remoteWorkDir/$_" }
    $chmodTargets = @($ProgramConfig["remoteBinaryPath"]) + $remoteScriptPaths
    Invoke-RemoteCommand -Command ("chmod +x " + ($chmodTargets -join " "))
}

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$repoRoot = Get-RepoRoot
$programConfig = Get-ProgramConfig -Name $Program
$localBinaryPath = Resolve-LocalBinaryPath -RepoRoot $repoRoot -ProgramConfig $programConfig
Write-Host "Local binary: $localBinaryPath"

try {
    Stop-RemoteProgram -ProgramConfig $programConfig
} catch {
    Write-Host "Stop command returned non-zero, continue."
}
Start-Sleep -Seconds 2
Invoke-RemoteCommand -Command "test -d $($programConfig["remoteWorkDir"]) || mkdir -p $($programConfig["remoteWorkDir"]) || true"
Copy-FileToBoard -LocalPath $localBinaryPath -RemotePath $programConfig["remoteBinaryPath"]
Sync-RemoteRuntimeScripts -RepoRoot $repoRoot -ProgramConfig $programConfig
Invoke-RemoteCommand -Command "chmod +x $($programConfig["remoteBinaryPath"])"
