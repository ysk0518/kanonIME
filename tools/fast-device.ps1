param(
  [switch]$Build,
  [switch]$Install,
  [switch]$SelectKanon,
  [switch]$OpenPreview,
  [string]$Tap = '',
  [string]$Screenshot = '',
  [string]$Target = '',
  [switch]$Status
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$deviceHdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$devEcoNode = 'C:/Program Files/Huawei/DevEco Studio/tools/node/node.exe'
$devEcoHvigor = 'C:/Program Files/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.js'
$hapPath = Join-Path $projectRoot 'entry/build/default/outputs/default/entry-default-signed.hap'
$localDir = Join-Path $projectRoot '.local'

if (!(Test-Path -LiteralPath $deviceHdc)) { throw "HDC not found: $deviceHdc" }
if (!$Build -and !$Install -and !$SelectKanon -and !$OpenPreview -and
    !$Tap -and !$Screenshot -and !$Status) {
  $Build = $true
  $Install = $true
}

function Invoke-Device([string[]]$Arguments) {
  $output = & $deviceHdc -t $Target @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) {
    throw "HDC failed: $($Arguments -join ' ')`n$($output -join "`n")"
  }
  return $output
}

if ($Build) {
  if (!(Test-Path -LiteralPath $devEcoNode) -or !(Test-Path -LiteralPath $devEcoHvigor)) {
    throw 'DevEco Studio build tools not found.'
  }
  New-Item -ItemType Directory -Path $localDir -Force | Out-Null
  $env:DEVECO_SDK_HOME = 'C:/Program Files/Huawei/DevEco Studio/sdk'
  $env:JAVA_HOME = 'C:/Program Files/Huawei/DevEco Studio/jbr'
  $buildLog = Join-Path $localDir 'fast-device-build.log'
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    & $devEcoNode $devEcoHvigor assembleHap *> $buildLog
    $buildExitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  $watch.Stop()
  if ($buildExitCode -ne 0) {
    Get-Content -LiteralPath $buildLog -Tail 45
    throw "Build failed. Full log: $buildLog"
  }
  Write-Output ('Build: {0:N1}s' -f $watch.Elapsed.TotalSeconds)
}

if ($Install -or $SelectKanon -or $OpenPreview -or $Tap -or $Screenshot -or $Status) {
  if (!$Target) {
    $targets = @(& $deviceHdc list targets -v)
    if ($LASTEXITCODE -ne 0) { throw 'Could not list HDC targets.' }
    $usb = @($targets | Where-Object { $_ -match '\sUSB\s+Connected\s' } |
      ForEach-Object { ($_ -split '\s+')[0] })
    $tcp = @($targets | Where-Object { $_ -match '\sTCP\s+Connected\s' } |
      ForEach-Object { ($_ -split '\s+')[0] })
    if ($usb.Count -eq 1) { $Target = $usb[0] }
    elseif ($usb.Count -gt 1) { throw "Multiple USB devices connected: $($usb -join ', '). Pass -Target." }
    elseif ($tcp.Count -eq 1) { $Target = $tcp[0] }
    elseif ($tcp.Count -gt 1) { throw "Multiple TCP devices connected: $($tcp -join ', '). Pass -Target." }
    else { throw 'No connected HDC device found.' }
  }
  Write-Output "Device: $Target"
}

if ($Install) {
  if (!(Test-Path -LiteralPath $hapPath)) { throw "Signed HAP not found: $hapPath" }
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  Invoke-Device @('install', '-r', $hapPath) | Out-Null
  $watch.Stop()
  Write-Output ('Install: {0:N1}s' -f $watch.Elapsed.TotalSeconds)
}
if ($SelectKanon) {
  Invoke-Device @('shell', 'ime', '-s', 'local.yplic.kanon') | Out-Null
  Write-Output 'IME: kanon'
}
if ($OpenPreview) {
  Invoke-Device @('shell', 'aa', 'start', '-a', 'EntryAbility', '-b', 'local.yplic.kanon') | Out-Null
  Start-Sleep -Milliseconds 650
  Write-Output 'Preview: opened (keyboard chooser may appear)'
}
$tapCount = 0
foreach ($point in ($Tap -split ';' | Where-Object { $_ })) {
  if ($point -notmatch '^(\d+),(\d+)$') { throw "Invalid tap '$point'; use x,y." }
  Invoke-Device @('shell', 'uinput', '-T', '-c', $Matches[1], $Matches[2]) | Out-Null
  $tapCount++
}
if ($tapCount -gt 0) { Write-Output "Taps: $tapCount" }
if ($Screenshot) {
  if ($Screenshot -notmatch '^[a-zA-Z0-9_-]+$') {
    throw 'Screenshot must be a simple name without a path or extension.'
  }
  $shotDir = Join-Path $localDir 'screenshots'
  New-Item -ItemType Directory -Path $shotDir -Force | Out-Null
  $remoteShot = '/data/local/tmp/kanon-fast-device.jpeg'
  $localShot = Join-Path $shotDir "$Screenshot.jpeg"
  Invoke-Device @('shell', 'snapshot_display', '-f', $remoteShot) | Out-Null
  Invoke-Device @('file', 'recv', $remoteShot, $localShot) | Out-Null
  Write-Output "Screenshot: $localShot"
}
if ($Status) {
  $currentIme = @(Invoke-Device @('shell', 'ime', '-g')) -join ' '
  Write-Output "Current IME: $currentIme"
}
