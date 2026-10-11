param([string]$DataDir = "$env:LOCALAPPDATA\CodexTodo", [switch]$Preview, [string]$PreviewImage, [switch]$SelfTest, [switch]$OpenSettings)
$ErrorActionPreference = 'Stop'
$script:Edition = 'mainland'
$editionFile = Join-Path $PSScriptRoot 'edition.json'
if (Test-Path -LiteralPath $editionFile) { $script:Edition = (Get-Content -LiteralPath $editionFile -Raw -Encoding UTF8 | ConvertFrom-Json).edition }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[void][System.IO.Directory]::CreateDirectory($DataDir)
$script:Instance = $null
if (-not $Preview) {
    $created = $false
    $script:Instance = New-Object System.Threading.Mutex($true, 'Local\CodexTodoWidget', [ref]$created)
    if (-not $created) { $script:Instance.Dispose(); exit }
}
$script:Worker = $null
$script:Paused = $false
$script:Filter = 'active'
$script:StateStamp = ''
$script:LastCheck = [datetime]::MinValue
$script:Actions = @{}
$script:State = $null
$script:ShowAll = $false
$script:Exiting = $false
$script:Settings = @{paused=$false;excluded=@();running=$true;intervalMinutes=30;provider="codex";codexModel="gpt-6-luna";codexEffort="medium";claudeModel="haiku";apiProtocol="openai";apiBase="https://api.deepseek.com";apiModel="deepseek-flash";serviceUrl="";claudePath="";setupComplete=$false;voiceModel="sensevoice-small-int8-2024-07-17";voiceLanguage="auto";voiceKey=113;voiceModifiers=0;voiceHotkey="F2"}
$script:Node = Join-Path $PSScriptRoot 'runtime/node.exe'
if (-not (Test-Path -LiteralPath $script:Node)) { $script:Node = (Get-Command node.exe -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
if (-not $script:Node) {
    $script:Node = "$env:USERPROFILE\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
}
function Read-Json($File) {
    if (Test-Path -LiteralPath $File) { return (Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json) }
    return $null
}
function Save-Actions {
    $temp = Join-Path $DataDir 'actions.tmp'
    [System.IO.File]::WriteAllText($temp, ($script:Actions | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination (Join-Path $DataDir 'actions.json') -Force
}
function Save-Settings {
    $temp = Join-Path $DataDir 'settings.tmp'
    [System.IO.File]::WriteAllText($temp, ($script:Settings | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temp -Destination (Join-Path $DataDir 'settings.json') -Force
}
$settingsPath = Join-Path $DataDir 'settings.json'
if (Test-Path -LiteralPath $settingsPath) {
    $savedSettings = Read-Json $settingsPath
    $script:Settings.paused = [bool]$savedSettings.paused
    $script:Settings.excluded = @($savedSettings.excluded)
    foreach ($p in $savedSettings.PSObject.Properties) { if ($p.Name -notin @('paused','excluded','running')) { $script:Settings[$p.Name] = $p.Value } }
}
if ($script:Settings.intervalMinutes -notin @(5,15,30,60,1440)) { $script:Settings.intervalMinutes = 30 }
if ($script:Edition -eq 'mainland' -and -not $script:Settings.apiModel -and $script:Settings.apiBase -eq 'https://api.openai.com/v1' -and -not (Test-Path -LiteralPath (Join-Path $DataDir 'byok.secret'))) {
    $script:Settings.apiBase = 'https://api.deepseek.com'; $script:Settings.apiModel = 'deepseek-flash'
}
if ($script:Edition -eq 'overseas' -and $script:Settings.provider -notin @('codex','claude','hosted')) {
    $script:Settings.provider = 'codex'; $script:Settings.setupComplete = $false
}
if ($script:Edition -eq 'mainland' -and $script:Settings.provider -eq 'hosted' -and $script:Settings.hostedModel -ne (Read-Json (Join-Path $PSScriptRoot 'hosted-policy.json')).mainlandModel) {
    $script:Settings.setupComplete = $false
}
$script:Paused = $script:Settings.paused
if (-not $Preview) { Save-Settings }
$saved = Read-Json (Join-Path $DataDir 'actions.json')
if ($saved) { foreach ($p in $saved.PSObject.Properties) { $script:Actions[$p.Name] = $p.Value } }
$layout = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="对话待办" Width="398" Height="590" MinWidth="350" MinHeight="260" WindowStyle="None"
    ResizeMode="CanResizeWithGrip" AllowsTransparency="True" Background="Transparent" Topmost="True" FontFamily="Microsoft YaHei UI">
 <Window.Resources>
  <Style TargetType="Button">
   <Setter Property="Foreground" Value="#BDCBDA"/><Setter Property="Background" Value="#202C3D"/>
   <Setter Property="BorderThickness" Value="0"/><Setter Property="Padding" Value="10,7"/><Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
    <Border Background="{TemplateBinding Background}" CornerRadius="7" Padding="{TemplateBinding Padding}">
     <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
    </Border><ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="#34465F"/></Trigger>
     <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
    </ControlTemplate.Triggers></ControlTemplate></Setter.Value></Setter>
  </Style>
  <Style TargetType="TextBlock"><Setter Property="Foreground" Value="#EDF3FC"/></Style>
 </Window.Resources>
 <Border Background="#111B29" CornerRadius="16" BorderBrush="#34465C" BorderThickness="1" Padding="18">
  <Grid>
   <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    <RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
   <Grid x:Name="Header" Grid.Row="0" Background="Transparent" Margin="0,0,0,16">
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel><TextBlock Text="接下来，做什么" FontSize="21" FontWeight="SemiBold"/>
     <TextBlock x:Name="ModelLabel" Text="分析服务" TextWrapping="Wrap" MaxWidth="240" FontSize="10" Foreground="#7F9AB8" Margin="0,5,0,0"/></StackPanel>
    <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Top">
     <Button x:Name="Pin" Content="钉" ToolTip="切换置顶" Padding="8,5" Margin="0,0,4,0"/>
     <Button x:Name="Collapse" Content="−" ToolTip="折叠 / 展开" Padding="8,5" Margin="0,0,4,0"/>
     <Button x:Name="Close" Content="×" ToolTip="收起到托盘，继续扫描" Padding="8,5"/>
    </StackPanel>
   </Grid>
   <Grid Grid.Row="1" x:Name="Summary" Margin="0,0,0,14">
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <StackPanel Orientation="Horizontal"><TextBlock x:Name="Count" Text="0" FontSize="29" FontWeight="SemiBold" Foreground="#90DECE"/>
     <TextBlock Text=" 件待办" VerticalAlignment="Bottom" Foreground="#A4B4C8" Margin="0,0,0,5"/></StackPanel>
    <Button Grid.Column="1" x:Name="Refresh" Content="检查对话" VerticalAlignment="Center" Background="#214C48" Foreground="#BFF5E5"/>
   </Grid>
   <StackPanel x:Name="Tabs" Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,14">
    <Button x:Name="ActiveTab" Content="待办" Margin="0,0,6,0"/>
    <Button x:Name="PendingTab" Content="待确认" Margin="0,0,6,0"/>
    <Button x:Name="DoneTab" Content="已结束" Margin="0,0,6,0"/>
    <Button x:Name="IgnoredTab" Content="已忽略"/>
   </StackPanel>
   <ScrollViewer x:Name="Scroller" Grid.Row="3" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
    <StackPanel x:Name="Cards"/>
   </ScrollViewer>
   <StackPanel Grid.Row="4" x:Name="Footer" Margin="0,14,0,0">
    <Button x:Name="Capture" Content="记录想法 · 按住 F2 说话" Margin="0,0,0,8"/>
    <Button x:Name="More" Content="展开其他任务" Visibility="Collapsed" Margin="0,0,0,8"/>
    <TextBlock x:Name="Status" Text="准备检查 Codex、Claude Code 与网页对话…" FontSize="11" Foreground="#8BA0BA" TextWrapping="Wrap" MaxHeight="60"/>
    <Grid Margin="0,9,0,0"><Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
     <TextBlock x:Name="IntervalLabel" Text="每 30 分钟 · 仅变化时分析" FontSize="10" Foreground="#697F99" VerticalAlignment="Center"/>
     <StackPanel Grid.Column="1" Orientation="Horizontal"><Button x:Name="Sources" Content="对话" Padding="8,4" FontSize="10" Margin="0,0,5,0"/>
     <Button x:Name="SettingsButton" Content="设置" Padding="8,4" FontSize="10" Margin="0,0,5,0"/>
     <Button x:Name="Pause" Content="暂停" Padding="8,4" FontSize="10"/></StackPanel>
    </Grid>
   </StackPanel>
  </Grid>
 </Border>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader ([xml]$layout)
$script:Window = [Windows.Markup.XamlReader]::Load($reader)
$themeReader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'SettingsTheme.xaml'))
try { $script:Window.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($themeReader)) } finally { $themeReader.Close() }
foreach ($name in @('Header','Pin','Collapse','Close','Summary','Count','Refresh','Tabs','ActiveTab','PendingTab','DoneTab','IgnoredTab','Scroller','Cards','Footer','Status','Pause','Sources','More','SettingsButton','IntervalLabel','ModelLabel','Capture')) {
    Set-Variable -Scope Script -Name $name -Value $script:Window.FindName($name)
}
$area = [System.Windows.SystemParameters]::WorkArea
$script:Window.Left = $area.Right - $script:Window.Width - 24
$script:Window.Top = $area.Top + 48
$prefs = Read-Json (Join-Path $DataDir 'window.json')
if ($prefs) {
    $script:Window.Left = [Math]::Max($area.Left, [Math]::Min($prefs.left, $area.Right - 350))
    $script:Window.Top = [Math]::Max($area.Top, [Math]::Min($prefs.top, $area.Bottom - 100))
    $script:Window.Topmost = [bool]$prefs.topmost
}
function Text-Line($Text, $Size = 12, $Color = '#D2DEED') {
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text; $block.FontSize = $Size; $block.Foreground = $Color
    $block.TextWrapping = 'Wrap'; $block.Margin = '0,0,0,7'
    return $block
}
function Action-Button($Label, $Id, $Action) {
    $button = New-Object System.Windows.Controls.Button
    $button.Content = $Label; $button.Margin = '0,0,6,0'; $button.FontSize = 11; $button.Padding = '8,5'
    $button.Tag = @{ Id = $Id; Action = $Action }
    $button.Add_Click({
        $info = $this.Tag
        $old = $script:Actions[$info.Id]
        $priority = $null; if ($old) { $priority = $old.priority }
        if ($info.Action -eq 'priority') {
            if ($null -eq $priority) { $priority = (@(Get-DisplayTasks) | Where-Object id -eq $info.Id | Select-Object -First 1).priority }
            $priority = ([int]$priority % 3) + 1
            $status = $null; if ($old) { $status = $old.status }
            $script:Actions[$info.Id] = @{ status = $status; priority = $priority; updated = [datetime]::UtcNow.ToString('o') }
        } else { $script:Actions[$info.Id] = @{ status = $info.Action; priority = $priority; updated = [datetime]::UtcNow.ToString('o') } }
        Save-Actions; Render-Tasks
    })
    return $button
}
function Get-DisplayTasks {
    if ($script:State -and $script:State.tasks) { foreach ($p in $script:State.tasks.PSObject.Properties) { $p.Value } }
    Read-ManualTasks
}
function Render-Tasks {
    $script:Cards.Children.Clear()
    $all = @()
    if (@(Get-DisplayTasks).Count) {
        $all = @(Get-DisplayTasks | ForEach-Object {
            $task = $_ | Select-Object *
            $action = $script:Actions[$task.id]
            if ($action) {
                if ($action.status -and (-not $task.resolvedAt -or $action.updated -gt $task.resolvedAt -or $action.status -ne 'active')) { $task.status = $action.status }
                if ($action.priority) { $task.priority = $action.priority }
            }
            if ($script:Settings.excluded -notcontains $task.sourceId) { $task }
        })
    }
    $script:Count.Text = [string]@($all | Where-Object status -eq 'active').Count
    $script:PendingTab.Content = '待确认 ' + @($all | Where-Object status -eq 'pending').Count
    foreach ($tab in @($script:ActiveTab,$script:PendingTab,$script:DoneTab,$script:IgnoredTab)) { $tab.Background = '#202C3D' }
    @{active=$script:ActiveTab;pending=$script:PendingTab;done=$script:DoneTab;ignored=$script:IgnoredTab}[$script:Filter].Background = '#36506E'
    $tasks = @($all | Where-Object { $_.status -eq $script:Filter -or ($script:Filter -eq 'done' -and $_.status -eq 'cancelled') } | Sort-Object priority, @{Expression={ if ($_.due) { $_.due } else { '9999' } }}, created)
    $script:More.Visibility = if ($tasks.Count -gt 3) { 'Visible' } else { 'Collapsed' }
    $script:More.Content = if ($script:ShowAll) { '收起，只看前三项' } else { '展开其他 ' + [math]::Max(0, $tasks.Count - 3) + ' 项' }
    if (-not $script:ShowAll) { $tasks = @($tasks | Select-Object -First 3) }
    if (-not $tasks.Count) {
        $empty = @{ active='这里还没有待办。可以检查对话，也可以按住快捷键记录想法。'; pending='AI 建议会出现在这里，由你决定是否加入待办。'; done='完成的待办会保留在这里。'; ignored='忽略的待办会保留在这里，可以重新加入。' }[$script:Filter]
        $script:Cards.Children.Add((Text-Line $empty 13 '#8BA0BA')) | Out-Null
    }
    foreach ($task in $tasks) {
        $card = New-Object System.Windows.Controls.Border
        $card.Background = '#1A2738'; $card.CornerRadius = '10'; $card.Padding = '12'; $card.Margin = '0,0,4,10'
        $body = New-Object System.Windows.Controls.StackPanel
        $color = @{1='#F4A79A';2='#E1CF96';3='#93ADCA'}[[int]$task.priority]
        $label = @{1='优先';2='常规';3='稍后'}[[int]$task.priority]
        if ($task.due) { $label += '  ·  ' + $task.due }
        if ($task.status -eq 'cancelled') { $label += '  ·  已取消' }
        $body.Children.Add((Text-Line $label 10 $color)) | Out-Null
        $body.Children.Add((Text-Line $task.title 14 '#F1F5FB')) | Out-Null
        $body.Children.Add((Text-Line $task.reason 11 '#9BB0C9')) | Out-Null
        $source = New-Object System.Windows.Controls.Expander
        $source.Header = '查看对话依据 · ' + $(if ($task.sourceType) { $task.sourceType } else { 'Codex' }); $source.Foreground = '#83BEB3'; $source.FontSize = 10; $source.Margin = '0,0,0,10'
        $details = New-Object System.Windows.Controls.StackPanel
        $details.Children.Add((Text-Line $task.sourceTitle 10 '#8398B3')) | Out-Null
        $details.Children.Add((Text-Line ('“' + $task.evidence + '”') 11 '#BDCADD')) | Out-Null
        $open = New-Object System.Windows.Controls.Button
        $open.Content = '打开来源'; $open.FontSize = 10
        $open.Tag = if ($task.sourceUrl) { $task.sourceUrl } elseif ($task.sourceType -eq 'Claude Code') { $task.sourceFile } else { 'codex://threads/' + $task.sourceId }
        $open.Add_Click({ Start-Process $this.Tag })
        if ($task.sourceId -ne 'manual') { $details.Children.Add($open) | Out-Null }
        $source.Content = $details; $body.Children.Add($source) | Out-Null
        $buttons = New-Object System.Windows.Controls.WrapPanel
        if ($task.status -eq 'pending') { $buttons.Children.Add((Action-Button '加入待办' $task.id 'active')) | Out-Null }
        if ($task.status -in @('active','pending')) {
            $buttons.Children.Add((Action-Button '完成' $task.id 'done')) | Out-Null
            $buttons.Children.Add((Action-Button '忽略' $task.id 'ignored')) | Out-Null
            $buttons.Children.Add((Action-Button '调优先级' $task.id 'priority')) | Out-Null
        } else { $buttons.Children.Add((Action-Button '重新加入' $task.id 'active')) | Out-Null }
        $body.Children.Add($buttons) | Out-Null
        $card.Child = $body; $script:Cards.Children.Add($card) | Out-Null
    }
}
function Update-AnalysisCaption {
    $script:ModelLabel.Text = switch ($script:Settings.provider) {
        'hosted' { 'OPENROUTER / ' + $script:Settings.hostedModel }
        'claude' { 'CLAUDE / ' + $script:Settings.claudeModel }
        'byok' { 'API / ' + $script:Settings.apiModel }
        default { 'CODEX / ' + $script:Settings.codexModel + ' · ' + ([string]$script:Settings.codexEffort).ToUpperInvariant() }
    }
}
function Start-Check {
    if ($Preview -or -not $script:Settings.setupComplete -or $script:Paused -or ($script:Worker -and -not $script:Worker.HasExited)) { return }
    if (-not (Test-Path -LiteralPath $script:Node)) { $script:Status.Text = '找不到 Node.js。请安装 Node.js 后重启组件。'; return }
    # Include user decisions in the next analysis without sharing write ownership of actions.json.
    $decisionsFile = Join-Path $DataDir 'decisions.json'
    [System.IO.File]::WriteAllText($decisionsFile, ($script:Actions | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
    $workerPath = Join-Path $PSScriptRoot 'analyze.js'
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $script:Node
    $info.Arguments = '"' + $workerPath + '" "' + $DataDir + '"'
    $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $script:Worker = [System.Diagnostics.Process]::Start($info)
    $script:LastCheck = [datetime]::Now
    $script:Status.Text = '正在检查本机对话…'
}
. (Join-Path $PSScriptRoot 'Voice.ps1')
. (Join-Path $PSScriptRoot 'Settings.ps1')
$script:Capture.Add_Click({Show-VoiceCapture})
$script:Capture.Content='记录想法 · 按住 ' + $script:Settings.voiceHotkey + ' 说话'
Update-AnalysisCaption
$script:IntervalLabel.Text = '每 ' + $script:Settings.intervalMinutes + ' 分钟 · 仅变化时分析'
$script:SettingsButton.Add_Click({
    if ($script:Worker -and -not $script:Worker.HasExited) { [void][Windows.MessageBox]::Show('请等待当前分析完成后再更换服务。'); return }
    Show-AnalysisSettings
})
$script:Header.Add_MouseLeftButtonDown({ if ($_.OriginalSource -isnot [System.Windows.Controls.Button]) { $script:Window.DragMove() } })
$script:Pin.Add_Click({ $script:Window.Topmost = -not $script:Window.Topmost; $script:Pin.Content = if ($script:Window.Topmost) { '钉' } else { '○' } })
$script:ExpandedHeight = 590
$script:Collapse.Add_Click({
    if ($script:Scroller.Visibility -eq 'Visible') {
        $script:ExpandedHeight = $script:Window.Height
        foreach ($item in @($script:Summary,$script:Tabs,$script:Scroller,$script:Footer)) { $item.Visibility = 'Collapsed' }
        $script:Window.MinHeight = 90; $script:Window.Height = 90; $script:Collapse.Content = '+'
    } else {
        foreach ($item in @($script:Summary,$script:Tabs,$script:Scroller,$script:Footer)) { $item.Visibility = 'Visible' }
        $script:Window.MinHeight = 260; $script:Window.Height = $script:ExpandedHeight; $script:Collapse.Content = '−'
    }
})
$script:Close.Add_Click({ $script:Window.Hide() })
$script:Refresh.Add_Click({ Start-Check })
$script:Pause.Add_Click({
    $script:Paused = -not $script:Paused
    $script:Settings.paused = $script:Paused; Save-Settings
    $script:Pause.Content = if ($script:Paused) { '继续' } else { '暂停' }
    if ($script:Paused) { $script:Status.Text = '已暂停采集与后续分析；当前分析会完成。' } else { Start-Check }
})
$script:More.Add_Click({ $script:ShowAll = -not $script:ShowAll; Render-Tasks })
$script:Sources.Add_Click({
    $dialog = New-Object Windows.Window
    $dialog.Title = '对话 · 扫描范围'; $dialog.Width = 620; $dialog.Height = 450; $dialog.Owner = $script:Window
    $dialog.WindowStartupLocation = 'CenterOwner'; $dialog.Background = '#111B29'; $dialog.Foreground = '#E8EEF6'; $dialog.FontFamily = 'Microsoft YaHei UI'
    $themeReader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'SettingsTheme.xaml'))
    try { $dialog.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($themeReader)) } finally { $themeReader.Close() }
    $scroll = New-Object Windows.Controls.ScrollViewer; $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '16'
    $panel.Children.Add((Text-Line '勾选表示排除：停止采集分析，并删除此对话生成的任务。取消勾选后，下次检查重新分析。' 13 '#A5B5C8')) | Out-Null
    $known = @{}
    if ($script:State -and $script:State.sources) { foreach ($p in $script:State.sources.PSObject.Properties) { $known[$p.Name] = $p.Value } }
    $browserDir = Join-Path $DataDir 'browser'
    if (Test-Path -LiteralPath $browserDir) { foreach ($file in Get-ChildItem -LiteralPath $browserDir -Filter '*.json') { $c = Read-Json $file.FullName; if ($c) { $known[$c.id] = $c } } }
    foreach ($id in $known.Keys | Sort-Object) {
        $check = New-Object Windows.Controls.CheckBox; $c = $known[$id]
        $checkText = New-Object Windows.Controls.TextBlock; $checkText.TextWrapping = 'Wrap'; $checkText.Text = [string]$c.sourceType + ' · ' + [string]$c.title
        $check.Content = $checkText; $check.Margin = '0,5,0,5'; $check.Tag = $id
        $check.IsChecked = $script:Settings.excluded -contains $id
        $check.Add_Click({
            $id = [string]$this.Tag
            if ($this.IsChecked) { $script:Settings.excluded = @($script:Settings.excluded | Where-Object { $_ -ne $id }) + @($id) }
            else { $script:Settings.excluded = @($script:Settings.excluded | Where-Object { $_ -ne $id }) }
            Save-Settings
            $browserDir = Join-Path $DataDir 'browser'
            if ($this.IsChecked -and (Test-Path -LiteralPath $browserDir)) { foreach ($file in Get-ChildItem -LiteralPath $browserDir -Filter '*.json') { $c = Read-Json $file.FullName; if ($c.id -eq $id) { Remove-Item -LiteralPath $file.FullName -Force } } }
            $info = New-Object Diagnostics.ProcessStartInfo
            $info.FileName = $script:Node; $info.Arguments = '"' + (Join-Path $PSScriptRoot 'analyze.js') + '" "' + $DataDir + '" --purge'
            $info.UseShellExecute = $false; $info.CreateNoWindow = $true; [void][Diagnostics.Process]::Start($info)
            Render-Tasks
        })
        $panel.Children.Add($check) | Out-Null
    }
    if (-not $known.Count) { $panel.Children.Add((Text-Line '首次扫描或网页采集后，对话会列在这里。' 13 '#A5B5C8')) | Out-Null }
    $scroll.Content = $panel; $dialog.Content = $scroll; [void]$dialog.ShowDialog()
})
$script:ActiveTab.Add_Click({ $script:Filter = 'active'; Render-Tasks })
$script:PendingTab.Add_Click({ $script:Filter = 'pending'; Render-Tasks })
$script:DoneTab.Add_Click({ $script:Filter = 'done'; Render-Tasks })
$script:IgnoredTab.Add_Click({ $script:Filter = 'ignored'; Render-Tasks })
$script:Timer = New-Object System.Windows.Threading.DispatcherTimer
$script:Timer.Interval = [timespan]::FromSeconds(2)
$script:Timer.Add_Tick({
    try {
        $file = Join-Path $DataDir 'state.json'
        if (Test-Path -LiteralPath $file) {
            $stamp = (Get-Item -LiteralPath $file).LastWriteTimeUtc.Ticks
            if ($stamp -ne $script:StateStamp) { $script:State = Read-Json $file; $script:StateStamp = $stamp; Render-Tasks }
        }
        $progress = Read-Json (Join-Path $DataDir 'progress.json')
        $busy = $script:Worker -and -not $script:Worker.HasExited
        $script:Refresh.IsEnabled = -not $busy -and -not $script:Paused
        if (-not $Preview -and -not $script:Settings.setupComplete) { $script:Status.Text = '请打开设置，选择分析方式并授权后台分析。' }
        elseif ($progress -and -not $script:Paused) { $script:Status.Text = $progress.message; $script:Status.ToolTip = $progress.message }
        if (-not $Preview -and -not $script:Paused -and -not $busy -and ([datetime]::Now - $script:LastCheck).TotalMinutes -ge $script:Settings.intervalMinutes) { Start-Check }
    } catch { $script:Status.Text = '读取本地状态失败：' + $_.Exception.Message }
})
$script:Window.Add_Closed({
    $script:Timer.Stop()
    if (-not $Preview) { $script:Settings.running = $false; Save-Settings }
    if ($script:Tray) { $script:Tray.Visible = $false; $script:Tray.Dispose() }
    if ($script:Instance) { $script:Instance.ReleaseMutex(); $script:Instance.Dispose() }
    $preferences = @{left=$script:Window.Left;top=$script:Window.Top;topmost=$script:Window.Topmost}
    [System.IO.File]::WriteAllText((Join-Path $DataDir 'window.json'), ($preferences | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
})
if (-not $Preview -or $SelfTest) {
    $script:Tray = New-Object Windows.Forms.NotifyIcon
    $script:Tray.Icon = [Drawing.SystemIcons]::Application; $script:Tray.Text = '对话待办 · 后台扫描'; $script:Tray.Visible = $true
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $show = $menu.Items.Add('显示待办'); $show.Add_Click({ $script:Window.Show(); $script:Window.Activate() })
    $capture = $menu.Items.Add('记录想法'); $capture.Add_Click({Show-VoiceCapture})
    $exit = $menu.Items.Add('退出，停止扫描'); $exit.Add_Click({ $script:Exiting = $true; $script:Window.Close() })
    $script:Tray.ContextMenuStrip = $menu
    $script:Tray.Add_DoubleClick({ $script:Window.Show(); $script:Window.Activate() })
    $script:Window.Add_Closing({ if (-not $script:Exiting) { $_.Cancel = $true; $script:Window.Hide() } })
}
$script:Pause.Content = if ($script:Paused) { '继续' } else { '暂停' }
$script:State = Read-Json (Join-Path $DataDir 'state.json')
Render-Tasks
if ($SelfTest) {
    $script:Window.Show(); $script:Window.UpdateLayout()
    function Click-Control($Control) { $Control.RaiseEvent((New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Button]::ClickEvent))) }
    function Check($Condition, $Message) { if (-not $Condition) { throw $Message } }
    Check ($script:Count.Text -eq '2') 'Active count failed'
    Click-Control $script:PendingTab
    Check ($script:Filter -eq 'pending') 'Pending tab failed'
    $buttons = $script:Cards.Children[0].Child.Children[4]
    Click-Control $buttons.Children[0]
    Check ($script:Actions['third'].status -eq 'active') 'Accept suggestion failed'
    Click-Control $script:ActiveTab
    Check ($script:Count.Text -eq '3') 'Accepted count failed'
    $buttons = $script:Cards.Children[0].Child.Children[4]
    Click-Control $buttons.Children[2]
    Check ($script:Actions['first'].priority -eq 2) 'Priority change failed'
    $card = @($script:Cards.Children | Where-Object { $_.Child.Children[1].Text -eq '提交预算报告' })[0]
    Click-Control $card.Child.Children[4].Children[0]
    Check ($script:Actions['first'].status -eq 'done') 'Complete failed'
    Click-Control $script:DoneTab
    Check ($script:Cards.Children.Count -eq 1) 'Done tab failed'
    Click-Control $script:Cards.Children[0].Child.Children[4].Children[0]
    Check ($script:Actions['first'].status -eq 'active') 'Restore failed'
    Click-Control $script:Collapse
    Check ($script:Window.Height -eq 90) 'Collapse failed'
    Click-Control $script:Collapse
    Check ($script:Scroller.Visibility -eq 'Visible') 'Expand failed'
    $restored = Read-Json (Join-Path $DataDir 'actions.json')
    Check ($restored.first.priority -eq 2) 'Persist priority failed'
    $fourth = $script:State.tasks.first | Select-Object *
    $fourth.id = 'fourth'; $fourth.title = '第四项测试任务'
    $script:State.tasks | Add-Member -NotePropertyName 'fourth' -NotePropertyValue $fourth
    Click-Control $script:ActiveTab
    Render-Tasks
    Check ($script:Cards.Children.Count -eq 3) 'Top three limit failed'
    Click-Control $script:More
    Check ($script:Cards.Children.Count -eq 4) 'Expand remaining failed'
    Click-Control $script:Pause
    Check ((Read-Json $settingsPath).paused) 'Persist pause failed'
    $voiceTask = Save-VoiceTask "记录下一次发布的想法`n完整内容保存在本机。"
    $script:State = [pscustomobject]@{tasks=[pscustomobject]@{};sources=[pscustomobject]@{}}
    Click-Control $script:ActiveTab
    Check ($script:Count.Text -eq '1') 'Manual task disappeared when analysis state was replaced'
    $buttons = $script:Cards.Children[0].Child.Children[4]
    Click-Control $buttons.Children[2]
    Check ($script:Actions[$voiceTask.id].priority -eq 3) 'Manual priority failed'
    Click-Control $script:Cards.Children[0].Child.Children[4].Children[0]
    Click-Control $script:DoneTab
    Check ($script:Cards.Children[0].Child.Children[1].Text -eq $voiceTask.title) 'Manual complete failed'
    Check (@(Read-ManualTasks)[0].evidence.Contains('完整内容')) 'Manual full text persistence failed'
    Click-Control $script:Close
    Check (-not $script:Window.IsVisible -and $script:Tray.Visible) 'Close to tray failed'
    $script:Exiting = $true
    $script:Window.Close()
    Write-Output 'PASS: WPF tabs, accept, complete, restore, priority, fold, persistence, top-three, pause, close-to-tray'
    exit
}
if ($PreviewImage) {
    $script:Window.Show()
    $script:Window.UpdateLayout()
    $bitmap = New-Object System.Windows.Media.Imaging.RenderTargetBitmap(398,590,96,96,[System.Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($script:Window)
    $encoder = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $stream = [System.IO.File]::Create($PreviewImage)
    $encoder.Save($stream); $stream.Close(); $script:Window.Close()
    exit
}
$script:Timer.Start()
$script:Window.Add_ContentRendered({
    if (-not $Preview -and (-not $script:Settings.setupComplete -or $OpenSettings)) { Show-AnalysisSettings }
    if ($script:Settings.setupComplete) { Start-Check } else { $script:Status.Text = '请打开设置，选择分析方式并授权后台分析。' }
})
$script:Window.Show()
$application = New-Object Windows.Application
$application.ShutdownMode = 'OnMainWindowClose'; $application.MainWindow = $script:Window
$application.Add_SessionEnding({ $script:Exiting = $true })
[void]$application.Run()
