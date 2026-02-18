; QA3D Inno Setup Installer Script
; Build: iscc build\installer.iss  (from project root)
; Requires: Inno Setup 6+ (https://jrsoftware.org/isinfo.php)
;
; Input:  dist\QA3D-compiled\  (PackageCompiler create_app output + runtime assets)
; Output: dist\QA3D-v0.1.0-windows-setup.exe

#define MyAppName "QA3D"
#define MyAppVersion "0.1.0"
#define MyAppPublisher "Defense POW/MIA Accounting Agency"
#define MyAppURL "https://github.com/dpaa-gov/QA3D"
#define MyAppExeName "qa3d.exe"

[Setup]
AppId={{A3D7B2E1-9C4F-4E8A-B5D6-1F2A3C4D5E6F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\dist
OutputBaseFilename=QA3D-v{#MyAppVersion}-windows-setup
SetupIconFile=qa3d.ico
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; Bundle the entire compiled app directory
Source: "..\dist\QA3D-compiled\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Runtime assets
Source: "..\public\*"; DestDir: "{app}\public"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\views\*"; DestDir: "{app}\views"; Flags: ignoreversion recursesubdirs createallsubdirs

; Manifest.toml for Genie package resolution
Source: "..\Manifest.toml"; DestDir: "{app}\share\julia"; Flags: ignoreversion

; VBS launcher (no console window) and icon
Source: "QA3D.vbs"; DestDir: "{app}"; Flags: ignoreversion
Source: "qa3d.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu — VBS launcher with icon (no console)
Name: "{group}\{#MyAppName}"; Filename: "{app}\QA3D.vbs"; IconFilename: "{app}\qa3d.ico"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; Desktop — VBS launcher with icon (no console)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\QA3D.vbs"; IconFilename: "{app}\qa3d.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\QA3D.vbs"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent shellexec
