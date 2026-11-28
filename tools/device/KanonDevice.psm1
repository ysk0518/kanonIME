$script:DeviceHdc = 'C:/Program Files/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
$script:KanonBundle = 'local.yplic.kanon'
$script:SettingsBundle = 'com.huawei.hmos.settings'
$script:ColorCards = @{ Light = 'ライト, tab_unlock'; Dark = 'ダーク, tab_unlock' }
$script:Sessions = @{}

function ConvertFrom-ScreenlockDump([string]$Dump) {
  $flags = @{}
  foreach ($name in 'screenState', 'screenLocked', 'deviceLocked') {
    $field = [regex]::Match($Dump, "(?m)^[ \t]*\*[ \t]+$name[ \t]+(true|false)\b")
    if ($field.Success) { $flags[$name] = $field.Groups[1].Value -eq 'true' }
  }
  $locked = $null
  if ($flags.screenLocked -eq $true -or $flags.deviceLocked -eq $true) { $locked = $true }
  elseif ($null -ne $flags.screenLocked -and $null -ne $flags.deviceLocked) { $locked = $false }
  [pscustomobject]@{ ScreenOn = $flags.screenState; Locked = $locked }
}

function ConvertFrom-PowerDump([string]$Dump) {
  $state = [regex]::Match($Dump, '(?m)^[ \t]*Current State:[ \t]+([A-Z_]+)\b')
  if ($state.Success) { $state.Groups[1].Value -ceq 'AWAKE' }
}

function ConvertFrom-MissionDump([string]$Dump) {
  foreach ($mission in ($Dump -split '(?m)(?=^[ \t]*Mission ID #)')) {
    if ($mission -match '(?m)^[ \t]*app state #FOREGROUND[ \t\r]*$' -and
        $mission -match 'mission name #\[#([a-zA-Z0-9_.-]+):([a-zA-Z0-9_.-]+):([a-zA-Z0-9_.-]+)\]') {
      return [pscustomobject]@{ Bundle = $Matches[1]; Module = $Matches[2]; Ability = $Matches[3] }
    }
  }
}

function ConvertFrom-ImeOutput([string]$Output) {
  if ($Output -match '(?m)^[ \t]*The current input method is:[ \t]*([a-z0-9_.]+)(?:[ \t]*,|[ \t\r]*$)') {
    $Matches[1]
  }
}

function ConvertFrom-UiBounds([string]$Value) {
  if ($Value -cnotmatch '^\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]$') { return }
  $left, $top, $right, $bottom = 1..4 | ForEach-Object { [int]$Matches[$_] }
  if ($right -le $left -or $bottom -le $top) { return }
  [pscustomobject]@{ Left = $left; Top = $top; Right = $right; Bottom = $bottom }
}

function Get-VisibleUiNodes($Node) {
  if ($null -eq $Node -or [string]$Node.attributes.visible -eq 'false') { return }
  $Node
  foreach ($child in $Node.children) { Get-VisibleUiNodes $child }
}

function Select-UiNodes($Nodes, [string]$Selector, [string]$Value) {
  switch ($Selector) {
    'Id'       { $Nodes | Where-Object { $_.attributes.id -ceq $Value } }
    'Text'     { $Nodes | Where-Object { $_.attributes.text -ceq $Value } }
    'TextLike' {
      $pattern = [regex]::new($Value)
      $Nodes | Where-Object { $pattern.IsMatch([string]$_.attributes.text) }
    }
  }
}

function Get-UiTapPoint($Node, $Layout, [double]$XFraction, [double]$YFraction) {
  $screen = ConvertFrom-UiBounds $Layout.attributes.bounds
  $bounds = ConvertFrom-UiBounds $Node.attributes.bounds
  if (!$screen -or !$bounds -or $screen.Left -lt 0 -or $screen.Top -lt 0 -or
      [string]$Node.attributes.visible -ne 'true' -or
      $bounds.Left -lt $screen.Left -or $bounds.Top -lt $screen.Top -or
      $bounds.Right -gt $screen.Right -or $bounds.Bottom -gt $screen.Bottom) {
    throw 'ノードが非表示か、座標が画面の範囲外です。'
  }
  [pscustomobject]@{
    X = [int][math]::Floor($bounds.Left + ($bounds.Right - $bounds.Left - 1) * $XFraction + 0.5)
    Y = [int][math]::Floor($bounds.Top + ($bounds.Bottom - $bounds.Top - 1) * $YFraction + 0.5)
  }
}

