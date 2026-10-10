#define ProductVersion "0.7.1"
[Setup]
AppId={{8FA8CB17-8D26-495F-9D5B-11801305BF6E}
AppName=对话待办
AppVersion={#ProductVersion}
AppPublisher=Conversation Todo
DefaultDirName={localappdata}\Programs\ConversationTodo
DefaultGroupName=对话待办
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
WizardStyle=modern
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
OutputDir=..\dist
#ifndef InstallerTest
OutputBaseFilename=ConversationTodo-Mainland-Setup-0.7.1
#endif
Compression=lzma2
SolidCompression=yes
UninstallDisplayIcon={app}\CodexTodo.exe
CloseApplications=yes
RestartApplications=no
SetupMutex=ConversationTodoSetup
#ifdef InstallerTest
CreateUninstallRegKey=no
OutputBaseFilename=ConversationTodo-InstallerTest
#endif

[Messages]
SetupWindowTitle=安装对话待办
WizardInstalling=正在安装
InstallingLabel=正在安装对话待办及内置运行环境，请稍候。
WizardFinished=安装完成
FinishedHeadingLabel=对话待办已安装
FinishedLabel=程序已准备好使用。首次打开请选择你的分析方式。%n%n本机对话采集无需额外设置；Chrome 网页采集可在设置中按引导开启。%n%n软件提供的 AI 暂未对朋友开放，可先使用自己的订阅或 API Key。
ButtonNext=下一步(&N) >
ButtonBack=< 上一步(&B)
ButtonInstall=安装(&I)
ButtonFinish=完成(&F)
ButtonCancel=取消
ConfirmUninstall=确认卸载对话待办吗？个人待办、设置和加密密钥会保留。
UninstalledAll=对话待办已卸载。个人数据已保留。

[Tasks]
Name: autorun; Description: 登录 Windows 时自动启动; Flags: checkedonce
Name: desktop; Description: 创建桌面快捷方式; Flags: checkedonce

[Files]
Source: "..\.build\payload\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\对话待办\对话待办"; Filename: "{app}\CodexTodo.exe"; Check: AllowIntegration
Name: "{userprograms}\对话待办\卸载对话待办"; Filename: "{uninstallexe}"; Check: AllowIntegration
Name: "{userdesktop}\对话待办"; Filename: "{app}\CodexTodo.exe"; Tasks: desktop; Check: AllowIntegration
Name: "{userstartup}\对话待办"; Filename: "{app}\CodexTodo.exe"; Tasks: autorun; Check: AllowIntegration

[Registry]
Root: HKCU; Subkey: "Software\Google\Chrome\NativeMessagingHosts\com.codextodo.capture"; ValueType: string; ValueName: ""; ValueData: "{app}\native-host.json"; Check: AllowIntegration

[Run]
Filename: "{app}\CodexTodo.exe"; Description: "打开对话待办"; Flags: nowait postinstall skipifsilent; Check: AllowIntegration

[UninstallDelete]
Type: files; Name: "{app}\node-path.txt"
Type: files; Name: "{app}\native-host.json"

[Code]
function AllowIntegration(): Boolean;
begin
#ifdef InstallerTest
  Result := False;
#else
  Result := True;
#endif
end;

function JsonPath(Value: String): String;
begin
  StringChangeEx(Value, '\', '\\', True);
  StringChangeEx(Value, '"', '\"', True);
  Result := Value;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Manifest: String;
begin
  if CurStep = ssPostInstall then
  begin
    if not SaveStringToFile(ExpandConstant('{app}\node-path.txt'), UTF8Encode(ExpandConstant('{app}\runtime\node.exe')), False) then
      RaiseException('无法配置内置运行环境。');
    Manifest := '{"name":"com.codextodo.capture","description":"Conversation Todo capture","path":"' + JsonPath(ExpandConstant('{app}\NativeHost.exe')) + '","type":"stdio","allowed_origins":["chrome-extension://njjaofmlponefknmpnicfaojimflanea/"]}';
    if not SaveStringToFile(ExpandConstant('{app}\native-host.json'), UTF8Encode(Manifest), False) then
      RaiseException('无法配置 Chrome 本机连接。');
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var CurrentHost: String;
begin
  if (CurUninstallStep = usPostUninstall) and AllowIntegration() then
    if RegQueryStringValue(HKCU, 'Software\Google\Chrome\NativeMessagingHosts\com.codextodo.capture', '', CurrentHost) then
      if CompareText(CurrentHost, ExpandConstant('{app}\native-host.json')) = 0 then
        RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Google\Chrome\NativeMessagingHosts\com.codextodo.capture');
end;
