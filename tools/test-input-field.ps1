param(
  [Parameter(Mandatory=$true)][string]$Target,
  [Parameter(Mandatory=$true)][string]$Case,
  [string]$FieldId = 'kanon_validation_input',
  [ValidatePattern('^[a-zA-Z0-9_.]+$')][string]$ExpectedMission = 'local.yplic.kanon',
  [string]$CasesFile = '',
  [ValidateRange(0.5,6)][double]$PixelsPerVp = 3,
  [switch]$PrepareQwerty
)
$ErrorActionPreference = 'Stop'
$fixtureRoot = Split-Path -Parent $PSScriptRoot
$fixtureHdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
if (!$CasesFile) { $CasesFile = Join-Path $fixtureRoot 'tests/device/native-input-cases.json' }
$caseData = (Get-Content -LiteralPath $CasesFile -Raw -Encoding UTF8 | ConvertFrom-Json).cases |
  Where-Object { $_.id -ceq $Case } | Select-Object -First 1
if ($null -eq $caseData) { throw 'Unknown input fixture case.' }
$fixtureDirectory = Join-Path $fixtureRoot ('.local/device-validation/' + (Get-Date -Format 'yyyyMMdd-HHmmss-ffff') + '-' + $Case)
New-Item -ItemType Directory -Path $fixtureDirectory -Force | Out-Null
$report = [ordered]@{ case=$Case; fieldId=$FieldId; expectedMission=$ExpectedMission; pixelsPerVp=$PixelsPerVp; status='not-run'; steps=@() }
$fixtureCandidates = @($caseData.steps | Where-Object { $_.candidate } | ForEach-Object { [string]$_.candidate } | Select-Object -Unique)
function Invoke-FixtureDevice([string[]]$DeviceArguments) {
  $output = & $fixtureHdc -t $Target @DeviceArguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw 'HDC failed during input validation.' }
  return ($output -join "`n")
}
function Get-FixtureNodes($Node) {
  $Node
  foreach ($child in $Node.children) { Get-FixtureNodes $child }
}
function Read-Fixture {
  $missions = Invoke-FixtureDevice @('shell','aa','dump','-l')
  $active = @([regex]::Matches($missions,'(?s)Mission ID #\d+.*?(?=Mission ID #|\z)') |
    Where-Object { $_.Value -match '(?m)^\s+state #FOREGROUND\b' })
  $report.observedMission = if ($active.Count -eq 1) {
    [regex]::Match($active[0].Value,'mission name #\[#([^:]+):').Groups[1].Value
  } else { '' }
  if ($report.observedMission -cne $ExpectedMission) {
    $report.status='environment-wait'; throw 'Expected foreground application missing. Stop without pressing keys.'
  }
  Invoke-FixtureDevice @('shell','uitest','dumpLayout','-p','/data/local/tmp/kanon-input-fixture.json') | Out-Null
  $path = Join-Path $fixtureDirectory 'layout.json'
  Invoke-FixtureDevice @('file','recv','/data/local/tmp/kanon-input-fixture.json',$path) | Out-Null
  try { $layoutTree = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json }
  catch { throw 'Unable to parse fixture UI dump.' }
  finally { [IO.File]::WriteAllText($path, '[]') }
  $nodes = @(Get-FixtureNodes $layoutTree)
  $fields = @($nodes | Where-Object { $_.attributes.id -ceq $FieldId })
  if ($FieldId -ceq 'kanon_web_input' -or $FieldId -ceq 'kanon_web_textarea') {
    # Huawei Web accessibility omits HTML ids. Restrict the fallback to our
    # fixture's unique heading and labelled fields within the same web area.
    $fields = @()
    foreach ($webArea in ($nodes | Where-Object { $_.attributes.type -ceq 'rootWebArea' })) {
      $webNodes = @(Get-FixtureNodes $webArea)
      $heading = @($webNodes | Where-Object { $_.attributes.type -ceq 'heading' -and $_.attributes.text -ceq 'kanon IME 入力確認' })
      if ($heading.Count -ne 1) { continue }
      $hint = if ($FieldId -ceq 'kanon_web_input') { '単行入力' } else { '複数行入力' }
      $fields += @($webNodes | Where-Object { $_.attributes.type -ceq 'textField' -and $_.attributes.hint -ceq $hint -and $_.attributes.visible -eq 'true' })
    }
  }
  # Replace the transport dump with only owned key bounds and fixture labels.
  # Predictions from the user's learning dictionary are not diagnostic data.
  $layoutRecords = @($nodes | Where-Object {
    $_.attributes.id -match '^(qwerty_|flick_|cand_slot_|deleteItem$|spaceItem$|returnItem$|layoutItem$|modeCycleItem$)'
  } | ForEach-Object {
    $entry=[ordered]@{ id=$_.attributes.id; type=$_.attributes.type; bounds=$_.attributes.bounds; visible=$_.attributes.visible }
    if ($_.attributes.id -match '^cand_slot_' -and $fixtureCandidates -ccontains $_.attributes.text) { $entry.fixtureLabel=$_.attributes.text }
    [pscustomobject]$entry
  })
  if ($fields.Count -eq 1) {
    $layoutRecords += [pscustomobject]@{ id=$FieldId; type=$fields[0].attributes.type; bounds=$fields[0].attributes.bounds;
      focused=$fields[0].attributes.focused; text=$fields[0].attributes.text }
  }
  $layoutRecords | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
  if ($fields.Count -ne 1) { $report.status='environment-wait'; throw 'Fixed input field missing or ambiguous. Stop without pressing keys.' }
  $report.actual=[string]$fields[0].attributes.text
  return [pscustomobject]@{ nodes=$nodes; text=[string]$fields[0].attributes.text; field=$fields[0] }
}
function Click-FixtureNode($Node, [string]$Direction = '', [int]$DragPixels = 0,
  [double]$TapXFraction = 0.5, [bool]$LongPress = $false, [switch]$DirectTouch) {
  $bounds = [regex]::Matches($Node.attributes.bounds,'-?\d+')
  if ($bounds.Count -ne 4) { throw 'Invalid target bounds.' }
  $left=[int]$bounds[0].Value; $top=[int]$bounds[1].Value
  $right=[int]$bounds[2].Value; $bottom=[int]$bounds[3].Value
  if ($right -le $left -or $bottom -le $top -or $left -lt 0 -or $top -lt 0) { throw 'Target is not visible.' }
  if ([double]::IsNaN($TapXFraction) -or [double]::IsInfinity($TapXFraction) -or
      $TapXFraction -le 0 -or $TapXFraction -ge 1) { throw 'Tap fraction must be strictly inside the fixture node.' }
  $x=[int]($left+($right-$left)*$TapXFraction); $y=[int](($top+$bottom)/2)
  if ($DragPixels -ne 0) {
    $endX=$x+$DragPixels
    if ($endX -le $left -or $endX -ge $right) { throw 'Space drag must stay inside the fixture key.' }
    Invoke-FixtureDevice @('shell','uitest','uiInput','drag',"$x","$y","$endX","$y",'200') | Out-Null
  }
  elseif (!$Direction) {
    if ($DirectTouch) { Invoke-FixtureDevice @('shell','uinput','-T','-c',"$x","$y") | Out-Null }
    else {
      $tapAction = if ($LongPress) { 'longClick' } else { 'click' }
      Invoke-FixtureDevice @('shell','uitest','uiInput',$tapAction,"$x","$y") | Out-Null
    }
  }
  else {
    $endX=$x; $endY=$y; $distance=[int]([Math]::Max(130,($bottom-$top)*0.65))
    switch ($Direction) {
      'left' { $endX-=$distance }; 'right' { $endX+=$distance }
      'up' { $endY-=$distance }; 'down' { $endY+=$distance }
      default { throw 'Unsupported flick direction.' }
    }
    Invoke-FixtureDevice @('shell','uitest','uiInput','swipe',"$x","$y","$endX","$endY",'600') | Out-Null
  }
}
function Find-FixtureNode($Snapshot, [string]$Id) {
  if ($Id -ceq 'fixtureField') { return $Snapshot.field }
  $matches = @($Snapshot.nodes | Where-Object { $_.attributes.id -ceq $Id })
  if ($matches.Count -ne 1) { throw 'Action target missing or ambiguous.' }
  return $matches[0]
}
function Wait-FixtureText([string]$Expected) {
  $watch=[Diagnostics.Stopwatch]::StartNew()
  do {
    $snapshot=Read-Fixture
    if ($snapshot.text -ceq $Expected) { return $snapshot }
    Start-Sleep -Milliseconds 120
  } while ($watch.ElapsedMilliseconds -lt 3500)
  throw 'Visible input text did not match the fixture. See report and layout.'
}
try {
  $report.ime = Invoke-FixtureDevice @('shell','ime','-g')
  $report.osVersion = Invoke-FixtureDevice @('shell','param','get','const.ohos.fullname')
  $report.casesSha256 = (Get-FileHash -LiteralPath $CasesFile -Algorithm SHA256).Hash.ToLowerInvariant()
  $fixtureHap = Join-Path $fixtureRoot 'entry/build/default/outputs/default/entry-default-signed.hap'
  if (Test-Path -LiteralPath $fixtureHap) {
    # Local artifact identity, not proof of the binary currently installed on a device.
    $report.localHapSha256 = (Get-FileHash -LiteralPath $fixtureHap -Algorithm SHA256).Hash.ToLowerInvariant()
  }
  $snapshot=Read-Fixture
  # Do not tap an already focused composing field: it can end the OS preview.
  if ($snapshot.field.attributes.focused -ne 'true') { Click-FixtureNode $snapshot.field }
  Start-Sleep -Milliseconds 200
  $snapshot=Read-Fixture
  # Clear only the identified test field, through the real IME editing path.
  $cancel=@($snapshot.nodes | Where-Object { $_.attributes.id -ceq 'cand_cancel' })
  if ($cancel.Count -eq 1) { Click-FixtureNode $cancel[0]; Start-Sleep -Milliseconds 200; $snapshot=Read-Fixture }
  for ($deletes=0; $snapshot.text.Length -gt 0 -and $deletes -lt 50; $deletes++) {
    Click-FixtureNode (Find-FixtureNode $snapshot 'deleteItem')
    Start-Sleep -Milliseconds 200
    $snapshot=Read-Fixture
  }
  if ($snapshot.text -ne '') { throw 'Unable to prepare an empty fixture field.' }
  if ($PrepareQwerty -and !($snapshot.nodes | Where-Object { $_.attributes.id -ceq 'qwerty_k' })) {
    Click-FixtureNode (Find-FixtureNode $snapshot 'layoutItem')
    Start-Sleep -Milliseconds 200
  }
  $repeats=1
  if ($null -ne $caseData.repeat) { $repeats=[int]$caseData.repeat }
  for ($iteration=0; $iteration -lt $repeats; $iteration++) {
    foreach ($step in $caseData.steps) {
      $expected=$null
      $snapshot=Read-Fixture
      $report.action = [pscustomobject]@{ iteration=$iteration; id=$step.id; candidate=$step.candidate }
      $burstElapsedMs=$null
      $burstEngine=$null
      if ($step.burst) {
        $burstKeys=@($step.burst)
        if ($burstKeys.Count -lt 2 -or $burstKeys.Count -gt 16) { throw 'Fixture burst needs 2 to 16 fixed letter keys.' }
        $burstNodes=@($burstKeys | ForEach-Object {
          if ($_ -cnotmatch '^qwerty_[a-z]$') { throw 'Only fixed QWERTY letter keys are allowed in a burst.' }
          Find-FixtureNode $snapshot $_
        })
        $burstWatch=[Diagnostics.Stopwatch]::StartNew()
        foreach ($burstNode in $burstNodes) { Click-FixtureNode $burstNode -DirectTouch }
        $burstWatch.Stop()
        $burstElapsedMs=$burstWatch.ElapsedMilliseconds
        $burstEngine='uinput'
        $tapXFraction=0.5
        $report.action | Add-Member -NotePropertyName burst -NotePropertyValue $burstKeys
      } else {
        if ($step.candidate) {
          $candidates=@($snapshot.nodes | Where-Object { $_.attributes.id -match '^cand_slot_\d+$' -and $_.attributes.text -ceq $step.candidate })
          if ($candidates.Count -ne 1) { throw 'Required fixture candidate is not uniquely visible.' }
          $node=$candidates[0]
        } else { $node=Find-FixtureNode $snapshot $step.id }
        $tapXFraction = if ($null -eq $step.tapXFraction) { 0.5 } else { [double]$step.tapXFraction }
        $report.action | Add-Member -NotePropertyName tapXFraction -NotePropertyValue $tapXFraction
        $report.action | Add-Member -NotePropertyName longPress -NotePropertyValue ([bool]$step.longPress)
        Click-FixtureNode $node $step.flick ([int][Math]::Round($step.dragVp * $PixelsPerVp)) $tapXFraction ([bool]$step.longPress)
      }
      Start-Sleep -Milliseconds 150
      if ($null -ne $step.expect) {
        $expected=([string]$caseData.repeatPrefix * $iteration) + [string]$step.expect
        $report.expected=$expected
        $snapshot=Wait-FixtureText $expected
      } else { $snapshot=Read-Fixture }
      $report.steps += [pscustomobject]@{ iteration=$iteration; id=$step.id; candidate=$step.candidate;
        tapXFraction=$tapXFraction; longPress=([bool]$step.longPress);
        burst=@($step.burst); burstElapsedMs=$burstElapsedMs; burstEngine=$burstEngine;
        expected=$expected; actual=$snapshot.text;
        candidateCount=@($snapshot.nodes | Where-Object { $_.attributes.id -match '^cand_slot_\d+$' }).Count;
        visibleFixtureCandidates=@($snapshot.nodes | Where-Object { $_.attributes.id -match '^cand_slot_\d+$' -and $fixtureCandidates -ccontains $_.attributes.text } | ForEach-Object { $_.attributes.text }) }
    }
  }
  $report.status='passed'
} catch {
  if ($report.status -ne 'environment-wait') { $report.status='failed-or-environment-error' }
  $report.message=$_.Exception.Message
  throw
} finally {
  $report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $fixtureDirectory 'report.json') -Encoding UTF8
  Write-Output ("Input fixture ${Case}: " + $report.status)
  Write-Output ('Report: ' + (Join-Path $fixtureDirectory 'report.json'))
}
