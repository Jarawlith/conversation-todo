param([switch]$Overseas)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$DataDir=Join-Path $PSScriptRoot ('settings-v3-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($DataDir)
$script:Settings=@{provider='codex';intervalMinutes=30;codexModel='gpt-6-luna';claudeModel='haiku';apiBase='https://api.deepseek.com';apiModel='fixture';apiProtocol='openai';setupComplete=$false}
$script:Edition = $(if ($Overseas) {'overseas'} else {'mainland'})
$script:Window=New-Object Windows.Window
$script:IntervalLabel=New-Object Windows.Controls.TextBlock
function Read-Json($file) { Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json }
$script:Node = (Get-Command node.exe).Source
function Save-Settings { [IO.File]::WriteAllText((Join-Path $DataDir 'settings.json'),($script:Settings|ConvertTo-Json)) }
. (Join-Path $PSScriptRoot '../src/Settings.ps1')
$script:Window.Show()
$script:settingsTestError=$null
$timer=New-Object Windows.Threading.DispatcherTimer
$timer.Interval=[timespan]::FromMilliseconds(200)
$timer.Add_Tick({
    $timer.Stop()
    try {
        $dialog=$script:Window.OwnedWindows[0];$p=$dialog.Content.Content
        $combos=@($p.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})
        if ($Overseas -and $combos[0].Items.Count -ne 3) {throw 'Overseas provider choices failed'}; $combos[0].SelectedIndex=$(if($Overseas){0}else{3});$combos[1].SelectedIndex=3; $dialog.UpdateLayout(); $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(540,730,96,96,[Windows.Media.PixelFormats]::Pbgra32); $bitmap.Render($dialog); $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder; $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap)); $stream=[IO.File]::Create((Join-Path $PSScriptRoot '../.build/SettingsPreview-0.3.png')); $encoder.Save($stream); $stream.Close()
        $apiPanel=@($p.Children|Where-Object {$_ -is [Windows.Controls.StackPanel]})[3]
        $supplier=@($apiPanel.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})[0]
        $advanced=@($apiPanel.Children|Where-Object {$_ -is [Windows.Controls.Expander]})[0]
        $format=@($advanced.Content.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})[0]
        $address=@($advanced.Content.Children|Where-Object {$_ -is [Windows.Controls.TextBox]})[0]
        $urls=@('https://api.deepseek.com','https://ark.cn-beijing.volces.com/api/v3','https://api.openai.com/v1','https://api.anthropic.com/v1')
        for($i=0;$i -lt 4;$i++) {
            $supplier.SelectedIndex=$i
            if($address.Text -ne $urls[$i] -or -not $address.IsReadOnly -or $format.SelectedIndex -ne $(if($i -eq 3){1}else{0})){throw 'Supplier automatic configuration failed'}
        }
        $supplier.SelectedIndex=4
        if($address.IsReadOnly -or -not $format.IsEnabled -or -not $advanced.IsExpanded){throw 'Custom supplier controls unavailable'}
        $supplier.SelectedIndex=3
        @($apiPanel.Children|Where-Object {$_ -is [Windows.Controls.TextBox]})[0].Text='fixture-model'
        $box=@($apiPanel.Children|Where-Object {$_ -is [Windows.Controls.PasswordBox]})[0];$box.Password='fixture-secret-not-real'
        $consent=@($p.Children|Where-Object {$_ -is [Windows.Controls.CheckBox]})[0];$consent.IsChecked=$true
        $save=@($p.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
        $save.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    } catch { $script:settingsTestError=$_; $dialog.Close() }
})
$timer.Start();Show-AnalysisSettings
if($script:settingsTestError){throw $script:settingsTestError}
if($script:Settings.provider -ne $(if ($Overseas) {'codex'} else {'byok'}) -or $script:Settings.intervalMinutes -ne 60 -or -not $script:Settings.setupComplete){throw 'Settings persistence failed'}
if ($Overseas) { $script:Window.Close(); 'PASS: overseas subscription and hosted choices, frequency persistence'; exit }
$file=Join-Path $DataDir 'byok.secret'
if([IO.File]::ReadAllText($file).Contains('fixture-secret-not-real')){throw 'Plaintext secret persisted'}
$value=& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot '../src/Secret.ps1') -File $file
if($value -ne 'fixture-secret-not-real'){throw 'DPAPI roundtrip failed'}
$script:Window.Close()
if($script:Settings.apiProtocol -ne 'anthropic' -or $script:Settings.apiBase -ne 'https://api.anthropic.com/v1'){throw 'Supplier settings persistence failed'}
'PASS: separate suppliers, automatic URL/protocol, custom connection controls, persistence and encrypted key'
