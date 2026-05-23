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

function Invoke-MsBuildOnce {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $properties = @()
    foreach ($property in $Config.project.msbuildProperties.PSObject.Properties) {
        $properties += "/p:{0}={1}" -f $property.Name, $property.Value
    }

    $targets = @()
    foreach ($targetName in $Config.project.msbuildTargets) {
        $targets += "/t:$targetName"
    }

    $command = 'call "{0}" {1} && "{2}" "{3}" {4} /nologo /verbosity:minimal {5}' -f `
        $Config.environment.vcVarsAll, `
        $Config.environment.vcArch, `
        $Config.environment.msbuildPath, `
        $Target.SolutionPath, `
        ($targets -join ' '), `
        ($properties -join ' ')

    return Invoke-LoggedProcess `
        -FilePath 'cmd.exe' `
        -Arguments @('/c', $command) `
        -WorkingDirectory $Target.ProjectRoot `
        -LogPath $LogPath
}

function Invoke-QmakeOnce {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    $buildDirectory = Ensure-Directory -Path $Target.BuildDirectory
    $qmakeArguments = @($Target.ProPath) + @($Config.project.qmakeArguments)
    $jomArguments = @($Config.project.jomArguments)

    $command = 'call "{0}" {1} && "{2}" {3} && "{4}" {5}' -f `
        $Config.environment.vcVarsAll, `
        $Config.environment.vcArch, `
        $Config.environment.qmakePath, `
        ($qmakeArguments -join ' '), `
        $Config.environment.jomPath, `
        ($jomArguments -join ' ')

    return Invoke-LoggedProcess `
        -FilePath 'cmd.exe' `
        -Arguments @('/c', $command) `
        -WorkingDirectory $buildDirectory `
        -LogPath $LogPath
}

function Start-BuildLoop {
    $ConfigPath = Resolve-ConfigReference -ScriptRoot $PSScriptRoot -ConfigPath $ConfigPath -Profile $Profile
    $config = Read-Config -ConfigPath $ConfigPath
    $environmentInfo = & "$PSScriptRoot\Initialize-BuildEnvironment.ps1" -ConfigPath $ConfigPath
    $target = & "$PSScriptRoot\Resolve-BuildTarget.ps1" -ConfigPath $ConfigPath -ProjectPath $ProjectPath

    Ensure-Directory -Path $target.BuildDirectory | Out-Null
    Ensure-Directory -Path $target.OutputDirectory | Out-Null
    Ensure-Directory -Path $target.TraceRoot | Out-Null

    $traceRoot = Ensure-Directory -Path (Join-Path -Path $target.TraceRoot -ChildPath (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $logsDirectory = Ensure-Directory -Path (Join-Path -Path $traceRoot -ChildPath 'logs')
    $reportJsonPath = Join-Path -Path $traceRoot -ChildPath $config.report.jsonReportFileName
    $reportMdPath = Join-Path -Path $traceRoot -ChildPath $config.report.reportFileName
    $qmManifestPath = Join-Path -Path $logsDirectory -ChildPath $config.report.qmManifestFileName

    Write-Log -Message ('resolved build target: {0}' -f $target.BuildMode)

    $translationResult = & "$PSScriptRoot\Update-QtTranslations.ps1" `
        -ConfigPath $ConfigPath `
        -ProjectRoot $target.ProjectRoot `
        -OutputDirectory $target.OutputDirectory `
        -ManifestPath $qmManifestPath

    $buildLogPath = Join-Path -Path $logsDirectory -ChildPath 'build.log'
    if ($target.BuildMode -eq 'msbuild') {
        $buildResult = Invoke-MsBuildOnce -Config $config -Target $target -LogPath $buildLogPath
    }
    else {
        $buildResult = Invoke-QmakeOnce -Config $config -Target $target -LogPath $buildLogPath
    }

    $report = [ordered]@{
        projectPath = $ProjectPath
        configPath = $ConfigPath
        buildMode = $target.BuildMode
        solutionPath = $target.SolutionPath
        proPath = $target.ProPath
        buildDirectory = $target.BuildDirectory
        outputDirectory = $target.OutputDirectory
        traceRoot = $traceRoot
        environment = $environmentInfo
        translation = $translationResult
        build = $buildResult
        success = ($buildResult.ExitCode -eq 0)
        generatedAt = (Get-Date).ToString('s')
    }

    Save-JsonFile -Path $reportJsonPath -InputObject $report

    $reportLines = @(
        '# Build Report',
        '',
        ('- ProjectPath: {0}' -f $ProjectPath),
        ('- BuildMode: {0}' -f $target.BuildMode),
        ('- Success: {0}' -f $report.success),
        ('- BuildLog: {0}' -f $buildLogPath),
        ('- JsonReport: {0}' -f $reportJsonPath)
    )
    if ($translationResult -and $translationResult.ManifestPath) {
        $reportLines += ('- QmManifest: {0}' -f $translationResult.ManifestPath)
    }

    [System.IO.File]::WriteAllText($reportMdPath, ($reportLines -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Log -Message ('build report generated: {0}' -f $reportMdPath)
    Write-Log -Message ('build json report generated: {0}' -f $reportJsonPath)

    if ($buildResult.ExitCode -ne 0) {
        throw ('build failed, see log: {0}' -f $buildLogPath)
    }

    return [pscustomobject]$report
}

Start-BuildLoop
