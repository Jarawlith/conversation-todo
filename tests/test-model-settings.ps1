param([switch]$Overseas)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$DataDir=Join-Path $PSScriptRoot ('model-settings-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($DataDir)
$script:Settings=@{provider='hosted';intervalMinutes=30;hostedModel='deepseek/deepseek-v4-flash-0731';serviceUrl='http://127.0.0.1:18787/analyze';codexModel='gpt-6-luna';apiBase='https://api.deepseek.com';claudeModel='haiku';setupComplete=$false}
$script:Edition=$(if($Overseas){'overseas'}else{'mainland'})
$script:Window=New-Object Windows.Window
$script:IntervalLabel=New-Object Windows.Controls.TextBlock
function Read-Json($file) {Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json}
$script:Node=(Get-Command node.exe).Source
function Save-Settings {[IO.File]::WriteAllText((Join-Path $DataDir 'settings.json'),($script:Settings|ConvertTo-Json))}
. (Join-Path $PSScriptRoot '../src/Settings.ps1')
$script:Window.Show();$script:testError=$null;$script:stage=0;$script:ticks=0
$timer=New-Object Windows.Threading.DispatcherTimer;$timer.Interval=[timespan]::FromMilliseconds(200)
$timer.Add_Tick({
    try {
        $script:ticks++;if($script:ticks -gt 180){throw 'Model refresh timed out'}
        $dialog=$script:Window.OwnedWindows[0];$panel=$dialog.Content.Tag.analysis
        $hosted=@($panel.Children|Where-Object {$_ -is [Windows.Controls.StackPanel]})[2]
        $combos=@($hosted.Children|Where-Object {$_ -is [Windows.Controls.ComboBox]})
        $refresh=@($hosted.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0]
        if($script:stage -eq 0){
            if($combos[0].Items.Count -ne $(if($Overseas){3}else{1})){throw 'Wrong families'}
            if($combos[1].SelectedItem.Tag.id -ne 'deepseek/deepseek-v4-flash-0731'){throw 'Default model lost'}
            $refresh.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
            $script:stage=1;return
        }
        if(-not $refresh.IsEnabled){return}
        if(-not (Test-Path (Join-Path $DataDir 'models.json'))){throw 'Refresh failed'}
        if($Overseas){$combos[0].SelectedIndex=1}
        if(-not $Overseas -and $combos[1].Items.Count -ne 1){throw 'Published edition must expose exactly one hosted model'}
        $combos[1].SelectedIndex=$(if($Overseas){1}else{0});$script:expected=$combos[1].SelectedItem.Tag.id
        if(-not $combos[1].SelectedItem.Tag.supported){throw 'Unsupported test selection'}
        [IO.File]::WriteAllText((Join-Path $DataDir ('hosted-'+$script:Edition+'.secret')),('fixture-token-not-real' | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString))
        if (@($hosted.Children|Where-Object {$_ -is [Windows.Controls.TextBox] -or $_ -is [Windows.Controls.PasswordBox]}).Count) { throw 'Developer connection fields leaked into normal settings' }
        @($panel.Children|Where-Object {$_ -is [Windows.Controls.CheckBox]})[0].IsChecked=$true
        $dialog.UpdateLayout();$bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap(580,760,96,96,[Windows.Media.PixelFormats]::Pbgra32);$bitmap.Render($dialog)
        $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream=[IO.File]::Create((Join-Path $PSScriptRoot ('../.build/ModelsPreview-'+$script:Edition+'.png')));$encoder.Save($stream);$stream.Close()
        $timer.Stop();@($panel.Children|Where-Object {$_ -is [Windows.Controls.Button]})[0].RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
    }catch{$script:testError=$_;$timer.Stop();$dialog.Close()}
})
$timer.Start();Show-AnalysisSettings
if($script:testError){throw $script:testError}
if($script:Settings.hostedModel -ne $script:expected -or $script:Settings.provider -ne 'hosted'){throw 'Selected model not persisted'}
$file=Join-Path $DataDir ('hosted-'+$script:Edition+'.secret')
if([IO.File]::ReadAllText($file).Contains('fixture-token-not-real')){throw 'Plaintext token'}
$value=& powershell.exe -NoProfile -File (Join-Path $PSScriptRoot '../src/Secret.ps1') -File $file
if($value -ne 'fixture-token-not-real'){throw 'Encrypted token roundtrip failed'}
$script:Window.Close()
'PASS: '+$script:Edition+' model families, live refresh, exact model persistence and encrypted edition token'
