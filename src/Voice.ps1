Add-Type -Path (Join-Path $PSScriptRoot 'VoiceNative.cs')
$script:VoiceModels = @(Read-Json (Join-Path $PSScriptRoot 'speech-models.json'))
$script:VoiceProcess = $null
$script:Microphone = $null
$script:VoiceHandle = [IntPtr]::Zero
$script:VoiceTimer = New-Object Windows.Threading.DispatcherTimer
$script:VoiceTimer.Interval = [timespan]::FromMilliseconds(40)
if (-not $Preview) { Remove-Item -LiteralPath (Join-Path $DataDir 'voice-capture.pcm') -Force -ErrorAction SilentlyContinue }

function Read-ManualTasks {
    $saved = Read-Json (Join-Path $DataDir 'manual-tasks.json')
    if ($saved) { return @($saved.tasks) }
    return @()
}
function Write-ManualTasks($Tasks) {
    $file = Join-Path $DataDir 'manual-tasks.json'
    [IO.File]::WriteAllText(($file + '.tmp'),(@{tasks=@($Tasks)} | ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath ($file + '.tmp') -Destination $file -Force
}
function Get-IdeaTitle([string]$Text) {
    $title = ($Text -split '[\r\n]')[0]
    if ($title.Length -gt 60) { $title = $title.Substring(0,60) + '…' }
    return $title
}
function Save-VoiceTask([string]$Text) {
    $text = $Text.Trim()
    if (-not $text) { throw '没有识别到文字，请重新录音。' }
    $task = [pscustomobject]@{id=('manual-' + [guid]::NewGuid().ToString('N'));title=(Get-IdeaTitle $text);reason='你记录的想法';
        evidence=$text;sourceType='语音 / 快速记录';sourceId='manual';sourceTitle='本机保存';
        priority=2;status='idea';created=[datetime]::UtcNow.ToString('o');due=$null;resolvedAt=$null}
    Write-ManualTasks (@(Read-ManualTasks) + @($task))
    return $task
}
function Update-Idea([string]$Id, [string]$Text) {
    $text=$Text.Trim(); if (-not $text) { throw '想法内容不能为空。' }
    $tasks=@(Read-ManualTasks); $task=$tasks | Where-Object id -eq $Id | Select-Object -First 1
    if (-not $task) { throw '这条想法已不存在。' }
    $task.evidence=$text; $task.title=Get-IdeaTitle $text
    Write-ManualTasks $tasks
}
function Show-IdeaEditor([string]$Id) {
    $task=Read-ManualTasks | Where-Object id -eq $Id | Select-Object -First 1
    if (-not $task) { return }
    $dialog=New-Object Windows.Window; $dialog.Title='修改想法'; $dialog.Width=500; $dialog.Height=380
    $dialog.MinWidth=400; $dialog.MinHeight=300; $dialog.Owner=$script:Window; $dialog.WindowStartupLocation='CenterOwner'
    $dialog.Background='#111B29'; $dialog.Foreground='#E8EEF6'; $dialog.FontFamily='Microsoft YaHei UI'; $dialog.Resources=$script:Window.Resources
    $grid=New-Object Windows.Controls.Grid; $grid.Margin='24'
    foreach ($height in @('Auto','*','Auto','Auto')) { $row=New-Object Windows.Controls.RowDefinition; $row.Height=$height; [void]$grid.RowDefinitions.Add($row) }
    [void]$grid.Children.Add((Text-Line '修改想法' 22))
    $text=New-Object Windows.Controls.TextBox; $text.Text=$task.evidence; $text.AcceptsReturn=$true; $text.TextWrapping='Wrap'; $text.VerticalScrollBarVisibility='Auto'
    [Windows.Controls.Grid]::SetRow($text,1); [void]$grid.Children.Add($text)
    $errorLabel=Text-Line '' 12 '#F4A79A'; [Windows.Controls.Grid]::SetRow($errorLabel,2); [void]$grid.Children.Add($errorLabel)
    $save=New-Object Windows.Controls.Button; $save.Content='保存修改'; $save.Margin='0,12,0,0'; $save.Tag=@{id=$Id;text=$text;error=$errorLabel;dialog=$dialog}
    $save.Add_Click({try { Update-Idea $this.Tag.id $this.Tag.text.Text; Render-Tasks; $this.Tag.dialog.DialogResult=$true } catch { $this.Tag.error.Text=$_.Exception.Message }})
    [Windows.Controls.Grid]::SetRow($save,3); [void]$grid.Children.Add($save); $dialog.Content=$grid
    [void]$dialog.ShowDialog()
}
function Set-VoiceNotice([string]$Text) { $script:VoiceNotice.Text=$Text }
function Update-VoiceCaption {
    $script:Capture.Content='我的想法 · 按住 ' + $script:Settings.voiceHotkey + ' 记录'
    $script:Capture.ToolTip='录音和识别在后台进行，自动保存文字。点击查看或修改想法。'
}
function Remove-VoiceHotkey {
    [ConversationTodo.MouseShortcut]::Disable()
    if ($script:VoiceHandle -ne [IntPtr]::Zero) { [void][ConversationTodo.Hotkey]::UnregisterHotKey($script:VoiceHandle,8102) }
}
function Register-VoiceShortcut([int]$Key, [uint32]$Modifiers) {
    Remove-VoiceHotkey
    if ($Key -in @(5,6)) { return [ConversationTodo.MouseShortcut]::Enable($script:VoiceHandle,$Key,$Modifiers) }
    return [ConversationTodo.Hotkey]::RegisterHotKey($script:VoiceHandle,8102,($Modifiers -bor 0x4000),[uint32]$Key)
}
function Set-VoiceHotkey {
    Update-VoiceCaption
    if ($script:VoiceHandle -eq [IntPtr]::Zero -or $Preview) { return }
    if (-not (Register-VoiceShortcut $script:Settings.voiceKey $script:Settings.voiceModifiers)) {
        throw '无法注册快捷键，可能已被其他程序占用。请在设置 → 语音记录里换一个快捷键。'
    }
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
    $script:VoiceTimer.Start()
}
function Start-VoiceRecording {
    if ($script:VoiceProcess -or $script:Microphone -or $script:VoiceSettingsOpen) { return }
    $model=$script:VoiceModels | Where-Object id -eq $script:Settings.voiceModel | Select-Object -First 1
    if (-not $model) { Set-VoiceNotice '请在语音设置中选择模型。'; return }
    $file=Join-Path (Join-Path $DataDir ('speech/' + $model.id)) $model.file
    if (-not (Test-Path -LiteralPath $file)) {
        try { Start-SpeechWorker 'prepare'; Set-VoiceNotice '首次使用正在下载模型（约 160 MB）。完成后请重新按住快捷键。' }
        catch { Set-VoiceNotice $_.Exception.Message }
        return
    }
    try {
        $script:Microphone=New-Object ConversationTodo.Microphone; $script:Microphone.Start()
        $script:VoiceStarted=[datetime]::Now; $script:VoiceTimer.Start()
        Set-VoiceNotice '正在后台录音 · 松开快捷键后保存想法'
    } catch { if ($script:Microphone) {$script:Microphone.Dispose();$script:Microphone=$null}; Set-VoiceNotice $_.Exception.Message }
}
function Stop-VoiceRecording {
    if (-not $script:Microphone) { return }
    try {
        $bytes=$script:Microphone.Stop(); $script:Microphone=$null
        if ($bytes.Length -lt 3200) { Set-VoiceNotice '录音太短，请重新按住快捷键说话。'; return }
        $script:VoiceAudio=Join-Path $DataDir 'voice-capture.pcm'
        [IO.File]::WriteAllBytes($script:VoiceAudio,$bytes)
        Start-SpeechWorker 'transcribe' $script:VoiceAudio
        Set-VoiceNotice '正在本机识别，完成后自动存入「我的想法」…'
    } catch { Set-VoiceNotice $_.Exception.Message }
}
function Complete-VoiceRecognition($Result) {
    if ($Result -and $Result.status -eq 'done') {
        if ([string]$Result.text -and $Result.text.Trim()) {
            [void](Save-VoiceTask $Result.text); Render-Tasks
            Set-VoiceNotice '已存入「我的想法」，可稍后查看或修改。'
        } else { Set-VoiceNotice '没有识别到文字，请重新录音。' }
    } elseif ($Result -and $Result.status -eq 'ready') { Set-VoiceNotice '模型已准备好。按住快捷键即可后台记录想法。' }
    else { Set-VoiceNotice ('识别或下载失败：' + $(if ($Result -and $Result.error) {$Result.error} else {'语音进程未正常完成'}) + '。可重新按住快捷键重试。') }
}
function Clear-VoiceFiles {
    if ($script:VoiceAudio) { Remove-Item -LiteralPath $script:VoiceAudio -Force -ErrorAction SilentlyContinue }
    if ($script:VoiceResult) {
        Remove-Item -LiteralPath $script:VoiceResult -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path (Split-Path $script:VoiceResult -Parent) 'request.json') -Force -ErrorAction SilentlyContinue
    }
}
$script:VoiceTimer.Add_Tick({
    try {
        if ($script:Microphone) {
            $seconds=([datetime]::Now-$script:VoiceStarted).TotalSeconds
            Set-VoiceNotice ('正在后台录音 · ' + [int]$seconds + ' 秒 · 松开后保存（最长 2 分钟）')
            $down=if ($script:Settings.voiceKey -in @(5,6)) { [ConversationTodo.MouseShortcut]::Pressed } else { [ConversationTodo.Hotkey]::IsDown([int]$script:Settings.voiceKey) }
            if (-not $down -or $seconds -ge 120) { Stop-VoiceRecording }
        }
        if ($script:VoiceProcess) {
            $result=Read-Json $script:VoiceResult
            if ($result -and $result.status -eq 'downloading') { Set-VoiceNotice ('正在下载语音模型 · ' + [math]::Round($result.bytes / 1MB) + ' MB / 约 160 MB') }
            if ($script:VoiceProcess.HasExited) {
                $script:VoiceProcess.Dispose(); $script:VoiceProcess=$null
                try { Complete-VoiceRecognition $result } finally { Clear-VoiceFiles; $script:VoiceTimer.Stop() }
            }
        } elseif (-not $script:Microphone) { $script:VoiceTimer.Stop() }
    } catch { Set-VoiceNotice $_.Exception.Message }
})
function Set-VoiceChoice($Choice, [int]$Key, [int]$Modifiers, [string]$Name) {
    $parts=@(); $native=0
    foreach ($pair in @(@(2,'Ctrl'),@(1,'Alt'),@(4,'Shift'),@(8,'Win'))) {
        if ($Modifiers -band $pair[0]) {$native=$native -bor $pair[0];$parts+=$pair[1]}
    }
    $parts+=$Name; $Choice.key=$Key; $Choice.modifiers=$native; $Choice.label=$parts -join '+'
}
function Save-VoicePreferences($Choice, [string]$Model, [string]$Language) {
    if ($script:Microphone -or $script:VoiceProcess) { throw '请等待当前录音、识别或下载完成后再保存。' }
    if ($script:VoiceHandle -ne [IntPtr]::Zero -and -not $Preview) {
        if (-not (Register-VoiceShortcut $Choice.key $Choice.modifiers)) { throw '快捷键已被占用或无法注册，请选择其他按键。' }
        Remove-VoiceHotkey
    }
    $script:Settings.voiceKey=$Choice.key; $script:Settings.voiceModifiers=$Choice.modifiers; $script:Settings.voiceHotkey=$Choice.label
    $script:Settings.voiceModel=$Model; $script:Settings.voiceLanguage=$Language; Save-Settings; Update-VoiceCaption
}
function New-VoiceSettingsPanel {
    $panel=New-Object Windows.Controls.StackPanel; $panel.Margin='28,22,28,28'
    [void]$panel.Children.Add((Text-Line '语音记录' 25))
    [void]$panel.Children.Add((Text-Line '按住录音，松开自动保存到「我的想法」。不弹窗，不切换当前应用。' 12 '#8BA0BA'))
    [void]$panel.Children.Add((Text-Line '快捷键 · 点击下方后按键，或按鼠标侧键'))
    $key=New-Object Windows.Controls.TextBox; $key.IsReadOnly=$true; $key.Text=$script:Settings.voiceHotkey; $key.Margin='0,0,0,12'
    $choice=@{key=[int]$script:Settings.voiceKey;modifiers=[uint32]$script:Settings.voiceModifiers;label=$key.Text}
    $key.Add_PreviewKeyDown({
        $pressed=$_.Key; if ($pressed -eq 'System') {$pressed=$_.SystemKey}
        if ($pressed -in @('LeftCtrl','RightCtrl','LeftAlt','RightAlt','LeftShift','RightShift','LWin','RWin','Tab','Escape')) { return }
        $mods=[int][Windows.Input.Keyboard]::Modifiers; $vk=[Windows.Input.KeyInterop]::VirtualKeyFromKey($pressed)
        if ($vk -eq 123 -or (($mods -band 1) -and $vk -eq 115)) { $_.Handled=$true; return }
        if (-not $mods -and $pressed -notmatch '^F([1-9]|1[01])$') { $_.Handled=$true; return }
        Set-VoiceChoice $choice $vk $mods ([string]$pressed); $key.Text=$choice.label; $_.Handled=$true
    }.GetNewClosure())
    $key.Add_PreviewMouseDown({
        if ($_.ChangedButton -in @([Windows.Input.MouseButton]::XButton1,[Windows.Input.MouseButton]::XButton2)) {
            $vk=if ($_.ChangedButton -eq [Windows.Input.MouseButton]::XButton1) {5} else {6}
            Set-VoiceChoice $choice $vk ([int][Windows.Input.Keyboard]::Modifiers) ('鼠标侧键 ' + ($vk-4))
            $key.Text=$choice.label; $_.Handled=$true
        }
    }.GetNewClosure())
    [void]$panel.Children.Add($key)
    [void]$panel.Children.Add((Text-Line '支持鼠标侧键 1 / 2、F1–F11，或带修饰键的组合。设置窗口打开时暂停快捷键监听。' 11 '#8BA0BA'))
    [void]$panel.Children.Add((Text-Line '识别模型'))
    $modelBox=New-Object Windows.Controls.ComboBox
    foreach ($m in $script:VoiceModels) { $item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$m.name; $item.Tag=$m; [void]$modelBox.Items.Add($item); if ($m.id -eq $script:Settings.voiceModel) {$modelBox.SelectedItem=$item} }
    [void]$panel.Children.Add($modelBox)
    [void]$panel.Children.Add((Text-Line '语言'))
    $language=New-Object Windows.Controls.ComboBox; $langs=@('auto','zh','yue','en')
    foreach ($name in @('自动识别','中文普通话','粤语','英语')) {[void]$language.Items.Add($name)}
    $language.SelectedIndex=[math]::Max(0,[Array]::IndexOf($langs,$script:Settings.voiceLanguage)); [void]$panel.Children.Add($language)
    [void]$panel.Children.Add((Text-Line '首次下载约 160 MB，之后离线识别。只在按住快捷键时录音，文字保存在本机，不发送给对话分析服务。' 11 '#8BA0BA'))
    $notice=Text-Line '' 12 '#90DECE'; [void]$panel.Children.Add($notice)
    $save=New-Object Windows.Controls.Button; $save.Content='保存语音设置'; $save.Margin='0,12,0,0'; $save.Tag=@{choice=$choice;model=$modelBox;language=$language;langs=$langs;notice=$notice}
    $save.Add_Click({
        $options=$this.Tag
        try { Save-VoicePreferences $options.choice $options.model.SelectedItem.Tag.id $options.langs[$options.language.SelectedIndex]; $options.notice.Text='已保存，关闭设置后快捷键生效。' }
        catch { $options.notice.Text=$_.Exception.Message }
    })
    [void]$panel.Children.Add($save)
    foreach ($line in $panel.Children | Where-Object {$_ -is [Windows.Controls.TextBlock]}) { $line.Margin='0,8,0,8' }
    return $panel
}
$script:Window.Add_SourceInitialized({
    $script:VoiceHandle=(New-Object Windows.Interop.WindowInteropHelper($script:Window)).Handle
    $script:VoiceSource=[Windows.Interop.HwndSource]::FromHwnd($script:VoiceHandle)
    $script:VoiceHook=[Windows.Interop.HwndSourceHook]{param($hwnd,$message,$wParam,$lParam,[ref]$handled)
        if (($message -eq 0x312 -and $wParam.ToInt32() -eq 8102) -or $message -eq 0x8001) { $handled.Value=$true; Start-VoiceRecording }
        return [IntPtr]::Zero
    }
    $script:VoiceSource.AddHook($script:VoiceHook)
    try { Set-VoiceHotkey } catch { Set-VoiceNotice $_.Exception.Message }
})
$script:Window.Add_Closed({
    $script:VoiceTimer.Stop(); Remove-VoiceHotkey
    if ($script:Microphone) { $script:Microphone.Dispose(); $script:Microphone=$null }
    if ($script:VoiceProcess) {
        if (-not $script:VoiceProcess.HasExited) { $script:VoiceProcess.Kill(); [void]$script:VoiceProcess.WaitForExit(2000) }
        $script:VoiceProcess.Dispose(); $script:VoiceProcess=$null
    }
    Clear-VoiceFiles
})
