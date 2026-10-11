function Show-AnalysisSettings {
    $env:PSModulePath = (Join-Path $PSHOME 'Modules') + ';' + $env:PSModulePath
Add-Type -AssemblyName Microsoft.PowerShell.Security
Import-Module -Assembly ([Microsoft.PowerShell.Commands.ConvertToSecureStringCommand].Assembly) -Global -Force -ErrorAction Stop
    $dialog = New-Object Windows.Window
    $dialog.Title = '设置 · 对话待办'; $dialog.Width = 580; $dialog.Height = 760
    $dialog.MinWidth = 500; $dialog.MinHeight = 600
    $dialog.Background = '#111B29'; $dialog.Foreground = '#E8EEF6'
    $dialog.FontFamily = 'Microsoft YaHei UI'
    $themeReader = [Xml.XmlReader]::Create((Join-Path $PSScriptRoot 'SettingsTheme.xaml'))
    try { $dialog.Resources.MergedDictionaries.Add([Windows.Markup.XamlReader]::Load($themeReader)) } finally { $themeReader.Close() }
    $dialog.Owner = $script:Window; $dialog.WindowStartupLocation = 'CenterOwner'
    $scroll = New-Object Windows.Controls.ScrollViewer
    $panel = New-Object Windows.Controls.StackPanel; $panel.Margin = '28,22,28,28'
    function Label($text) {
        $b = New-Object Windows.Controls.TextBlock; $b.Text = $text; $b.TextWrapping = 'Wrap'; $b.Margin = '0,12,0,8'
        [void]$panel.Children.Add($b)
    }
    function Field($name, $value) {
        Label $name
        $b = New-Object Windows.Controls.TextBox; $b.Text = [string]$value; $b.Padding = '12,9'
        [void]$panel.Children.Add($b); return $b
    }
    $heading = New-Object Windows.Controls.TextBlock; $heading.Text = '设置'; $heading.FontSize = 25; $heading.FontWeight = 'SemiBold'; $heading.Foreground = '#E8EEF6'
    [void]$panel.Children.Add($heading)
    Label '让对话变成下一步。随时调整，已有待办会保留。'
    Label '分析方式'
    $provider = New-Object Windows.Controls.ComboBox
    $names = @('使用我的 Codex 订阅','使用我的 Claude 订阅','使用软件提供的 AI','使用我的 API Key')
    $ids = @('codex','claude','hosted','byok')
    if ($script:Edition -eq 'overseas') { $names = $names[0..2]; $ids = $ids[0..2] }
    foreach ($name in $names) { [void]$provider.Items.Add($name) }
    $provider.SelectedIndex = [Math]::Max(0,[Array]::IndexOf($ids,$script:Settings.provider))
    [void]$panel.Children.Add($provider)
    Label '检查频率'
    $interval = New-Object Windows.Controls.ComboBox; $minutes = @(5,15,30,60,1440)
    foreach ($name in @('5 分钟','15 分钟','30 分钟（默认）','1 小时','每天一次')) { [void]$interval.Items.Add($name) }
    $interval.SelectedIndex = [Math]::Max(0,[Array]::IndexOf($minutes,[int]$script:Settings.intervalMinutes))
    [void]$panel.Children.Add($interval)
    Label '仅分析新增或变化的内容。没有变化，不调用模型。'
    $codexPanel = New-Object Windows.Controls.StackPanel; $outer = $panel; $panel = $codexPanel
    $subscriptionModels = Read-Json (Join-Path $PSScriptRoot 'subscription-models.json')
    $codexOptions = @($subscriptionModels.codex)
    $codexHome = $(if ($env:CODEX_HOME) {$env:CODEX_HOME} else {Join-Path $env:USERPROFILE '.codex'})
    $cachePath = Join-Path $codexHome 'models_cache.json'
    if (Test-Path -LiteralPath $cachePath) {
        try {
            $cached = @((Read-Json $cachePath).models | Where-Object { $_.visibility -eq 'list' -and $_.slug -like 'gpt-*' } | ForEach-Object {
                [pscustomobject]@{id=$_.slug;name=$_.display_name;efforts=@($_.supported_reasoning_levels | ForEach-Object {$_.effort})}
            })
            if ($cached.Count) { $codexOptions = $cached }
        } catch { }
    }
    function ModelChoice($options, $value) {
        $choice = New-Object Windows.Controls.ComboBox; $choice.MaxDropDownHeight = 320
        foreach ($option in $options) {
            $item = New-Object Windows.Controls.ComboBoxItem; $item.Content = $option.name; $item.Tag = $option; $item.ToolTip = $option.id
            [void]$choice.Items.Add($item)
        }
        $custom = New-Object Windows.Controls.ComboBoxItem; $custom.Content = '自定义模型…'; $custom.Tag = [pscustomobject]@{id='';efforts=@('low','medium','high')}
        [void]$choice.Items.Add($custom); [void]$panel.Children.Add($choice)
        $choice.SelectedIndex = $choice.Items.Count - 1
        for ($i=0; $i -lt $options.Count; $i++) { if ($options[$i].id -eq $value) {$choice.SelectedIndex=$i; break} }
        return $choice
    }
    Label 'Codex 模型'
    $codexModel = ModelChoice $codexOptions $script:Settings.codexModel
    $codexCustom = New-Object Windows.Controls.TextBox; $codexCustom.Text = [string]$script:Settings.codexModel; $codexCustom.ToolTip = '自定义 Codex 模型 ID'; [void]$panel.Children.Add($codexCustom)
    Label '推理强度'
    $codexEffort = New-Object Windows.Controls.ComboBox; [void]$panel.Children.Add($codexEffort)
    $effortNames = @{none='无';minimal='最低';low='低';medium='中等';high='高';xhigh='很高';max='最高';ultra='极高'}
    $effortState = @{value=$(if ($script:Settings.codexEffort) {$script:Settings.codexEffort} else {'medium'})}
    $updateCodex = {
        if ($codexEffort.SelectedItem) { $effortState.value=$codexEffort.SelectedItem.Tag }
        $codexCustom.Visibility = $(if ($codexModel.SelectedItem.Tag.id) {'Collapsed'} else {'Visible'})
        $codexEffort.Items.Clear()
        foreach ($level in $codexModel.SelectedItem.Tag.efforts) {
            $item = New-Object Windows.Controls.ComboBoxItem; $item.Content = $effortNames[$level] + ' · ' + $level; $item.Tag=$level
            [void]$codexEffort.Items.Add($item)
        }
        $codexEffort.SelectedIndex=0
        foreach ($item in $codexEffort.Items) { if ($item.Tag -eq 'medium') {$codexEffort.SelectedItem=$item} }
        foreach ($item in $codexEffort.Items) { if ($item.Tag -eq $effortState.value) {$codexEffort.SelectedItem=$item} }
    }.GetNewClosure()
    $codexModel.Add_SelectionChanged($updateCodex); & $updateCodex
    Label '列表优先使用本机 Codex 目录。模型权限由账号决定；推理越强，通常消耗越多额度。自定义型号请确认支持所选档位。'
    Label '使用本机已安装、已登录的 Codex。无需向本软件提供账号密码。'
    $claudePanel = New-Object Windows.Controls.StackPanel; $panel = $claudePanel
    Label 'Claude 模型'
    $claudeModel = ModelChoice @($subscriptionModels.claude) $script:Settings.claudeModel
    $claudeCustom = New-Object Windows.Controls.TextBox; $claudeCustom.Text = [string]$script:Settings.claudeModel; $claudeCustom.ToolTip = '自定义 Claude 模型 ID'; [void]$panel.Children.Add($claudeCustom)
    $updateClaude = { $claudeCustom.Visibility = $(if ($claudeModel.SelectedItem.Tag.id) {'Collapsed'} else {'Visible'}) }.GetNewClosure()
    $claudeModel.Add_SelectionChanged($updateClaude); & $updateClaude
    Label 'Haiku、Sonnet、Opus 使用官方最新版本别名；具体版本也可直接选择。可用性取决于订阅、组织权限及 Claude Code 版本。Fable 可能使用额外付费额度。'
    $claudeAdvanced = New-Object Windows.Controls.Expander; $claudeAdvanced.Header = '高级设置'
    $claudeFields = New-Object Windows.Controls.StackPanel; $panel = $claudeFields
    $claudePath = Field 'Claude Code 安装路径（留空自动查找）' $script:Settings.claudePath
    $claudeAdvanced.Content = $claudeFields; $panel = $claudePanel; [void]$panel.Children.Add($claudeAdvanced)
    Label '请先通过官方 Claude Code 登录；本软件不收集账号密码。'
    $hostedPanel = New-Object Windows.Controls.StackPanel; $panel = $hostedPanel
    Label '选择模型'
    Label '内置服务固定使用 DeepSeek V4 Flash 0731，避免切换到高价模型。'
    $family = New-Object Windows.Controls.ComboBox
    $families = @('deepseek'); $familyLabels = @('DeepSeek')
    if ($script:Edition -eq 'overseas') { $families += @('openai','anthropic'); $familyLabels += @('OpenAI','Claude') }
    foreach ($name in $familyLabels) { [void]$family.Items.Add($name) }
    $family.SelectedIndex = 0; [void]$panel.Children.Add($family)
    if ($script:Edition -eq 'mainland') { $family.Visibility = 'Collapsed' }
    $model = New-Object Windows.Controls.ComboBox; $model.MaxDropDownHeight = 320
    [void]$panel.Children.Add($model)
    $price = New-Object Windows.Controls.TextBlock; $price.TextWrapping = 'Wrap'; $price.Margin = '0,6,0,8'
    $modelDetails = New-Object Windows.Controls.Expander; $modelDetails.Header = '模型详情'; $modelDetails.Content = $price
    [void]$panel.Children.Add($modelDetails)
    $catalogFile = Join-Path $DataDir 'models.json'
    if (-not (Test-Path -LiteralPath $catalogFile)) { $catalogFile = Join-Path $PSScriptRoot 'models.json' }
    $catalogState = @{value=(Read-Json $catalogFile)}
    $settingsEdition = $script:Edition
    $hostedPolicy = Read-Json (Join-Path $PSScriptRoot 'hosted-policy.json')
    $defaultHostedModel = $script:Settings.hostedModel
    if ($script:Edition -eq 'mainland') { $defaultHostedModel = $hostedPolicy.mainlandModel }
    $fillModels = {
        $wanted = $(if ($defaultHostedModel) {$defaultHostedModel} else {'deepseek/deepseek-v4-flash'})
        if ($model.SelectedItem) { $wanted = $model.SelectedItem.Tag.id }
        $model.Items.Clear(); $selectedIndex = -1; $firstUsable = -1
        foreach ($m in @($catalogState.value.models | Where-Object { $_.family -eq $families[$family.SelectedIndex] -and ($settingsEdition -ne 'mainland' -or $_.id -eq $hostedPolicy.mainlandModel) })) {
            $item = New-Object Windows.Controls.ComboBoxItem
            $item.Content = $m.name; $item.ToolTip = $m.id; $item.Tag = $m; $item.IsEnabled = [bool]$m.supported
            if (-not $m.supported) { $item.Content += '（不支持文本待办）' }
            $i = $model.Items.Add($item)
            if ($m.supported -and $firstUsable -lt 0) { $firstUsable = $i }
            if ($m.id -eq $wanted -and $m.supported) { $selectedIndex = $i }
        }
        $model.SelectedIndex = $(if ($selectedIndex -ge 0) {$selectedIndex} else {$firstUsable})
    }.GetNewClosure()
    $model.Add_SelectionChanged({
        if ($model.SelectedItem) { $m = $model.SelectedItem.Tag; if ($settingsEdition -eq 'mainland') { $m.inputPrice = $hostedPolicy.maxPrice.prompt; $m.outputPrice = $hostedPolicy.maxPrice.completion }; $price.Text = '模型 ID：' + $m.id + "`n内置服务单价上限：每百万输入 token $" + $m.inputPrice + '；输出 $' + $m.outputPrice + '。实际可用性以账户和调用结果为准。' }
        else { $price.Text = '当前没有可选模型，请刷新目录。' }
    }.GetNewClosure())
    $family.Add_SelectionChanged({ & $fillModels }.GetNewClosure())
    if ($script:Settings.hostedModel) { $family.SelectedIndex = [Math]::Max(0,[Array]::IndexOf($families,($script:Settings.hostedModel -split '/')[0])) }
    & $fillModels
    $refreshModels = New-Object Windows.Controls.Button; $refreshModels.Content = '更新模型列表'; $refreshModels.Margin = '0,12,0,0'
    $catalogNode = $script:Node; $catalogScript = Join-Path $PSScriptRoot 'catalog.js'
    $catalogDestination = Join-Path $DataDir 'models.json'
    $refreshModels.Add_Click({
        try {
            $refreshModels.IsEnabled = $false
            $destination = $catalogDestination
            $info = New-Object Diagnostics.ProcessStartInfo
            $info.FileName = $catalogNode; $info.Arguments = '"' + $catalogScript + '" "' + $destination + '"'
            $info.UseShellExecute = $false; $info.CreateNoWindow = $true
            $process = [Diagnostics.Process]::Start($info)
            $poll = New-Object Windows.Threading.DispatcherTimer; $poll.Interval = [timespan]::FromMilliseconds(300)
            $currentRefresh = @{process=$process;timer=$poll;button=$refreshModels;catalog=$catalogState;destination=$destination;fill=$fillModels;price=$price}
            $poll.Add_Tick({
                if ($currentRefresh.process.HasExited) {
                    $currentRefresh.timer.Stop(); $currentRefresh.button.IsEnabled = $true
                    if ($currentRefresh.process.ExitCode -eq 0) { $currentRefresh.catalog.value = Get-Content -LiteralPath $currentRefresh.destination -Raw -Encoding UTF8 | ConvertFrom-Json; & $currentRefresh.fill }
                    else { $currentRefresh.price.Text = '目录刷新失败，保留现有列表。' }
                }
            }.GetNewClosure())
            $poll.Start()
        } catch { $refreshModels.IsEnabled = $true; $price.Text = '无法刷新模型目录。' }
    }.GetNewClosure())
    [void]$panel.Children.Add($refreshModels)
    # Connection details belong to deployment, not the user's settings form.
    $serviceUrl = New-Object Windows.Controls.TextBox; $serviceUrl.Text = [string]$script:Settings.serviceUrl
    $hostedKey = New-Object Windows.Controls.PasswordBox
    $serviceConfig = Join-Path $PSScriptRoot 'service.json'
    if (Test-Path -LiteralPath $serviceConfig) {
        $preset = Read-Json $serviceConfig
        if ($preset.analyzeUrl) { $serviceUrl.Text = [string]$preset.analyzeUrl }
    }
    Label $(if ($serviceUrl.Text) {'服务已配置，无需填写地址。'} else {'内置服务暂未开放。你仍可使用自己的订阅或 API Key。'})
    $apiPanel = New-Object Windows.Controls.StackPanel; $panel = $apiPanel
    Label 'API 供应商'
    $apiSuppliers = @(
        @{id='deepseek';name='DeepSeek';url='https://api.deepseek.com';protocol='openai'},
        @{id='doubao';name='豆包';url='https://ark.cn-beijing.volces.com/api/v3';protocol='openai'},
        @{id='openai';name='OpenAI';url='https://api.openai.com/v1';protocol='openai'},
        @{id='claude';name='Claude';url='https://api.anthropic.com/v1';protocol='anthropic'},
        @{id='other';name='其他供应商';url='';protocol='openai'}
    )
    $apiSupplier = New-Object Windows.Controls.ComboBox
    foreach ($supplier in $apiSuppliers) { $item=New-Object Windows.Controls.ComboBoxItem; $item.Content=$supplier.name; $item.Tag=$supplier; [void]$apiSupplier.Items.Add($item) }
    $apiSupplier.SelectedIndex=4
    for ($i=0;$i -lt 4;$i++) { if ($script:Settings.apiBase.TrimEnd('/') -eq $apiSuppliers[$i].url -or ($i -eq 0 -and $script:Settings.apiBase.TrimEnd('/') -eq 'https://api.deepseek.com/v1')) {$apiSupplier.SelectedIndex=$i;break} }
    [void]$panel.Children.Add($apiSupplier)
    Label '直接连接所选供应商，使用你自己的 Key，费用由该供应商收取。'
    $apiAdvanced=New-Object Windows.Controls.Expander; $apiAdvanced.Header='连接设置'
    $apiConnection=New-Object Windows.Controls.StackPanel; $panel=$apiConnection
    Label '接口格式（其他供应商请按其文档选择）'
    $protocol = New-Object Windows.Controls.ComboBox
    [void]$protocol.Items.Add('OpenAI 兼容（OpenAI、DeepSeek、豆包等）'); [void]$protocol.Items.Add('Anthropic 原生（Claude）')
    $protocol.SelectedIndex = $(if ($script:Settings.apiProtocol -eq 'anthropic') {1} else {0})
    [void]$panel.Children.Add($protocol)
    $apiBase = Field 'API 地址（Base URL）' $script:Settings.apiBase
    $apiAdvanced.Content=$apiConnection; $panel=$apiPanel; [void]$panel.Children.Add($apiAdvanced)
    $apiModel = Field '模型 ID（豆包可填写已开通的模型或推理接入点 ID）' $script:Settings.apiModel
    Label 'API Key（当前 Windows 用户加密保存）；留空保留已有密钥'
    $apiKey = New-Object Windows.Controls.PasswordBox; [void]$panel.Children.Add($apiKey)
    $updateApiSupplier = {
        $supplier=$apiSupplier.SelectedItem.Tag
        $custom=$supplier.id -eq 'other'
        $apiAdvanced.IsExpanded=$custom; $apiBase.IsReadOnly=-not $custom; $protocol.IsEnabled=$custom
        if (-not $custom) { $protocol.SelectedIndex=$(if($supplier.protocol -eq 'anthropic'){1}else{0}) }
    }.GetNewClosure()
    & $updateApiSupplier
    $apiSupplier.Add_SelectionChanged({
        $supplier=$apiSupplier.SelectedItem.Tag
        if ($supplier.url) { $apiBase.Text=$supplier.url } else { $apiBase.Text='' }
        $apiModel.Text=''; $apiKey.Password=''
        & $updateApiSupplier
    }.GetNewClosure())
    $panel = $outer
    foreach ($p in @($codexPanel,$claudePanel,$hostedPanel,$apiPanel)) { [void]$panel.Children.Add($p) }
    $update = {
        $i=0; foreach ($p in @($codexPanel,$claudePanel,$hostedPanel,$apiPanel)) {
            $p.Visibility = $(if ($i -eq $provider.SelectedIndex) {'Visible'} else {'Collapsed'}); $i++
        }
    }
    $provider.Add_SelectionChanged($update); & $update
    $browserGuide = New-Object Windows.Controls.Expander; $browserGuide.Header = '开启 Chrome 网页采集（可选）'
    $guidePanel = New-Object Windows.Controls.StackPanel
    $guideText = New-Object Windows.Controls.TextBlock; $guideText.TextWrapping = 'Wrap'; $guideText.Margin = '0,4,0,12'
    $guideText.Text = "本机 Codex / Claude Code 对话无需扩展。采集网页聊天时，只需设置一次：打开 Chrome 扩展管理 → 开启开发者模式 → 加载已解压的扩展程序，选择下方提供的文件夹。"
    [void]$guidePanel.Children.Add($guideText)
    $openExtensions = New-Object Windows.Controls.Button; $openExtensions.Content = '打开 Chrome 并复制扩展路径'
    $extensionFolder = Join-Path $PSScriptRoot 'ChromeExtension'
    $openExtensions.Add_Click({
        try {
            [Windows.Clipboard]::SetText($extensionFolder)
            $chrome = @((Join-Path $env:ProgramFiles 'Google/Chrome/Application/chrome.exe'),(Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Google/Chrome/Application/chrome.exe'),(Join-Path $env:LOCALAPPDATA 'Google/Chrome/Application/chrome.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $chrome) { throw '未找到 Chrome。请在 Chrome 打开 chrome://extensions；扩展路径已复制。' }
            Start-Process -FilePath $chrome -ArgumentList 'chrome://extensions/'
            $openExtensions.Content = '路径已复制 · 加载时粘贴即可'
        } catch { [void][Windows.MessageBox]::Show($_.Exception.Message,'Chrome 网页采集') }
    }.GetNewClosure())
    [void]$guidePanel.Children.Add($openExtensions); $browserGuide.Content = $guidePanel; [void]$panel.Children.Add($browserGuide)
    $voiceOptions=New-Object Windows.Controls.Button; $voiceOptions.Content='语音记录 · 快捷键与语言'; $voiceOptions.Margin='0,14,0,0'
    $voiceOptions.Add_Click({ Show-VoiceSettings })
    $voiceSection=New-Object Windows.Controls.Expander; $voiceSection.Header='语音记录'; $voiceSection.Content=$voiceOptions; [void]$panel.Children.Add($voiceSection)
    Label '必要对话文字会发送至所选服务，并消耗相应订阅额度或 API 费用。网页只采集已打开、已加载的消息。'
    $consent = New-Object Windows.Controls.CheckBox; $consentText = New-Object Windows.Controls.TextBlock; $consentText.Text = '同意发送必要对话文字，并开启后台分析'; $consentText.TextWrapping = 'Wrap'
    $consent.Content = $consentText
    $consent.IsChecked = $false; [void]$panel.Children.Add($consent)
    $save = New-Object Windows.Controls.Button; $save.Content = '保存并启用'; $save.Padding = '14,12'; $save.Margin = '0,22,0,0'; $save.Background = '#284E49'; $save.Foreground = '#BCEFE4'
    $save.Add_Click({
        try {
            if (-not $consent.IsChecked) { throw '请先确认后台分析授权。' }
            $selected = $ids[$provider.SelectedIndex]
            if ($selected -eq 'byok' -or $selected -eq 'hosted') {
                if ($selected -eq 'hosted' -and -not $serviceUrl.Text) { throw '内置服务暂未开放，请选择自己的订阅或 API Key。' }
                $address = $(if ($selected -eq 'byok') {$apiBase.Text} else {$serviceUrl.Text})
                $uri = [uri]$address
                if (-not $uri.IsAbsoluteUri -or $uri.UserInfo -or ($uri.Scheme -ne 'https' -and -not ($uri.Scheme -eq 'http' -and $uri.IsLoopback))) { throw '请填写 HTTPS 接口地址；本机测试可用 HTTP。' }
                $keyBox = $(if ($selected -eq 'byok') {$apiKey} else {$hostedKey})
                if ($selected -eq 'byok' -and -not $keyBox.Password -and $apiBase.Text.TrimEnd('/') -ne ([string]$script:Settings.apiBase).TrimEnd('/')) { throw '更换供应商或接口地址后，请填写对应的 API Key。' }
                $secretName = $(if ($selected -eq 'hosted') {'hosted-' + $script:Edition} else {'byok'})
                $keyFile = Join-Path $DataDir ($secretName + '.secret')
                if ($selected -eq 'hosted' -and -not $keyBox.Password -and -not (Test-Path -LiteralPath $keyFile) -and (Test-Path -LiteralPath (Join-Path $DataDir 'hosted.secret'))) { $keyFile = Join-Path $DataDir 'hosted.secret' }
                if (-not $keyBox.Password -and -not (Test-Path -LiteralPath $keyFile)) { if ($selected -eq 'hosted') { throw '此设备的内置服务尚未开通。请先使用自己的订阅或 API Key。' } else { throw '请填写你的 API Key。' } }
                if ($selected -eq 'byok' -and -not $apiModel.Text.Trim()) { throw '请填写模型 ID。' }
                if ($selected -eq 'hosted' -and (-not $model.SelectedItem -or -not $model.SelectedItem.Tag.supported)) { throw '请选择支持文本待办的具体模型。' }
                if ($keyBox.Password) { [IO.File]::WriteAllText($keyFile,($keyBox.SecurePassword | ConvertFrom-SecureString)) }
            }
            $script:Settings.provider = $selected; $script:Settings.intervalMinutes = $minutes[$interval.SelectedIndex]
            if ($model.SelectedItem) { $script:Settings.hostedModel = $model.SelectedItem.Tag.id }
            $chosenCodex = $(if ($codexModel.SelectedItem.Tag.id) {$codexModel.SelectedItem.Tag.id} else {$codexCustom.Text.Trim()})
            $chosenClaude = $(if ($claudeModel.SelectedItem.Tag.id) {$claudeModel.SelectedItem.Tag.id} else {$claudeCustom.Text.Trim()})
            if (($selected -eq 'codex' -and -not $chosenCodex) -or ($selected -eq 'claude' -and -not $chosenClaude)) { throw '请选择模型或填写自定义模型 ID。' }
            $script:Settings.codexModel = $chosenCodex; $script:Settings.claudeModel = $chosenClaude
            $script:Settings.codexEffort = $codexEffort.SelectedItem.Tag
            $script:Settings.claudePath = $claudePath.Text.Trim(); $script:Settings.serviceUrl = $serviceUrl.Text.Trim()
            if ($selected -eq 'byok') {
                $script:Settings.apiBase = $apiBase.Text.Trim(); $script:Settings.apiModel = $apiModel.Text.Trim()
                $script:Settings.apiProtocol = $(if ($protocol.SelectedIndex -eq 1) {'anthropic'} else {'openai'})
            }
            $script:Settings.setupComplete = $true; Save-Settings
            if ($script:ModelLabel) { Update-AnalysisCaption }
            $script:IntervalLabel.Text = '每 ' + $script:Settings.intervalMinutes + ' 分钟 · 仅变化时分析'
            $dialog.DialogResult = $true
        } catch { [void][Windows.MessageBox]::Show($_.Exception.Message,'设置未保存') }
    })
    [void]$panel.Children.Add($save); $scroll.VerticalScrollBarVisibility = 'Auto'; $scroll.HorizontalScrollBarVisibility = 'Disabled'; $scroll.Content = $panel; $dialog.Content = $scroll
    [void]$dialog.ShowDialog()
}