function Read-KeyboardLayout($Layout) {
  $nodes = @(Get-VisibleUiNodes $Layout)
  $mode = $null
  $keyLayout = $null
  if ($nodes.attributes.id -ccontains 'qwerty_k') { $keyLayout = 'QWERTY' }
  elseif ($nodes.attributes.id -cmatch '^flick_') { $keyLayout = '12KEY' }

  $spaces = @(Select-UiNodes $nodes Id spaceItem)
  if ($spaces.Count -eq 0 -and $keyLayout -eq '12KEY') {
    $spaces = @(Select-UiNodes $nodes Id flick_convert_space)
  }
  # The English 12-key space key carries no id, so fall back to the whole
  # keyboard: only the space key shows these labels.
  $labelRoot = if ($spaces.Count -eq 1) { $spaces[0] } elseif ($keyLayout) { $Layout } else { $null }
  if ($labelRoot) {
    $texts = @(Get-VisibleUiNodes $labelRoot).attributes.text
    $jp = $texts -ccontains '日本語 ␣'
    $en = $texts -ccontains 'English ␣'
    if ($jp -and !$en) { $mode = 'JP' }
    elseif ($en -and !$jp) { $mode = 'EN' }
  }
  [pscustomobject]@{
    KeyboardVisible = [bool]($keyLayout -or ($spaces.Count -gt 0 -and $nodes.attributes.id -ccontains 'modeCycleItem'))
    InputMode = $mode
    Layout = $keyLayout
  }
}

function Read-ColorLayout($Layout) {
  $nodes = @(Get-VisibleUiNodes $Layout)
  $selected = @(foreach ($mode in 'Light', 'Dark') {
    $cards = @(Select-UiNodes $nodes Text $script:ColorCards[$mode])
    if ($cards.Count -ne 1 -or [string]$cards[0].attributes.selected -notin @('true', 'false')) { return }
    if ([string]$cards[0].attributes.selected -eq 'true') { $mode }
  })
  if ($selected.Count -eq 1) { $selected[0] }
}

function Invoke-DeviceHdc([string]$Target, [string[]]$Arguments) {
  if (!(Test-Path -LiteralPath $script:DeviceHdc -PathType Leaf)) { throw "hdc が見つかりません。 $script:DeviceHdc" }
  $nativeArguments = $Arguments
  if ($Target) { $nativeArguments = @('-t', $Target) + $Arguments }
  $ErrorActionPreference = 'Continue'
  $PSNativeCommandUseErrorActionPreference = $false
  $output = (& $script:DeviceHdc @nativeArguments 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0 -or $output -match '(?m)^[ \t]*\[(?:Fail|Error)\]') {
    throw "hdc の実行に失敗しました。 $($Arguments -join ' ')`n$output"
  }
  $output
}

function Get-ConnectionState([string]$Target) {
  $targets = @((Invoke-DeviceHdc '' @('list', 'targets')) -split '\r?\n' |
    ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -ne '[Empty]' })
  if (!$Target) {
    if ($targets.Count -gt 1) { throw '複数の端末が接続されています。-Target で対象を指定してください。' }
    if ($targets.Count -eq 1) { $Target = $targets[0] }
  }
  [pscustomobject]@{ Target = $Target; Connected = [bool]($Target -and $targets -ccontains $Target) }
}

function New-DeviceState([string]$Target) {
  $connection = Get-ConnectionState $Target
  $state = [pscustomobject]@{
    Target = $connection.Target; Connected = $connection.Connected; ScreenOn = $null; Locked = $null
    ForegroundBundle = $null; ForegroundAbility = $null; CurrentIme = $null
    KeyboardVisible = $null; InputMode = $null; Layout = $null; ColorMode = $null
  }
  if ($state.Connected) {
    $lock = ConvertFrom-ScreenlockDump (Invoke-DeviceHdc $state.Target @('shell', 'hidumper -s ScreenlockService -a -all'))
    $power = ConvertFrom-PowerDump (Invoke-DeviceHdc $state.Target @('shell', 'hidumper -s 3301 -a -a'))
    $state.Locked = $lock.Locked
    if ($lock.ScreenOn -eq $false -or $power -eq $false) { $state.ScreenOn = $false }
    elseif ($lock.ScreenOn -eq $true -and $power -eq $true) { $state.ScreenOn = $true }
  }
  $state
}

function Assert-KanonDeviceReady {
  [CmdletBinding()]
  param([string]$Target, [switch]$PassThru)
  $state = New-DeviceState $Target
  if (!$state.Connected) { throw '端末が接続されていません。USB 接続と -Target を確認してください。' }
  if ($state.Locked -eq $true) { throw '端末がロックされています。解除してから再実行してください。' }
  if ($state.ScreenOn -eq $false) { throw '端末の画面がオフです。点灯してから再実行してください。' }
  if ($state.Locked -ne $false -or $state.ScreenOn -ne $true) {
    throw '端末の画面やロックの状態を確認できませんでした。'
  }
  if ($PassThru) { $state }
}

