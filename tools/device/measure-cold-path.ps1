[CmdletBinding()]
param(
  [string]$Target,
  [ValidateRange(1, 1000)][int]$Repeat = 10,
  [ValidateRange(1, 120)][int]$TimeoutSeconds = 15,
  [string]$Commit,
  [switch]$SkipDebugSetup
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'KanonDevice.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'KanonPerf.psm1') -Force

$bundle = 'local.yplic.kanon'
$fieldId = 'kanon_validation_input'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$device = Assert-KanonDeviceReady -Target $Target -PassThru
$Target = $device.Target

function Invoke-PerfShell([string]$Command) {
  Invoke-KanonDeviceShell -Target $Target -Command $Command
}

function Assert-KanonSelected {
  $state = Get-KanonDeviceState -Target $Target -SkipLayout
  if ($state.CurrentIme -cne $bundle) { throw 'Kanon is no longer the selected IME. Select it before rerunning.' }
}

function Invoke-PerfTap([string]$Id) {
  Invoke-KanonUiTap -Target $Target -Id $Id
}

function Open-PerfPreview {
  $result = Invoke-PerfShell "aa start -a EntryAbility -b $bundle --pb kanonPreview true"
  if ($result -notmatch '\bstart ability successfully\b') { throw "Could not open preview: $result" }
  $clock = [Diagnostics.Stopwatch]::StartNew()
  do {
    try {
      $field = Find-KanonUiNode -Target $Target -Id $fieldId
      if ($field.attributes.focused -eq 'false' -and $field.attributes.text -ceq '') { return }
    } catch {
      if ($_.Exception.Message -notlike "*Id=$fieldId*") { throw }
    }
    Start-Sleep -Milliseconds 150
  } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
  throw 'The empty, unfocused preview input did not appear.'
}

function Clear-PerfLog {
  $result = Invoke-PerfShell 'hilog -r'
  if ($result -notmatch '\bbuffer clear successfully\b') { throw "Could not clear hilog: $result" }
}

function Wait-PerfMarks([ref]$Raw, [string]$ExpectedEvent, [int]$Count = 1) {
  $clock = [Diagnostics.Stopwatch]::StartNew()
  do {
    $Raw.Value = Invoke-PerfShell 'hilog -x -L D -T KanonPerf'
    $marks = @(ConvertFrom-KanonPerfLog $Raw.Value)
    if (@($marks | Where-Object Event -CEQ $ExpectedEvent).Count -ge $Count) { return $marks }
    Start-Sleep -Milliseconds 100
  } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
  throw "Timed out waiting for $Count $ExpectedEvent mark(s). Check the preview focus, selected IME and KanonPerf DEBUG logging."
}

function Save-Utf8([string]$Name, [string]$Content) {
  [IO.File]::WriteAllText((Join-Path $outDir $Name), $Content, [Text.UTF8Encoding]::new($false))
}

function Add-PerfTrial([int]$Iteration, [string]$Scenario, [object[]]$Marks, [int]$WarmPid = 0) {
  try {
    $samples = @(Get-KanonPerfIntervals -Scenario $Scenario -Marks $Marks -WarmPid $WarmPid)
    $trial = [ordered]@{ Iteration = $Iteration; Scenario = $Scenario; Samples = $samples }
    if ($Scenario -eq 'M2') {
      $frame = (Get-KanonPerfFrame $Marks).Mark
      $first = $Marks | Where-Object { $_.Event -ceq 'key.down' -and $_.Pid -eq $frame.Pid -and
        $_.Index -gt $frame.Index } | Select-Object -First 1
      $trial.FirstKeyAfterFrameMs = $first.WallMs - $frame.WallMs
    }
    $trials.Add([pscustomobject]$trial)
  } catch {
    $issues.Add([pscustomobject]@{ Iteration = $Iteration; Scenario = $Scenario; Message = $_.Exception.Message })
    Write-Warning "$Scenario #${Iteration}: $($_.Exception.Message)"
  }
}

function Write-PerfReport([string]$Failure) {
  $rows = @(foreach ($group in @($trials | ForEach-Object Samples |
      Group-Object Scenario, Interval, Mode, Layout, BackgroundImage)) {
    $sample = $group.Group[0]
    $stats = Get-KanonPerfStatistics -Milliseconds $group.Group.Ms
    [pscustomobject]@{
      Scenario = $sample.Scenario; Interval = $sample.Interval; Mode = $sample.Mode; Layout = $sample.Layout
      BackgroundImage = $sample.BackgroundImage; Median = $stats.Median; P90 = $stats.P90
      Max = $stats.Max; Count = $stats.Count
    }
  })
  $report = [ordered]@{
    Device = $Target; VersionName = $version; Commit = $Commit; CommitSource = $commitSource
    Repeat = $Repeat; Trials = $trials.ToArray(); Statistics = $rows; Issues = $issues.ToArray(); Failure = $Failure
  }
  Save-Utf8 'results.json' ($report | ConvertTo-Json -Depth 8)
  $lines = @(
    '# KanonIME P63'
    ''
    "- Device: $Target"
    "- versionName: $version"
    "- Commit: $Commit ($commitSource)"
    "- Requested trials per scenario: $Repeat"
    ''
    '| Scenario | Interval | Input mode | Layout | Background image | Median (ms) | p90 (ms) | Max (ms) | Count |'
    '| --- | --- | --- | --- | --- | ---: | ---: | ---: | ---: |'
    foreach ($row in $rows) {
      $photo = if ($row.BackgroundImage -eq 'unknown') { '不明' } else { $row.BackgroundImage }
      "| $($row.Scenario) | $($row.Interval) | $($row.Mode) | $($row.Layout) | $photo | $($row.Median) | $($row.P90) | $($row.Max) | $($row.Count) |"
    }
    if ($issues.Count -or $Failure) {
      ''
      '## Incomplete trials'
      ''
      foreach ($issue in $issues) { "- $($issue.Scenario) #$($issue.Iteration) $($issue.Message)" }
      if ($Failure) { "- $Failure" }
    }
  )
  Save-Utf8 'results.md' (($lines -join "`n") + "`n")
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$outDir = Join-Path $repo ".local/perf/$stamp"
New-Item -Path $outDir -ItemType Directory | Out-Null
$version = '不明'
$commitSource = 'provided'
if (!$Commit) {
  $Commit = git -C $repo rev-parse HEAD
  if ($LASTEXITCODE -ne 0) { throw 'Could not identify the source commit. Supply -Commit.' }
  $commitSource = 'worktree HEAD'
  if (git -C $repo status --porcelain) { $commitSource = 'worktree HEAD, dirty' }
}
$trials = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[object]]::new()
$failure = ''

try {
  Assert-KanonSelected
  $bundleDump = Invoke-PerfShell "bm dump -n $bundle"
  if ($bundleDump -match '(?m)^\s*"versionName"\s*:\s*"([^"]+)"|^\s*bundle version name\s*:\s*(\S+)') {
    $version = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
  }
  if (!$SkipDebugSetup) {
    $level = Invoke-PerfShell 'hilog -b D -D 0x4B50'
    if ($level -notmatch '\blog level to D successfully\b') {
      throw "Could not enable DEBUG: $level. See docs/PERFORMANCE.md for -SkipDebugSetup."
    }
  }

  $raw = ''
  try {
    Clear-PerfLog
    Open-PerfPreview
    Invoke-PerfTap $fieldId
    $warm = Get-KanonPerfFrame @(Wait-PerfMarks ([ref]$raw) 'kb.frame')
  } finally {
    Save-Utf8 'warmup.txt' $raw
  }

  for ($i = 1; $i -le $Repeat; $i++) {
    $raw = ''
    try {
      Clear-PerfLog
      Invoke-PerfTap 'kikaInputDown'
      Wait-PerfMarks ([ref]$raw) 'kb.hide' | Out-Null
      # Hiding can leave the editor focused. Reopen only when needed to force
      # a real onFocus, and reject M1 if the extension restarted.
      $field = Find-KanonUiNode -Target $Target -Id $fieldId
      if ($field.attributes.focused -ne 'false' -or $field.attributes.text -cne '') { Open-PerfPreview }
      Invoke-PerfTap $fieldId
      $marks = @(Wait-PerfMarks ([ref]$raw) 'kb.frame')
      $frame = Get-KanonPerfFrame $marks
      foreach ($key in (Get-KanonPerfKeyIds $frame)) { Invoke-PerfTap $key }
      Add-PerfTrial $i M1 $marks $warm.Mark.Pid
      $warm = $frame
      $marks = @(Wait-PerfMarks ([ref]$raw) 'key.done' 3)
      Add-PerfTrial $i M2 $marks
      for ($letter = 0; $letter -lt 3; $letter++) { Invoke-PerfTap 'deleteItem' }
    } finally {
      Save-Utf8 ('M1-M2-{0:D3}.txt' -f $i) $raw
    }
  }

  for ($i = 1; $i -le $Repeat; $i++) {
    $raw = ''
    try {
      Clear-PerfLog
      $stopped = Invoke-PerfShell "aa force-stop $bundle"
      if ($stopped -notmatch '\bforce stop process successfully\b') { throw "Could not force-stop Kanon: $stopped" }
      Assert-KanonSelected
      Open-PerfPreview
      Invoke-PerfTap $fieldId
      Wait-PerfMarks ([ref]$raw) 'kb.frame' | Out-Null
      $marks = @(Wait-PerfMarks ([ref]$raw) 'mozc.init.end')
      Add-PerfTrial $i M3 $marks
    } finally {
      Save-Utf8 ('M3-{0:D3}.txt' -f $i) $raw
    }
  }
} catch {
  $failure = $_.Exception.Message
  throw
} finally {
  Write-PerfReport $failure
  Write-Output $outDir
}
if ($issues.Count) { throw "$($issues.Count) trial(s) were rejected. See results.md in $outDir." }
