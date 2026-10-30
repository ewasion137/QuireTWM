#define MyAppName "QuireTWM"
#define MyAppVersion "0.2.0"
#define MyAppPublisher "ewasion137"
#define MyAppURL "https://github.com/ewasion137/QuireTWM"
#define MyAppExeName "QuireTWM.exe"

[Setup]
AppId={{E8A39C21-4F29-4B52-8703-99933B0A5E12}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=LICENSE
OutputDir=build\Installer
OutputBaseFilename=QuireTWM-Setup-v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=logo\Quire.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"

[Tasks]
Name: "startup"; Description: "Run QuireTWM on Windows startup"; GroupDescription: "Additional options:"; Flags: unchecked
Name: "addtopath"; Description: "Add QuireTWM to system PATH (enables 'quirectl' in terminal)"; GroupDescription: "Additional options:"

[Files]
Source: "build\Release\QuireTWM.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "quirectl.ps1"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\Release\scripts\*"; DestDir: "{app}\scripts"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion
Source: "LICENSE"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{userstartup}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: startup

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
const EnvironmentKey = 'SYSTEM\CurrentControlSet\Control\Session Manager\Environment';

procedure AddToPath(PathToAdd: string);
var
    Paths: string;
begin
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths) then
        Paths := '';

    if Pos(';' + Uppercase(PathToAdd) + ';', ';' + Uppercase(Paths) + ';') = 0 then
    begin
        if (Paths <> '') and (Paths[Length(Paths)] <> ';') then
            Paths := Paths + ';';
        Paths := Paths + PathToAdd;
        RegWriteStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths);
    end;
end;

procedure RemoveFromPath(PathToRemove: string);
var
    Paths: string;
    P: Integer;
begin
    if not RegQueryStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths) then
        Exit;

    P := Pos(';' + Uppercase(PathToRemove) + ';', ';' + Uppercase(Paths) + ';');
    if P > 0 then
    begin
        Delete(Paths, P, Length(PathToRemove) + 1);
        RegWriteStringValue(HKEY_LOCAL_MACHINE, EnvironmentKey, 'Path', Paths);
    end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
    if (CurStep = ssPostInstall) and WizardIsTaskSelected('addtopath') then
    begin
        AddToPath(ExpandConstant('{app}'));
    end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
    if CurUninstallStep = usPostUninstall then
    begin
        RemoveFromPath(ExpandConstant('{app}'));
    end;
end;