function Get-Foreground([string]$Target) {
  ConvertFrom-MissionDump (Invoke-DeviceHdc $Target @('shell', 'aa dump -l'))
}

function Invoke-KanonDeviceShell {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Command, [string]$Target)
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  Invoke-DeviceHdc $device.Target @('shell', $Command)
}

function Get-CurrentIme([string]$Target) {
  ConvertFrom-ImeOutput (Invoke-DeviceHdc $Target @('shell', 'ime -g'))
}

function Receive-DeviceFile([string]$Target, [string]$Remote, [string]$Destination) {
  Invoke-DeviceHdc $Target @('file', 'recv', $Remote, $Destination) | Out-Null
  $file = Get-Item -LiteralPath $Destination -ErrorAction Stop
  if ($file.PSIsContainer -or $file.Length -le 0) { throw "端末から空のファイルを受信しました。 $Remote" }
}

function Remove-DeviceFiles([string]$Target, [string[]]$Paths) {
  for ($start = 0; $start -lt $Paths.Count; $start += 32) {
    $end = [math]::Min($start + 31, $Paths.Count - 1)
    try { Invoke-DeviceHdc $Target @('shell', ('rm -f ' + ($Paths[$start..$end] -join ' '))) | Out-Null }
    catch { Write-Warning "端末の一時ファイルを削除できませんでした。 $($_.Exception.Message)" }
  }
}

function Read-DeviceLayout([string]$Target) {
  $name = 'kanon-layout-' + [guid]::NewGuid().ToString('N') + '.json'
  $local = Join-Path ([IO.Path]::GetTempPath()) $name
  $remote = "/data/local/tmp/$name"
  try {
    Invoke-DeviceHdc $Target @('shell', "uitest dumpLayout -p $remote") | Out-Null
    Receive-DeviceFile $Target $remote $local
    $layout = Get-Content -Raw -Encoding UTF8 -LiteralPath $local -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if (!$layout.attributes) { throw '端末の画面構造を取得できませんでした。' }
    if (@(Select-UiNodes @(Get-VisibleUiNodes $layout) Id ScreenLockRootComponent).Count) {
      throw 'ロック画面が表示されています。解除してから再実行してください。'
    }
    $layout
  } finally {
    Remove-Item -LiteralPath $local -Force -ErrorAction SilentlyContinue
    Remove-DeviceFiles $Target @($remote)
  }
}

function Get-KanonDeviceState {
  [CmdletBinding()]
  param([string]$Target, [switch]$SkipLayout, [switch]$IncludeColorMode)
  $state = New-DeviceState $Target
  if (!$state.Connected) { return $state }
  $front = Get-Foreground $state.Target
  $state.ForegroundBundle = $front.Bundle
  $state.ForegroundAbility = $front.Ability
  $state.CurrentIme = Get-CurrentIme $state.Target
  if (!$SkipLayout -and $state.ScreenOn -eq $true -and $state.Locked -eq $false) {
    $keyboard = Read-KeyboardLayout (Read-DeviceLayout $state.Target)
    $state.KeyboardVisible = $keyboard.KeyboardVisible
    $state.InputMode = $keyboard.InputMode
    $state.Layout = $keyboard.Layout
  }
  if ($IncludeColorMode) { $state.ColorMode = Get-KanonColorMode -Target $state.Target }
  $state
}

function Assert-Foreground([string]$Target, [string]$Bundle, [string]$Ability) {
  $front = Get-Foreground $Target
  if ($front.Bundle -cne $Bundle -or ($Ability -and $front.Ability -cne $Ability)) {
    throw "前面アプリが変わったため操作を中止しました。 期待するアプリ $Bundle $Ability"
  }
}

