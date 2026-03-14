. (Join-Path $PSScriptRoot "common.ps1")

$config = Get-AutomationConfig
$programNames = Get-ProgramNames | Sort-Object
$rows = foreach ($name in $programNames) {
    $program = Get-ProgramConfig -Name $name
    [PSCustomObject]@{
        Program = $name
        BuildTarget = $program["buildTarget"]
        RemoteBinary = $program["remoteBinaryPath"]
        RemoteLogGlob = $program["remoteLogGlob"]
        ConfigureArgs = ($program["configureArgs"] -join " ")
    }
}

$rows | Format-Table -AutoSize
