#Requires -Version 5.1
<#
  카카오 발송기가 돌아가는 데 필요한 것들을 확인하고, 없으면 설치합니다.

  확인하는 것
    1. 윈도우 판  (윈도우 10 이상)
    2. .NET Framework 4.7.2 이상   — 프로그램이 이것으로 돌아갑니다
    3. 한국어 문자 인식(OCR)        — 채팅방 이름을 읽는 데 씁니다. 이게 없으면 목록을 못 읽습니다
    4. PC 카카오톡                  — 이건 저희가 설치해 드릴 수 없어 안내만 합니다

  한국어 문자 인식을 설치하려면 관리자 권한이 필요합니다.
  필요할 때만 물어보고 올립니다.
#>
param([switch]$Elevated)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Say([string]$Text) { Write-Host $Text }
function Ok([string]$Text)  { Write-Host "  [정상] $Text" -ForegroundColor Green }
function Bad([string]$Text) { Write-Host "  [필요] $Text" -ForegroundColor Yellow }

Say ''
Say '=========================================='
Say '  카카오 발송기 — 필수 요소 확인'
Say '=========================================='
Say ''

$missing = New-Object System.Collections.Generic.List[string]

# --- 1. 윈도우 판 ---------------------------------------------------------
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $build = [int]$os.BuildNumber
    if ($build -ge 10240) { Ok "윈도우: $($os.Caption) (빌드 $build)" }
    else {
        Bad "윈도우 10 이상이 필요합니다. 지금: $($os.Caption)"
        $missing.Add('윈도우 판')
    }
} catch { Bad "윈도우 판을 확인하지 못했습니다: $($_.Exception.Message)" }

# --- 2. .NET Framework ----------------------------------------------------
# 프로그램(.exe)이 .NET Framework 로 돌아갑니다.
# 윈도우 10 이상에는 대개 들어 있지만 확인해 둡니다.
$dotnetOk = $false
try {
    $key = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full'
    if (Test-Path $key) {
        $release = (Get-ItemProperty -Path $key -Name Release -ErrorAction Stop).Release
        if ([int]$release -ge 461808) { Ok ".NET Framework 4.7.2 이상 (Release $release)"; $dotnetOk = $true }
        else { Bad ".NET Framework 이 낮습니다 (Release $release). 4.7.2 이상이 필요합니다." }
    } else { Bad '.NET Framework 4 가 보이지 않습니다.' }
} catch { Bad ".NET Framework 를 확인하지 못했습니다: $($_.Exception.Message)" }
if (-not $dotnetOk) { $missing.Add('.NET Framework 4.7.2') }

# --- 3. 한국어 문자 인식 (OCR) --------------------------------------------
# 채팅방 목록은 카카오톡이 직접 그려서 글자를 내놓지 않습니다.
# 그래서 화면을 떠서 글자로 읽습니다. 이 기능이 없으면 목록을 한 개도 못 읽습니다.
$ocrName = 'Language.OCR~~~ko-KR~0.0.1.0'
$ocrOk = $false
# Get-WindowsCapability 는 확인만 해도 관리자 권한을 요구합니다.
# 그래서 프로그램이 쓰는 것과 같은 방법으로 확인합니다.
# 한국어 인식기를 실제로 만들어 보는 것이라 권한이 필요 없고 결과도 정확합니다.
try {
    [void][Windows.Globalization.Language, Windows.Foundation, ContentType = WindowsRuntime]
    [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType = WindowsRuntime]
    $lang = New-Object Windows.Globalization.Language 'ko-KR'
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($lang)
    if ($null -ne $engine) { Ok '한국어 문자 인식 (채팅방 이름 읽기)'; $ocrOk = $true }
    else { Bad '한국어 문자 인식이 없습니다.' }
} catch {
    Bad "한국어 문자 인식을 확인하지 못했습니다: $($_.Exception.Message)"
}
if (-not $ocrOk) { $missing.Add('한국어 문자 인식') }

