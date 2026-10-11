param([string]$ModelDirectory, [string]$AudioFixture)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$DataDir=Join-Path $env:TEMP ('todo-voice-ui-'+[guid]::NewGuid().ToString('N')); [void][IO.Directory]::CreateDirectory($DataDir)
$Preview=$true
$script:Edition='mainland'
$script:Settings=@{provider='codex';intervalMinutes=30;codexModel='gpt-6-luna';codexEffort='medium';claudeModel='haiku';apiBase='https://api.deepseek.com';apiModel='fixture';voiceHotkey='F2';voiceKey=113;voiceModifiers=0;voiceModel='sensevoice-small-int8-2024-07-17';voiceLanguage='auto'}
$script:Window=New-Object Windows.Window
$reader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot '../src/SettingsTheme.xaml'))
try{$script:Window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($reader))}finally{$reader.Close()}
$script:Capture=New-Object Windows.Controls.Button
$script:VoiceNotice=New-Object Windows.Controls.TextBlock
$script:IntervalLabel=New-Object Windows.Controls.TextBlock
$script:Filter='pending'
function Read-Json($f){if(Test-Path -LiteralPath $f){return (Get-Content -LiteralPath $f -Raw -Encoding UTF8|ConvertFrom-Json)}}
function Save-Settings{[IO.File]::WriteAllText((Join-Path $DataDir 'settings.json'),($script:Settings|ConvertTo-Json))}
function Text-Line($text,$size=12,$color='#D2DEED'){$b=New-Object Windows.Controls.TextBlock;$b.Text=$text;$b.FontSize=$size;$b.Foreground=$color;$b.TextWrapping='Wrap';return $b}
function Render-Tasks{}
function Click($control){$control.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))}
function Check($condition,$message){if(-not $condition){throw $message}}
function Render-Image($window,$name){
    $window.UpdateLayout();$bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap([int]$window.ActualWidth,[int]$window.ActualHeight,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($window)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream=[IO.File]::Create((Join-Path $PSScriptRoot ('../.build/'+$name)));try{$encoder.Save($stream)}finally{$stream.Close()}
}
. (Join-Path $PSScriptRoot '../src/Voice.ps1')
. (Join-Path $PSScriptRoot '../src/Settings.ps1')
try{
    # Completion must save without making the hidden widget visible or changing its filter.
    $windowsBefore=$script:Window.OwnedWindows.Count
    Complete-VoiceRecognition ([pscustomobject]@{status='done';text="明天完善项目介绍`n保留完整想法内容。"})
    $tasks=@(Read-ManualTasks)
    Check ($tasks.Count -eq 1 -and $tasks[0].status -eq 'idea' -and $tasks[0].evidence.Contains('完整想法')) 'Background capture did not save an idea'
    Check (-not $script:Window.IsVisible -and $script:Window.OwnedWindows.Count -eq $windowsBefore -and $script:Filter -eq 'pending') 'Recognition interrupted the user'
    Complete-VoiceRecognition ([pscustomobject]@{status='done';text='  '})
    Complete-VoiceRecognition ([pscustomobject]@{status='error';error='fixture error'})
    Check (@(Read-ManualTasks).Count -eq 1) 'Empty/error result created an idea'
    Update-Idea $tasks[0].id "更新后的想法`n第二行仍然保留"
    Check (@(Read-ManualTasks)[0].evidence.Contains('第二行')) 'Idea edit lost full text'
    $rejected=$false;try{Update-Idea $tasks[0].id ' '}catch{$rejected=$true};Check $rejected 'Empty edit accepted'
    [IO.File]::WriteAllText((Join-Path $DataDir 'state.json'),'{"tasks":{}}')
    Check (@(Read-ManualTasks).Count -eq 1) 'Analysis replaced ideas'

    # No microphone is used: mock only its constructor, keep production start/stop flow.
    $script:Recorded=$false;$script:WorkerCalls=0
    $script:FakeMicrophone=New-Object psobject
    $script:FakeMicrophone|Add-Member ScriptMethod Start {$script:Recorded=$true}
    $script:FakeMicrophone|Add-Member ScriptMethod Stop {return ,(New-Object byte[] 6400)}
    $script:FakeMicrophone|Add-Member ScriptMethod Dispose {}
    $modelPath=Join-Path $DataDir ('speech/'+$script:Settings.voiceModel+'/model.int8.onnx');[void][IO.Directory]::CreateDirectory((Split-Path $modelPath));[IO.File]::WriteAllText($modelPath,'fixture')
    $originalWorker=${function:Start-SpeechWorker}
    function Start-SpeechWorker($Operation,$Audio){$script:WorkerCalls++;$script:MockAudio=$Audio}
    function New-Object {param([string]$TypeName) if($TypeName -eq 'ConversationTodo.Microphone'){return $script:FakeMicrophone}; Microsoft.PowerShell.Utility\New-Object $TypeName @args}
    Start-VoiceRecording;Check $script:Recorded ('Shortcut did not start background recording: '+$script:VoiceNotice.Text)
    Check (-not $script:Window.IsVisible -and $script:Window.OwnedWindows.Count -eq $windowsBefore) 'Recording opened a window'
    Stop-VoiceRecording;Check ($script:WorkerCalls -eq 1 -and (Test-Path $script:MockAudio)) 'Release did not start recognition'
    Remove-Item Function:\New-Object;${function:Start-SpeechWorker}=$originalWorker
    Clear-VoiceFiles;$script:VoiceTimer.Stop()

    $script:Window.Show()
    $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(150)
    $timer.Add_Tick({
        $timer.Stop();$d=$script:Window.OwnedWindows[0]
        try{
            Check ($d.Content -is [Windows.Controls.Grid]) 'Settings has no sidebar layout'
            $pages=$d.Content.Tag;Check ($pages.navigation.Count -eq 4) 'Missing settings categories'
            Click $pages.navigation[1];Check ($pages.scroll.Content -eq $pages.voice) 'Voice sidebar navigation failed'
            $key=@($pages.voice.Children|Where-Object {$_ -is [Windows.Controls.TextBox]})[0]
            $event=New-Object Windows.Input.KeyEventArgs([Windows.Input.Keyboard]::PrimaryDevice,([Windows.Interop.HwndSource]::FromHwnd((New-Object Windows.Interop.WindowInteropHelper($d)).Handle)),0,[Windows.Input.Key]::F3)
            $event.RoutedEvent=[Windows.Input.Keyboard]::PreviewKeyDownEvent;$key.RaiseEvent($event)
            Check ($key.Text -eq 'F3') 'Keyboard picker failed'
            $save=@($pages.voice.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
            $combos=@($pages.voice.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]});$combos[1].SelectedIndex=2
            foreach($mouse in @([Windows.Input.MouseButton]::XButton1,[Windows.Input.MouseButton]::XButton2)){
                $event=New-Object Windows.Input.MouseButtonEventArgs([Windows.Input.Mouse]::PrimaryDevice,0,$mouse)
                $event.RoutedEvent=[Windows.Input.Mouse]::PreviewMouseDownEvent;$key.RaiseEvent($event);Click $save
                Check ($script:Settings.voiceKey -eq $(if($mouse -eq 'XButton1'){5}else{6})) 'Mouse side button not saved'
                Check ($save.Tag.notice.Text.StartsWith('已保存') -and $script:Capture.Content.Contains($key.Text)) 'Shortcut save/caption failed'
            }
            Render-Image $d 'voice-settings.png'
            Click $pages.navigation[0];Render-Image $d 'analysis-settings.png'
            Click $pages.navigation[2];Check ($pages.scroll.Content -eq $pages.browser) 'Browser navigation failed'
            Click $pages.navigation[3];Check ($pages.scroll.Content -eq $pages.privacy) 'Privacy navigation failed'
            $d.Close()
        }catch{$script:TestError=$_;$d.Close()}
    })
    $timer.Start();Show-AnalysisSettings
    if($script:TestError){throw $script:TestError}
    $saved=Read-Json (Join-Path $DataDir 'settings.json');Check ($saved.voiceKey -eq 6 -and $saved.voiceLanguage -eq 'yue') 'Voice settings not persisted'
    $timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(100)
    $timer.Add_Tick({
        $timer.Stop();$d=$script:Window.OwnedWindows[0]
        try {
            $d.Content.Children[1].Text="在想法界面修改内容`n保存完整第二行"
            Click $d.Content.Children[3]
        } catch {$script:TestError=$_;$d.Close()}
    })
    $timer.Start();Show-IdeaEditor $tasks[0].id
    if($script:TestError){throw $script:TestError}
    Check (@(Read-ManualTasks)[0].evidence.Contains('保存完整第二行')) 'Idea editor did not persist text'
    if ($ModelDirectory -and $AudioFixture) {
        # Public fixture PCM exercises the real worker/timer; never open the microphone.
        Copy-Item -LiteralPath (Join-Path $ModelDirectory 'model.int8.onnx') -Destination $modelPath -Force
        $script:Node=(Get-Command node.exe).Source;$script:Settings.voiceLanguage='zh'
        $script:VoiceAudio=Join-Path $DataDir 'voice-capture.pcm';Copy-Item -LiteralPath $AudioFixture -Destination $script:VoiceAudio -Force
        $script:Window.Hide();$script:Filter='pending';$count=@(Read-ManualTasks).Count
        Start-SpeechWorker 'transcribe' $script:VoiceAudio
        $frame=New-Object Windows.Threading.DispatcherFrame;$deadline=[datetime]::Now.AddSeconds(45)
        $poll=New-Object Windows.Threading.DispatcherTimer;$poll.Interval=[timespan]::FromMilliseconds(100)
        $poll.Add_Tick({if(-not $script:VoiceProcess -or [datetime]::Now -gt $deadline){$poll.Stop();$frame.Continue=$false}})
        $poll.Start();[Windows.Threading.Dispatcher]::PushFrame($frame)
        Check (-not $script:VoiceProcess -and @(Read-ManualTasks).Count -eq ($count+1)) ('Real worker did not save: '+$script:VoiceNotice.Text)
        Check (-not $script:Window.IsVisible -and $script:Filter -eq 'pending' -and $script:Window.OwnedWindows.Count -eq 0) 'Real recognition opened a window or changed view'
        Check (-not (Test-Path $script:VoiceAudio) -and -not (Test-Path $script:VoiceResult)) 'Recognition left temporary audio/results'
    }

    # Exercise native mouse state without injecting input or opening the microphone.
    Check ([ConversationTodo.MouseShortcut]::Enable([IntPtr]::Zero,5,2)) 'Mouse hook installation failed'
    $handler=[ConversationTodo.MouseShortcut].GetMethod('HandleButton',[Reflection.BindingFlags]'NonPublic,Static')
    Check (-not $handler.Invoke($null,@(0x20B,2,[uint32]2))) 'Unselected mouse button intercepted'
    Check (-not $handler.Invoke($null,@(0x20B,1,[uint32]0))) 'Mouse shortcut ignored modifiers'
    Check ($handler.Invoke($null,@(0x20B,1,[uint32]2)) -and [ConversationTodo.MouseShortcut]::Pressed) 'Mouse press failed'
    Check ($handler.Invoke($null,@(0x20C,1,[uint32]0)) -and -not [ConversationTodo.MouseShortcut]::Pressed) 'Mouse release failed after modifiers changed'
    [ConversationTodo.MouseShortcut]::Disable()
    Check ([ConversationTodo.MouseShortcut]::Enable([IntPtr]::Zero,6,0)) 'Second side button hook failed'
    Check ($handler.Invoke($null,@(0x20B,2,[uint32]0))) 'Second side button press failed'
    [ConversationTodo.MouseShortcut]::Disable();Check (-not [ConversationTodo.MouseShortcut]::Pressed) 'Hook cleanup failed'
    $h=(New-Object Windows.Interop.WindowInteropHelper($script:Window)).Handle
    Check ([ConversationTodo.Hotkey]::RegisterHotKey($h,9811,0x4003,122)) 'Test hotkey unavailable'
    try{
        $Preview=$false
        $rejected=$false;try{Save-VoicePreferences @{key=122;modifiers=3;label='Ctrl+Alt+F11'} $script:Settings.voiceModel 'en'}catch{$rejected=$true}
        Check ($rejected -and $script:Settings.voiceKey -eq 6) 'Conflict overwrote saved shortcut'
    }finally{$Preview=$true;[void][ConversationTodo.Hotkey]::UnregisterHotKey($h,9811)}
    'PASS: background recording and auto-save without focus changes, full-text edit, empty/error handling, sidebar, keyboard/mouse picker, native side button press/release, conflict and persistence'
}finally{Remove-Item Function:\New-Object -ErrorAction SilentlyContinue;$script:Window.Close()}
