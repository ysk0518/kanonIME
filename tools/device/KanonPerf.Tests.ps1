$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'KanonPerf.psm1') -Force
$fixtures = Join-Path $PSScriptRoot '../../tests/fixtures/device'
$checks = 0

function Assert-Same($Expected, $Actual, [string]$Label) {
  if ($Expected -cne $Actual) { throw "$Label expected [$Expected], got [$Actual]" }
  $script:checks++
}

function Assert-Throws([scriptblock]$Action, [string]$Message) {
  $caught = $null
  try { & $Action | Out-Null }
  catch { $caught = $_.Exception.Message }
  if (!$caught -or $caught -notmatch $Message) { throw "Expected /$Message/, got [$caught]" }
  $script:checks++
}

$warm = @(ConvertFrom-KanonPerfLog (Get-Content (Join-Path $fixtures 'perf-warm.txt') -Raw -Encoding UTF8))
Assert-Same 12 $warm.Count 'parse documented prefixes and ignore other levels/domains'
Assert-Same 1795910400100 $warm[1].WallMs 'use payload wall clock'
Assert-Same '4,11,15' ((Get-KanonPerfIntervals M1 $warm 224).Ms -join ',') 'M1'
Assert-Same '23,10,0' ((Get-KanonPerfIntervals M2 $warm).Ms -join ',') 'M2 matches PID and sequence, using press order'
Assert-Same 'key.1 down -> done,key.2 down -> done,key.3 down -> done' (
  (Get-KanonPerfIntervals M2 $warm).Interval -join ',') 'M2 key labels'
$frame = Get-KanonPerfFrame $warm
Assert-Same 'qwerty_k,qwerty_a,qwerty_n' ((Get-KanonPerfKeyIds $frame) -join ',') 'QWERTY ids'
Assert-Same 'present' $frame.BackgroundImage 'background metadata'
Assert-Throws { Get-KanonPerfIntervals M1 $warm 987 } 'restarted'
Assert-Throws { Get-KanonPerfIntervals M1 @($warm | Where-Object Event -CNE 'field.focus') 224 } 'field.focus'
Assert-Throws { Get-KanonPerfIntervals M2 @($warm | Where-Object Index -NE 8) } 'three key.down'
$warm[9].Detail = '24'
Assert-Throws { Get-KanonPerfIntervals M2 $warm } 'Expected one key.done'

$cold = @(ConvertFrom-KanonPerfLog (Get-Content (Join-Path $fixtures 'perf-cold.txt') -Raw -Encoding UTF8))
Assert-Same '15,65,51,65' ((Get-KanonPerfIntervals M3 $cold).Ms -join ',') 'M3 pairs concurrent prepares'
$coldFrame = Get-KanonPerfFrame $cold
Assert-Same 'jp_flick' $coldFrame.Layout 'Japanese 12-key layout'
Assert-Same 'unknown' $coldFrame.BackgroundImage 'unknown background'
Assert-Same 'flick_a,flick_d,flick_g' ((Get-KanonPerfKeyIds @{ Layout = 'en_flick' }) -join ',') 'English 12-key ids'
Assert-Throws { Get-KanonPerfFrame ($cold + $cold[6]) } 'one kb.frame'
$cold[0].WallMs = $cold[1].WallMs + 1
Assert-Throws { Get-KanonPerfIntervals M3 $cold } 'Invalid order'

$stats = Get-KanonPerfStatistics @(12, 5, 2, 1, 3, 9, 6, 8, 4, 7)
Assert-Same 10 $stats.Count 'count'
Assert-Same 5.5 $stats.Median 'even sample median'
Assert-Same 9 $stats.P90 'nearest-rank p90'
Assert-Same 12 $stats.Max 'maximum'
Assert-Same 2 (Get-KanonPerfStatistics @(8, 1, 2)).Median 'odd sample median'
Assert-Same 0 (Get-KanonPerfStatistics @()).Count 'empty sample set'

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
  (Join-Path $PSScriptRoot 'measure-cold-path.ps1'), [ref]$tokens, [ref]$parseErrors) | Out-Null
Assert-Same 0 $parseErrors.Count 'collector syntax'
Write-Output "Passed $checks perf assertions."
