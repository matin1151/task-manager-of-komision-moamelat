#define MyAppName "Dastyar Komision"
#define MyAppVersion "1.0.1"
#define MyAppPublisher "Dastyar Komision"

[Setup]
AppId={{B8AB4F0B-5E7E-4E18-9C3E-DASTYARKOMISION}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\DastyarKomision
DefaultGroupName={#MyAppName}
PrivilegesRequired=lowest
OutputDir=build
OutputBaseFilename=DastyarKomision-Setup-v{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
Uninstallable=yes
DisableProgramGroupPage=yes

[Files]
Source: "build\DastyarKomision-Windows\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autodesktop}\Dastyar Komision"; Filename: "{sys}\wscript.exe"; Parameters: "//B //Nologo \\"{app}\start-app.vbs\\""
Name: "{userstartup}\Dastyar Komision"; Filename: "{sys}\wscript.exe"; Parameters: "//B //Nologo \\"{app}\start-app.vbs\\" -NoBrowser"
Name: "{group}\Open Dastyar Komision"; Filename: "{sys}\wscript.exe"; Parameters: "//B //Nologo \\"{app}\start-app.vbs\\""

[Run]
Filename: "{sys}\wscript.exe"; Parameters: "//B //Nologo \\"{app}\start-app.vbs\\""; Flags: nowait postinstall skipifsilent
