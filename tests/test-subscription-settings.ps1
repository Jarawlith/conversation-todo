param([switch]$Claude)
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
        $combos[0].SelectedIndex=$(if($Claude){1}else{0})
        $panels=@($p.Children|Where-Object {$_ -is [Windows.Controls.StackPanel]})
        $codex=@($panels[0].Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})
        if($codex[0].Items.Count -lt 7){throw 'Missing Codex model choices'}
        $codex[0].SelectedItem=@($codex[0].Items|Where-Object {$_.Tag.id -eq 'gpt-6-sol'})[0]
        $codex[1].SelectedItem=@($codex[1].Items|Where-Object {$_.Tag -eq 'ultra'})[0]
        $codex[0].SelectedItem=@($codex[0].Items|Where-Object {$_.Tag.id -eq 'gpt-6-luna'})[0]
        if(@($codex[1].Items|Where-Object {$_.Tag -eq 'ultra'}).Count){throw 'Unsupported Luna effort offered'}
        $codex[1].SelectedItem=@($codex[1].Items|Where-Object {$_.Tag -eq 'high'})[0]
        $claudeChoice=@($panels[1].Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})[0]
        $claudeChoice.SelectedItem=@($claudeChoice.Items|Where-Object {$_.Tag.id -eq 'sonnet'})[0]
        $dialog.UpdateLayout()
        $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(580,760,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($dialog)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $PSScriptRoot '../.build/subscription-settings.png'));$encoder.Save($stream);$stream.Close()
        $consent=@($p.Children|Where-Object {$_ -is [Windows.Controls.CheckBox]})[0];$consent.IsChecked=$true
        $save=@($p.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
        $save.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    } catch { $script:settingsTestError=$_; $dialog.Close() }
})
$timer.Start();Show-AnalysisSettings
if($script:settingsTestError){throw $script:settingsTestError}
if($script:Settings.codexModel -ne 'gpt-6-luna' -or $script:Settings.codexEffort -ne 'high' -or $script:Settings.claudeModel -ne 'sonnet'){throw 'Subscription selection persistence failed'}
$script:Window.Close()
'PASS: model dropdowns, dependent effort limits, selected model and effort persistence'