# --- 4. PC 카카오톡 -------------------------------------------------------
$kakaoOk = $false
try {
    if (Get-Process -Name KakaoTalk -ErrorAction SilentlyContinue) { Ok 'PC 카카오톡 (지금 켜져 있습니다)'; $kakaoOk = $true }
    else {
        $paths = @(
            "${env:ProgramFiles(x86)}\Kakao\KakaoTalk\KakaoTalk.exe",
            "$env:ProgramFiles\Kakao\KakaoTalk\KakaoTalk.exe"
        )
        foreach ($path in $paths) { if (Test-Path -LiteralPath $path) { Ok 'PC 카카오톡 (설치되어 있습니다)'; $kakaoOk = $true; break } }
        if (-not $kakaoOk) { Bad 'PC 카카오톡이 보이지 않습니다.' }
    }
} catch { }

Say ''
if ($missing.Count -eq 0 -and $kakaoOk) {
    Say '필요한 것이 모두 준비되어 있습니다. 그대로 쓰시면 됩니다.'
    Say ''
    if (-not $Elevated) { Read-Host '엔터를 누르면 닫힙니다' | Out-Null }
    exit 0
}

# --- 없는 것을 채웁니다 ---------------------------------------------------
if (-not $ocrOk) {
    Say '한국어 문자 인식을 설치하겠습니다.'
    Say '이것이 없으면 채팅방 목록을 한 개도 읽지 못합니다.'
    Say ''
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Say '설치에는 관리자 권한이 필요합니다. 권한을 올려 다시 실행합니다.'
        Say '(창이 하나 더 뜨면 [예] 를 눌러 주세요)'
        try {
            $self = $MyInvocation.MyCommand.Path
            if (-not $self) { $self = $PSCommandPath }
            Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
                '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$self`"", '-Elevated') -Wait
            Say ''
            Say '설치 창이 끝났습니다. 이 창을 닫고 프로그램을 다시 실행해 주세요.'
        } catch {
            Say "권한을 올리지 못했습니다: $($_.Exception.Message)"
            Say ''
            Say '직접 설치하시려면 이렇게 하시면 됩니다.'
            Say '  윈도우 설정 → 시간 및 언어 → 언어 및 지역'
            Say '  → 한국어 → 점 세 개 → 언어 옵션 → 광학 문자 인식 설치'
        }
    } else {
        try {
            Say '설치 중입니다. 몇 분 걸릴 수 있습니다...'
            Add-WindowsCapability -Online -Name $ocrName -ErrorAction Stop | Out-Null
            Say ''
            Say '한국어 문자 인식을 설치했습니다.'
        } catch {
            Say ''
            Say "설치하지 못했습니다: $($_.Exception.Message)"
            Say '윈도우 설정 → 시간 및 언어 → 언어 및 지역 → 한국어 → 언어 옵션 에서'
            Say '광학 문자 인식을 설치해 주세요.'
        }
    }
    Say ''
}

if (-not $dotnetOk) {
    Say '.NET Framework 4.7.2 이상이 필요합니다.'
    Say '아래 주소에서 받아 설치해 주세요. 설치 뒤에는 컴퓨터를 다시 시작해야 합니다.'
    Say '  https://dotnet.microsoft.com/download/dotnet-framework'
    Say ''
    if (-not $Elevated) {
        $answer = Read-Host '지금 받는 곳을 열까요? (예/아니오)'
        if ($answer -eq '예' -or $answer -match '^[yY]') {
            Start-Process 'https://dotnet.microsoft.com/download/dotnet-framework'
        }
    }
}

if (-not $kakaoOk) {
    Say 'PC 카카오톡이 필요합니다. 아래에서 받아 설치하고 로그인해 주세요.'
    Say '  https://www.kakaocorp.com/page/service/service/KakaoTalk'
    Say ''
    if (-not $Elevated) {
        $answer = Read-Host '지금 받는 곳을 열까요? (예/아니오)'
        if ($answer -eq '예' -or $answer -match '^[yY]') {
            Start-Process 'https://www.kakaocorp.com/page/service/service/KakaoTalk'
        }
    }
}

Say ''
if (-not $Elevated) { Read-Host '엔터를 누르면 닫힙니다' | Out-Null }
