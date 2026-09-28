param([string]$Actions = '', [string]$Capture = '', [int]$ExpectedFieldLength = -1,
  [int]$ExpectedCandidates = -1)
$ErrorActionPreference = 'Stop'
$probeRoot = Split-Path -Parent $PSScriptRoot
$probeLayout = Join-Path $probeRoot '.local/probe-layout.json'
New-Item -ItemType Directory -Path (Split-Path -Parent $probeLayout) -Force | Out-Null
$probeHdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
function Read-ProbeLayout {
  & $probeHdc shell uitest dumpLayout -p /data/local/tmp/kanon-probe.json | Out-Null
  & $probeHdc file recv /data/local/tmp/kanon-probe.json $probeLayout | Out-Null
  Get-Content -Raw -Encoding UTF8 $probeLayout | ConvertFrom-Json
}
function Get-ProbeNodes($node) {
  $node
  foreach ($child in $node.children) { Get-ProbeNodes $child }
}
foreach ($action in ($Actions -split ',' | Where-Object { $_ -ne '' })) {
  $nodes = @(Get-ProbeNodes (Read-ProbeLayout))
  $target = $null
  switch ($action) {
    'CANCEL' { $target = $nodes | Where-Object { $_.attributes.id -eq 'cand_cancel' } | Select-Object -First 1 }
    'MODE' { $target = $nodes | Where-Object { $_.attributes.id -eq 'cand_mode' } | Select-Object -First 1 }
    'EXPAND' { $target = $nodes | Where-Object { $_.attributes.id -eq 'cand_expand' } | Select-Object -First 1 }
    'RETURN' { $target = $nodes | Where-Object { $_.attributes.id -eq 'returnItem' } | Select-Object -First 1 }
    'SPACE' { $target = $nodes | Where-Object { $_.attributes.id -eq 'spaceItem' } | Select-Object -First 1 }
    'LONGMODE' { $target = $nodes | Where-Object { $_.attributes.id -eq 'spaceItem' } | Select-Object -First 1 }
    'BACKSPACE' { $target = $nodes | Where-Object { $_.attributes.id -eq 'deleteItem' } | Select-Object -First 1 }
    'CAND0' {
      $target = $nodes | Where-Object { $_.attributes.id -eq 'cand_slot_0' } | Select-Object -First 1
      if (!$target) {
      $list = $nodes | Where-Object { $_.attributes.id -eq 'cand_list' } | Select-Object -First 1
      $target = @(Get-ProbeNodes $list) | Where-Object { $_.attributes.type -eq 'Text' } | Select-Object -First 1
      }
    }
    default {
      $target = $nodes | Where-Object { $_.attributes.type -eq 'Text' -and $_.attributes.text -ceq $action } | Select-Object -Last 1
    }
  }
  if ($target) {
    if (!$target) { throw "Missing target $action" }
    $bounds = [regex]::Matches($target.attributes.bounds, '\d+')
    $x = [int](([int]$bounds[0].Value + [int]$bounds[2].Value) / 2)
    $y = [int](([int]$bounds[1].Value + [int]$bounds[3].Value) / 2)
    if ($action -eq 'LONGMODE') {
      & $probeHdc shell uitest uiInput longClick $x $y | Out-Null
    } else {
      & $probeHdc shell uitest uiInput click $x $y | Out-Null
    }
  } else {
    throw "Missing target $action"
  }
  Start-Sleep -Milliseconds 450
}
$nodes = @(Get-ProbeNodes (Read-ProbeLayout))
$field = $nodes | Where-Object { $_.attributes.type -eq 'TextInput' } | Select-Object -First 1
$state = $nodes | Where-Object { $_.attributes.id -eq 'cand_state' } | Select-Object -First 1
$diag = $nodes | Where-Object { $_.attributes.id -eq 'cand_diag' } | Select-Object -First 1
$candidates = @($nodes | Where-Object { $_.attributes.id -match '^cand_slot_' })
Write-Output ("actions=$Actions fieldLen=$($field.attributes.text.Length) candidates=$($candidates.Count) state=$($state.attributes.text) diag=$($diag.attributes.text)")
if ($ExpectedFieldLength -ge 0 -and $field.attributes.text.Length -ne $ExpectedFieldLength) {
  throw "Expected field length $ExpectedFieldLength, actual $($field.attributes.text.Length)"
}
if ($ExpectedCandidates -ge 0 -and $candidates.Count -ne $ExpectedCandidates) {
  throw "Expected candidates $ExpectedCandidates, actual $($candidates.Count)"
}
if ($Capture) {
  & $probeHdc shell uitest screenCap -p /data/local/tmp/kanon-probe.png | Out-Null
  & $probeHdc file recv /data/local/tmp/kanon-probe.png (Join-Path $probeRoot $Capture) | Out-Null
}
