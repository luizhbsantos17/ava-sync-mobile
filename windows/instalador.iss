; Instalador do AVA Sync para Windows (Inno Setup 6).
; Gerado pelo GitHub Actions; veja .github/workflows/desktop.yml.
; Por padrão instala só para a pessoa (sem pedir administrador) em %LOCALAPPDATA%\Programs;
; na primeira instalação dá para escolher a pasta e instalar para todos (pede administrador).
; Atualiza por cima: o app baixa este mesmo instalador e roda em modo silencioso, que
; reaproveita a pasta e as escolhas da instalação anterior.
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
; {autopf}: %LOCALAPPDATA%\Programs só para mim; Arquivos de Programas para todos
DefaultDirName={autopf}\{#Nome}
; pasta: pergunta na primeira instalação; nas atualizações usa a mesma
DisableDirPage=auto
UsePreviousAppDir=yes
DisableProgramGroupPage=yes
DisableReadyPage=no
PrivilegesRequired=lowest
; "Instalar só para mim" ou "para todos os usuários" (este pede administrador)
PrivilegesRequiredOverridesAllowed=dialog commandline
UsePreviousPrivileges=yes
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
Name: "menu"; Description: "Criar atalho no Menu Iniciar"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#Nome}"; Filename: "{app}\{#Exe}"; Tasks: menu
Name: "{autodesktop}\{#Nome}"; Filename: "{app}\{#Exe}"; Tasks: atalho

[Run]
; também roda na atualização silenciosa: o app fecha para atualizar e volta sozinho
Filename: "{app}\{#Exe}"; Description: "Abrir {#Nome}"; Flags: nowait postinstall

[UninstallRun]
; tira o "abrir com o sistema" ao desinstalar
Filename: "reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v ""{#StringChange(Nome, " ", "")}"" /f"; Flags: runhidden; RunOnceId: "TirarInicio"