function Resolve-UiSelection($Options, [string]$Selector, [string]$Target, $ExpectedFront) {
  for ($scroll = 0; ; $scroll++) {
    Assert-KanonDeviceReady -Target $Target
    if ($ExpectedFront) { Assert-Foreground $Target $ExpectedFront.Bundle $ExpectedFront.Ability }
    $layout = Read-DeviceLayout $Target
    $nodes = @(Select-UiNodes @(Get-VisibleUiNodes $layout) $Selector $Options[$Selector])
    if ($nodes.Count) {
      if ($Options.ContainsKey('Index')) {
        if ($Options.Index -ge $nodes.Count) { throw "一致したノードは $($nodes.Count) 件です。-Index は 0 から数えます。" }
        $node = $nodes[$Options.Index]
      } elseif ($nodes.Count -eq 1) {
        $node = $nodes[0]
      } else {
        throw "一致したノードが $($nodes.Count) 件あります。-Index で指定してください。"
      }
      return [pscustomobject]@{ Node = $node; Layout = $layout }
    }
    $maxScrolls = 5
    if ($Options.ContainsKey('MaxScrolls')) { $maxScrolls = $Options.MaxScrolls }
    if (!$Options.ScrollUntilFound -or $scroll -ge $maxScrolls) {
      throw "表示中のノードに一致するものがありません。 $Selector=$($Options[$Selector])"
    }
    $screen = ConvertFrom-UiBounds $layout.attributes.bounds
    if (!$screen) { throw '画面の範囲を取得できなかったためスクロールできません。' }
    $x = $screen.Left + [int](($screen.Right - $screen.Left) * 0.032)
    $height = $screen.Bottom - $screen.Top
    $start = $screen.Top + [int]($height * 0.88)
    $end = $screen.Top + [int]($height * 0.42)
    Assert-KanonDeviceReady -Target $Target
    if ($ExpectedFront) { Assert-Foreground $Target $ExpectedFront.Bundle $ExpectedFront.Ability }
    Invoke-DeviceHdc $Target @('shell', "uitest uiInput swipe $x $start $x $end 2000") | Out-Null
    Start-Sleep -Milliseconds 350
  }
}

function Find-KanonUiNode {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ParameterSetName='Id')][string]$Id,
    [Parameter(Mandatory, ParameterSetName='Text')][string]$Text,
    [Parameter(Mandatory, ParameterSetName='TextLike')][string]$TextLike,
    [string]$Target, [ValidateRange(0, 2147483647)][int]$Index,
    [switch]$ScrollUntilFound, [ValidateRange(0, 50)][int]$MaxScrolls = 5
  )
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $front = $null
  if ($ScrollUntilFound) {
    $front = Get-Foreground $device.Target
    if (!$front) { throw 'スクロールする前面アプリを確認できませんでした。' }
  }
  (Resolve-UiSelection $PSBoundParameters $PSCmdlet.ParameterSetName $device.Target $front).Node
}

function Send-UiTap([string]$Target, $Selection, $ExpectedFront, [double]$XFraction = 0.5, [double]$YFraction = 0.5) {
  $point = Get-UiTapPoint $Selection.Node $Selection.Layout $XFraction $YFraction
  Assert-KanonDeviceReady -Target $Target
  Assert-Foreground $Target $ExpectedFront.Bundle $ExpectedFront.Ability
  Invoke-DeviceHdc $Target @('shell', "uinput -T -c $($point.X) $($point.Y)") | Out-Null
}

function Invoke-KanonUiTap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ParameterSetName='Id')][string]$Id,
    [Parameter(Mandatory, ParameterSetName='Text')][string]$Text,
    [Parameter(Mandatory, ParameterSetName='TextLike')][string]$TextLike,
    [string]$Target, [ValidateRange(0, 2147483647)][int]$Index,
    [switch]$ScrollUntilFound, [ValidateRange(0, 50)][int]$MaxScrolls = 5,
    [ValidateRange(0.0, 1.0)][double]$XFraction = 0.5,
    [ValidateRange(0.0, 1.0)][double]$YFraction = 0.5
  )
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $front = Get-Foreground $device.Target
  if (!$front) { throw 'タップする前面アプリを確認できませんでした。' }
  $selection = Resolve-UiSelection $PSBoundParameters $PSCmdlet.ParameterSetName $device.Target $front
  Send-UiTap $device.Target $selection $front $XFraction $YFraction
}



function Enter-SettingsApp([string]$Target) {
  Assert-KanonDeviceReady -Target $Target
  Invoke-DeviceHdc $Target @('shell', "aa start -b $script:SettingsBundle -a com.huawei.hmos.settings.MainAbility") | Out-Null
  Wait-Foreground $Target $script:SettingsBundle
}

function Test-Foreground($Actual, $Expected) {
  $Actual.Bundle -ceq $Expected.Bundle -and $Actual.Ability -ceq $Expected.Ability -and $Actual.Module -ceq $Expected.Module
}

function Wait-Foreground([string]$Target, [string]$Bundle, [string]$Ability) {
  for ($attempt = 0; $attempt -lt 8; $attempt++) {
    $front = Get-Foreground $Target
    if ($front.Bundle -ceq $Bundle -and (!$Ability -or $front.Ability -ceq $Ability)) { return }
    Start-Sleep -Milliseconds 250
  }
  throw "前面アプリの切り替えを確認できませんでした。 $Bundle $Ability"
}

