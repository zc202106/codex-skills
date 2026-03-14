param(
    [Parameter(Mandatory = $true)]
    [string]$Program,
    [switch]$Clean
)

. (Join-Path $PSScriptRoot "common.ps1")

$programNames = Get-ProgramNames
if ($programNames -notcontains $Program) {
    throw "Unknown program: $Program"
}

$programConfig = Get-ProgramConfig -Name $Program
$toolchain = Get-ToolchainConfig
$wslProjectPath = Get-WslProjectPath
$buildDir = $programConfig["buildDir"]
$buildTarget = $programConfig["buildTarget"]
$configureArgs = ($programConfig["configureArgs"] -join " ")

if ($Clean) {
    Invoke-WslCommand -Command "cd $wslProjectPath && rm -rf $buildDir"
}

$configureCommand = @(
    "cd $wslProjectPath",
    "export CC=$($toolchain["cCompiler"])",
    "export CXX=$($toolchain["cxxCompiler"])",
    "$($toolchain["cmake"]) -S . -B $buildDir $configureArgs",
    "$($toolchain["cmake"]) --build $buildDir --target $buildTarget -j"
) -join " && "

Invoke-WslCommand -Command $configureCommand
