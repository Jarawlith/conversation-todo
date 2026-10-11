Add-Type -Path (Join-Path $PSScriptRoot 'VoiceNative.cs')
$script:VoiceModels = @(Read-Json (Join-Path $PSScriptRoot 'speech-models.json'))
$script:VoiceProcess = $null
$script:Microphone = $null
$script:CaptureWindow = $null
$script:VoiceHandle = [IntPtr]::Zero
$script:VoiceTimer = New-Object Windows.Threading.DispatcherTimer
$script:VoiceTimer.Interval = [timespan]::FromMilliseconds(40)
if (-not $Preview) { Remove-Item -LiteralPath (Join-Path $DataDir 'voice-capture.pcm') -Force -ErrorAction SilentlyContinue }

function Read-ManualTasks {
    $saved = Read-Json (Join-Path $DataDir 'manual-tasks.json')
    if ($saved) { return @($saved.tasks) }
    return @()
}
function Save-VoiceTask([string]$Text) {
    $text = $Text.Trim()
    if (-not $text) { throw '请先说出或输入你的想法。' }
    $title = ($text -split '[\r\n]')[0]
    if ($title.Length -gt 60) { $title = $title.Substring(0,60) + '…' }
    $task = [pscustomobject]@{id=('manual-' + [guid]::NewGuid().ToString('N'));title=$title;reason='你记录的想法';
        evidence=$text;sourceType='语音 / 快速记录';sourceId='manual';sourceTitle='本机保存';
        priority=2;status='active';created=[datetime]::UtcNow.ToString('o');due=$null;resolvedAt=$null}
    $file = Join-Path $DataDir 'manual-tasks.json'
    [IO.File]::WriteAllText(($file + '.tmp'),(@{tasks=@(Read-ManualTasks) + @($task)} | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath ($file + '.tmp') -Destination $file -Force
    return $task
}
function Set-VoiceHotkey {
    if ($script:VoiceHandle -eq [IntPtr]::Zero -or $Preview) { return }
    [void][ConversationTodo.Hotkey]::UnregisterHotKey($script:VoiceHandle, 8102)
    if (-not [ConversationTodo.Hotkey]::RegisterHotKey($script:VoiceHandle,8102,([uint32]$script:Settings.voiceModifiers -bor 0x4000),[uint32]$script:Settings.voiceKey)) {
        $script:Capture.Content='记录想法 · 快捷键被占用'; $script:Capture.ToolTip='打开记录窗口，选择语音设置并更换快捷键。'
        throw '快捷键已被其他程序占用。请在语音记录设置里换一个快捷键。'
    }
    $script:Capture.Content='记录想法 · 按住 ' + $script:Settings.voiceHotkey + ' 说话'; $script:Capture.ToolTip=$null
}
function Start-SpeechWorker($Operation, $Audio = '') {
    $model = $script:VoiceModels | Where-Object id -eq $script:Settings.voiceModel | Select-Object -First 1
    if (-not $model) { throw '未找到所选语音模型，请在语音记录设置中重新选择。' }
    $directory = Join-Path $DataDir ('speech/' + $model.id)
    [void][IO.Directory]::CreateDirectory($directory)
    $script:VoiceResult = Join-Path $directory 'result.json'
    Remove-Item -LiteralPath $script:VoiceResult -Force -ErrorAction SilentlyContinue
    $request = Join-Path $directory 'request.json'
    $body = @{model=$model.id;directory=$directory;result=$script:VoiceResult;operation=$Operation;audio=$Audio;language=$script:Settings.voiceLanguage}
    [IO.File]::WriteAllText($request,($body | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$script:Node; $info.Arguments='"' + (Join-Path $PSScriptRoot 'speech-worker.js') + '" "' + $request + '"'
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $script:VoiceProcess=[Diagnostics.Process]::Start($info)
    $script:VoiceOperation=$Operation; $script:VoiceStarted=[datetime]::Now
    $script:VoiceText.IsReadOnly=($Operation -ne 'prepare'); $script:VoiceSave.IsEnabled=($Operation -eq 'prepare')
    $script:VoiceTimer.Start()
}
function Show-VoiceCapture {
    if ($script:CaptureWindow) { $script:CaptureWindow.Show(); [void]$script:CaptureWindow.Activate(); return }
    $script:CaptureWindow=New-Object Windows.Window
    $dialog=$script:CaptureWindow
    $dialog.Title='记录一个想法'; $dialog.Width=480; $dialog.Height=370; $dialog.MinHeight=330; $dialog.MinWidth=400
    $dialog.Topmost=$true; $dialog.WindowStartupLocation='CenterScreen'; $dialog.Background='#111B29'; $dialog.Foreground='#E8EEF6'; $dialog.FontFamily='Microsoft YaHei UI'
    $themeReader=[Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'SettingsTheme.xaml'))
    try { $dialog.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($themeReader)) } finally { $themeReader.Close() }
    $grid=New-Object Windows.Controls.Grid; $grid.Margin='24'
    foreach ($height in @('Auto','Auto','*','Auto')) { $row=New-Object Windows.Controls.RowDefinition; $row.Height=$height; [void]$grid.RowDefinitions.Add($row) }
    $heading=Text-Line '把刚刚的想法留下来' 21 '#EDF3FC'; [void]$grid.Children.Add($heading)
    $script:VoiceStatus=Text-Line ('按住 ' + $script:Settings.voiceHotkey + ' 说话，松开识别。文字确认后再保存。') 12 '#8BA0BA'
    [Windows.Controls.Grid]::SetRow($script:VoiceStatus,1); [void]$grid.Children.Add($script:VoiceStatus)
    $script:VoiceText=New-Object Windows.Controls.TextBox; $script:VoiceText.AcceptsReturn=$true; $script:VoiceText.TextWrapping='Wrap'; $script:VoiceText.VerticalScrollBarVisibility='Auto'; $script:VoiceText.Margin='0,8,0,16'
    [Windows.Controls.Grid]::SetRow($script:VoiceText,2); [void]$grid.Children.Add($script:VoiceText)
    $buttons=New-Object Windows.Controls.WrapPanel
    $script:VoiceSave=New-Object Windows.Controls.Button; $script:VoiceSave.Content='保存为待办'; $script:VoiceSave.Background='#284E49'; $script:VoiceSave.Margin='0,0,8,0'
    $script:VoiceSave.Add_Click({ try { [void](Save-VoiceTask $script:VoiceText.Text); $script:Filter='active'; Render-Tasks; $script:CaptureWindow.Close() } catch { $script:VoiceStatus.Text=$_.Exception.Message } })
    [void]$buttons.Children.Add($script:VoiceSave)
    $cancel=New-Object Windows.Controls.Button; $cancel.Content='取消'; $cancel.Margin='0,0,8,0'; $cancel.Add_Click({$script:CaptureWindow.Close()}); [void]$buttons.Children.Add($cancel)
    $settings=New-Object Windows.Controls.Button; $settings.Content='语音设置'; $settings.Add_Click({ if (-not $script:Microphone -and -not $script:VoiceProcess) { Show-VoiceSettings } }); [void]$buttons.Children.Add($settings)
    [Windows.Controls.Grid]::SetRow($buttons,3); [void]$grid.Children.Add($buttons); $dialog.Content=$grid
    $dialog.Add_Closed({
        if ($script:Microphone) { $script:Microphone.Dispose(); $script:Microphone=$null }
        if ($script:VoiceProcess) {
            if (-not $script:VoiceProcess.HasExited) { $script:VoiceProcess.Kill(); [void]$script:VoiceProcess.WaitForExit(2000) }
            $script:VoiceProcess.Dispose(); $script:VoiceProcess=$null
        }
        if ($script:VoiceAudio) { Remove-Item -LiteralPath $script:VoiceAudio -Force -ErrorAction SilentlyContinue }
        if ($script:VoiceResult) {
            Remove-Item -LiteralPath $script:VoiceResult -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path (Split-Path $script:VoiceResult -Parent) 'request.json') -Force -ErrorAction SilentlyContinue
        }
        $script:VoiceTimer.Stop(); $script:CaptureWindow=$null
    })
    $dialog.Show(); [void]$dialog.Activate(); [void]$script:VoiceText.Focus()
}
function Start-VoiceRecording {
    if ($script:VoiceProcess -or $script:Microphone -or $script:VoiceSettingsOpen) { return }
    Show-VoiceCapture
    if ($script:VoiceText.Text.Trim()) { $script:VoiceStatus.Text='请先保存或取消当前想法，再记录下一条。'; return }
    $model=$script:VoiceModels | Where-Object id -eq $script:Settings.voiceModel | Select-Object -First 1
    if (-not $model) { $script:VoiceStatus.Text='请在语音设置中选择模型。'; return }
    $file=Join-Path (Join-Path $DataDir ('speech/' + $model.id)) $model.file
    if (-not (Test-Path -LiteralPath $file)) {
        try { Start-SpeechWorker 'prepare'; $script:VoiceStatus.Text='首次使用正在下载模型（约 160 MB）。下载完成后，请重新按住快捷键。' }
        catch { $script:VoiceStatus.Text=$_.Exception.Message }
        return
    }
    try {
        $script:Microphone=New-Object ConversationTodo.Microphone; $script:Microphone.Start()
        $script:VoiceStarted=[datetime]::Now; $script:VoiceText.IsReadOnly=$true; $script:VoiceSave.IsEnabled=$false
        $script:VoiceTimer.Start()
    } catch { if ($script:Microphone) {$script:Microphone.Dispose();$script:Microphone=$null}; $script:VoiceStatus.Text=$_.Exception.Message }
}
function Stop-VoiceRecording {
    if (-not $script:Microphone) { return }
    try {
        $bytes=$script:Microphone.Stop(); $script:Microphone=$null
        if ($bytes.Length -lt 3200) { $script:VoiceStatus.Text='录音太短，请重新按住快捷键说话。'; $script:VoiceText.IsReadOnly=$false; $script:VoiceSave.IsEnabled=$true; return }
        $script:VoiceAudio=Join-Path $DataDir 'voice-capture.pcm'
        [IO.File]::WriteAllBytes($script:VoiceAudio,$bytes)
        Start-SpeechWorker 'transcribe' $script:VoiceAudio
        $script:VoiceStatus.Text='正在本机识别，不上传录音…'
    } catch { $script:VoiceStatus.Text=$_.Exception.Message; $script:VoiceText.IsReadOnly=$false; $script:VoiceSave.IsEnabled=$true }
}
$script:VoiceTimer.Add_Tick({
    try {
        if ($script:Microphone) {
            $seconds=([datetime]::Now-$script:VoiceStarted).TotalSeconds
            $script:VoiceStatus.Text='正在录音 · ' + [int]$seconds + ' 秒 · 松开 ' + $script:Settings.voiceHotkey + ' 后识别（最长 2 分钟）'
            if (-not [ConversationTodo.Hotkey]::IsDown([int]$script:Settings.voiceKey) -or $seconds -ge 120) { Stop-VoiceRecording }
        }
        if ($script:VoiceProcess) {
            $result=Read-Json $script:VoiceResult
            if ($result.status -eq 'downloading') { $script:VoiceStatus.Text='正在下载模型 · ' + [math]::Round($result.bytes / 1MB) + ' MB / 约 160 MB。现在可以先用键盘记录。' }
            if ($script:VoiceProcess.HasExited) {
                $script:VoiceProcess.Dispose(); $script:VoiceProcess=$null
                $script:VoiceText.IsReadOnly=$false; $script:VoiceSave.IsEnabled=$true
                if ($result.status -eq 'done') {
                    $script:VoiceText.Text=$result.text
                    $script:VoiceStatus.Text=if ($result.text) { '识别完成 · ' + [math]::Round($result.elapsedMs/1000,2) + ' 秒。确认或修改后保存。' } else { '没有识别到文字，请重新录音或直接输入。' }
                    [void]$script:VoiceText.Focus(); $script:VoiceText.CaretIndex=$script:VoiceText.Text.Length
                } elseif ($result.status -eq 'ready') { $script:VoiceStatus.Text='模型已准备好。按住快捷键说话，之后可离线识别。' }
                else { $script:VoiceStatus.Text='识别或下载失败：' + $(if ($result.error) {$result.error} else {'语音进程未正常完成'}) + '。可重新按住快捷键重试。' }
                $script:VoiceTimer.Stop()
            }
        } elseif (-not $script:Microphone) { $script:VoiceTimer.Stop() }
    } catch { $script:VoiceStatus.Text=$_.Exception.Message }
})
function Show-VoiceSettings {
    if ($script:Microphone -or $script:VoiceProcess) { return }
    $script:VoiceSettingsOpen=$true
    if ($script:VoiceHandle -ne [IntPtr]::Zero) { [void][ConversationTodo.Hotkey]::UnregisterHotKey($script:VoiceHandle,8102) }
    $dialog=New-Object Windows.Window; $dialog.Title='语音记录设置'; $dialog.Width=480; $dialog.Height=520; $dialog.MinHeight=520; $dialog.MinWidth=480; $dialog.Topmost=$true; $dialog.WindowStartupLocation='CenterScreen'; $dialog.Background='#111B29'; $dialog.Foreground='#E8EEF6'; $dialog.FontFamily='Microsoft YaHei UI'
    $dialog.Owner=$script:Window
    $dialog.Resources=$script:Window.Resources
    $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='24'
    [void]$panel.Children.Add((Text-Line '语音记录' 22))
    [void]$panel.Children.Add((Text-Line '按住快捷键录音，松开识别。只在你操作时使用麦克风。' 12 '#8BA0BA'))
    [void]$panel.Children.Add((Text-Line '快捷键 · 点击后按下新的快捷键'))
    $key=New-Object Windows.Controls.TextBox; $key.IsReadOnly=$true; $key.Text=$script:Settings.voiceHotkey; $key.Margin='0,0,0,12'
    $choice=@{key=[int]$script:Settings.voiceKey;modifiers=[uint32]$script:Settings.voiceModifiers;label=$key.Text}
    $key.Add_PreviewKeyDown({
        $pressed=$_.Key; if ($pressed -eq 'System') {$pressed=$_.SystemKey}
        if ($pressed -in @('LeftCtrl','RightCtrl','LeftAlt','RightAlt','LeftShift','RightShift','LWin','RWin','Tab','Escape')) { return }
        $mods=[int][Windows.Input.Keyboard]::Modifiers
        $vk=[Windows.Input.KeyInterop]::VirtualKeyFromKey($pressed)
        if ($vk -eq 123 -or (($mods -band 4) -and $vk -eq 115)) { $_.Handled=$true; return }
        if (-not $mods -and $pressed -notmatch '^F([1-9]|1[01])$') { $_.Handled=$true; return }
        $native=0; $parts=@()
        if ($mods -band 2) {$native=$native -bor 2;$parts+='Ctrl'}
        if ($mods -band 1) {$native=$native -bor 1;$parts+='Alt'}
        if ($mods -band 4) {$native=$native -bor 4;$parts+='Shift'}
        if ($mods -band 8) {$native=$native -bor 8;$parts+='Win'}
        $parts+=[string]$pressed; $choice.key=$vk;$choice.modifiers=$native;$choice.label=$parts -join '+'; $key.Text=$choice.label; $_.Handled=$true
    }.GetNewClosure())
    [void]$panel.Children.Add($key)
    [void]$panel.Children.Add((Text-Line '支持 F1–F11，或带 Ctrl / Alt / Shift / Win 的组合键。占用时会提示。' 11 '#8BA0BA'))
    [void]$panel.Children.Add((Text-Line '识别模型'))
    $modelBox=New-Object Windows.Controls.ComboBox
    foreach ($m in $script:VoiceModels) { $item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$m.name; $item.Tag=$m; [void]$modelBox.Items.Add($item); if ($m.id -eq $script:Settings.voiceModel) {$modelBox.SelectedItem=$item} }
    [void]$panel.Children.Add($modelBox)
    [void]$panel.Children.Add((Text-Line '语言'))
    $language=New-Object Windows.Controls.ComboBox; $langs=@('auto','zh','yue','en')
    foreach ($name in @('自动识别','中文普通话','粤语','英语')) {[void]$language.Items.Add($name)}
    $language.SelectedIndex=[math]::Max(0,[Array]::IndexOf($langs,$script:Settings.voiceLanguage)); [void]$panel.Children.Add($language)
    [void]$panel.Children.Add((Text-Line '首次下载约 160 MB，之后离线识别。录音仅临时用于识别，保存待办只保留文字。' 11 '#8BA0BA'))
    $save=New-Object Windows.Controls.Button; $save.Content='保存语音设置'; $save.Margin='0,12,0,0'
    $save.Add_Click({
        if ($script:VoiceHandle -ne [IntPtr]::Zero -and -not [ConversationTodo.Hotkey]::RegisterHotKey($script:VoiceHandle,8102,([uint32]$choice.modifiers -bor 0x4000),[uint32]$choice.key)) { [void][Windows.MessageBox]::Show('快捷键已被占用，请选择其他按键。'); return }
        $script:Settings.voiceKey=$choice.key; $script:Settings.voiceModifiers=$choice.modifiers; $script:Settings.voiceHotkey=$choice.label
        $script:Settings.voiceModel=$modelBox.SelectedItem.Tag.id; $script:Settings.voiceLanguage=$langs[$language.SelectedIndex]; Save-Settings
        $script:Capture.Content='记录想法 · 按住 ' + $script:Settings.voiceHotkey + ' 说话'; $dialog.Close()
    })
    [void]$panel.Children.Add($save); $dialog.Content=$panel
    try { [void]$dialog.ShowDialog() } finally { $script:VoiceSettingsOpen=$false; try { Set-VoiceHotkey } catch { [void][Windows.MessageBox]::Show($_.Exception.Message) } }
}
$script:Window.Add_SourceInitialized({
    $script:VoiceHandle=(New-Object Windows.Interop.WindowInteropHelper($script:Window)).Handle
    $script:VoiceSource=[Windows.Interop.HwndSource]::FromHwnd($script:VoiceHandle)
    $script:VoiceHook=[Windows.Interop.HwndSourceHook]{param($hwnd,$message,$wParam,$lParam,[ref]$handled)
        if ($message -eq 0x312 -and $wParam.ToInt32() -eq 8102) { $handled.Value=$true; Start-VoiceRecording }
        return [IntPtr]::Zero
    }
    $script:VoiceSource.AddHook($script:VoiceHook)
    try { Set-VoiceHotkey } catch { $script:Status.Text=$_.Exception.Message }
})
$script:Window.Add_Closed({
    if ($script:CaptureWindow) {$script:CaptureWindow.Close()}
    $script:VoiceTimer.Stop()
    if ($script:VoiceHandle -ne [IntPtr]::Zero) {[void][ConversationTodo.Hotkey]::UnregisterHotKey($script:VoiceHandle,8102)}
})
