; 카카오 발송기 설치 프로그램
;
; 이 프로그램은 설정과 실행 기록을 자기 폴더 안에 만듭니다.
; 그래서 Program Files 에 넣으면 권한 때문에 쓰지 못합니다.
; 사용자 폴더(localappdata)에 넣고, 관리자 권한도 요구하지 않습니다.

#define AppName "카카오 발송기"
#define AppExe "카카오 발송기.exe"
#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId={{8F2C1A64-5D3E-4B7A-9C21-7E4D2B905A13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} v{#AppVersion}
AppPublisher=upmate0703-hue
DefaultDirName={localappdata}\KakaoSender
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
AllowNoIcons=yes
PrivilegesRequired=lowest
OutputBaseFilename=KakaoSender-Setup
SetupIconFile=app.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 아이콘 만들기"; GroupDescription: "추가 작업:"

[Files]
Source: "카카오 발송기.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "README.md"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "사용설명서.html"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "app.ico"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; 스크립트 판도 함께 넣습니다. 예전 방식으로 쓰시던 분을 위해서입니다.
Source: "KakaoRoomScheduler.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
; 필수 요소를 확인하고 없으면 설치해 주는 도구입니다.
Source: "prereq.ps1"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "*.cmd"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{group}\사용설명서"; Filename: "{app}\사용설명서.html"; Flags: createonlyiffileexists
Name: "{group}\필수 요소 확인"; Filename: "{app}\필수요소 확인.cmd"; WorkingDir: "{app}"; Flags: createonlyiffileexists
Name: "{group}\{#AppName} 제거"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; 설치 뒤에 필요한 것이 다 있는지 한 번 확인해 봅니다.
Filename: "{app}\필수요소 확인.cmd"; Description: "필수 요소 확인하기 (한국어 문자 인식 등)"; WorkingDir: "{app}"; Flags: postinstall skipifsilent unchecked
Filename: "{app}\{#AppExe}"; Description: "지금 실행하기"; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 지울 때 설정과 기록도 함께 지웁니다. 남겨 두면 다음 설치에 그대로 딸려옵니다.
Type: filesandordirs; Name: "{app}\logs"
Type: filesandordirs; Name: "{app}\backup"
Type: files; Name: "{app}\config.json"
Type: dirifempty; Name: "{app}"