function Restore-Foreground([string]$Target, $Original) {
  if (Test-Foreground (Get-Foreground $Target) $Original) { return }
  Assert-KanonDeviceReady -Target $Target
  Invoke-DeviceHdc $Target @('shell', "aa start -b $($Original.Bundle) -m $($Original.Module) -a $($Original.Ability)") | Out-Null
  Wait-Foreground $Target $Original.Bundle $Original.Ability
}

function Invoke-ColorMode([string]$Target, [string]$Mode) {
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $Target = $device.Target
  $original = Get-Foreground $Target
  if (!$original) { throw '元の前面アプリを確認できないため、設定を開けません。' }
  $originalIsSettings = $original.Bundle -ceq $script:SettingsBundle
  $displayOpened = $false
  $settings = @{ Bundle = $script:SettingsBundle }
  # Opening the settings app hides the keyboard. Remember the focused field
  # so the keyboard can be brought back on the original page afterwards.
  $focusedId = $null
  if (!$originalIsSettings) {
    $focused = @(Get-VisibleUiNodes (Read-DeviceLayout $Target) | Where-Object {
      $_.attributes.type -cin @('TextInput', 'TextArea', 'textField') -and
        [string]$_.attributes.focused -eq 'true' -and $_.attributes.id
    })
    if ($focused.Count -eq 1) { $focusedId = [string]$focused[0].attributes.id }
  }
  try {
    if (!$originalIsSettings) { Enter-SettingsApp $Target }
    Assert-Foreground $Target $settings.Bundle
    $current = Read-ColorLayout (Read-DeviceLayout $Target)
    if (!$current) {
      $selection = Resolve-UiSelection @{ Text = 'ディスプレイと画面の明るさ'; ScrollUntilFound = $true } Text $Target $settings
      Send-UiTap $Target $selection $settings
      $displayOpened = $true
      Start-Sleep -Milliseconds 500
      Assert-Foreground $Target $settings.Bundle
      $current = Read-ColorLayout (Read-DeviceLayout $Target)
    }
    if (!$current) { throw 'ライト／ダークの選択状態を確認できませんでした。' }
    if ($Mode -and $current -ne $Mode) {
      $selection = Resolve-UiSelection @{ Text = $script:ColorCards[$Mode] } Text $Target $settings
      Send-UiTap $Target $selection $settings
      for ($attempt = 0; $attempt -lt 6; $attempt++) {
        Start-Sleep -Milliseconds 300
        Assert-Foreground $Target $settings.Bundle
        $current = Read-ColorLayout (Read-DeviceLayout $Target)
        if ($current -eq $Mode) { break }
      }
      if ($current -ne $Mode) { throw "表示モードが $Mode に切り替わりませんでした。" }
    }
    $current
  } finally {
    try {
      # Back returns to the original task with its page kept; starting the
      # ability again would reopen its first page. The display page sits one
      # level below the settings home, so leaving can take two presses.
      $backs = if ($originalIsSettings) { [int]$displayOpened } else { 3 }
      for ($press = 0; $press -lt $backs; $press++) {
        if ((Get-Foreground $Target).Bundle -cne $script:SettingsBundle) { break }
        Assert-KanonDeviceReady -Target $Target
        Invoke-DeviceHdc $Target @('shell', 'uitest uiInput keyEvent Back') | Out-Null
        Start-Sleep -Milliseconds 400
      }
    } finally {
      Restore-Foreground $Target $original
      if ($focusedId) {
        $layout = Read-DeviceLayout $Target
        if (!(Read-KeyboardLayout $layout).KeyboardVisible) {
          $selection = Resolve-UiSelection @{ Id = $focusedId } Id $Target $original
          Send-UiTap $Target $selection $original
          Start-Sleep -Milliseconds 600
        }
      }
    }
  }
}

function Get-KanonColorMode {
  [CmdletBinding()]
  param([string]$Target)
  Invoke-ColorMode $Target
}

function Set-KanonColorMode {
  [CmdletBinding()]
  param([Parameter(Mandatory)][ValidateSet('Light', 'Dark')][string]$Mode, [string]$Target)
  Invoke-ColorMode $Target $Mode | Out-Null
}

function Get-KanonInputMode {
  [CmdletBinding()]
  param([string]$Target)
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $keyboard = Read-KeyboardLayout (Read-DeviceLayout $device.Target)
  if (!$keyboard.KeyboardVisible -or !$keyboard.InputMode) {
    throw 'Kanon の入力モードが確認できません。入力欄をフォーカスし、キーボードを表示してください。'
  }
  $keyboard.InputMode
}

