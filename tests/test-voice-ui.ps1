$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$DataDir=Join-Path $env:TEMP ('todo-voice-ui-'+[guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($DataDir)
$Preview=$true
$script:Settings=@{voiceHotkey='F2';voiceKey=113;voiceModifiers=0;voiceModel='sensevoice-small-int8-2024-07-17';voiceLanguage='auto'}
$script:Window=New-Object Windows.Window
$reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot '../src/SettingsTheme.xaml'))
try{$script:Window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($reader))}finally{$reader.Close()}
$script:Capture=New-Object Windows.Controls.Button
function Read-Json($f){if(Test-Path -LiteralPath $f){Get-Content -LiteralPath $f -Raw -Encoding UTF8|ConvertFrom-Json}}
function Save-Settings{[IO.File]::WriteAllText((Join-Path $DataDir 'settings.json'),($script:Settings|ConvertTo-Json))}
function Text-Line($text,$size=12,$color='#D2DEED'){$b=New-Object Windows.Controls.TextBlock;$b.Text=$text;$b.FontSize=$size;$b.Foreground=$color;$b.TextWrapping='Wrap';return $b}
function Render-Tasks{}
. (Join-Path $PSScriptRoot '../src/Voice.ps1')
function Click($control){$control.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
try{
  $emptyRejected=$false;try{Save-VoiceTask '  '}catch{$emptyRejected=$true};if(-not $emptyRejected){throw 'Empty task accepted'}
  Show-VoiceCapture
  Show-VoiceCapture
  if(@(Read-ManualTasks).Count){throw 'Opening capture saved a task'}
  $script:VoiceText.Text="明天完善项目介绍`n保留完整想法内容。"
  $script:CaptureWindow.UpdateLayout()
  $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(480,370,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($script:CaptureWindow)
  $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
  $out=Join-Path $PSScriptRoot '../.build/voice-capture.png';$stream=[IO.File]::Create($out);$encoder.Save($stream);$stream.Close()
  Click $script:VoiceSave
  $tasks=@(Read-ManualTasks)
  if($tasks.Count -ne 1 -or $tasks[0].title -ne '明天完善项目介绍' -or $tasks[0].evidence -notmatch '保留完整想法内容' -or $tasks[0].status -ne 'active'){throw 'Confirmed capture storage failed'}
  [IO.File]::WriteAllText((Join-Path $DataDir 'state.json'),'{"tasks":{}}')
  if(@(Read-ManualTasks).Count -ne 1){throw 'Analysis replaced manual task'}
  Show-VoiceCapture;$script:VoiceText.Text='不会保存的草稿';$script:CaptureWindow.Close()
  if(@(Read-ManualTasks).Count -ne 1){throw 'Cancel created task'}
  $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(150)
  $timer.Add_Tick({
    $timer.Stop();$d=@([Windows.Application]::Current.Windows | Where-Object Title -eq '语音记录设置')[0]
    if(-not $d){$d=$script:Window.OwnedWindows[0]}
    try{
      $p=$d.Content;$key=@($p.Children|Where-Object {$_ -is [Windows.Controls.TextBox]})[0]
      $event=New-Object Windows.Input.KeyEventArgs([Windows.Input.Keyboard]::PrimaryDevice,([Windows.Interop.HwndSource]::FromHwnd((New-Object Windows.Interop.WindowInteropHelper($d)).Handle)),0,[Windows.Input.Key]::F3)
      $event.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent;$key.RaiseEvent($event)
      $combos=@($p.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]});$combos[1].SelectedIndex=2
      $d.UpdateLayout();$bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(480,520,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($d)
      $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
      $out=Join-Path $PSScriptRoot '../.build/voice-settings.png';$stream=[IO.File]::Create($out);$encoder.Save($stream);$stream.Close()
      $b=@($p.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0];Click $b
    }catch{$script:TestError=$_;$d.Close()}
  })
  $script:Window.Show();$timer.Start();Show-VoiceSettings
  if($script:TestError){throw $script:TestError}
  $saved=Read-Json (Join-Path $DataDir 'settings.json');if($saved.voiceKey -ne 114 -or $saved.voiceLanguage -ne 'yue'){throw 'Hotkey/language not saved'}
  $h=(New-Object Windows.Interop.WindowInteropHelper($script:Window)).Handle
  $mods=[uint32]0x4003;$vk=[uint32]122
  if([ConversationTodo.Hotkey]::RegisterHotKey($h,9811,$mods,$vk)){
    try{if([ConversationTodo.Hotkey]::RegisterHotKey($h,9812,$mods,$vk)){throw 'Conflict detection failed'}}finally{[void][ConversationTodo.Hotkey]::UnregisterHotKey($h,9811);[void][ConversationTodo.Hotkey]::UnregisterHotKey($h,9812)}
  }else{throw 'Test hotkey unavailable'}
  'PASS: capture confirmation, full text, cancel, durable manual storage, hotkey/language settings and conflict detection'
}finally{if($script:CaptureWindow){$script:CaptureWindow.Close()};$script:Window.Close()}
