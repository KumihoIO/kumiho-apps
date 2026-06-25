#define MyAppVersion GetEnv("APP_VERSION")
#if MyAppVersion == ""
  #define MyAppVersion "0.0.0.0"
#endif

[Setup]
AppId={{A3BEEA32-9AD8-4AA6-8B3D-5A44A0E7D733}
AppName=Kumiho Browser
AppVersion={#MyAppVersion}
AppPublisher=Kumiho
AppPublisherURL=https://kumiho.io
AppSupportURL=https://kumiho.io
AppUpdatesURL=https://kumiho.io
DefaultDirName={localappdata}\Programs\Kumiho Browser
DefaultGroupName=Kumiho Browser
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\kumiho_asset_browser.exe
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
WizardStyle=modern
OutputDir=..\..\dist\windows
OutputBaseFilename=KumihoBrowserSetup-{#MyAppVersion}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Kumiho Browser"; Filename: "{app}\kumiho_asset_browser.exe"; WorkingDir: "{app}"
Name: "{commondesktop}\Kumiho Browser"; Filename: "{app}\kumiho_asset_browser.exe"; Tasks: desktopicon; WorkingDir: "{app}"

[Run]
Filename: "{app}\kumiho_asset_browser.exe"; Description: "Launch Kumiho Browser"; Flags: nowait postinstall skipifsilent