function Set-KanonInputMode {
  [CmdletBinding()]
  param([Parameter(Mandatory)][ValidateSet('JP', 'EN')][string]$Mode, [string]$Target)
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $front = Get-Foreground $device.Target
  if (!$front) { throw 'Kanon が表示されている前面アプリを確認できませんでした。' }
  # The 12-key mode key cycles Japanese, English and numbers, so up to three
  # presses can be needed; the number mode shows no language label.
  for ($attempt = 0; $attempt -le 3; $attempt++) {
    Assert-Foreground $device.Target $front.Bundle $front.Ability
    $layout = Read-DeviceLayout $device.Target
    $keyboard = Read-KeyboardLayout $layout
    $nodes = @(Select-UiNodes @(Get-VisibleUiNodes $layout) Id modeCycleItem)
    if ($nodes.Count -eq 0) {
      throw 'Kanon の入力モードが確認できません。入力欄をフォーカスし、キーボードを表示してください。'
    }
    if ($keyboard.InputMode -eq $Mode) { return }
    if ($attempt -eq 3) { break }
    if ($nodes.Count -ne 1) { throw 'Kanon の入力モード切替キーを一意に特定できませんでした。' }
    Send-UiTap $device.Target @{ Node = $nodes[0]; Layout = $layout } $front
    Start-Sleep -Milliseconds 400
  }
  throw "入力モードが 3 回のタップで $Mode に切り替わりませんでした。"
}

function Save-DeviceFrames([string]$Target, [string[]]$Files, [int]$IntervalMs) {
  $nonce = [guid]::NewGuid().ToString('N')
  $paths = [System.Collections.Generic.List[string]]::new()
  try {
    for ($i = 0; $i -lt $Files.Count; $i++) {
      Assert-KanonDeviceReady -Target $Target
      $remote = "/data/local/tmp/kanon-shot-$nonce-$i.jpeg"
      $paths.Add($remote)
      Invoke-DeviceHdc $Target @('shell', "snapshot_display -f $remote") | Out-Null
      if ($IntervalMs -gt 0 -and $i + 1 -lt $Files.Count) { Start-Sleep -Milliseconds $IntervalMs }
    }
    for ($i = 0; $i -lt $Files.Count; $i++) {
      $temporary = Join-Path ([IO.Path]::GetDirectoryName($Files[$i])) "kanon-shot-$nonce-$i.jpeg"
      try {
        Receive-DeviceFile $Target $paths[$i] $temporary
        Move-Item -LiteralPath $temporary -Destination $Files[$i] -Force -ErrorAction Stop
      } finally {
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
      }
    }
  } finally {
    Remove-DeviceFiles $Target ($paths.ToArray())
  }
}

function Get-LocalPath([string]$Path) {
  $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Save-KanonScreenshot {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Path, [string]$Target)
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $file = Get-LocalPath $Path
  if (Test-Path -LiteralPath $file -PathType Container) { throw '撮影先には JPEG ファイルのパスを指定してください。' }
  $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
  Save-DeviceFrames $device.Target @($file) 0
  Get-Item -LiteralPath $file
}

function Write-FrameSheet([string[]]$Files, $CropBounds, [string]$Path, [int]$Columns) {
  $bitmap = $graphics = $null
  $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
  try {
    $Columns = [math]::Min($Columns, $Files.Count)
    $rows = [int][math]::Ceiling($Files.Count / $Columns)
    for ($i = 0; $i -lt $Files.Count; $i++) {
      $image = [System.Drawing.Image]::FromFile($Files[$i])
      try {
        $bounds = $CropBounds
        if (!$bounds) { $bounds = @{ Left = 0; Top = 0; Right = $image.Width; Bottom = $image.Height } }
        if ($bounds.Right -gt $image.Width -or $bounds.Bottom -gt $image.Height) {
          throw "切り出し範囲が画像の外にあります。 $($Files[$i])"
        }
        $width = $bounds.Right - $bounds.Left
        $height = $bounds.Bottom - $bounds.Top
        if (!$bitmap) {
          $bitmap = [System.Drawing.Bitmap]::new($Columns * $width, $rows * $height)
          $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        }
        if ($bitmap.Width -ne $Columns * $width -or $bitmap.Height -ne $rows * $height) {
          throw 'フレームサイズが途中で変わりました。'
        }
        $source = [System.Drawing.Rectangle]::new($bounds.Left, $bounds.Top, $width, $height)
        $destination = [System.Drawing.Rectangle]::new(($i % $Columns) * $width,
          [int][math]::Floor($i / $Columns) * $height, $width, $height)
        $graphics.DrawImage($image, $destination, $source, [System.Drawing.GraphicsUnit]::Pixel)
      } finally { $image.Dispose() }
    }
    $format = [System.Drawing.Imaging.ImageFormat]::Jpeg
    if ([IO.Path]::GetExtension($Path) -eq '.png') { $format = [System.Drawing.Imaging.ImageFormat]::Png }
    $bitmap.Save($temporary, $format)
    Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
  } finally {
    if ($graphics) { $graphics.Dispose() }
    if ($bitmap) { $bitmap.Dispose() }
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
  }
}

