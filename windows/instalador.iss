; Instalador do AVA Sync para Windows (Inno Setup 6).
; Gerado pelo GitHub Actions; veja .github/workflows/desktop.yml.
; Instala só para a pessoa (sem pedir administrador) em %LOCALAPPDATA%\Programs,
; e atualiza por cima: o app baixa este mesmo instalador e roda em modo silencioso.
;
; Variáveis (passadas com /D na linha de comando):
;   Nome    "AVA Sync" ou "AVA Sync Teste"
;   AppId   identificador fixo do canal (NUNCA mude: é o que permite atualizar por cima)
;   Versao  versão do pubspec.yaml

#ifndef Nome
  #define Nome "AVA Sync"
#endif
#ifndef AppId
  #define AppId "{{8B0F5E36-2C4D-4C1B-9A7E-5D2F1A6C3B90}"
#endif
#ifndef Versao
  #define Versao "0.0.0"
#endif
#define Exe "ava_sync_mobile.exe"

[Setup]
AppId={#AppId}
AppName={#Nome}
AppVersion={#Versao}
AppPublisher=AVA Sync
DefaultDirName={localappdata}\Programs\{#Nome}
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
PrivilegesRequired=lowest
OutputDir=..\build\instalador
OutputBaseFilename=setup
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#Exe}
UninstallDisplayName={#Nome}
CloseApplications=force
RestartApplications=no
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "pt"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Tasks]
Name: "atalho"; Description: "Criar atalho na área de trabalho"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{userprograms}\{#Nome}"; Filename: "{app}\{#Exe}"
Name: "{userdesktop}\{#Nome}"; Filename: "{app}\{#Exe}"; Tasks: atalho

[Run]
; também roda na atualização silenciosa: o app fecha para atualizar e volta sozinho
Filename: "{app}\{#Exe}"; Description: "Abrir {#Nome}"; Flags: nowait postinstall

[UninstallRun]
; tira o "abrir com o sistema" ao desinstalar
Filename: "reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v ""{#StringChange(Nome, " ", "")}"" /f"; Flags: runhidden; RunOnceId: "TirarInicio"
