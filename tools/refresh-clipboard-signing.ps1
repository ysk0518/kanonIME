param(
  [ValidateSet('OpenSigning', 'Inspect', 'Capture', 'Click', 'Keys', 'Session')][string]$Action = 'Inspect',
  [double]$X = 0, [double]$Y = 0, [string]$Keys = ''
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KanonSigningWindow {
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
}
'@
[KanonSigningWindow]::ShowWindow([KanonSigningWindow]::GetConsoleWindow(), 0) | Out-Null
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$taskRoot = [System.Windows.Automation.AutomationElement]::RootElement
$taskWindows = $taskRoot.FindAll([System.Windows.Automation.TreeScope]::Children,
  [System.Windows.Automation.Condition]::TrueCondition)
$taskWindow = $null
for ($taskIndex = 0; $taskIndex -lt $taskWindows.Count; $taskIndex++) {
  $taskCandidate = $taskWindows.Item($taskIndex)
  $taskProcess = Get-Process -Id $taskCandidate.Current.ProcessId -ErrorAction SilentlyContinue
  if ($taskProcess.ProcessName -eq 'devecostudio64' -and $taskCandidate.Current.Name -match 'KanonIME') {
    $taskWindow = $taskCandidate
    break
  }
}
if ($null -eq $taskWindow) { throw 'KanonIME DevEco Studio window not found.' }
$taskShell = New-Object -ComObject WScript.Shell
function Focus-KanonSigningWindow {
  $taskDialog = $taskWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Project Structure')))
  $taskTarget = if ($null -ne $taskDialog) { $taskDialog } else { $taskWindow }
  [KanonSigningWindow]::SetForegroundWindow([IntPtr]$taskTarget.Current.NativeWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 300
  [uint32]$taskForegroundPid = 0
  [KanonSigningWindow]::GetWindowThreadProcessId([KanonSigningWindow]::GetForegroundWindow(), [ref]$taskForegroundPid) | Out-Null
  if ($taskForegroundPid -ne $taskWindow.Current.ProcessId) { throw 'DevEco Studio is not in the foreground. No input was sent.' }
}
if ($Action -ne 'Capture') {
  Focus-KanonSigningWindow
}
Start-Sleep -Milliseconds 300
if ($Action -eq 'Click') {
  if ($X -le 0 -or $X -ge 1 -or $Y -le 0 -or $Y -ge 1) { throw 'Click must stay inside KanonIME window.' }
  $taskClickBounds = $taskWindow.Current.BoundingRectangle
  [KanonSigningWindow]::SetCursorPos([int]($taskClickBounds.X + $X * $taskClickBounds.Width),
    [int]($taskClickBounds.Y + $Y * $taskClickBounds.Height)) | Out-Null
  [KanonSigningWindow]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  [KanonSigningWindow]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 500
}
if ($Action -eq 'Keys') { $taskShell.SendKeys($Keys); Start-Sleep -Milliseconds 500 }
if ($Action -eq 'OpenSigning' -or $Action -eq 'Session') {
  $taskShell.SendKeys('^%+s')
  Start-Sleep -Milliseconds 4000
  $taskDialog = $taskWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Project Structure')))
  if ($null -eq $taskDialog) { throw 'Project Structure did not open. Signing configuration was not changed.' }
}
if ($Action -eq 'Inspect' -or $Action -eq 'OpenSigning') {
  $taskElements = $taskWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    [System.Windows.Automation.Condition]::TrueCondition)
  for ($taskIndex = 0; $taskIndex -lt [Math]::Min($taskElements.Count, 120); $taskIndex++) {
    $taskElement = $taskElements.Item($taskIndex)
    if ($taskElement.Current.Name.Length -gt 0 -and -not $taskElement.Current.IsPassword) {
      [pscustomobject]@{name=$taskElement.Current.Name; type=$taskElement.Current.ControlType.ProgrammaticName}
    }
  }
}
Add-Type -AssemblyName System.Drawing
function Save-KanonSigningScreenshot {
$taskBounds = $taskWindow.Current.BoundingRectangle
$taskBitmap = New-Object System.Drawing.Bitmap([int]$taskBounds.Width, [int]$taskBounds.Height)
$taskGraphics = [System.Drawing.Graphics]::FromImage($taskBitmap)
try {
  $taskGraphics.CopyFromScreen([int]$taskBounds.X, [int]$taskBounds.Y, 0, 0, $taskBitmap.Size)
  $taskOutput = Join-Path $PSScriptRoot '../.local/screenshots/signing'
  New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
  $taskBitmap.Save((Join-Path $taskOutput 'deveco-signing.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally { $taskGraphics.Dispose(); $taskBitmap.Dispose(); }
}
Save-KanonSigningScreenshot
if ($Action -eq 'Session') {
  Write-Output 'Signing session ready. Commands: click <x fraction> <y fraction>, key <SendKeys>, capture, exit.'
  while ($true) {
    $taskInput = [Console]::ReadLine()
    if ($null -eq $taskInput -or $taskInput -eq 'exit') { break }
    if ($taskInput -ne 'capture') {
      $taskDialog = $taskWindow.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, 'Project Structure')))
      if ($null -eq $taskDialog) { throw 'Signing dialog is no longer open. No input was sent.' }
      Focus-KanonSigningWindow
    }
    if ($taskInput -match '^click ([0-9.]+) ([0-9.]+)$') {
      $taskX = [double]::Parse($Matches[1], [Globalization.CultureInfo]::InvariantCulture)
      $taskY = [double]::Parse($Matches[2], [Globalization.CultureInfo]::InvariantCulture)
      if ($taskX -le 0 -or $taskX -ge 1 -or $taskY -le 0 -or $taskY -ge 1) { throw 'Click outside KanonIME window.' }
      $taskBounds = $taskWindow.Current.BoundingRectangle
      [KanonSigningWindow]::SetCursorPos([int]($taskBounds.X + $taskX * $taskBounds.Width),
        [int]($taskBounds.Y + $taskY * $taskBounds.Height)) | Out-Null
      [KanonSigningWindow]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
      [KanonSigningWindow]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
    } elseif ($taskInput.StartsWith('key ')) { $taskShell.SendKeys($taskInput.Substring(4)) }
    elseif ($taskInput -ne 'capture') { Write-Output 'Unknown signing action.'; continue }
    Start-Sleep -Milliseconds 1200
    Save-KanonSigningScreenshot
    Write-Output 'Signing screenshot updated.'
  }
}
