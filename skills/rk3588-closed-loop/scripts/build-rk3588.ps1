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
$configureArgs = @($programConfig["configureArgs"] | Where-Object { $_ }) -join " "

if (-not $buildDir) {
    throw "Missing buildDir for program: $Program"
}

if (-not $buildTarget) {
    throw "Missing buildTarget for program: $Program"
}

if ($Clean) {
    Write-Host "Clean build directory: $buildDir"
    Invoke-WslCommand -Command "cd $wslProjectPath && rm -rf $buildDir"
}

$configureCommand = @(
    "cd $wslProjectPath",
    "export CC=$($toolchain["cCompiler"])",
    "export CXX=$($toolchain["cxxCompiler"])",
    "$($toolchain["cmake"]) -S . -B $buildDir $configureArgs",
    "$($toolchain["cmake"]) --build $buildDir --target $buildTarget -j"
) -join " && "

Write-Host "Program: $Program"
Write-Host "Build target: $buildTarget"
Write-Host "Build directory: $buildDir"
Invoke-WslCommand -Command $configureCommand