function Save-KanonBurst {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ValidateRange(1, 1000)][int]$Count,
    [Parameter(Mandatory)][ValidateRange(0, 2147483647)][int]$IntervalMs,
    [Parameter(Mandatory)][string]$OutDir,
    [string]$Crop, [string]$SheetPath, [ValidateRange(1, 1000)][int]$Columns = 4, [string]$Target
  )
  $cropBounds = $null
  if ($Crop) {
    if ($Crop -notmatch '^\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$') {
      throw '切り出し範囲は l,t,r,b で指定してください。'
    }
    $cropBounds = ConvertFrom-UiBounds "[$($Matches[1]),$($Matches[2])][$($Matches[3]),$($Matches[4])]"
    if (!$cropBounds) { throw '切り出し範囲には正の幅と高さが必要です。' }
  }
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $directory = Get-LocalPath $OutDir
  $frames = @(1..$Count | ForEach-Object { Join-Path $directory ('frame-{0:D3}.jpeg' -f $_) })
  if ($Crop -and !$SheetPath) { $SheetPath = Join-Path $directory 'sheet.jpeg' }
  if ($SheetPath) {
    $SheetPath = Get-LocalPath $SheetPath
    if ([IO.Path]::GetExtension($SheetPath) -notin @('.jpeg', '.jpg', '.png') -or
        $SheetPath -in $frames -or (Test-Path -LiteralPath $SheetPath -PathType Container)) {
      throw 'シートにはフレームとは別の JPEG または PNG ファイルのパスを指定してください。'
    }
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $null = [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($SheetPath))
  }
  $null = [IO.Directory]::CreateDirectory($directory)
  foreach ($file in $frames) {
    if (Test-Path -LiteralPath $file -PathType Container) { throw "撮影先に同名のフォルダーがあります。 $file" }
  }
  Save-DeviceFrames $device.Target $frames $IntervalMs
  if ($SheetPath) { Write-FrameSheet $frames $cropBounds $SheetPath $Columns }
  [pscustomobject]@{ Frames = $frames; SheetPath = $SheetPath }
}



function Start-KanonDeviceSession {
  [CmdletBinding()]
  param([string]$Target)
  $device = Assert-KanonDeviceReady -Target $Target -PassThru
  $Target = $device.Target
  if ($script:Sessions.ContainsKey($Target)) { throw "端末 $Target のセッションを先に終了してください。" }
  $original = Get-Foreground $Target
  $ime = Get-CurrentIme $Target
  if (!$original -or !$ime) { throw '前面アプリまたは現在の IME を確認できませんでした。' }
  $inputMode = $focusedId = $null
  if ($ime -eq $script:KanonBundle) {
    $layout = Read-DeviceLayout $Target
    $keyboard = Read-KeyboardLayout $layout
    if ($keyboard.KeyboardVisible -and !$keyboard.InputMode) { throw '現在の Kanon 入力モードを記録できませんでした。' }
    if ($keyboard.KeyboardVisible) {
      $inputMode = $keyboard.InputMode
      $focused = @(Get-VisibleUiNodes $layout | Where-Object {
        $_.attributes.type -cin @('TextInput', 'TextArea', 'textField') -and
          [string]$_.attributes.focused -eq 'true' -and $_.attributes.id
      })
      if ($focused.Count -eq 1) { $focusedId = $focused[0].attributes.id }
    }
  }

  $session = [pscustomobject]@{
    Target = $Target; ColorMode = $null; InputMode = $inputMode; CurrentIme = $ime
    Foreground = $original; FocusedId = $focusedId
    PendingColor = $false; PendingIme = $false; PendingInput = $false; PendingPower = $true
  }
  $script:Sessions[$Target] = $session
  try {
    Assert-KanonDeviceReady -Target $Target
    Set-DevicePowerMode $Target 602
    $session.ColorMode = Get-KanonColorMode -Target $Target
    $session.PendingColor = $true
    $session.PendingIme = $true
    $session.PendingInput = [bool]$inputMode
    $session
  } catch {
    try { Stop-KanonDeviceSession -Target $Target }
    catch { Write-Warning $_.Exception.Message }
    throw
  }
}

function Set-DevicePowerMode([string]$Target, [int]$Mode) {
  $result = Invoke-DeviceHdc $Target @('shell', "power-shell setmode $Mode")
  if ($result -match '\b(?:fail(?:ed|ure)?|error)\b') {
    throw "画面の電源設定を切り替えられませんでした。 $result"
  }
}

