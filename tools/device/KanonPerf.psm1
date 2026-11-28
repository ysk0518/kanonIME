function ConvertFrom-KanonPerfLog {
  param([string]$Log)
  $index = 0
  foreach ($line in ($Log -split '\r?\n')) {
    if ($line -cmatch '^\s*\S+\s+\S+\s+(?<process>\d+)\s+\d+\s+D\s+[Aa]0?4[bB]50/(?:[^\s/]+/)?KanonPerf:\s+P63 (?<event>[a-zA-Z.]+) (?<ms>[0-9]{13}) (?<detail>\S+)\s*$') {
      [pscustomobject]@{
        Index = $index; Pid = [int]$Matches.process; Event = $Matches.event
        WallMs = [long]$Matches.ms; Detail = $Matches.detail
      }
    }
    $index++
  }
}

function Get-OnePerfMark($Marks, [string]$Event) {
  $found = @($Marks | Where-Object Event -CEQ $Event)
  if ($found.Count -ne 1) { throw "Expected one $Event, got $($found.Count)." }
  $found[0]
}

function Get-KanonPerfFrame {
  param([object[]]$Marks)
  $show = Get-OnePerfMark $Marks 'kb.show'
  $frame = Get-OnePerfMark $Marks 'kb.frame'
  if ($show.Pid -ne $frame.Pid -or $show.Index -ge $frame.Index -or $show.WallMs -gt $frame.WallMs) {
    throw 'kb.show and kb.frame do not describe the same display.'
  }
  if ($frame.Detail -cnotmatch '^(?<mode>JP|EN|-)/(?<layout>[a-z_]+|-)/(?<photo>present|absent|unknown)$') {
    throw "Invalid kb.frame detail: $($frame.Detail)"
  }
  [pscustomobject]@{
    Mark = $frame; Mode = $Matches.mode; Layout = $Matches.layout; BackgroundImage = $Matches.photo
  }
}

function Get-KanonPerfKeyIds {
  param($Frame)
  switch -CaseSensitive ($Frame.Layout) {
    'jp_flick' { 'flick_あ'; 'flick_か'; 'flick_さ' }
    'en_flick' { 'flick_a'; 'flick_d'; 'flick_g' }
    'jp_qwerty' { 'qwerty_k'; 'qwerty_a'; 'qwerty_n' }
    'en_qwerty' { 'qwerty_k'; 'qwerty_a'; 'qwerty_n' }
    default { throw "Unsupported layout: $($Frame.Layout)" }
  }
}

function New-PerfInterval([string]$Scenario, [string]$Interval, $Start, $End, $Frame) {
  if ($End.WallMs -lt $Start.WallMs -or ($Start.Pid -eq $End.Pid -and $End.Index -le $Start.Index)) {
    throw "Invalid order for $Scenario $Interval."
  }
  [pscustomobject]@{
    Scenario = $Scenario; Interval = $Interval; Ms = $End.WallMs - $Start.WallMs
    Mode = $Frame.Mode; Layout = $Frame.Layout; BackgroundImage = $Frame.BackgroundImage
  }
}

function Test-PerfSequence($Mark) { $Mark.Detail -cmatch '^[1-9][0-9]*$' }

