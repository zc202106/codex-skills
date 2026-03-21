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

function Invoke-BuildOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [string]$LogPath
    )

    if ($Target.BuildMode -eq 'msbuild') {
        return Invoke-MsBuild -Config $Config -Target $Target -LogPath $LogPath
    }

    return Invoke-QmakeBuild -Config $Config -Target $Target -LogPath $LogPath
}

function Invoke-MsBuild {
    [CmdletBinding()]
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

    if (-not ($properties | Where-Object { $_ -eq '/nologo' })) {
        $properties += '/nologo'
    }
    if (-not ($properties | Where-Object { $_ -match '^/verbosity:' })) {
        $properties += '/verbosity:minimal'
    }

    $args = @(
        "/c",
        ('call "{0}" {1} && "{2}" "{3}" {4} {5}' -f `
            $Config.environment.vcVarsAll,
            $Config.environment.vcArch,
            $Config.environment.msbuildPath,
            $Target.SolutionPath,
            ($targets -join ' '),
            ($properties -join ' '))
    )

    return Invoke-LoggedProcess `
        -FilePath 'cmd.exe' `
        -Arguments $args `
        -WorkingDirectory $Target.ProjectRoot `
        -LogPath $LogPath
}

function Invoke-QmakeBuild {
    [CmdletBinding()]
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
        $Config.environment.vcVarsAll,
        $Config.environment.vcArch,
        $Config.environment.qmakePath,
        ($qmakeArguments -join ' '),
        $Config.environment.jomPath,
        ($jomArguments -join ' ')

    return Invoke-LoggedProcess `
        -FilePath 'cmd.exe' `
        -Arguments @('/c', $command) `
        -WorkingDirectory $buildDirectory `
        -LogPath $LogPath
}

function Add-TraceSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TraceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $summaryPath = Join-Path -Path $TraceDirectory -ChildPath 'change-summary.md'
    [System.IO.File]::AppendAllText($summaryPath, "`r`n- $Message", [System.Text.UTF8Encoding]::new($false))
}

function Invoke-AutoFix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$Target,

        [Parameter(Mandatory = $true)]
        [object]$Analysis,

        [Parameter(Mandatory = $true)]
        [object]$TraceInfo
    )

    $fixes = @($Analysis.SuggestedFixes | Where-Object { $_ })
    if ($fixes.Count -eq 0) {
        return $false
    }

    foreach ($fix in $fixes) {
        switch ($fix) {
            'rerun-qmake' {
                Add-TraceSummary -TraceDirectory $TraceInfo.TraceDirectory -Message '执行自动修复: 重新生成 qmake 工程。'
                $tempLog = Join-Path -Path $TraceInfo.LogsDirectory -ChildPath 'rerun-qmake.log'
                Invoke-QmakeBuild -Config $Config -Target $Target -LogPath $tempLog | Out-Null
                return $true
            }
            'ensure-output-directory' {
                Ensure-Directory -Path $Target.OutputDirectory | Out-Null
                Add-TraceSummary -TraceDirectory $TraceInfo.TraceDirectory -Message "执行自动修复: 创建输出目录 $($Target.OutputDirectory)"
                return $true
            }
            'refresh-translations' {
                & "$PSScriptRoot\Update-QtTranslations.ps1" `
                    -ConfigPath $ConfigPath `
                    -ProjectRoot $Target.ProjectRoot `
                    -OutputDirectory $Target.OutputDirectory `
                    -ManifestPath (Join-Path -Path $TraceInfo.LogsDirectory -ChildPath $Config.report.qmManifestFileName) | Out-Null
                Add-TraceSummary -TraceDirectory $TraceInfo.TraceDirectory -Message '执行自动修复: 重新生成 Qt 翻译文件。'
                return $true
            }
        }
    }

    return $false
}

function Invoke-RuntimePhase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Config,

        [Parameter(Mandatory = $true)]
        [object]$TraceInfo
    )

    if (-not $Config.runtime.enabled) {
        return [pscustomobject]@{
            Enabled = $false
            Repro = $null
            Result = $null
            Analysis = $null
        }
    }

    $runtimeLogPath = Join-Path -Path $TraceInfo.LogsDirectory -ChildPath 'runtime.log'
    $runtimeResult = & "$PSScriptRoot\Start-ProgramWithLogs.ps1" `
        -ConfigPath $ConfigPath `
        -LogPath $runtimeLogPath

    $reproResult = $runtimeResult.Repro
    if ($reproResult) {
        Save-JsonFile -Path (Join-Path -Path $TraceInfo.LogsDirectory -ChildPath 'repro-summary.json') -InputObject $reproResult
    }

    $runtimeAnalysis = & "$PSScriptRoot\Analyze-RuntimeLog.ps1" `
        -ConfigPath $ConfigPath `
        -LogPath $runtimeLogPath `
        -ExitCode ([int]$runtimeResult.ExitCode) `
        -TimedOut ([bool]$runtimeResult.TimedOut)

    if ($reproResult -and $reproResult.Enabled -and ($Config.repro.mode -eq 'ui-automation') -and -not $reproResult.Success) {
        $runtimeAnalysis = [pscustomobject]@{
            RuntimeSuccess = $false
            ErrorCategory = 'repro-scenario-failed'
            Confidence = 'high'
            SuggestedFixes = @()
            CanAutoFix = $false
            Matches = @(
                [pscustomobject]@{
                    Id = 'repro-scenario-failed'
                    Category = 'repro-scenario-failed'
                    Pattern = ''
                    AutoFix = ''
                    CanAutoFix = $false
                    Confidence = 'high'
                }
            )
        }
    }

    Save-JsonFile -Path (Join-Path -Path $TraceInfo.LogsDirectory -ChildPath 'runtime-analysis.json') -InputObject $runtimeAnalysis

    return [pscustomobject]@{
        Enabled = $true
        Repro = $reproResult
        Result = $runtimeResult
        Analysis = $runtimeAnalysis
    }
}

function Start-BuildLoop {
    [CmdletBinding()]
    param()

    $config = Read-Config -ConfigPath $ConfigPath
    $environmentInfo = & "$PSScriptRoot\Initialize-BuildEnvironment.ps1" -ConfigPath $ConfigPath
    $target = & "$PSScriptRoot\Resolve-BuildTarget.ps1" -ConfigPath $ConfigPath -ProjectPath $ProjectPath
    $projectGuard = Resolve-ProjectConfigGuard -Config $config -Target $target

    Ensure-Directory -Path $target.BuildDirectory | Out-Null
    Ensure-Directory -Path $target.OutputDirectory | Out-Null
    Ensure-Directory -Path $target.TraceRoot | Out-Null

    $maxAttempts = [int]$config.trace.maxAttempts
    $attemptReports = @()
    $lastAnalysis = $null
    $translationResult = $null
    $runtimePhase = $null
    $success = $false

    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        Write-Log -Message "开始第 $attempt 次闭环。"

        $trackedFiles = @()
        if ($target.SolutionPath) { $trackedFiles += $target.SolutionPath }
        if ($target.ProPath) { $trackedFiles += $target.ProPath }

        $traceInfo = & "$PSScriptRoot\New-TraceRecord.ps1" `
            -TraceRoot $target.TraceRoot `
            -Attempt $attempt `
            -FilesBefore $trackedFiles `
            -Summary "第 $attempt 次闭环开始。"

        $guardSnapshotBefore = @()
        if ($projectGuard.Enabled) {
            $guardSnapshotBefore = @(Get-ProjectConfigSnapshot -Guard $projectGuard)
        }

        $translationResult = & "$PSScriptRoot\Update-QtTranslations.ps1" `
            -ConfigPath $ConfigPath `
            -ProjectRoot $target.ProjectRoot `
            -OutputDirectory $target.OutputDirectory `
            -ManifestPath (Join-Path -Path $traceInfo.LogsDirectory -ChildPath $config.report.qmManifestFileName)

        $logPath = Join-Path -Path $traceInfo.LogsDirectory -ChildPath 'build.log'
        $buildResult = Invoke-BuildOnce `
            -Config $config `
            -Target $target `
            -LogPath $logPath

        $attemptReport = [ordered]@{
            attempt = $attempt
            buildMode = $target.BuildMode
            exitCode = $buildResult.ExitCode
            logPath = $buildResult.LogPath
            command = $buildResult.Command
            projectGuardChanged = $false
            projectGuardReportPath = $null
        }
        $attemptReports += [pscustomobject]$attemptReport

        if ($projectGuard.Enabled) {
            $guardSnapshotAfter = @(Get-ProjectConfigSnapshot -Guard $projectGuard)
            $guardChanges = @(Compare-ProjectConfigSnapshot -Before $guardSnapshotBefore -After $guardSnapshotAfter)
            $guardReportPath = Join-Path -Path $traceInfo.LogsDirectory -ChildPath 'project-config-guard.json'
            $guardReport = [pscustomobject]@{
                enabled = $true
                checkedAt = (Get-Date).ToString('s')
                roots = $projectGuard.Roots
                includePatterns = $projectGuard.IncludePatterns
                excludeDirectories = $projectGuard.ExcludeDirectories
                beforeCount = $guardSnapshotBefore.Count
                afterCount = $guardSnapshotAfter.Count
                changed = $guardChanges.Count -gt 0
                changes = $guardChanges
            }
            Save-JsonFile -Path $guardReportPath -InputObject $guardReport
            $attemptReports[-1].projectGuardReportPath = $guardReportPath

            if ($guardChanges.Count -gt 0) {
                $attemptReports[-1].projectGuardChanged = $true
                $lastAnalysis = [pscustomobject]@{
                    RuntimeSuccess = $false
                    ErrorCategory = 'project-config-changed'
                    Confidence = 'high'
                    SuggestedFixes = @()
                    CanAutoFix = $false
                    Matches = @(
                        [pscustomobject]@{
                            Id = 'project-config-changed'
                            Category = 'project-config-changed'
                            Pattern = ''
                            AutoFix = ''
                            CanAutoFix = $false
                            Confidence = 'high'
                        }
                    )
                    ChangedFiles = $guardChanges
                    GuardReportPath = $guardReportPath
                }
                [System.IO.File]::AppendAllText(
                    (Join-Path -Path $traceInfo.TraceDirectory -ChildPath 'change-summary.md'),
                    "`r`n- 检测到工程配置文件被修改，已中止闭环并输出保护报告: $guardReportPath",
                    [System.Text.UTF8Encoding]::new($false))
                Write-Log -Level ERROR -Message "检测到工程配置文件变化，已中止闭环。详情见: $guardReportPath"
                break
            }
        }

        if ($buildResult.ExitCode -eq 0) {
            $runtimePhase = Invoke-RuntimePhase -Config $config -TraceInfo $traceInfo
            if (-not $config.runtime.enabled -or $runtimePhase.Analysis.RuntimeSuccess) {
                $success = $true
                break
            }

            $lastAnalysis = $runtimePhase.Analysis
            if (-not $lastAnalysis.CanAutoFix -or $attempt -ge $maxAttempts) {
                break
            }

            $fixed = Invoke-AutoFix `
                -Config $config `
                -Target $target `
                -Analysis $lastAnalysis `
                -TraceInfo $traceInfo

            if (-not $fixed) {
                break
            }

            continue
        }

        $lastAnalysis = & "$PSScriptRoot\Analyze-BuildError.ps1" -ConfigPath $ConfigPath -LogPath $logPath
        Save-JsonFile -Path (Join-Path -Path $traceInfo.LogsDirectory -ChildPath 'analysis.json') -InputObject $lastAnalysis

        if (-not $lastAnalysis.CanAutoFix -or $attempt -ge $maxAttempts) {
            break
        }

        $fixed = Invoke-AutoFix `
            -Config $config `
            -Target $target `
            -Analysis $lastAnalysis `
            -TraceInfo $traceInfo

        if (-not $fixed) {
            break
        }
    }

    $report = [ordered]@{
        projectPath = $ProjectPath
        buildMode = $target.BuildMode
        success = $success
        projectGuard = $projectGuard
        attempts = $attemptReports
        translation = $translationResult
        runtime = $runtimePhase
        lastAnalysis = $lastAnalysis
        environment = $environmentInfo
        generatedAt = (Get-Date).ToString('s')
    }

    $reportJsonPath = Join-Path -Path $target.TraceRoot -ChildPath $config.report.jsonReportFileName
    Save-JsonFile -Path $reportJsonPath -InputObject $report

    $reportMdPath = Join-Path -Path $target.TraceRoot -ChildPath $config.report.reportFileName
    $reportLines = @(
        '# 构建报告',
        '',
        "- 项目路径: $ProjectPath",
        "- 构建方式: $($target.BuildMode)",
        "- 是否成功: $success",
        "- 闭环次数: $($attemptReports.Count)"
    )

    if ($translationResult) {
        $reportLines += "- QM 清单: $($translationResult.ManifestPath)"
    }

    if ($lastAnalysis) {
        $reportLines += "- 最后错误分类: $($lastAnalysis.ErrorCategory)"
    }

    if ($projectGuard.Enabled) {
        $guardTriggered = @($attemptReports | Where-Object { $_.projectGuardChanged }).Count -gt 0
        $reportLines += "- 工程配置保护: $(if ($guardTriggered) { '检测到变更' } else { '未检测到变更' })"
    }

    [System.IO.File]::WriteAllText($reportMdPath, ($reportLines -join "`r`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Log -Message "构建报告已生成: $reportMdPath"
    Write-Log -Message "构建 JSON 报告已生成: $reportJsonPath"

    return $report
}

Start-BuildLoop
