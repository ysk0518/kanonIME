param([string]$EngineRoot = 'D:/kanon-engine')

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'native/bridge/kanon_bridge.cc'
$destination = Join-Path $EngineRoot 'bridge/kanon_bridge.cc'
$buildDirectory = Join-Path $EngineRoot 'build-ohos'
$builtLibrary = Join-Path $EngineRoot 'libs/arm64-v8a/libkanon_bridge.so'
$appLibrary = Join-Path $repoRoot 'entry/libs/arm64-v8a/libkanon_bridge.so'
$cmake = 'C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe'
$ninjaDirectory = 'C:/Program Files/Microsoft Visual Studio/2022/Community/Common7/IDE/CommonExtensions/Microsoft/CMake/Ninja'
$env:PATH = "$ninjaDirectory;C:/Program Files/Git/bin;$env:PATH"

if (!(Test-Path -LiteralPath (Join-Path $buildDirectory 'CMakeCache.txt'))) {
  throw "Configured OHOS engine build missing: $buildDirectory"
}
Copy-Item -LiteralPath $source -Destination $destination
& $cmake --build $buildDirectory --target kanon_bridge --parallel 4
if ($LASTEXITCODE -ne 0) { throw "Native bridge build failed: $LASTEXITCODE" }
Copy-Item -LiteralPath $builtLibrary -Destination $appLibrary
Write-Output 'Native bridge built and copied into entry/libs/arm64-v8a.'
