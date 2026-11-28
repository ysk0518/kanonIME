$ErrorActionPreference = 'Stop'
$module = Import-Module (Join-Path $PSScriptRoot 'KanonDevice.psm1') -PassThru -Force
$fixtures = Join-Path $PSScriptRoot '../../tests/fixtures/device'

& $module {
  param($Fixtures)
  $script:Checks = 0

  function Assert-Same($Expected, $Actual, [string]$Label) {
    if ($Expected -cne $Actual) { throw "$Label expected [$Expected], got [$Actual]" }
    $script:Checks++
  }

  function Assert-Throws([scriptblock]$Action, [string]$Message) {
    $caught = $null
    try { & $Action | Out-Null }
    catch { $caught = $_.Exception.Message }
    if (!$caught -or $caught -notmatch $Message) { throw "Expected /$Message/, got [$caught]" }
    $script:Checks++
  }

  function Read-Sample([string]$Name) {
    Get-Content -LiteralPath (Join-Path $Fixtures $Name) -Raw -Encoding UTF8
  }

  function Read-LayoutSample([string]$Name) {
    Read-Sample $Name | ConvertFrom-Json
  }

  # This replacement covers every command path. Unexpected calls fail in memory.
  function script:Invoke-DeviceHdc([string]$Target, [string[]]$Arguments) {
    $command = $Arguments -join ' '
    $script:Commands.Add($command)
    if ($command -ne 'list targets' -and $Target -cne 'fixture-device') { throw "Wrong target: $Target" }
    switch -Regex ($command) {
      '^list targets$' { return $script:TargetList }
      '^shell hidumper -s ScreenlockService -a -all$' { return $script:LockSample }
      '^shell hidumper -s 3301 -a -a$' { return $script:PowerSample }
      '^shell aa dump -l$' { return $script:MissionSample }
      '^shell ime -g$' { return $script:ImeSample }
      '^shell ime -s local\.yplic\.kanon$' { $script:ImeSample = $script:KanonIme; return }
      '^shell uitest dumpLayout -p ' { return }
      '^file recv .*kanon-layout-' {
        if ($script:EnglishMode -and $script:LayoutFile -eq $script:KeyboardLayout) {
          $sample = Get-Content -LiteralPath $script:LayoutFile -Raw -Encoding UTF8
          $sample.Replace('日本語 ␣', 'English ␣') | Set-Content -LiteralPath $Arguments[3] -Encoding UTF8
        } else {
          Copy-Item -LiteralPath $script:LayoutFile -Destination $Arguments[3]
        }
        return
      }
      '^shell rm -f /data/local/tmp/kanon-layout-' { return }
      '^shell uitest uiInput swipe ' { return }
      '^shell uinput -T -c ' {
        if ($script:Setting) {
          switch ($command) {
            'shell uinput -T -c 911 1110' { $script:SavedColorLayout = $script:DarkLayout }
            'shell uinput -T -c 348 1110' { $script:SavedColorLayout = $script:LightLayout }
            default { throw "Unexpected color tap: $command" }
          }
          $script:LayoutFile = $script:SavedColorLayout
        } elseif ($script:EnglishMode) { $script:EnglishMode = $false }
        return
      }
      '^shell aa start -b com\.huawei\.hmos\.settings ' {
        $script:Setting = $true
        $script:MissionSample = $script:SettingsMission
        $script:LayoutFile = $script:SavedColorLayout
        return
      }
      '^shell uitest uiInput keyEvent Back$' {
        $script:Setting = $false
        $script:MissionSample = $script:PreviewMission
        $script:LayoutFile = $script:KeyboardLayout
        return
      }
      '^shell power-shell setmode (600|602)$' { return }
      default { throw "Unexpected fixture command: $command" }
    }
  }

  $unlocked = Read-Sample 'screenlock-unlocked.txt'
  $locked = Read-Sample 'screenlock-locked.txt'
  Assert-Same $true (ConvertFrom-ScreenlockDump $unlocked).ScreenOn 'screen on'
  Assert-Same $false (ConvertFrom-ScreenlockDump $unlocked).Locked 'unlocked'
  Assert-Same $true (ConvertFrom-ScreenlockDump $locked).Locked 'locked'
  Assert-Same $true (ConvertFrom-ScreenlockDump ($locked -replace '(screenLocked\s+)true', '$1false')).Locked 'device lock alone'
  Assert-Same $null (ConvertFrom-ScreenlockDump '').Locked 'missing lock data'
  Assert-Same $true (ConvertFrom-PowerDump (Read-Sample 'power-awake.txt')) 'awake'
  Assert-Same $false (ConvertFrom-PowerDump (Read-Sample 'power-asleep.txt')) 'sleep'
  Assert-Same $null (ConvertFrom-PowerDump '') 'missing power data'

  $front = ConvertFrom-MissionDump (Read-Sample 'missions-other-foreground.txt')
  Assert-Same 'com.example.app' $front.Bundle 'foreground app with Kanon in background'
  Assert-Same 'entry' $front.Module 'foreground module'
  Assert-Same 'EntryAbility' $front.Ability 'mission ability'
  Assert-Same 'local.yplic.kanon' (ConvertFrom-MissionDump (Read-Sample 'missions-kanon-foreground.txt')).Bundle 'Kanon foreground'
  Assert-Same 'local.yplic.kanon' (ConvertFrom-ImeOutput (Read-Sample 'ime-current.txt')) 'selected IME'
  Assert-Same $null (ConvertFrom-ImeOutput '[Empty]') 'unknown IME'

  $preview = Read-LayoutSample 'layout-preview-keyboard.json'
  $keyboard = Read-KeyboardLayout $preview
  Assert-Same $true $keyboard.KeyboardVisible 'keyboard visible'
  Assert-Same 'JP' $keyboard.InputMode '12-key Japanese mode'
  Assert-Same '12KEY' $keyboard.Layout 'flick layout'
  $nodes = @(Get-VisibleUiNodes $preview)
  $space = @(Select-UiNodes $nodes Id flick_convert_space)[0]
  $space.attributes.id = 'spaceItem'
  $space.attributes.text = 'English ␣'
  @(Select-UiNodes $nodes TextLike '^English\b')[0].attributes.id | ForEach-Object { Assert-Same 'spaceItem' $_ 'regex match' }
  @(Select-UiNodes $nodes Id flick_あ)[0].attributes.id = 'qwerty_k'
  $keyboard = Read-KeyboardLayout $preview
  Assert-Same 'EN' $keyboard.InputMode 'English space label'
  Assert-Same 'QWERTY' $keyboard.Layout 'QWERTY marker'

  # The English 12-key space key has no id; its label still gives the mode.
  $english12 = Read-KeyboardLayout (Read-LayoutSample 'layout-12key-english.json')
  Assert-Same $true $english12.KeyboardVisible 'English 12-key keyboard visible'
  Assert-Same 'EN' $english12.InputMode 'English 12-key mode from the unnamed space key'
  Assert-Same '12KEY' $english12.Layout 'English 12-key layout'

  $lockLayout = Read-LayoutSample 'layout-lockscreen.json'
  Assert-Same 1 @(Select-UiNodes @(Get-VisibleUiNodes $lockLayout) Id ScreenLockRootComponent).Count 'lockscreen marker'
  Assert-Same $false (Read-KeyboardLayout $lockLayout).KeyboardVisible 'no Kanon keyboard on lockscreen'
  $light = Read-LayoutSample 'layout-settings-display-light.json'
  $dark = Read-LayoutSample 'layout-settings-display-dark.json'
  Assert-Same 'Light' (Read-ColorLayout $light) 'selected light card'
  Assert-Same 'Dark' (Read-ColorLayout $dark) 'selected dark card'
  Assert-Same $null (Read-ColorLayout $lockLayout) 'missing color cards'
  $card = @(Select-UiNodes @(Get-VisibleUiNodes $light) Text 'ライト, tab_unlock')[0]
  Assert-Same 67 (ConvertFrom-UiBounds $card.attributes.bounds).Left 'card left edge'
  $point = Get-UiTapPoint $card $light 0.5 0.5
  Assert-Same 348 $point.X 'card center x'
  Assert-Same 1110 $point.Y 'card center y'
  Assert-Same 629 (Get-UiTapPoint $card $light 1 1).X 'rightmost valid x'
  Assert-Same $null (ConvertFrom-UiBounds '[4,5][4,10]') 'empty bounds'
  Assert-Same $null (ConvertFrom-UiBounds '4,5,9,10') 'invalid bounds'
  $card.attributes.bounds = '[-1,519][630,1701]'
  Assert-Throws { Get-UiTapPoint $card $light 0.5 0.5 } '範囲外'
  $card.attributes.visible = 'false'
  Assert-Same 0 @(Select-UiNodes @(Get-VisibleUiNodes $light) Text 'ライト, tab_unlock').Count 'hidden node excluded'

  $script:Commands = [System.Collections.Generic.List[string]]::new()
  $script:TargetList = '[Empty]'
  Assert-Same $false (Get-KanonDeviceState -Target fixture-device).Connected 'disconnected state'
  Assert-Throws { Save-KanonScreenshot -Path 'no-shot.jpeg' -Target fixture-device } '接続されていません'
  $script:TargetList = "fixture-device`nanother-device"
  Assert-Throws { Assert-KanonDeviceReady } '複数'
  $script:TargetList = 'fixture-device'
  $script:LockSample = $locked
  $script:PowerSample = Read-Sample 'power-awake.txt'
  Assert-Throws { Invoke-KanonUiTap -Id spaceItem } 'ロックされています'
  $script:LockSample = $unlocked
  $script:PowerSample = Read-Sample 'power-asleep.txt'
  Assert-Throws { Save-KanonScreenshot -Path 'no-shot.jpeg' } '画面がオフ'
  Assert-Same 0 @($script:Commands -match 'uinput|snapshot_display').Count 'no device input when unready'

  $script:PowerSample = Read-Sample 'power-awake.txt'
  $script:PreviewMission = Read-Sample 'missions-kanon-foreground.txt'
  $script:MissionSample = $script:PreviewMission
  $script:SettingsMission = $script:PreviewMission.Replace('local.yplic.kanon:entry:EntryAbility',
    'com.huawei.hmos.settings:entry:com.huawei.hmos.settings.MainAbility')
  $script:KanonIme = Read-Sample 'ime-current.txt'
  $script:ImeSample = $script:KanonIme
  $script:KeyboardLayout = Join-Path $Fixtures 'layout-preview-keyboard.json'
  $script:LightLayout = Join-Path $Fixtures 'layout-settings-display-light.json'
  $script:DarkLayout = Join-Path $Fixtures 'layout-settings-display-dark.json'
  $script:SavedColorLayout = $script:LightLayout
  $script:LayoutFile = $script:KeyboardLayout
  Assert-Same $null (Get-KanonDeviceState -SkipLayout).KeyboardVisible 'layout can be skipped'
  Assert-Same 0 @($script:Commands -match 'dumpLayout|aa start').Count 'skip layout and color by default'
  Assert-Same 'JP' (Get-KanonDeviceState).InputMode 'state reads keyboard mode'
  Assert-Throws { Find-KanonUiNode -TextLike '^.*$' } '一致したノードが'
  Assert-Same 'kanon_validation_direct_input' (Find-KanonUiNode -Id kanon_validation_direct_input).attributes.id 'public find'
  Assert-Same 'kanon_validation_direct_input' (Find-KanonUiNode -TextLike '.*' -Index 4).attributes.id 'Index selects in tree order'
  Assert-Throws { Find-KanonUiNode -Id absent -ScrollUntilFound -MaxScrolls 1 } '一致するものがありません'
  Assert-Same 1 @($script:Commands -match '^shell uitest uiInput swipe 40 2503 40 1194 2000$').Count 'bounded left-edge scroll'
  $script:LayoutFile = Join-Path $Fixtures 'layout-lockscreen.json'
  Assert-Throws { Invoke-KanonUiTap -Id ScreenLockRootComponent } 'ロック画面'
  Assert-Same 0 @($script:Commands -match 'uinput').Count 'lockscreen marker blocks taps'
  $script:LayoutFile = $script:KeyboardLayout
  Assert-Same 'Light' (Get-KanonDeviceState -IncludeColorMode).ColorMode 'opt-in color'
  Assert-Same 'local.yplic.kanon' (Get-Foreground fixture-device).Bundle 'color read returns to old app'
  Set-KanonColorMode -Mode Dark
  Assert-Same 1 @($script:Commands -match '^shell uinput -T -c 911 1110$').Count 'dark card tapped and verified'
  Assert-Throws { Set-KanonInputMode -Mode EN } '3 回のタップ'
  Assert-Same 3 @($script:Commands -match '^shell uinput' | Where-Object { $_ -ne 'shell uinput -T -c 911 1110' }).Count 'at most three mode taps (12-key cycles JP, EN and numbers)'
  Assert-Throws {
    Use-KanonDeviceSession {
      Set-KanonColorMode -Mode Light
      $script:EnglishMode = $true
      $script:ImeSample = $script:KanonIme.Replace('local.yplic.kanon', 'com.example.ime')
      throw 'body failure'
    }
  } '^body failure$'
  Assert-Same $script:DarkLayout $script:SavedColorLayout 'failure restores display mode'
  Assert-Same 'local.yplic.kanon' (Get-CurrentIme fixture-device) 'failure restores selected IME'
  Assert-Same 'JP' (Get-KanonInputMode) 'failure restores initial input mode'
  Assert-Same 1 @($script:Commands -match '^shell power-shell setmode 602$').Count 'session enables keep-awake'
  Assert-Same 1 @($script:Commands -match '^shell power-shell setmode 600$').Count 'failure restores sleep timeout'
  Assert-Same 0 $script:Sessions.Count 'finished session removed'
  Write-Output "Passed $script:Checks device assertions."
} $fixtures