function Restore-SessionInputMode($Session) {
  $target = $Session.Target
  Assert-KanonDeviceReady -Target $target
  $keyboard = Read-KeyboardLayout (Read-DeviceLayout $target)
  if (!$keyboard.KeyboardVisible -and $Session.FocusedId) {
    Restore-Foreground $target $Session.Foreground
    $selection = Resolve-UiSelection @{ Id = $Session.FocusedId } Id $target $Session.Foreground
    if ($selection.Node.attributes.type -cnotin @('TextInput', 'TextArea', 'textField')) {
      throw '記録した入力欄を確認できませんでした。'
    }
    Send-UiTap $target $selection $Session.Foreground
    Start-Sleep -Milliseconds 500
  }
  Set-KanonInputMode -Target $target -Mode $Session.InputMode
}

function Stop-KanonDeviceSession {
  [CmdletBinding(DefaultParameterSetName='Target')]
  param(
    [Parameter(Mandatory, Position=0, ParameterSetName='Session')][psobject]$Session,
    [Parameter(ParameterSetName='Target')][string]$Target
  )
  if ($PSCmdlet.ParameterSetName -eq 'Session') {
    $Target = $Session.Target
    if (!$Target -or ![object]::ReferenceEquals($Session, $script:Sessions[$Target])) { return }
  } elseif (!$Target) {
    if ($script:Sessions.Count -eq 0) { return }
    if ($script:Sessions.Count -gt 1) { throw '終了するセッションを -Target で指定してください。' }
    $Target = @($script:Sessions.Keys)[0]
  }
  $Session = $script:Sessions[$Target]
  if (!$Session) { return }

  $failures = [System.Collections.Generic.List[string]]::new()
  if ($Session.PendingColor) {
    try {
      Set-KanonColorMode -Target $Target -Mode $Session.ColorMode
      $Session.PendingColor = $false
    } catch { $failures.Add("表示モード: $($_.Exception.Message)") }
  }
  if ($Session.PendingIme) {
    try {
      Assert-KanonDeviceReady -Target $Target
      if ((Get-CurrentIme $Target) -cne $Session.CurrentIme) {
        Invoke-DeviceHdc $Target @('shell', "ime -s $($Session.CurrentIme)") | Out-Null
        Start-Sleep -Milliseconds 400
        if ((Get-CurrentIme $Target) -cne $Session.CurrentIme) { throw '元の IME に切り替わりませんでした。' }
      }
      $Session.PendingIme = $false
    } catch { $failures.Add("IME: $($_.Exception.Message)") }
  }
  if ($Session.PendingInput) {
    try {
      if ((Get-CurrentIme $Target) -cne $Session.CurrentIme) { throw '元の IME を選択してから再実行してください。' }
      Restore-SessionInputMode $Session
      $Session.PendingInput = $false
    } catch { $failures.Add("入力モード: $($_.Exception.Message)") }
  }
  if ($Session.PendingPower) {
    try {
      if (!(Get-ConnectionState $Target).Connected) { throw '端末が接続されていません。' }
      # Restore normal timeout even if the screen locked during the session.
      Set-DevicePowerMode $Target 600
      $Session.PendingPower = $false
    } catch { $failures.Add("画面の自動消灯: $($_.Exception.Message)") }
  }
  if ($failures.Count) {
    throw "端末 $Target のセッションを復元できませんでした。原因を解消して Stop-KanonDeviceSession -Target を再実行してください。`n$($failures -join "`n")"
  }
  $script:Sessions.Remove($Target)
}

function Use-KanonDeviceSession {
  [CmdletBinding()]
  param([Parameter(Mandatory, Position=0)][scriptblock]$ScriptBlock, [string]$Target)
  $session = Start-KanonDeviceSession -Target $Target
  $bodyFailed = $false
  try { & $ScriptBlock $session }
  catch {
    $bodyFailed = $true
    throw
  } finally {
    try { Stop-KanonDeviceSession -Session $session }
    catch {
      if (!$bodyFailed) { throw }
      Write-Warning $_.Exception.Message
    }
  }
}

Export-ModuleMember -Function @(
  'Get-KanonDeviceState', 'Assert-KanonDeviceReady', 'Find-KanonUiNode', 'Invoke-KanonUiTap', 'Invoke-KanonDeviceShell',
  'Save-KanonScreenshot', 'Save-KanonBurst', 'Get-KanonColorMode', 'Set-KanonColorMode',
  'Get-KanonInputMode', 'Set-KanonInputMode',
  'Start-KanonDeviceSession', 'Stop-KanonDeviceSession', 'Use-KanonDeviceSession'
)

