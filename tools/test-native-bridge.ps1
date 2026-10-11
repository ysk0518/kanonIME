param(
  [switch]$BuildOnly,
  [string]$Target = '',
  [string]$SigningProfile = '',
  [string]$RestoreHap = ''
)

$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $PSScriptRoot
$testHdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$testNode = 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe'
$testHvigor = 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js'
$testHap = Join-Path $testRoot 'entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap'
$runDirectory = Join-Path $testRoot ('.local/native-device/' + (Get-Date -Format 'yyyyMMdd-HHmmss-ffff'))
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
$result = [ordered]@{ status='not-run'; expectedTests=10; buildMode='release'; module='entry_test';
  buildLog=(Join-Path $runDirectory 'build.log'); testLog=(Join-Path $runDirectory 'test.log');
  hapSha256=$null; target=$Target; cleanup='not-installed' }
$installed = $false

function Invoke-TestDevice([string[]]$DeviceArguments) {
  $output = & $testHdc -t $Target @DeviceArguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw 'HDC command failed. Check connection and test logs.' }
  return ($output -join "`n")
}

try {
  if (!$BuildOnly) {
    if (!$RestoreHap -or !(Test-Path -LiteralPath $RestoreHap)) {
      throw 'Device tests require -RestoreHap pointing to the normal signed release HAP to restore after removing entry_test.'
    }
    $RestoreHap = (Resolve-Path -LiteralPath $RestoreHap).Path
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $restoreArchive = [IO.Compression.ZipFile]::OpenRead($RestoreHap)
    try {
      $restoreReader = [IO.StreamReader]::new($restoreArchive.GetEntry('module.json').Open())
      try { $restoreManifest = $restoreReader.ReadToEnd() | ConvertFrom-Json }
      finally { $restoreReader.Dispose() }
      if ($restoreManifest.app.bundleName -ne 'local.yplic.kanon' -or
          $restoreManifest.module.name -ne 'entry' -or $restoreManifest.app.debug -ne $false) {
        throw 'RestoreHap must be the normal kanon entry release HAP.'
      }
    } finally { $restoreArchive.Dispose() }
    $result.restoreHapSha256 = (Get-FileHash -LiteralPath $RestoreHap -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  Push-Location $testRoot
  try {
    $profilePath = Join-Path $testRoot 'build-profile.json5'
    $profileBytes = [IO.File]::ReadAllBytes($profilePath)
    try {
      if ($SigningProfile) { Copy-Item -LiteralPath $SigningProfile -Destination $profilePath -Force }
      $env:DEVECO_SDK_HOME = 'C:/Program Files/Huawei/DevEco Studio/sdk'
      $env:JAVA_HOME = 'C:/Program Files/Huawei/DevEco Studio/jbr'
      $previousPreference = $ErrorActionPreference
      try {
        $ErrorActionPreference = 'Continue'
        & $testNode $testHvigor assembleHap --mode module -p product=default -p module=entry@ohosTest -p isOhosTest=true -p buildMode=release *> $result.buildLog
        $buildExitCode = $LASTEXITCODE
      } finally { $ErrorActionPreference = $previousPreference }
      if ($buildExitCode -ne 0) { throw 'Native test HAP build failed. See build.log.' }
    } finally { [IO.File]::WriteAllBytes($profilePath, $profileBytes) }
    if (!(Test-Path -LiteralPath $testHap)) { throw 'Signed test HAP missing. Configure local signing.' }
    $result.hapSha256 = (Get-FileHash -LiteralPath $testHap -Algorithm SHA256).Hash.ToLowerInvariant()
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($testHap)
    try {
      $nativeEntry = $archive.GetEntry('libs/arm64-v8a/libkanon_bridge.so')
      if ($null -eq $nativeEntry) { throw 'Product native library is missing from the test HAP.' }
      $nativeStream = $nativeEntry.Open()
      $hasher = [Security.Cryptography.SHA256]::Create()
      try { $result.packagedLibrarySha256 = [BitConverter]::ToString($hasher.ComputeHash($nativeStream)).Replace('-', '').ToLowerInvariant() }
      finally { $nativeStream.Dispose(); $hasher.Dispose() }
      $manifestReader = [IO.StreamReader]::new($archive.GetEntry('module.json').Open())
      try { $result.testAppDebug = ($manifestReader.ReadToEnd() | ConvertFrom-Json).app.debug }
      finally { $manifestReader.Dispose() }
    } finally { $archive.Dispose() }
    $result.testSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $testRoot 'entry/src/ohosTest/ets/test/NativeBridge.test.ets') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.sourceLibrarySha256 = (Get-FileHash -LiteralPath (Join-Path $testRoot 'entry/libs/arm64-v8a/libkanon_bridge.so') -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.bridgeSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $testRoot 'native/bridge/kanon_bridge.cc') -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($BuildOnly) {
      $result.status = 'built-not-run'
    } else {
      if (!$Target) {
        $targets = @(& $testHdc list targets -v)
        if ($LASTEXITCODE -ne 0) { throw 'HDC targets unavailable.' }
        $connected = @($targets | Where-Object { $_ -match '\s(USB|TCP)\s+Connected\s' } |
          ForEach-Object { ($_ -split '\s+')[0] })
        if ($connected.Count -ne 1) { throw 'Pass -Target: exactly one Connected USB/TCP device is required.' }
        $Target = $connected[0]
      }
      $result.target = $Target
      $result.osVersion = Invoke-TestDevice @('shell', 'param', 'get', 'const.ohos.fullname')
      $result.imeBeforeTest = Invoke-TestDevice @('shell', 'ime', '-g')
      $previousIme = [regex]::Match($result.imeBeforeTest, 'input method is:\s*([a-zA-Z0-9_.]+),\s*status:\s*([A-Z_]+)')
      if (!$previousIme.Success) { throw 'Cannot record the current IME before installing the test module.' }
      $installOutput = Invoke-TestDevice @('install', $testHap)
      $installOutput | Set-Content -LiteralPath (Join-Path $runDirectory 'install.log') -Encoding UTF8
      if ($installOutput -notmatch 'install bundle successfully') { throw 'Test HAP installation was not confirmed.' }
      $installed = $true
      $testOutput = Invoke-TestDevice @('shell', 'aa', 'test', '-b', 'local.yplic.kanon', '-m', 'entry_test',
        '-s', 'unittest', 'OpenHarmonyTestRunner', '-s', 'class', 'KanonNativeBridge', '-w', '45000')
      $testOutput | Set-Content -LiteralPath $result.testLog -Encoding UTF8
      # aa test can return exit code 0 even when assertions fail or the app dies.
      $summary = [regex]::Match($testOutput, 'Tests run:\s*(\d+), Failure:\s*(\d+), Error:\s*(\d+), Pass:\s*(\d+), Ignore:\s*(\d+)')
      if (!$summary.Success) { throw 'No test summary. Treat startup failure or timeout as not passed.' }
      $result.tests = [int]$summary.Groups[1].Value
      $result.failures = [int]$summary.Groups[2].Value
      $result.errors = [int]$summary.Groups[3].Value
      $result.passed = [int]$summary.Groups[4].Value
      $result.ignored = [int]$summary.Groups[5].Value
      if ($result.tests -ne $result.expectedTests -or $result.passed -ne $result.expectedTests -or
          $result.failures -ne 0 -or $result.errors -ne 0 -or $result.ignored -ne 0) {
        $result.status = 'failed'
        throw 'Native bridge tests did not all pass. See test.log.'
      }
      $result.status = 'passed'
    }
  } finally { Pop-Location }
} catch {
  if ($result.status -ne 'failed') { $result.status = 'environment-or-build-error' }
  $result.message = $_.Exception.Message
  throw
} finally {
  try {
    if ($installed) {
      $result.cleanup = 'failed'
      $cleanupOutput = Invoke-TestDevice @('shell', 'bm', 'uninstall', '-n', 'local.yplic.kanon', '-m', 'entry_test', '-k')
      $cleanupOutput | Set-Content -LiteralPath (Join-Path $runDirectory 'cleanup.log') -Encoding UTF8
      if ($cleanupOutput -notmatch '(?i)success') { throw 'Test module cleanup was not confirmed.' }
      $result.cleanup = 'test-module-removed'
      # Removing an ohosTest feature module can remove the main IME registration.
      # Restore the explicitly supplied normal HAP and the saved selection.
      $restoreOutput = Invoke-TestDevice @('install', '-r', $RestoreHap)
      $restoreOutput | Set-Content -LiteralPath (Join-Path $runDirectory 'restore.log') -Encoding UTF8
      if ($restoreOutput -notmatch 'install bundle successfully') { throw 'Normal release HAP restoration was not confirmed.' }
      if ($previousIme.Groups[1].Value -eq 'local.yplic.kanon') {
        $restoreMode = if ($previousIme.Groups[2].Value -eq 'FULL_EXPERIENCE_MODE') { '-f' } else { '-b' }
        Invoke-TestDevice @('shell', 'ime', '-e', 'local.yplic.kanon', $restoreMode) | Out-Null
      }
      Invoke-TestDevice @('shell', 'ime', '-s', $previousIme.Groups[1].Value) | Out-Null
      $result.imeAfterRestore = Invoke-TestDevice @('shell', 'ime', '-g')
      if ($result.imeAfterRestore.Trim() -ne $result.imeBeforeTest.Trim()) { throw 'IME selection or mode was not restored.' }
      $result.cleanup = 'test-module-removed-release-and-ime-restored'
    }
  } catch {
    if ($result.status -eq 'passed') { $result.status = 'tests-passed-cleanup-failed' }
    throw
  } finally {
    $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $runDirectory 'report.json') -Encoding UTF8
    Write-Output ('Native bridge status: ' + $result.status)
    Write-Output ('Cleanup: ' + $result.cleanup)
    Write-Output ('Report: ' + (Join-Path $runDirectory 'report.json'))
  }
}