function Get-KanonPerfIntervals {
  param(
    [ValidateSet('M1', 'M2', 'M3')][string]$Scenario,
    [object[]]$Marks,
    [int]$WarmPid
  )
  $frame = Get-KanonPerfFrame $Marks
  $shown = $frame.Mark
  $ime = @($Marks | Where-Object Pid -EQ $shown.Pid)
  if ($Scenario -eq 'M2') {
    $typing = @($ime | Where-Object Index -GT $shown.Index)
    $downs = @($typing | Where-Object Event -CEQ 'key.down')
    $dones = @($typing | Where-Object Event -CEQ 'key.done')
    if ($downs.Count -ne 3 -or $dones.Count -ne 3) { throw 'Expected three key.down and three key.done marks.' }
    $seen = @{}
    for ($i = 0; $i -lt $downs.Count; $i++) {
      $down = $downs[$i]
      if (!(Test-PerfSequence $down) -or $seen.ContainsKey($down.Detail)) { throw 'Invalid or duplicate key sequence.' }
      $seen[$down.Detail] = $true
      $done = Get-OnePerfMark @($dones | Where-Object Detail -CEQ $down.Detail) 'key.done'
      New-PerfInterval M2 "key.$($i + 1) down -> done" $down $done $frame
    }
    return
  }

  $focus = Get-OnePerfMark $Marks 'field.focus'
  if ($Scenario -eq 'M1') {
    if ($shown.Pid -ne $WarmPid -or @($ime | Where-Object Event -CEQ 'ime.create').Count) {
      throw 'IME restarted during the warm display trial.'
    }
    $inputStart = Get-OnePerfMark $ime 'ime.inputStart'
    New-PerfInterval M1 'field.focus -> ime.inputStart' $focus $inputStart $frame
    New-PerfInterval M1 'ime.inputStart -> kb.frame' $inputStart $shown $frame
    New-PerfInterval M1 'field.focus -> kb.frame' $focus $shown $frame
    return
  }

  $create = Get-OnePerfMark $ime 'ime.create'
  # Multiple prepares can already run concurrently. Use the first successful
  # session acquisition and its own start, even if panel layout completed earlier.
  $end = $ime | Where-Object Event -CEQ 'mozc.init.end' | Select-Object -First 1
  if (!$end -or !(Test-PerfSequence $end)) { throw 'No successful Mozc initialization.' }
  $start = Get-OnePerfMark @($ime | Where-Object Detail -CEQ $end.Detail) 'mozc.init.start'
  if ($start.Index -le $create.Index -or $start.WallMs -lt $create.WallMs -or $shown.Index -le $create.Index) {
    throw 'Mozc initialization or keyboard frame precedes IME creation.'
  }
  # On a cold start the system creates the IME as the field takes focus,
  # often a few milliseconds before the app reports the focus, so time
  # from whichever came first.
  $origin = if ($create.WallMs -lt $focus.WallMs) { $create } else { $focus }
  New-PerfInterval M3 'ime.create -> kb.frame' $create $shown $frame
  New-PerfInterval M3 'ime.create -> mozc.init.start' $create $start $frame
  New-PerfInterval M3 'mozc.init.start -> mozc.init.end' $start $end $frame
  New-PerfInterval M3 'focus or create -> kb.frame' $origin $shown $frame
  New-PerfInterval M3 'focus or create -> mozc.init.end' $origin $end $frame
  # The keyboard can be on screen before Mozc is ready; keys typed in this
  # window wait for the initialization. Zero when Mozc finished first.
  [pscustomobject]@{
    Scenario = 'M3'; Interval = 'kb.frame -> mozc.init.end (not ready)'
    Ms = [Math]::Max(0, $end.WallMs - $shown.WallMs)
    Mode = $frame.Mode; Layout = $frame.Layout; BackgroundImage = $frame.BackgroundImage
  }
}

function Get-KanonPerfStatistics {
  param([long[]]$Milliseconds)
  $sorted = @($Milliseconds | Sort-Object)
  $count = $sorted.Count
  if ($count -eq 0) { return [pscustomobject]@{ Count = 0; Median = $null; P90 = $null; Max = $null } }
  $left = [int][math]::Floor(($count - 1) / 2)
  $right = [int][math]::Floor($count / 2)
  $rank90 = [int][math]::Ceiling(0.9 * $count)
  [pscustomobject]@{
    Count = $count; Median = ($sorted[$left] + $sorted[$right]) / 2
    P90 = $sorted[$rank90 - 1]; Max = $sorted[$count - 1]
  }
}

Export-ModuleMember -Function ConvertFrom-KanonPerfLog, Get-KanonPerfFrame, Get-KanonPerfKeyIds,
  Get-KanonPerfIntervals, Get-KanonPerfStatistics
