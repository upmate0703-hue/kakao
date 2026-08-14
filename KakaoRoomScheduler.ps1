param(
    [switch]$SelfTest,
    [switch]$UiSmokeTest,
    [switch]$NoUpdateCheck,
    [switch]$ScanTest,
    [switch]$MaskNames,
    [string]$ScreenshotDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 배포 정보 (CI가 아래 AppVersion 줄을 그대로 치환합니다. 형식을 바꾸지 마세요.)
# ---------------------------------------------------------------------------
$script:AppVersion = '3.2.0'
$script:RepoOwner  = 'upmate0703-hue'
$script:RepoName   = 'kakao'
$script:RepoUrl    = "https://github.com/$($script:RepoOwner)/$($script:RepoName)"
$script:ApiLatest  = "https://api.github.com/repos/$($script:RepoOwner)/$($script:RepoName)/releases/latest"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName Microsoft.VisualBasic

if (-not ('NativeKakao' -as [type])) {
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class NativeKakao {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    public sealed class WindowInfo {
        public IntPtr Handle;
        public int ProcessId;
        public string Title;
        public string ClassName;
        public bool Visible;
        public RECT Rect;
        public int Width;
        public int Height;
    }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr extraData);
    [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr parent, EnumWindowsProc callback, IntPtr extraData);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint GetWindowThreadId(IntPtr hWnd, IntPtr zero);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    public static bool IsWindowMinimized(IntPtr hWnd) { return IsIconic(hWnd); }
    [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int command);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int virtualKey);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);

    static WindowInfo Describe(IntPtr hWnd, uint pid) {
        var title = new StringBuilder(512);
        var cls = new StringBuilder(256);
        RECT rect;
        GetWindowText(hWnd, title, title.Capacity);
        GetClassName(hWnd, cls, cls.Capacity);
        GetWindowRect(hWnd, out rect);
        return new WindowInfo {
            Handle = hWnd, ProcessId = (int)pid, Title = title.ToString(),
            ClassName = cls.ToString(), Visible = IsWindowVisible(hWnd), Rect = rect,
            Width = rect.Right - rect.Left, Height = rect.Bottom - rect.Top
        };
    }

    public static List<WindowInfo> GetWindows(int processId) {
        var result = new List<WindowInfo>();
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if (pid == processId) { result.Add(Describe(hWnd, pid)); }
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static WindowInfo GetWindow(IntPtr hWnd) {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return Describe(hWnd, pid);
    }

    public static List<WindowInfo> GetChildWindows(IntPtr parent) {
        var result = new List<WindowInfo>();
        EnumChildWindows(parent, delegate(IntPtr hWnd, IntPtr ignored) {
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            result.Add(Describe(hWnd, pid));
            return true;
        }, IntPtr.Zero);
        return result;
    }

    public static int GetProcessId(IntPtr hWnd) {
        uint pid;
        GetWindowThreadProcessId(hWnd, out pid);
        return (int)pid;
    }

    // 카카오톡은 단순 SetForegroundWindow 를 무시하는 경우가 있어 입력 스레드를 붙여 활성화합니다.
    public static bool ForceForeground(IntPtr hWnd) {
        if (IsIconic(hWnd)) { ShowWindow(hWnd, 9); }
        IntPtr fore = GetForegroundWindow();
        if (fore == hWnd) { return true; }
        uint foreThread = GetWindowThreadId(fore, IntPtr.Zero);
        uint thisThread = GetCurrentThreadId();
        bool attached = false;
        if (foreThread != 0 && foreThread != thisThread) {
            attached = AttachThreadInput(thisThread, foreThread, true);
        }
        ShowWindow(hWnd, 9);
        BringWindowToTop(hWnd);
        bool ok = SetForegroundWindow(hWnd);
        if (attached) { AttachThreadInput(thisThread, foreThread, false); }
        return ok;
    }

    public static void Click(int x, int y, bool doubleClick) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(60);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        if (doubleClick) {
            System.Threading.Thread.Sleep(90);
            mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
            mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
        }
    }

    public static void Scroll(int x, int y, int delta) {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(40);
        mouse_event(0x0800, 0, 0, unchecked((uint)delta), UIntPtr.Zero);
    }

    // 실제 마우스를 움직이지 않고 목록 컨트롤에만 휠 신호를 보냅니다.
    public static void ScrollControl(IntPtr hWnd, int delta, int screenX, int screenY) {
        IntPtr wParam = (IntPtr)(delta << 16);
        IntPtr lParam = (IntPtr)((screenY << 16) | (screenX & 0xFFFF));
        SendMessage(hWnd, 0x020A, wParam, lParam);
    }
}
"@
}

# ---------------------------------------------------------------------------
# 경로 및 설정
# ---------------------------------------------------------------------------
$AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $AppDir 'config.json'
$LogDir = Join-Path $AppDir 'logs'
$BackupDir = Join-Path $AppDir 'backup'
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Path $LogDir | Out-Null }

$script:txtLog = $null
$script:form = $null
$script:armed = $false
$script:running = $false
$script:activePage = 'compose'
$script:navItems = @()
$script:navText = @{}
$script:latestRelease = $null
$script:statusText = '준비됨'
$script:statusKind = 'idle'
$script:pillStatus = $null
$script:hoverNav = ''

$script:RoomTypeNormal = '일반채팅'
$script:RoomTypeOpen = '오픈채팅'
$script:RoomTypeUnknown = '미분류'

function New-DefaultConfig {
    [pscustomobject]@{
        Rooms = @()
        KnownRooms = @()
        RoomTypes = [pscustomobject]@{}
        Message = ''
        Attachments = @()
        ScheduledAt = (Get-Date).AddMinutes(10).ToString('yyyy-MM-dd HH:mm:ss')
        IntervalSeconds = 8
        DryRun = $true
        ScanPages = 30
        TestRoom = '나와의 채팅'
        AttachmentWaitMs = 1500
        AutoCheckUpdate = $true
        TourDone = $false
        Calibration = [pscustomobject]@{
            ChatTabX = -1.0
            ChatTabY = -1.0
            ChatViewName = ''
            OpenChatTabX = -1.0
            OpenChatTabY = -1.0
            OpenChatViewName = ''
        }
    }
}

function Save-Config([object]$Config) {
    $Config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
}

function Add-ConfigPropertyIfMissing([object]$Object, [string]$Name, [object]$Value) {
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Repair-Config([object]$Config) {
    $defaults = New-DefaultConfig
    foreach ($property in $defaults.PSObject.Properties) {
        if ($property.Name -eq 'Calibration') { continue }
        Add-ConfigPropertyIfMissing $Config $property.Name $property.Value
    }
    Add-ConfigPropertyIfMissing $Config 'Calibration' $defaults.Calibration
    foreach ($property in $defaults.Calibration.PSObject.Properties) {
        Add-ConfigPropertyIfMissing $Config.Calibration $property.Name $property.Value
    }
    if ($null -eq $Config.RoomTypes) { $Config.RoomTypes = [pscustomobject]@{} }
    # 예전 버전이 쓰던 표기를 현재 표기로 맞춥니다.
    foreach ($property in @($Config.RoomTypes.PSObject.Properties)) {
        if ([string]$property.Value -eq '확인 필요') { $Config.RoomTypes.($property.Name) = $script:RoomTypeUnknown }
    }
    return $Config
}

function Import-AppConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) {
        $default = New-DefaultConfig
        Save-Config $default
        return $default
    }
    try { return (Repair-Config (Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json)) }
    catch {
        [System.Windows.Forms.MessageBox]::Show("config.json을 읽을 수 없어 기본값으로 시작합니다.`r`n$($_.Exception.Message)", '설정 오류') | Out-Null
        return (New-DefaultConfig)
    }
}

function Write-RunLog([string]$Text) {
    $line = "{0}  {1}" -f (Get-Date -Format 'HH:mm:ss'), $Text
    try {
        Add-Content -LiteralPath (Join-Path $LogDir ((Get-Date -Format 'yyyy-MM-dd') + '.log')) -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Text) -Encoding UTF8
    } catch { }
    if ($script:txtLog) {
        $script:txtLog.AppendText($line + [Environment]::NewLine)
        $script:txtLog.SelectionStart = $script:txtLog.TextLength
        $script:txtLog.ScrollToCaret()
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Get-RoomType([string]$Name) {
    if ($null -eq $script:config.RoomTypes) { return $script:RoomTypeUnknown }
    $property = $script:config.RoomTypes.PSObject.Properties[$Name]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $script:RoomTypeUnknown }
    return [string]$property.Value
}

function Set-RoomType([string]$Name, [string]$Type) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    if ($null -eq $script:config.RoomTypes) { $script:config.RoomTypes = [pscustomobject]@{} }
    if ($null -eq $script:config.RoomTypes.PSObject.Properties[$Name]) {
        $script:config.RoomTypes | Add-Member -NotePropertyName $Name -NotePropertyValue $Type
    } else {
        $script:config.RoomTypes.$Name = $Type
    }
}

# ---------------------------------------------------------------------------
# 카카오톡 창 찾기
# ---------------------------------------------------------------------------
function Get-KakaoProcesses {
    @(Get-Process -Name KakaoTalk -ErrorAction SilentlyContinue)
}

# 열려 있는 개별 채팅창을 메인 창으로 착각하지 않도록, 제목과 내부 화면 이름으로 확인합니다.
function Find-KakaoMainHandle {
    $fallback = @()
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($window.Title -eq '카카오톡' -or $window.Title -eq 'KakaoTalk') { return $window.Handle }
            if ($window.Visible -and $window.Width -ge 240 -and $window.Height -ge 320) { $fallback += $window }
        }
    }
    foreach ($window in $fallback) {
        $children = @([NativeKakao]::GetChildWindows($window.Handle))
        if (@($children | Where-Object { $_.Title -match 'ChatRoomListView|ContactListView|OpenChat|OnlineMainView' }).Count -gt 0) {
            return $window.Handle
        }
    }
    return [IntPtr]::Zero
}

function Test-WindowMinimized([object]$Window) {
    if ($null -eq $Window) { return $false }
    if ([NativeKakao]::IsWindowMinimized($Window.Handle)) { return $true }
    return ($Window.Rect.Left -le -30000 -or $Window.Width -lt 200 -or $Window.Height -lt 200)
}

function Get-MainKakaoWindow([bool]$Restore = $false) {
    $handle = Find-KakaoMainHandle
    if ($handle -eq [IntPtr]::Zero) { return $null }
    $window = [NativeKakao]::GetWindow($handle)
    if ($Restore -and (Test-WindowMinimized $window)) {
        [void][NativeKakao]::ShowWindow($handle, 9)
        Start-Sleep -Milliseconds 600
        $window = [NativeKakao]::GetWindow($handle)
        Write-RunLog '카카오톡 창이 최소화되어 있어 다시 열었습니다.'
    }
    return $window
}

function Enter-KakaoForeground([object]$Window) {
    [void][NativeKakao]::ForceForeground($Window.Handle)
    Start-Sleep -Milliseconds 320
    return ([NativeKakao]::GetForegroundWindow() -eq $Window.Handle)
}

# ---------------------------------------------------------------------------
# 카카오톡 화면 구조 분석 (보정을 대신합니다)
# ---------------------------------------------------------------------------
# 카카오톡은 내부 창에 ChatRoomListView / ContactListView 같은 이름을 붙여 둡니다.
# 이 이름과 위치를 실시간으로 읽어 클릭 좌표를 스스로 계산하므로,
# 사용자가 좌표를 지정할 필요가 없습니다.
function Get-KakaoLayout([object]$MainWindow) {
    $children = @([NativeKakao]::GetChildWindows($MainWindow.Handle))

    $view = @($children | Where-Object {
        $_.Visible -and $_.Title -match 'View_0x' -and $_.Title -notmatch 'MainView' -and
        $_.Width -ge 150 -and $_.Height -ge 150
    } | Sort-Object -Property @{ Expression = { $_.Width * $_.Height } } -Descending | Select-Object -First 1)
    $activeView = if ($view.Count -gt 0) { $view[0] } else { $null }
    $viewName = if ($null -ne $activeView) { ($activeView.Title -replace '_0x[0-9A-Fa-f]+$', '') } else { '' }

    $lists = @($children | Where-Object {
        $_.Visible -and $_.ClassName -like '*ListControl*' -and $_.Width -ge 150 -and $_.Height -ge 180
    } | Sort-Object -Property @{ Expression = { $_.Width * $_.Height } } -Descending)
    $list = if ($lists.Count -gt 0) { $lists[0] } else { $null }

    $searchRow = $null
    if ($null -ne $list) {
        $rows = @($children | Where-Object {
            $_.Visible -and $_.Height -ge 22 -and $_.Height -le 72 -and
            $_.Width -ge ($list.Width * 0.6) -and
            $_.Rect.Top -lt $list.Rect.Top -and (($list.Rect.Top - $_.Rect.Top) -le 100)
        } | Sort-Object -Property @{ Expression = { $list.Rect.Top - $_.Rect.Top } })
        if ($rows.Count -gt 0) { $searchRow = $rows[0] }
    }

    return [pscustomobject]@{
        Main = $MainWindow
        List = $list
        SearchRow = $searchRow
        ViewName = $viewName
        IsChatList = ($viewName -match 'ChatRoom')
        IsOpenChatList = ($viewName -match 'OpenChat|OpenLink')
    }
}

function Get-RoomTypeFromViewName([string]$ViewName) {
    if ($ViewName -match 'OpenChat|OpenLink') { return $script:RoomTypeOpen }
    if ($ViewName -match 'ChatRoom') { return $script:RoomTypeNormal }
    return $script:RoomTypeUnknown
}

function Test-KakaoReady([bool]$Restore = $false) {
    $main = Get-MainKakaoWindow $Restore
    if ($null -eq $main) {
        return [pscustomobject]@{ Ok = $false; Reason = 'PC 카카오톡이 실행되어 있지 않습니다. 카카오톡을 먼저 실행해 주세요.'; Layout = $null }
    }
    if (Test-WindowMinimized $main) {
        return [pscustomobject]@{ Ok = $false; Reason = '카카오톡 창이 최소화되어 있습니다. 작업 표시줄에서 카카오톡 창을 열어 주세요.'; Layout = $null }
    }
    $layout = Get-KakaoLayout $main
    if ($null -eq $layout.List) {
        return [pscustomobject]@{ Ok = $false; Reason = '채팅 목록이 보이지 않습니다. 카카오톡에서 채팅 탭을 눌러 주세요.'; Layout = $layout }
    }
    if ($null -eq $layout.SearchRow) {
        return [pscustomobject]@{ Ok = $false; Reason = '검색창을 찾지 못했습니다. 카카오톡 창을 조금 더 크게 해 보세요.'; Layout = $layout }
    }
    return [pscustomobject]@{ Ok = $true; Reason = ''; Layout = $layout }
}

function Invoke-PointClick([int]$X, [int]$Y, [bool]$DoubleClick = $false) {
    [NativeKakao]::Click($X, $Y, $DoubleClick)
}

function Invoke-RatioClick([object]$Window, [double]$XRatio, [double]$YRatio) {
    $x = $Window.Rect.Left + [int]($Window.Width * $XRatio)
    $y = $Window.Rect.Top + [int]($Window.Height * $YRatio)
    [NativeKakao]::Click($x, $y, $false)
}

function Test-TabTaught([string]$Which) {
    $calibration = $script:config.Calibration
    if ($Which -eq 'OpenChatTab') { return ([double]$calibration.OpenChatTabX -ge 0) }
    return ([double]$calibration.ChatTabX -ge 0)
}

# 필요한 탭으로 전환합니다. 이미 그 탭이면 아무것도 하지 않습니다.
function Enter-KakaoTab([string]$Type) {
    $main = Get-MainKakaoWindow $true
    if ($null -eq $main) { throw 'PC 카카오톡이 실행되어 있지 않습니다. 카카오톡을 먼저 실행해 주세요.' }
    if (Test-WindowMinimized $main) { throw '카카오톡 창이 최소화되어 있습니다. 카카오톡 창을 열어 주세요.' }
    $layout = Get-KakaoLayout $main
    $wantOpen = ($Type -eq $script:RoomTypeOpen)
    if ($wantOpen -and $layout.IsOpenChatList) { return $layout }
    if (-not $wantOpen -and $layout.IsChatList) { return $layout }

    $which = if ($wantOpen) { 'OpenChatTab' } else { 'ChatTab' }
    if (-not (Test-TabTaught $which)) {
        $label = if ($wantOpen) { '오픈채팅' } else { '채팅' }
        throw "카카오톡에서 [$label] 탭을 눌러 목록이 보이게 해 주세요.`r`n(설정 화면에서 [$label] 탭 위치를 한 번 알려 주면 다음부터는 자동으로 눌러 줍니다.)"
    }
    [void](Enter-KakaoForeground $main)
    $calibration = $script:config.Calibration
    if ($wantOpen) { Invoke-RatioClick $main ([double]$calibration.OpenChatTabX) ([double]$calibration.OpenChatTabY) }
    else { Invoke-RatioClick $main ([double]$calibration.ChatTabX) ([double]$calibration.ChatTabY) }
    Start-Sleep -Milliseconds 700
    return (Get-KakaoLayout (Get-MainKakaoWindow))
}

# ---------------------------------------------------------------------------
# 클립보드 및 채팅창
# ---------------------------------------------------------------------------
function Set-ClipboardTextSafe([string]$Text) {
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try { [System.Windows.Forms.Clipboard]::SetText($Text); return }
        catch { Start-Sleep -Milliseconds 200 }
    }
    throw '클립보드에 문구를 넣지 못했습니다. 다른 프로그램이 클립보드를 사용 중일 수 있습니다.'
}

function Set-ClipboardFileSafe([string]$Path) {
    $files = New-Object System.Collections.Specialized.StringCollection
    [void]$files.Add((Resolve-Path -LiteralPath $Path).Path)
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try { [System.Windows.Forms.Clipboard]::SetFileDropList($files); return }
        catch { Start-Sleep -Milliseconds 200 }
    }
    throw '클립보드에 첨부 파일을 넣지 못했습니다.'
}

function Test-RoomTitle([string]$Actual, [string]$Expected) {
    $a = ([string]$Actual).Trim()
    $e = ([string]$Expected).Trim()
    if (-not $a -or -not $e) { return $false }
    if ($a -eq $e) { return $true }
    # 카카오톡은 인원수를 붙여 "방이름 (12)" 형태로 창 제목을 표시하기도 합니다.
    return $a -match ('^' + [regex]::Escape($e) + '\s*\(\d+\)$')
}

function Find-ChatWindow([string]$Room, [IntPtr]$MainHandle) {
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if (-not $window.Visible -or $window.Handle -eq $MainHandle) { continue }
            if (Test-RoomTitle $window.Title $Room) { return $window }
        }
    }
    return $null
}

function Close-ChatWindow([object]$Window) {
    [void][NativeKakao]::ForceForeground($Window.Handle)
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('%{F4}')
    Start-Sleep -Milliseconds 400
}

# 채팅창 하단의 입력칸을 UI 자동화로 찾아 직접 포커스를 줍니다.
function Set-ChatInputFocus([object]$Window) {
    try {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($Window.Handle)
        if ($null -eq $root) { return $false }
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Edit)
        $edits = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        $best = $null
        $bestTop = [double]::MinValue
        foreach ($edit in $edits) {
            try {
                $rect = $edit.Current.BoundingRectangle
                if ($rect.Width -lt 60 -or $rect.Height -lt 12) { continue }
                if ($rect.Top -gt $bestTop) { $bestTop = $rect.Top; $best = $edit }
            } catch { }
        }
        if ($null -ne $best) { $best.SetFocus(); Start-Sleep -Milliseconds 150; return $true }
    } catch { }
    return $false
}

# ---------------------------------------------------------------------------
# 방 이름 후보 정리
# ---------------------------------------------------------------------------
$script:RoomNoiseLabels = @(
    '친구', '채팅', '오픈채팅', '더보기', '검색', '설정', '채팅방 검색', '새로운 채팅',
    '쇼핑', '보기', '전체', '즐겨찾기', '알림', '메뉴', '이름', '프로필', '읽지 않음',
    '일반채팅', '광고', '카카오톡', '친구 검색', '채팅 검색', '멀티프로필',
    '조용한 채팅방', '일반 채팅방', '숨김 채팅방', '숨긴 채팅방', '안 읽은 채팅방',
    '채팅방 이름', '전체 채팅방', '광고 문의', '오픈채팅 검색', '새 채팅'
)

function ConvertTo-RoomCandidate([string]$RawName) {
    if ([string]::IsNullOrWhiteSpace($RawName)) { return $null }
    $parts = @($RawName -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -eq 0) { return $null }
    $name = $parts[0].Trim()
    if ($name.Length -lt 2 -or $name.Length -gt 60) { return $null }
    if ($name -notmatch '[0-9A-Za-z가-힣]') { return $null }
    if ($name -match '^\d{1,2}:\d{2}$') { return $null }
    if ($name -match '^\d+$') { return $null }
    if ($name -match '^(오전|오후)\s*\d') { return $null }
    if ($name -match '^\d{4}[.\-/]\d{1,2}[.\-/]\d{1,2}') { return $null }
    if ($name -match '^(어제|오늘|그저께)$') { return $null }
    if ($name -match '^안 읽은 메시지') { return $null }
    if ($name -match '^\d+개') { return $null }
    if ($name -in $script:RoomNoiseLabels) { return $null }
    return $name
}

# 채팅 목록의 각 행 오른쪽에 나타나는 시각·날짜 표기입니다. 행의 기준선으로 사용합니다.
function Test-RowAnchorText([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return $false }
    if ($t -match '^(오전|오후)\s*\d{1,2}\s*[:：]\s*\d{2}$') { return $true }
    if ($t -match '^\d{1,2}\s*[:：]\s*\d{2}$') { return $true }
    if ($t -match '^(어제|오늘|그저께)$') { return $true }
    if ($t -match '^\d{4}\s*[.\-/]\s*\d{1,2}\s*[.\-/]\s*\d{1,2}\s*\.?$') { return $true }
    if ($t -match '^\d{1,2}\s*[.\-/]\s*\d{1,2}\s*\.?$') { return $true }
    return $false
}

# OCR 로 읽은 줄에서 방 이름만 골라냅니다. 순수 함수라 자체 점검으로 검증합니다.
function Get-RoomNamesFromOcrLines([object[]]$Lines, [int]$Width) {
    $all = @($Lines)
    if ($all.Count -eq 0 -or $Width -le 0) { return @() }

    $nameLines = @($all | Where-Object { $_.Left -ge ($Width * 0.13) -and $_.Left -le ($Width * 0.46) } | Sort-Object Top)
    if ($nameLines.Count -eq 0) { return @() }

    $anchors = @($all | Where-Object { $_.Left -ge ($Width * 0.60) -and (Test-RowAnchorText $_.Text) } | Sort-Object Top)

    $picked = New-Object System.Collections.Generic.List[object]
    foreach ($anchor in $anchors) {
        $best = $null
        $bestDelta = [int]::MaxValue
        foreach ($line in $nameLines) {
            $delta = [Math]::Abs($line.Top - $anchor.Top)
            if ($delta -lt $bestDelta) { $bestDelta = $delta; $best = $line }
        }
        if ($null -ne $best -and $bestDelta -le 16 -and -not $picked.Contains($best)) { $picked.Add($best) }
    }

    # 시각 표기를 못 읽은 경우에만 세로 묶음의 첫 줄을 대신 사용합니다.
    if ($picked.Count -lt 2) {
        $picked.Clear()
        $previousTop = [int]::MinValue
        foreach ($line in $nameLines) {
            if (($line.Top - $previousTop) -gt 34) { $picked.Add($line) }
            $previousTop = $line.Top
        }
    }

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($picked | Sort-Object Top)) {
        $candidate = ConvertTo-RoomCandidate $line.Text
        if ($candidate -and -not $result.Contains($candidate)) { $result.Add($candidate) }
    }
    return @($result)
}

# ---------------------------------------------------------------------------
# 화면 글자 읽기 (Windows 내장 OCR)
# ---------------------------------------------------------------------------
$script:ocrEngine = $null
$script:ocrReady = $null
$script:ocrError = ''
$script:awaitAsTask = $null

function Initialize-Ocr {
    if ($null -ne $script:ocrReady) { return $script:ocrReady }
    $script:ocrReady = $false
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime
        $script:awaitAsTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
            $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
            $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
        if ($null -eq $script:awaitAsTask) { throw 'WinRT 비동기 도우미를 찾지 못했습니다.' }
        [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType = WindowsRuntime]
        [void][Windows.Media.Ocr.OcrEngine, Windows.Media, ContentType = WindowsRuntime]
        [void][Windows.Globalization.Language, Windows.Globalization, ContentType = WindowsRuntime]
        $language = New-Object Windows.Globalization.Language 'ko'
        $script:ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage($language)
        if ($null -eq $script:ocrEngine) { $script:ocrEngine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
        if ($null -eq $script:ocrEngine) { throw '한국어 문자 인식(OCR) 기능이 설치되어 있지 않습니다.' }
        $script:ocrReady = $true
    } catch {
        $script:ocrError = $_.Exception.Message
    }
    return $script:ocrReady
}

function Wait-WinRt($Operation, $ResultType) {
    $task = $script:awaitAsTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
    [void]$task.Wait(-1)
    return $task.Result
}

function Test-ImageBlank([System.Drawing.Bitmap]$Bitmap) {
    $seen = @{}
    for ($y = 0; $y -lt $Bitmap.Height; $y += 17) {
        for ($x = 0; $x -lt $Bitmap.Width; $x += 13) {
            $seen[$Bitmap.GetPixel($x, $y).ToArgb()] = $true
            if ($seen.Keys.Count -gt 3) { return $false }
        }
    }
    return $true
}

# PrintWindow 는 창이 가려져 있거나 뒤에 있어도 내용을 그려 줍니다.
# 다만 첫 호출은 아직 그려지지 않은 빈 화면을 돌려주는 경우가 있어 비면 다시 시도합니다.
function Get-WindowImage([object]$Window) {
    $bitmap = $null
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if ($null -ne $bitmap) { $bitmap.Dispose() }
        $bitmap = New-Object System.Drawing.Bitmap($Window.Width, $Window.Height)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try {
            $hdc = $graphics.GetHdc()
            try { [void][NativeKakao]::PrintWindow($Window.Handle, $hdc, 2) }
            finally { $graphics.ReleaseHdc($hdc) }
        } finally { $graphics.Dispose() }
        if (-not (Test-ImageBlank $bitmap)) { return $bitmap }
        Start-Sleep -Milliseconds 200
    }
    return $bitmap
}

function Get-OcrLines([object]$Window, [int]$Scale = 2) {
    if (-not (Initialize-Ocr)) { throw "문자 인식을 사용할 수 없습니다. $($script:ocrError)" }
    $source = Get-WindowImage $Window
    $scaled = $null
    $stream = $null
    try {
        if (Test-ImageBlank $source) { return @() }
        $scaled = New-Object System.Drawing.Bitmap(($source.Width * $Scale), ($source.Height * $Scale))
        $graphics = [System.Drawing.Graphics]::FromImage($scaled)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($source, 0, 0, $scaled.Width, $scaled.Height)
        $graphics.Dispose()

        $stream = New-Object System.IO.MemoryStream
        $scaled.Save($stream, [System.Drawing.Imaging.ImageFormat]::Bmp)
        [void]$stream.Seek(0, 'Begin')
        $random = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($stream)
        $decoder = Wait-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($random)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $software = Wait-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $recognized = Wait-WinRt ($script:ocrEngine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])

        $lines = @()
        foreach ($line in $recognized.Lines) {
            $words = @($line.Words)
            if ($words.Count -eq 0) { continue }
            $left = ($words | ForEach-Object { $_.BoundingRect.X } | Measure-Object -Minimum).Minimum
            $top = ($words | ForEach-Object { $_.BoundingRect.Y } | Measure-Object -Minimum).Minimum
            $lines += [pscustomobject]@{
                Text = [string]$line.Text
                Left = [int]($left / $Scale)
                Top = [int]($top / $Scale)
            }
        }
        return $lines
    } finally {
        if ($null -ne $scaled) { $scaled.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
        $source.Dispose()
    }
}

function Move-ListByWheel([object]$ListControl, [string]$Direction, [int]$Notches = 4) {
    $x = $ListControl.Rect.Left + [int]($ListControl.Width / 2)
    $y = $ListControl.Rect.Top + [int]($ListControl.Height / 2)
    $delta = 120 * [Math]::Max(1, $Notches)
    if ($Direction -eq 'down') { $delta = -$delta }
    [NativeKakao]::ScrollControl($ListControl.Handle, $delta, $x, $y)
}

function Move-ListByMouse([object]$MainWindow, [string]$Direction) {
    $x = $MainWindow.Rect.Left + [int]($MainWindow.Width * 0.55)
    $y = $MainWindow.Rect.Top + [int]($MainWindow.Height * 0.55)
    $delta = if ($Direction -eq 'down') { -480 } else { 480 }
    [NativeKakao]::Scroll($x, $y, $delta)
}

# ---------------------------------------------------------------------------
# 채팅방 목록 읽기
# ---------------------------------------------------------------------------
function Get-KakaoRoomNames([int]$MaxPages = 30) {
    $ready = Test-KakaoReady $true
    if (-not $ready.Ok) { throw $ready.Reason }
    $layout = $ready.Layout
    $list = $layout.List
    $roomType = Get-RoomTypeFromViewName $layout.ViewName

    if (-not (Initialize-Ocr)) {
        throw "화면의 글자를 읽을 수 없습니다.`r`n$($script:ocrError)`r`n`r`nWindows 설정 → 시간 및 언어 → 언어 및 지역에서 한국어의 추가 기능 중 [광학 문자 인식]을 설치해 주세요."
    }

    $names = New-Object System.Collections.Generic.List[string]
    $pages = 0
    $noChange = 0
    $useMouse = $false
    $pageLimit = [Math]::Max(1, [Math]::Min(60, $MaxPages))

    for ($page = 0; $page -lt $pageLimit; $page++) {
        $before = $names.Count
        $found = @(Get-RoomNamesFromOcrLines (Get-OcrLines $list 2) $list.Width)
        foreach ($name in $found) {
            if (-not $names.Contains([string]$name)) { $names.Add([string]$name) }
        }
        $pages++

        if ($names.Count -eq $before) { $noChange++ } else { $noChange = 0 }
        if ($noChange -ge 2) { break }

        # 한 화면에 보이는 행 수만큼 내려 겹침을 최소화합니다.
        $notches = [Math]::Max(3, [Math]::Min(8, $found.Count - 1))
        if ($useMouse) {
            [void](Enter-KakaoForeground $layout.Main)
            Move-ListByMouse $layout.Main 'down'
        } else {
            Move-ListByWheel $list 'down' $notches
        }
        Start-Sleep -Milliseconds 170

        # 메시지 방식이 먹지 않으면 실제 마우스 휠로 한 번만 전환합니다.
        if (-not $useMouse -and $noChange -eq 1 -and $page -le 1) { $useMouse = $true }
    }

    # 목록을 맨 위로 되돌립니다.
    if ($useMouse) {
        for ($i = 0; $i -lt ($pages + 4); $i++) { Move-ListByMouse $layout.Main 'up' }
    } else {
        for ($i = 0; $i -lt ($pages + 4); $i++) { Move-ListByWheel $list 'up' 8; Start-Sleep -Milliseconds 25 }
    }
    Start-Sleep -Milliseconds 200

    return [pscustomobject]@{
        Names = @($names | Sort-Object -Unique)
        Type = $roomType
        ViewName = $layout.ViewName
        Pages = $pages
    }
}

# ---------------------------------------------------------------------------
# 검색으로 방 열기 · 발송
# ---------------------------------------------------------------------------
function Open-RoomBySearch([string]$Query, [string]$RoomType, [int]$TimeoutMs = 5000) {
    $layout = Enter-KakaoTab $RoomType
    if ($null -eq $layout.List -or $null -eq $layout.SearchRow) {
        throw '채팅 목록과 검색창을 찾지 못했습니다. 카카오톡에서 채팅 목록이 보이게 해 주세요.'
    }
    $main = $layout.Main
    if (-not (Enter-KakaoForeground $main)) {
        Write-RunLog '경고: 카카오톡 창을 앞으로 가져오지 못했습니다. 계속 시도합니다.'
    }

    $existing = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($window.Visible) { $existing[[string]$window.Handle] = $true }
        }
    }

    # 검색창을 눌러 입력칸에 포커스를 줍니다.
    $searchX = $layout.SearchRow.Rect.Left + [int]($layout.SearchRow.Width / 2)
    $searchY = $layout.SearchRow.Rect.Top + [int]($layout.SearchRow.Height / 2)
    Invoke-PointClick $searchX $searchY
    Start-Sleep -Milliseconds 300
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Set-ClipboardTextSafe $Query
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 1100

    # 검색 결과 첫 줄을 두 번 눌러 방을 엽니다. 결과 목록은 원래 목록과 같은 자리에 나타납니다.
    $resultX = $layout.List.Rect.Left + [int]($layout.List.Width * 0.35)
    $resultY = $layout.List.Rect.Top + 32
    Invoke-PointClick $resultX $resultY $true

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible -or $window.Handle -eq $main.Handle) { continue }
                if ($existing.ContainsKey([string]$window.Handle)) { continue }
                if ([string]::IsNullOrWhiteSpace($window.Title)) { continue }
                return $window
            }
        }
        Start-Sleep -Milliseconds 220
    }

    # 이미 열려 있던 창이면 제목으로 찾습니다.
    return (Find-ChatWindow $Query $main.Handle)
}

# 읽어온 이름을 실제 채팅창 제목으로 교정합니다.
function Resolve-RoomName([string]$Query, [string]$RoomType) {
    $chat = Open-RoomBySearch $Query $RoomType
    if ($null -eq $chat) { return $null }
    $title = ([string]$chat.Title).Trim()
    Close-ChatWindow $chat
    if (-not $title) { return $null }
    return ($title -replace '\s*\(\d+\)$', '')
}

function Invoke-OneRoom([string]$Room, [string]$RoomType, [object]$Content) {
    $chat = Open-RoomBySearch $Room $RoomType
    if ($null -eq $chat) {
        Write-RunLog "건너뜀: '$Room' — 검색으로 채팅창을 열지 못했습니다."
        return $false
    }
    if (-not (Test-RoomTitle $chat.Title $Room)) {
        Write-RunLog "건너뜀: '$Room' — 열린 채팅창 제목('$($chat.Title)')이 정확히 일치하지 않습니다."
        Close-ChatWindow $chat
        return $false
    }

    if ([bool]$Content.DryRun) {
        Write-RunLog "확인 성공: '$Room' (전송하지 않음)"
        Close-ChatWindow $chat
        return $true
    }

    [void][NativeKakao]::ForceForeground($chat.Handle)
    Start-Sleep -Milliseconds 400
    [void](Set-ChatInputFocus $chat)

    $message = [string]$Content.Message
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        Set-ClipboardTextSafe $message
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds 800
    }

    $waitMs = [Math]::Max(600, [int]$Content.AttachmentWaitMs)
    foreach ($attachment in @($Content.Attachments)) {
        $path = [string]$attachment
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-RunLog "첨부 건너뜀: 파일 없음 — $path"
            continue
        }
        Set-ClipboardFileSafe $path
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds $waitMs
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds ($waitMs + 300)
    }

    Write-RunLog "발송 완료: '$Room'"
    Close-ChatWindow $chat
    return $true
}

function New-SendContent([bool]$DryRun) {
    return [pscustomobject]@{
        Message = [string]$script:config.Message
        Attachments = @($script:config.Attachments)
        AttachmentWaitMs = [int]$script:config.AttachmentWaitMs
        DryRun = $DryRun
    }
}

function Invoke-Broadcast {
    $rooms = @($script:config.Rooms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($rooms.Count -eq 0) { throw '보낼 채팅방을 한 개 이상 선택해 주세요.' }
    if ($rooms.Count -gt 50) { throw '안전을 위해 한 번에 최대 50개 방까지만 처리합니다.' }
    $dryRun = [bool]$script:config.DryRun
    if (-not $dryRun) {
        foreach ($attachment in @($script:config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }

    # 같은 종류끼리 묶어 탭 전환을 최소화합니다.
    $ordered = @($rooms | Sort-Object -Property @{ Expression = { Get-RoomType $_ } }, @{ Expression = { $_ } })
    $content = New-SendContent $dryRun
    $mode = if ($dryRun) { '확인 전용' } else { '실제 발송' }
    Write-RunLog ("작업 시작: 방 {0}개 / 모드={1}" -f $ordered.Count, $mode)

    $success = 0
    for ($i = 0; $i -lt $ordered.Count; $i++) {
        $room = $ordered[$i]
        try { if (Invoke-OneRoom $room (Get-RoomType $room) $content) { $success++ } }
        catch { Write-RunLog "오류: '$room' — $($_.Exception.Message)" }
        if ($i -lt ($ordered.Count - 1)) { Start-Sleep -Seconds ([Math]::Max(5, [int]$script:config.IntervalSeconds)) }
    }
    Write-RunLog ("작업 종료: 성공 {0}/{1}" -f $success, $ordered.Count)
    return $success
}

function Invoke-TestSend([bool]$DryRun) {
    $room = ([string]$script:config.TestRoom).Trim()
    if (-not $room) { throw '테스트 채팅방 이름을 입력해 주세요.' }
    if (-not $DryRun) {
        foreach ($attachment in @($script:config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }
    $type = Get-RoomType $room
    if ($type -eq $script:RoomTypeUnknown) { $type = $script:RoomTypeNormal }
    $label = if ($DryRun) { '테스트(확인만)' } else { '테스트 발송' }
    Write-RunLog "$label 시작: '$room'"
    $ok = Invoke-OneRoom $room $type (New-SendContent $DryRun)
    Write-RunLog ("$label 종료: {0}" -f $(if ($ok) { '성공' } else { '실패' }))
    return $ok
}

# ---------------------------------------------------------------------------
# 업데이트
# ---------------------------------------------------------------------------
function ConvertTo-AppVersion([string]$Text) {
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $clean = ($Text.Trim() -replace '^[vV]', '')
    $match = [regex]::Match($clean, '^\d+(\.\d+){0,3}')
    if (-not $match.Success) { return $null }
    try { return [version]$match.Value } catch { return $null }
}

function Get-LatestRelease {
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    $headers = @{ 'User-Agent' = 'KakaoRoomScheduler'; 'Accept' = 'application/vnd.github+json' }
    $response = Invoke-RestMethod -Uri $script:ApiLatest -Headers $headers -TimeoutSec 20
    $zipUrl = $null
    if ($response.PSObject.Properties['assets']) {
        $asset = @($response.assets | Where-Object { ([string]$_.name) -like '*.zip' }) | Select-Object -First 1
        if ($asset) { $zipUrl = [string]$asset.browser_download_url }
    }
    if (-not $zipUrl -and $response.PSObject.Properties['zipball_url']) { $zipUrl = [string]$response.zipball_url }
    return [pscustomobject]@{
        Tag = [string]$response.tag_name
        Version = ConvertTo-AppVersion ([string]$response.tag_name)
        PageUrl = [string]$response.html_url
        ZipUrl = $zipUrl
        Notes = [string]$response.body
    }
}

function Test-UpdateAvailable([object]$Release) {
    if ($null -eq $Release -or $null -eq $Release.Version) { return $false }
    $current = ConvertTo-AppVersion $script:AppVersion
    if ($null -eq $current) { return $false }
    return ($Release.Version -gt $current)
}

function Install-AppUpdate([object]$Release) {
    if ($null -eq $Release -or -not $Release.ZipUrl) { throw '내려받을 수 있는 파일을 찾지 못했습니다.' }
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "KakaoRoomScheduler-$stamp"
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    $zipPath = Join-Path $work 'update.zip'

    Write-RunLog "업데이트 내려받는 중: $($Release.Tag)"
    Invoke-WebRequest -Uri $Release.ZipUrl -OutFile $zipPath -Headers @{ 'User-Agent' = 'KakaoRoomScheduler' } -TimeoutSec 120

    $extract = Join-Path $work 'extract'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extract -Force

    $mainScript = @(Get-ChildItem -LiteralPath $extract -Recurse -Filter 'KakaoRoomScheduler.ps1' -File) | Select-Object -First 1
    if ($null -eq $mainScript) { throw '내려받은 파일에서 KakaoRoomScheduler.ps1 을 찾지 못했습니다.' }
    $sourceDir = $mainScript.Directory.FullName

    $backup = Join-Path $BackupDir $stamp
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in @('KakaoRoomScheduler.ps1', 'Start-KakaoRoomScheduler.cmd', 'README.md', 'Publish-Release.ps1')) {
        $existing = Join-Path $AppDir $name
        if (Test-Path -LiteralPath $existing) { Copy-Item -LiteralPath $existing -Destination $backup -Force }
    }

    $copied = 0
    foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -File)) {
        if ($file.Name -eq 'config.json') { continue }
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $AppDir $file.Name) -Force
        $copied++
    }
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Write-RunLog "업데이트 적용 완료: 파일 $copied 개 교체, 이전 파일은 backup\$stamp 에 보관"
    return $backup
}

function Restart-App {
    $launcher = Join-Path $AppDir 'Start-KakaoRoomScheduler.cmd'
    if (Test-Path -LiteralPath $launcher) { Start-Process -FilePath $launcher -WorkingDirectory $AppDir }
    else { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', (Join-Path $AppDir 'KakaoRoomScheduler.ps1')) -WorkingDirectory $AppDir }
    $script:armed = $false
    $script:form.Close()
}

# ---------------------------------------------------------------------------
# 가이드 투어 내용
# ---------------------------------------------------------------------------
$script:TourSteps = @(
    @{
        Page = 'compose'
        Title = '카카오 발송기에 오신 것을 환영합니다'
        Body  = "선택한 카카오톡 채팅방에 같은 문구와 사진을 한 번에, 또는 예약한 시각에 보내 주는 프로그램입니다.`r`n`r`n좌표를 맞추거나 설정할 것은 없습니다. 카카오톡을 켜 두기만 하면 됩니다.`r`n`r`n다음을 눌러 순서대로 따라와 주세요."
    },
    @{
        Page = 'rooms'
        Title = '1단계 · 보낼 채팅방 가져오기'
        Body  = "먼저 카카오톡에서 [채팅] 탭을 눌러 채팅방 목록이 보이게 해 주세요.`r`n`r`n그 상태로 [카카오톡에서 읽기]를 누르면 목록을 훑어 방 이름을 가져옵니다. 읽는 동안에는 마우스와 키보드를 사용하지 마세요.`r`n`r`n오픈채팅방도 보내려면, 카카오톡에서 [오픈채팅] 탭으로 바꾼 뒤 [카카오톡에서 읽기]를 한 번 더 누르면 됩니다. 종류는 자동으로 구분해서 저장됩니다."
    },
    @{
        Page = 'rooms'
        Title = '2단계 · 이름 정확하게 맞추기'
        Body  = "방 이름은 화면의 글자를 읽어 오기 때문에 가끔 틀리게 들어옵니다.`r`n`r`n보낼 방만 체크한 다음 [이름 확인·보정]을 누르세요. 체크한 방을 하나씩 열어 실제 이름으로 자동으로 고쳐 줍니다.`r`n`r`n안 잡히는 방은 [직접 추가]로 카카오톡에 보이는 이름 그대로 입력하면 됩니다."
    },
    @{
        Page = 'compose'
        Title = '3단계 · 문구와 사진 준비'
        Body  = "[발송 준비] 화면에 보낼 문구를 적고, 사진이나 파일을 추가합니다.`r`n`r`n문구가 먼저 한 개의 메시지로 전송되고, 그다음 첨부가 목록 순서대로 하나씩 전송됩니다. 순서는 [위로] [아래로] 버튼으로 바꿀 수 있습니다.`r`n`r`n입력한 내용은 자동으로 저장되니 따로 저장하지 않아도 됩니다."
    },
    @{
        Page = 'run'
        Title = '4단계 · 먼저 테스트해 보기'
        Body  = "가장 중요한 단계입니다. 여러 방에 한꺼번에 보내기 전에 [테스트 모드]로 한 방에만 똑같이 보내 결과를 확인하세요.`r`n`r`n기본값은 '나와의 채팅'이라 아무에게도 가지 않습니다. [테스트 발송]을 누르면 실제와 똑같은 방식으로 전송되므로 줄바꿈이나 사진 순서를 미리 볼 수 있습니다.`r`n`r`n[방 확인만]은 채팅창을 열어 이름만 맞는지 확인하고 전송은 하지 않습니다."
    },
    @{
        Page = 'run'
        Title = '5단계 · 지금 실행 또는 예약'
        Body  = "[지금 실행]은 바로 보내고, [예약 시작]은 지정한 시각에 자동으로 보냅니다.`r`n`r`n예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 하고, 화면 잠금이나 절전 상태에서는 동작하지 않습니다.`r`n`r`n방 사이 간격은 최소 5초이며, 한 번에 최대 50개 방까지만 처리합니다."
    },
    @{
        Page = 'log'
        Title = '마지막 · 안전하게 쓰기'
        Body  = "실행 중에는 마우스와 키보드를 사용하지 마세요. 클릭이 엉뚱한 곳으로 가면 잘못된 방에 전송될 수 있습니다.`r`n`r`n성공·건너뜀·오류는 모두 [실행 기록]에 남고 날짜별 파일로도 저장됩니다.`r`n`r`n수신에 동의한 분들이 있는 채팅방에서만 사용하세요. 반복적인 대량 발송은 카카오톡 이용 제한의 원인이 될 수 있습니다.`r`n`r`n이 가이드는 오른쪽 위 [?] 버튼으로 언제든 다시 볼 수 있습니다."
    }
)

# ---------------------------------------------------------------------------
# 자체 점검 및 진단 모드
# ---------------------------------------------------------------------------
$script:config = Import-AppConfig

if ($SelfTest) {
    $required = @('Rooms', 'KnownRooms', 'RoomTypes', 'Message', 'Attachments', 'ScheduledAt', 'IntervalSeconds', 'DryRun', 'ScanPages', 'TestRoom', 'AttachmentWaitMs', 'AutoCheckUpdate', 'TourDone', 'Calibration')
    foreach ($name in $required) {
        if ($null -eq $script:config.PSObject.Properties[$name]) { throw "필수 설정 항목 누락: $name" }
    }
    foreach ($name in @('ChatTabX', 'ChatTabY', 'ChatViewName', 'OpenChatTabX', 'OpenChatTabY', 'OpenChatViewName')) {
        if ($null -eq $script:config.Calibration.PSObject.Properties[$name]) { throw "필수 보정 항목 누락: $name" }
    }
    if ($null -ne (ConvertTo-RoomCandidate '오후 3:20')) { throw '후보 필터 자체 점검 실패 (시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '12:30')) { throw '후보 필터 자체 점검 실패 (숫자 시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '채팅')) { throw '후보 필터 자체 점검 실패 (메뉴)' }
    if ($null -ne (ConvertTo-RoomCandidate '·')) { throw '후보 필터 자체 점검 실패 (기호)' }
    if ((ConvertTo-RoomCandidate "테스트 채팅방`r`n안녕하세요") -ne '테스트 채팅방') { throw '후보 추출 자체 점검 실패' }
    if (-not (Test-RoomTitle '우리반 공지방 (24)' '우리반 공지방')) { throw '창 제목 비교 자체 점검 실패' }
    if (Test-RoomTitle '우리반 공지방 2기' '우리반 공지방') { throw '창 제목 비교가 너무 느슨합니다' }
    if ((ConvertTo-AppVersion 'v3.1.0') -le (ConvertTo-AppVersion '3.0.0')) { throw '버전 비교 자체 점검 실패' }
    if ($null -ne (ConvertTo-AppVersion 'nightly')) { throw '버전 파싱 자체 점검 실패' }

    foreach ($anchor in @('오후 3:20', '오전 11:05', '12:30', '어제', '2026. 8. 13.', '8/12')) {
        if (-not (Test-RowAnchorText $anchor)) { throw "행 기준선 인식 실패: $anchor" }
    }
    foreach ($notAnchor in @('안녕하세요', '우리반 공지방', '')) {
        if (Test-RowAnchorText $notAnchor) { throw "행 기준선 오인식: $notAnchor" }
    }
    $sample = @(
        [pscustomobject]@{ Text = '우리반 공지방'; Left = 80; Top = 92 },
        [pscustomobject]@{ Text = '내일 준비물 알려드립니다'; Left = 80; Top = 110 },
        [pscustomobject]@{ Text = '오후 3:20'; Left = 257; Top = 90 },
        [pscustomobject]@{ Text = '동네 모임'; Left = 80; Top = 160 },
        [pscustomobject]@{ Text = '또 봬요'; Left = 80; Top = 180 },
        [pscustomobject]@{ Text = '오후 1:02'; Left = 257; Top = 160 },
        [pscustomobject]@{ Text = '홍보방'; Left = 80; Top = 224 },
        [pscustomobject]@{ Text = 'https://example.com'; Left = 80; Top = 242 },
        [pscustomobject]@{ Text = '이어지는 미리보기 두 번째 줄'; Left = 80; Top = 258 },
        [pscustomobject]@{ Text = '어제'; Left = 262; Top = 224 },
        [pscustomobject]@{ Text = '3'; Left = 286; Top = 108 }
    )
    $parsed = @(Get-RoomNamesFromOcrLines $sample 325)
    if ($parsed.Count -ne 3) { throw "화면 읽기 행 분리 실패: 방 $($parsed.Count)개 (기대 3개) — $($parsed -join ', ')" }
    if ($parsed[0] -ne '우리반 공지방' -or $parsed[1] -ne '동네 모임' -or $parsed[2] -ne '홍보방') {
        throw "화면 읽기 결과가 기대와 다릅니다: $($parsed -join ', ')"
    }
    if (@(Get-RoomNamesFromOcrLines @() 325).Count -ne 0) { throw '빈 입력 처리 실패' }

    if ((Get-RoomTypeFromViewName 'ChatRoomListView') -ne $script:RoomTypeNormal) { throw '채팅 탭 인식 실패' }
    if ((Get-RoomTypeFromViewName 'OpenChatRoomListView') -ne $script:RoomTypeOpen) { throw '오픈채팅 탭 인식 실패' }
    if ((Get-RoomTypeFromViewName 'ContactListView') -ne $script:RoomTypeUnknown) { throw '알 수 없는 탭 처리 실패' }

    Set-RoomType '점검용 방' $script:RoomTypeOpen
    if ((Get-RoomType '점검용 방') -ne $script:RoomTypeOpen) { throw '방 종류 저장 실패' }
    if ((Get-RoomType '없는 방') -ne $script:RoomTypeUnknown) { throw '방 종류 기본값 실패' }

    if ($script:TourSteps.Count -lt 3) { throw '가이드 투어 단계가 비어 있습니다' }
    foreach ($step in $script:TourSteps) {
        foreach ($key in @('Page', 'Title', 'Body')) {
            if (-not $step.ContainsKey($key) -or [string]::IsNullOrWhiteSpace([string]$step[$key])) { throw "가이드 투어 항목 누락: $key" }
        }
        if ($step.Page -notin @('compose', 'rooms', 'run', 'settings', 'log')) { throw "가이드 투어의 화면 이름이 잘못되었습니다: $($step.Page)" }
    }
    [void](Get-KakaoProcesses)
    Write-Output 'SELFTEST_OK'
    exit 0
}

if ($ScanTest) {
    Write-Output ("문자 인식 사용 가능: {0}" -f (Initialize-Ocr))
    if ($script:ocrError) { Write-Output ("메모: {0}" -f $script:ocrError) }
    $ready = Test-KakaoReady
    Write-Output ("카카오톡 준비 상태: {0} {1}" -f $ready.Ok, $ready.Reason)
    if ($ready.Ok) {
        Write-Output ("현재 화면: {0} / 목록 {1}x{2} / 검색줄 {3}x{4}" -f `
            $ready.Layout.ViewName, $ready.Layout.List.Width, $ready.Layout.List.Height, `
            $ready.Layout.SearchRow.Width, $ready.Layout.SearchRow.Height)
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $scan = Get-KakaoRoomNames ([int]$script:config.ScanPages)
    $watch.Stop()
    Write-Output ("종류: {0} / 화면 {1}개 / 후보 {2}개 / {3:N1}초" -f $scan.Type, $scan.Pages, @($scan.Names).Count, ($watch.ElapsedMilliseconds / 1000))
    foreach ($name in $scan.Names) {
        if ($MaskNames -and $name.Length -gt 2) {
            Write-Output ("  - {0}{1} [{2}자]" -f $name.Substring(0, 2), ('*' * [Math]::Min(10, $name.Length - 2)), $name.Length)
        } else {
            Write-Output "  - $name"
        }
    }
    Write-Output 'SCANTEST_OK'
    exit 0
}

# ---------------------------------------------------------------------------
# 디자인 토큰
# ---------------------------------------------------------------------------
function New-Rgb([int]$R, [int]$G, [int]$B) { [System.Drawing.Color]::FromArgb($R, $G, $B) }

$Theme = @{
    Sidebar    = (New-Rgb 26 27 32)
    SidebarHi  = (New-Rgb 44 46 55)
    NavIdle    = (New-Rgb 160 165 175)
    Accent     = (New-Rgb 254 229 0)
    AccentInk  = (New-Rgb 26 26 30)
    Bg         = (New-Rgb 245 246 248)
    Card       = [System.Drawing.Color]::White
    Border     = (New-Rgb 228 231 236)
    Ink        = (New-Rgb 24 25 31)
    Sub        = (New-Rgb 88 94 105)
    Muted      = (New-Rgb 130 137 148)
    Success    = (New-Rgb 21 128 61)
    Danger     = (New-Rgb 200 50 55)
    Info       = (New-Rgb 30 90 220)
    FieldEdge  = (New-Rgb 214 219 226)
}

$FontBase   = New-Object System.Drawing.Font('Malgun Gothic', 9.75)
$FontSmall  = New-Object System.Drawing.Font('Malgun Gothic', 9)
$FontStrong = New-Object System.Drawing.Font('Malgun Gothic', 9.75, [System.Drawing.FontStyle]::Bold)
$FontCard   = New-Object System.Drawing.Font('Malgun Gothic', 11.25, [System.Drawing.FontStyle]::Bold)
$FontPage   = New-Object System.Drawing.Font('Malgun Gothic', 15.75, [System.Drawing.FontStyle]::Bold)
$FontLogo   = New-Object System.Drawing.Font('Malgun Gothic', 12, [System.Drawing.FontStyle]::Bold)
$FontLogoMark = New-Object System.Drawing.Font('Malgun Gothic', 13, [System.Drawing.FontStyle]::Bold)
$FontTourTitle = New-Object System.Drawing.Font('Malgun Gothic', 13.5, [System.Drawing.FontStyle]::Bold)
$FontTourBody = New-Object System.Drawing.Font('Malgun Gothic', 10)

$TextLeft = [System.Windows.Forms.TextFormatFlags]::Left -bor
            [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
            [System.Windows.Forms.TextFormatFlags]::NoPrefix
$TextCenter = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor
              [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor
              [System.Windows.Forms.TextFormatFlags]::NoPrefix

function Get-RoundedPath([System.Drawing.Rectangle]$Rect, [int]$Radius) {
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $diameter = [Math]::Max(1, $Radius * 2)
    $path.AddArc($Rect.X, $Rect.Y, $diameter, $diameter, 180, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Y, $diameter, $diameter, 270, 90)
    $path.AddArc($Rect.Right - $diameter, $Rect.Bottom - $diameter, $diameter, $diameter, 0, 90)
    $path.AddArc($Rect.X, $Rect.Bottom - $diameter, $diameter, $diameter, 90, 90)
    $path.CloseFigure()
    return $path
}

# 사용자 지정 그리기에서도 라벨과 같은 글자 배치를 쓰기 위해 TextRenderer 를 사용합니다.
# GDI+ DrawString 은 한글 자간이 벌어져 글자가 깨져 보입니다.
function Write-Text($Graphics, [string]$Text, $Font, [System.Drawing.Color]$Color, [System.Drawing.Rectangle]$Rect, $Flags) {
    [System.Windows.Forms.TextRenderer]::DrawText($Graphics, $Text, $Font, $Rect, $Color, $Flags)
}

# ---------------------------------------------------------------------------
# UI 헬퍼
# ---------------------------------------------------------------------------
function New-Card([object]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Title, [string]$Subtitle = '') {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point($X, $Y)
    $panel.Size = New-Object System.Drawing.Size($W, $H)
    $panel.BackColor = $Theme.Bg
    $panel.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = Get-RoundedPath $rect 12
        $brush = New-Object System.Drawing.SolidBrush ($Theme.Card)
        $pen = New-Object System.Drawing.Pen ($Theme.Border)
        $e.Graphics.FillPath($brush, $path)
        $e.Graphics.DrawPath($pen, $path)
        $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    })
    $Parent.Controls.Add($panel)

    if ($Title) {
        $label = New-Object System.Windows.Forms.Label
        $label.Text = $Title
        $label.Font = $FontCard
        $label.ForeColor = $Theme.Ink
        $label.BackColor = $Theme.Card
        $label.Location = New-Object System.Drawing.Point(24, 18)
        $label.Size = New-Object System.Drawing.Size(($W - 48), 26)
        $panel.Controls.Add($label)
    }
    if ($Subtitle) {
        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = $Subtitle
        $sub.Font = $FontSmall
        $sub.ForeColor = $Theme.Muted
        $sub.BackColor = $Theme.Card
        $sub.Location = New-Object System.Drawing.Point(24, 46)
        $sub.Size = New-Object System.Drawing.Size(($W - 48), 22)
        $panel.Controls.Add($sub)
    }
    return $panel
}

function New-CardLabel([object]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 24, [object]$Font = $null, [object]$Color = $null) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object System.Drawing.Point($X, $Y)
    $label.Size = New-Object System.Drawing.Size($W, $H)
    $label.BackColor = $Theme.Card
    $label.Font = if ($Font) { $Font } else { $FontBase }
    $label.ForeColor = if ($Color) { $Color } else { $Theme.Ink }
    $Parent.Controls.Add($label)
    return $label
}

function New-FieldFrame([object]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $frame = New-Object System.Windows.Forms.Panel
    $frame.Location = New-Object System.Drawing.Point($X, $Y)
    $frame.Size = New-Object System.Drawing.Size($W, $H)
    $frame.BackColor = $Theme.Card
    $frame.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = Get-RoundedPath $rect 8
        $brush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
        $pen = New-Object System.Drawing.Pen ($Theme.FieldEdge)
        $e.Graphics.FillPath($brush, $path)
        $e.Graphics.DrawPath($pen, $path)
        $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    })
    $Parent.Controls.Add($frame)
    return $frame
}

function New-AppTextBox([object]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H, [bool]$Multiline = $false) {
    $frame = New-FieldFrame $Parent $X $Y $W $H
    $box = New-Object System.Windows.Forms.TextBox
    $box.BorderStyle = 'None'
    $box.Font = $FontBase
    $box.ForeColor = $Theme.Ink
    $box.BackColor = [System.Drawing.Color]::White
    if ($Multiline) {
        $box.Multiline = $true
        $box.ScrollBars = 'Vertical'
        $box.Location = New-Object System.Drawing.Point(14, 12)
        $box.Size = New-Object System.Drawing.Size(($W - 30), ($H - 24))
    } else {
        $box.Location = New-Object System.Drawing.Point(14, 0)
        $box.Width = $W - 28
        $box.Top = [int](($H - $box.Height) / 2)
    }
    $frame.Controls.Add($box)
    return $box
}

function New-AppButton([object]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Kind = 'default') {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object System.Drawing.Point($X, $Y)
    $button.Size = New-Object System.Drawing.Size($W, $H)
    $button.FlatStyle = 'Flat'
    $button.Font = $FontBase
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.UseVisualStyleBackColor = $false
    switch ($Kind) {
        'primary' {
            $button.BackColor = $Theme.Accent
            $button.ForeColor = $Theme.AccentInk
            $button.Font = $FontStrong
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 246 222 0)
            $button.Add_EnabledChanged({
                if ($this.Enabled) { $this.BackColor = $Theme.Accent; $this.ForeColor = $Theme.AccentInk }
                else { $this.BackColor = (New-Rgb 236 238 241); $this.ForeColor = (New-Rgb 158 163 171) }
            })
        }
        'danger' {
            $button.BackColor = [System.Drawing.Color]::White
            $button.ForeColor = $Theme.Danger
            $button.FlatAppearance.BorderSize = 1
            $button.FlatAppearance.BorderColor = (New-Rgb 240 202 202)
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 253 244 244)
        }
        'ghost' {
            $button.BackColor = $Theme.Card
            $button.ForeColor = $Theme.Sub
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = $Theme.Bg
        }
        default {
            $button.BackColor = [System.Drawing.Color]::White
            $button.ForeColor = $Theme.Ink
            $button.FlatAppearance.BorderSize = 1
            $button.FlatAppearance.BorderColor = $Theme.FieldEdge
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 246 247 250)
        }
    }
    $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
    $path = Get-RoundedPath $rect 8
    $button.Region = New-Object System.Drawing.Region ($path)
    $path.Dispose()
    $Parent.Controls.Add($button)
    return $button
}

function Set-StatusPill([string]$Text, [string]$Kind) {
    $script:statusText = $Text
    $script:statusKind = $Kind
    if ($script:pillStatus) { $script:pillStatus.Invalidate() }
}

# ---------------------------------------------------------------------------
# 창 구성
# ---------------------------------------------------------------------------
[System.Windows.Forms.Application]::EnableVisualStyles()

$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = "카카오 발송기  ·  v$($script:AppVersion)"
$script:form.ClientSize = New-Object System.Drawing.Size(1060, 740)
$script:form.StartPosition = 'CenterScreen'
$script:form.FormBorderStyle = 'FixedSingle'
$script:form.MaximizeBox = $false
$script:form.AutoScaleMode = 'None'
$script:form.BackColor = $Theme.Bg
$script:form.Font = $FontBase

# ----- 사이드바 -----
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(0, 0)
$sidebar.Size = New-Object System.Drawing.Size(220, 740)
$sidebar.BackColor = $Theme.Sidebar
$script:form.Controls.Add($sidebar)

$logo = New-Object System.Windows.Forms.Panel
$logo.Location = New-Object System.Drawing.Point(0, 0)
$logo.Size = New-Object System.Drawing.Size(220, 104)
$logo.BackColor = $Theme.Sidebar
$logo.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $mark = New-Object System.Drawing.Rectangle(26, 28, 44, 44)
    $path = Get-RoundedPath $mark 13
    $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
    $e.Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
    Write-Text $e.Graphics '톡' $FontLogoMark $Theme.AccentInk $mark $TextCenter
    Write-Text $e.Graphics '카카오 발송기' $FontLogo ([System.Drawing.Color]::White) (New-Object System.Drawing.Rectangle(82, 32, 130, 22)) $TextLeft
    Write-Text $e.Graphics "v$($script:AppVersion)" $FontSmall $Theme.NavIdle (New-Object System.Drawing.Rectangle(82, 54, 130, 20)) $TextLeft
})
$sidebar.Controls.Add($logo)

$script:NavPages = @(
    @{ Key = 'compose';  Text = '발송 준비';   Title = '발송 준비' },
    @{ Key = 'rooms';    Text = '채팅방 선택'; Title = '채팅방 선택' },
    @{ Key = 'run';      Text = '실행 · 예약'; Title = '실행 · 예약' },
    @{ Key = 'settings'; Text = '설정';        Title = '설정' },
    @{ Key = 'log';      Text = '실행 기록';   Title = '실행 기록' }
)

$navY = 122
foreach ($page in $script:NavPages) {
    $script:navText[$page.Key] = $page.Text
    $item = New-Object System.Windows.Forms.Panel
    $item.Location = New-Object System.Drawing.Point(0, $navY)
    $item.Size = New-Object System.Drawing.Size(220, 48)
    $item.BackColor = $Theme.Sidebar
    $item.Cursor = [System.Windows.Forms.Cursors]::Hand
    $item.Tag = $page.Key
    $item.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $key = [string]$sender.Tag
        $isActive = ($script:activePage -eq $key)
        $isHover = ($script:hoverNav -eq $key)
        if ($isActive -or $isHover) {
            $fill = New-Object System.Drawing.SolidBrush ($Theme.SidebarHi)
            $e.Graphics.FillRectangle($fill, 0, 0, $sender.Width, $sender.Height)
            $fill.Dispose()
        }
        if ($isActive) {
            $bar = New-Object System.Drawing.SolidBrush ($Theme.Accent)
            $e.Graphics.FillRectangle($bar, 0, 9, 4, ($sender.Height - 18))
            $bar.Dispose()
        }
        $color = if ($isActive) { [System.Drawing.Color]::White } else { $Theme.NavIdle }
        $font = if ($isActive) { $FontStrong } else { $FontBase }
        Write-Text $e.Graphics $script:navText[$key] $font $color (New-Object System.Drawing.Rectangle(30, 0, 176, $sender.Height)) $TextLeft
    })
    $item.Add_Click({ Show-AppPage ([string]$this.Tag) })
    $item.Add_MouseEnter({ $script:hoverNav = [string]$this.Tag; $this.Invalidate() })
    $item.Add_MouseLeave({ $script:hoverNav = ''; $this.Invalidate() })
    $sidebar.Controls.Add($item)
    $script:navItems += $item
    $navY += 48
}

$script:pnlUpdate = New-Object System.Windows.Forms.Panel
$script:pnlUpdate.Location = New-Object System.Drawing.Point(18, 626)
$script:pnlUpdate.Size = New-Object System.Drawing.Size(184, 46)
$script:pnlUpdate.BackColor = $Theme.Sidebar
$script:pnlUpdate.Cursor = [System.Windows.Forms.Cursors]::Hand
$script:pnlUpdate.Visible = $false
$script:pnlUpdate.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $path = Get-RoundedPath $rect 10
    $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
    $e.Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
    $text = if ($script:latestRelease) { "새 버전 $($script:latestRelease.Tag) 받기" } else { '업데이트 확인' }
    Write-Text $e.Graphics $text $FontStrong $Theme.AccentInk $rect $TextCenter
})
$script:pnlUpdate.Add_Click({ Show-AppPage 'settings' })
$sidebar.Controls.Add($script:pnlUpdate)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "수신에 동의한 채팅방에서만 사용하세요."
$lblHint.Location = New-Object System.Drawing.Point(26, 684)
$lblHint.Size = New-Object System.Drawing.Size(176, 40)
$lblHint.BackColor = $Theme.Sidebar
$lblHint.ForeColor = (New-Rgb 112 118 128)
$lblHint.Font = $FontSmall
$sidebar.Controls.Add($lblHint)

# ----- 헤더 -----
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(220, 0)
$header.Size = New-Object System.Drawing.Size(840, 80)
$header.BackColor = $Theme.Bg
$script:form.Controls.Add($header)

$script:lblPageTitle = New-Object System.Windows.Forms.Label
$script:lblPageTitle.Text = '발송 준비'
$script:lblPageTitle.Font = $FontPage
$script:lblPageTitle.ForeColor = $Theme.Ink
$script:lblPageTitle.BackColor = $Theme.Bg
$script:lblPageTitle.Location = New-Object System.Drawing.Point(28, 26)
$script:lblPageTitle.Size = New-Object System.Drawing.Size(360, 36)
$header.Controls.Add($script:lblPageTitle)

$script:pillStatus = New-Object System.Windows.Forms.Panel
$script:pillStatus.Location = New-Object System.Drawing.Point(452, 26)
$script:pillStatus.Size = New-Object System.Drawing.Size(300, 38)
$script:pillStatus.BackColor = $Theme.Bg
$script:pillStatus.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    switch ($script:statusKind) {
        'run'   { $fill = New-Rgb 255 248 219; $ink = New-Rgb 141 100 0 }
        'wait'  { $fill = New-Rgb 229 239 255; $ink = $Theme.Info }
        'done'  { $fill = New-Rgb 227 246 233; $ink = $Theme.Success }
        'error' { $fill = New-Rgb 253 237 237; $ink = $Theme.Danger }
        default { $fill = [System.Drawing.Color]::White; $ink = $Theme.Sub }
    }
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $path = Get-RoundedPath $rect 19
    $brush = New-Object System.Drawing.SolidBrush ($fill)
    $pen = New-Object System.Drawing.Pen ($Theme.Border)
    $e.Graphics.FillPath($brush, $path)
    $e.Graphics.DrawPath($pen, $path)
    $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    $dot = New-Object System.Drawing.SolidBrush ($ink)
    $e.Graphics.FillEllipse($dot, 17, ([int]($sender.Height / 2) - 4), 9, 9)
    $dot.Dispose()
    Write-Text $e.Graphics $script:statusText $FontBase $ink (New-Object System.Drawing.Rectangle(34, 0, ($sender.Width - 46), $sender.Height)) $TextLeft
})
$header.Controls.Add($script:pillStatus)

$btnHelp = New-AppButton $header '?' 768 26 44 38 'default'
$btnHelp.Font = $FontStrong
$tipHelp = New-Object System.Windows.Forms.ToolTip
$tipHelp.SetToolTip($btnHelp, '사용 가이드 다시 보기')

# ----- 페이지 컨테이너 -----
$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Location = New-Object System.Drawing.Point(220, 80)
$pageHost.Size = New-Object System.Drawing.Size(840, 660)
$pageHost.BackColor = $Theme.Bg
$script:form.Controls.Add($pageHost)

$script:pages = @{}
function New-Page([string]$Key) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 0)
    $panel.Size = New-Object System.Drawing.Size(840, 660)
    $panel.BackColor = $Theme.Bg
    $panel.Visible = $false
    $pageHost.Controls.Add($panel)
    $script:pages[$Key] = $panel
    return $panel
}

function Show-AppPage([string]$Key) {
    if (-not $script:pages.ContainsKey($Key)) { return }
    $script:activePage = $Key
    foreach ($entry in $script:pages.GetEnumerator()) { $entry.Value.Visible = ($entry.Key -eq $Key) }
    foreach ($page in $script:NavPages) { if ($page.Key -eq $Key) { $script:lblPageTitle.Text = $page.Title } }
    foreach ($item in $script:navItems) { $item.Invalidate() }
}

# ===========================================================================
# 페이지 1 — 발송 준비
# ===========================================================================
$pageCompose = New-Page 'compose'

$cardMessage = New-Card $pageCompose 28 12 784 268 '발송 문구' '카카오톡에 붙여넣기로 전송됩니다. 줄바꿈도 그대로 유지됩니다.'
$script:txtMessage = New-AppTextBox $cardMessage 24 78 736 158 $true
$script:txtMessage.Text = [string]$script:config.Message
$script:lblMessageCount = New-CardLabel $cardMessage '' 24 240 736 20 $FontSmall $Theme.Muted

$cardFiles = New-Card $pageCompose 28 292 784 312 '첨부 사진 · 파일' '문구를 보낸 뒤 아래 순서대로 하나씩 전송합니다.'
$frameFiles = New-FieldFrame $cardFiles 24 78 576 212
$script:lstFiles = New-Object System.Windows.Forms.ListBox
$script:lstFiles.BorderStyle = 'None'
$script:lstFiles.Font = $FontBase
$script:lstFiles.Location = New-Object System.Drawing.Point(12, 12)
$script:lstFiles.Size = New-Object System.Drawing.Size(552, 188)
$frameFiles.Controls.Add($script:lstFiles)
foreach ($file in @($script:config.Attachments)) { [void]$script:lstFiles.Items.Add([string]$file) }

$btnAddFile    = New-AppButton $cardFiles '파일 추가' 616 78 144 40 'primary'
$btnFileUp     = New-AppButton $cardFiles '위로' 616 128 144 36
$btnFileDown   = New-AppButton $cardFiles '아래로' 616 170 144 36
$btnRemoveFile = New-AppButton $cardFiles '선택 제거' 616 218 144 36 'danger'
[void](New-CardLabel $cardFiles '사진은 미리보기를 거쳐 전송됩니다.' 616 262 144 40 $FontSmall $Theme.Muted)

$lblComposeHint = New-CardLabel $pageCompose '내용은 자동 저장됩니다. 실제 발송 전에 [실행 · 예약] 화면에서 테스트 발송으로 결과를 먼저 확인하세요.' 28 618 784 30 $FontSmall $Theme.Muted
$lblComposeHint.BackColor = $Theme.Bg

# ===========================================================================
# 페이지 2 — 채팅방 선택
# ===========================================================================
$pageRooms = New-Page 'rooms'
$cardRooms = New-Card $pageRooms 28 12 784 636 '발송 대상 채팅방' '카카오톡에서 보고 있는 탭의 목록을 읽어옵니다. 채팅 탭과 오픈채팅 탭을 각각 한 번씩 읽으면 됩니다.'

$script:txtRoomFilter = New-AppTextBox $cardRooms 24 80 216 38
$btnScanRooms  = New-AppButton $cardRooms '카카오톡에서 읽기' 252 80 170 38 'primary'
$btnVerifyRoom = New-AppButton $cardRooms '이름 확인·보정' 430 80 140 38
$btnAddRoom    = New-AppButton $cardRooms '직접 추가' 578 80 90 38
$btnEditRoom   = New-AppButton $cardRooms '이름 수정' 676 80 84 38

[void](New-CardLabel $cardRooms '보기' 24 134 34 26 $FontSmall $Theme.Muted)
$btnFilterAll  = New-AppButton $cardRooms '전체' 62 130 74 32
$btnFilterChat = New-AppButton $cardRooms '일반채팅' 142 130 88 32
$btnFilterOpen = New-AppButton $cardRooms '오픈채팅' 236 130 88 32
$script:lblRoomCount = New-CardLabel $cardRooms '선택 0 / 전체 0' 340 134 420 26 $FontStrong $Theme.Ink

$frameRooms = New-FieldFrame $cardRooms 24 174 736 372
$script:lstRooms = New-Object System.Windows.Forms.ListView
$script:lstRooms.View = 'Details'
$script:lstRooms.CheckBoxes = $true
$script:lstRooms.FullRowSelect = $true
$script:lstRooms.HideSelection = $false
$script:lstRooms.BorderStyle = 'None'
$script:lstRooms.Font = $FontBase
$script:lstRooms.Location = New-Object System.Drawing.Point(12, 12)
$script:lstRooms.Size = New-Object System.Drawing.Size(712, 348)
[void]$script:lstRooms.Columns.Add('채팅방 이름', 560)
[void]$script:lstRooms.Columns.Add('종류', 130)
$frameRooms.Controls.Add($script:lstRooms)

$btnCheckAll  = New-AppButton $cardRooms '보이는 항목 전체 선택' 24 560 176 34
$btnCheckNone = New-AppButton $cardRooms '전체 해제' 208 560 104 34
$btnDeleteRoom = New-AppButton $cardRooms '선택 항목 삭제' 320 560 128 34 'danger'
[void](New-CardLabel $cardRooms '최대 탐색 화면 수' 542 566 118 22 $FontSmall $Theme.Muted)
$script:numScanPages = New-Object System.Windows.Forms.NumericUpDown
$script:numScanPages.Minimum = 1
$script:numScanPages.Maximum = 60
$script:numScanPages.Value = [Math]::Max(1, [Math]::Min(60, [int]$script:config.ScanPages))
$script:numScanPages.Location = New-Object System.Drawing.Point(666, 562)
$script:numScanPages.Size = New-Object System.Drawing.Size(94, 30)
$script:numScanPages.Font = $FontBase
$script:numScanPages.BorderStyle = 'FixedSingle'
$cardRooms.Controls.Add($script:numScanPages)

[void](New-CardLabel $cardRooms '이름이 틀려도 안전합니다. 발송 직전에 채팅창 제목이 정확히 같은지 다시 확인하고, 다르면 보내지 않고 건너뜁니다.' 24 602 736 24 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 3 — 실행 · 예약
# ===========================================================================
$pageRun = New-Page 'run'

$cardMode = New-Card $pageRun 28 12 784 150 '발송 방식'
$script:rdoLive = New-Object System.Windows.Forms.RadioButton
$script:rdoLive.Text = '실제 발송 — 선택한 모든 방에 문구와 첨부를 보냅니다.'
$script:rdoLive.Location = New-Object System.Drawing.Point(24, 58)
$script:rdoLive.Size = New-Object System.Drawing.Size(730, 28)
$script:rdoLive.BackColor = $Theme.Card
$script:rdoLive.Font = $FontBase
$cardMode.Controls.Add($script:rdoLive)

$script:rdoDry = New-Object System.Windows.Forms.RadioButton
$script:rdoDry.Text = '확인 전용 — 방을 하나씩 열어 이름만 확인하고 전송하지 않습니다.'
$script:rdoDry.Location = New-Object System.Drawing.Point(24, 92)
$script:rdoDry.Size = New-Object System.Drawing.Size(730, 28)
$script:rdoDry.BackColor = $Theme.Card
$script:rdoDry.Font = $FontBase
$cardMode.Controls.Add($script:rdoDry)
if ([bool]$script:config.DryRun) { $script:rdoDry.Checked = $true } else { $script:rdoLive.Checked = $true }

$cardTest = New-Card $pageRun 28 174 784 176 '테스트 모드' '실제 발송 전에 지정한 한 방에만 똑같이 보내 결과를 확인합니다.'
[void](New-CardLabel $cardTest '테스트로 보낼 채팅방 이름' 24 82 220 22 $FontSmall $Theme.Muted)
$script:txtTestRoom = New-AppTextBox $cardTest 24 108 414 38
$script:txtTestRoom.Text = [string]$script:config.TestRoom
$btnTestSend = New-AppButton $cardTest '테스트 발송' 454 108 148 38 'primary'
$btnTestDry  = New-AppButton $cardTest '방 확인만' 612 108 148 38

$cardSchedule = New-Card $pageRun 28 362 784 286 '지금 실행 및 예약'
[void](New-CardLabel $cardSchedule '예약 시각' 24 56 100 22 $FontSmall $Theme.Muted)
$script:dtSchedule = New-Object System.Windows.Forms.DateTimePicker
$script:dtSchedule.Format = 'Custom'
$script:dtSchedule.CustomFormat = 'yyyy-MM-dd  HH:mm:ss'
$script:dtSchedule.ShowUpDown = $true
$script:dtSchedule.Location = New-Object System.Drawing.Point(24, 80)
$script:dtSchedule.Size = New-Object System.Drawing.Size(222, 32)
$script:dtSchedule.Font = $FontBase
try { $script:dtSchedule.Value = [datetime]::ParseExact([string]$script:config.ScheduledAt, 'yyyy-MM-dd HH:mm:ss', $null) }
catch { $script:dtSchedule.Value = (Get-Date).AddMinutes(10) }
if ($script:dtSchedule.Value -lt $script:dtSchedule.MinDate) { $script:dtSchedule.Value = (Get-Date).AddMinutes(10) }
$cardSchedule.Controls.Add($script:dtSchedule)

[void](New-CardLabel $cardSchedule '방 사이 간격(초)' 274 56 130 22 $FontSmall $Theme.Muted)
$script:numInterval = New-Object System.Windows.Forms.NumericUpDown
$script:numInterval.Minimum = 5
$script:numInterval.Maximum = 300
$script:numInterval.Value = [Math]::Max(5, [Math]::Min(300, [int]$script:config.IntervalSeconds))
$script:numInterval.Location = New-Object System.Drawing.Point(274, 80)
$script:numInterval.Size = New-Object System.Drawing.Size(94, 30)
$script:numInterval.Font = $FontBase
$script:numInterval.BorderStyle = 'FixedSingle'
$cardSchedule.Controls.Add($script:numInterval)

$btnRunNow    = New-AppButton $cardSchedule '지금 실행' 24 134 164 46 'primary'
$btnArm       = New-AppButton $cardSchedule '예약 시작' 200 134 164 46
$btnCancelArm = New-AppButton $cardSchedule '예약 취소' 376 134 164 46
$btnSave      = New-AppButton $cardSchedule '설정 저장' 552 134 164 46 'ghost'
$btnCancelArm.Enabled = $false

$script:lblCountdown = New-CardLabel $cardSchedule '예약이 설정되지 않았습니다.' 24 196 736 26 $FontStrong $Theme.Muted
[void](New-CardLabel $cardSchedule '예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 합니다. 화면 잠금·절전 상태에서는 동작하지 않으며, 실행 중에는 마우스와 키보드를 사용하지 마세요.' 24 226 736 44 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 4 — 설정
# ===========================================================================
$pageSettings = New-Page 'settings'

$cardStatus = New-Card $pageSettings 28 12 784 240 '카카오톡 연결 상태' '좌표를 맞출 필요는 없습니다. 카카오톡 화면 구조를 그때그때 읽어 자동으로 찾습니다.'
$script:lblKakaoState = New-CardLabel $cardStatus '확인 중입니다...' 24 78 736 104 $FontBase $Theme.Sub
$btnCheckKakao = New-AppButton $cardStatus '지금 확인' 24 190 150 40 'primary'
$btnTeachChat = New-AppButton $cardStatus '채팅 탭 위치 알려주기' 184 190 190 40
$btnTeachOpen = New-AppButton $cardStatus '오픈채팅 탭 위치 알려주기' 384 190 210 40

$cardUpdate = New-Card $pageSettings 28 264 784 196 '업데이트' "GitHub 저장소 $($script:RepoOwner)/$($script:RepoName) 의 최신 배포본을 확인합니다."
$script:lblUpdateState = New-CardLabel $cardUpdate "현재 버전 v$($script:AppVersion)" 24 76 736 46 $FontBase $Theme.Ink
$btnCheckUpdate  = New-AppButton $cardUpdate '업데이트 확인' 24 130 160 40
$script:btnDoUpdate = New-AppButton $cardUpdate '지금 업데이트' 194 130 160 40 'primary'
$script:btnDoUpdate.Enabled = $false
$btnOpenRepo     = New-AppButton $cardUpdate '저장소 열기' 364 130 160 40
$script:chkAutoUpdate = New-Object System.Windows.Forms.CheckBox
$script:chkAutoUpdate.Text = '시작할 때 자동 확인'
$script:chkAutoUpdate.Checked = [bool]$script:config.AutoCheckUpdate
$script:chkAutoUpdate.Location = New-Object System.Drawing.Point(542, 138)
$script:chkAutoUpdate.Size = New-Object System.Drawing.Size(216, 26)
$script:chkAutoUpdate.BackColor = $Theme.Card
$script:chkAutoUpdate.Font = $FontBase
$cardUpdate.Controls.Add($script:chkAutoUpdate)

$cardFolders = New-Card $pageSettings 28 472 784 176 '도움말 및 관리'
$btnGuide      = New-AppButton $cardFolders '가이드 다시 보기' 24 62 160 40 'primary'
$btnOpenApp    = New-AppButton $cardFolders '프로그램 폴더 열기' 194 62 170 40
$btnOpenLogs   = New-AppButton $cardFolders '로그 폴더 열기' 374 62 150 40
$btnResetConf  = New-AppButton $cardFolders '설정 초기화' 534 62 150 40 'danger'
[void](New-CardLabel $cardFolders "설정 파일 위치: $ConfigPath" 24 114 736 22 $FontSmall $Theme.Muted)
[void](New-CardLabel $cardFolders '카카오 계정, 비밀번호, 인증 정보는 저장하지 않습니다. 설정은 이 PC 안에만 보관됩니다.' 24 136 736 22 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 5 — 실행 기록
# ===========================================================================
$pageLog = New-Page 'log'
$cardLog = New-Card $pageLog 28 12 784 636 '실행 기록' '날짜별 파일로도 저장됩니다.'
$frameLog = New-FieldFrame $cardLog 24 78 736 470
$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.BorderStyle = 'None'
$script:txtLog.BackColor = [System.Drawing.Color]::White
$script:txtLog.Font = $FontBase
$script:txtLog.Location = New-Object System.Drawing.Point(14, 12)
$script:txtLog.Size = New-Object System.Drawing.Size(708, 446)
$frameLog.Controls.Add($script:txtLog)
$btnOpenLogDir = New-AppButton $cardLog '로그 폴더 열기' 24 566 170 40
$btnClearLog   = New-AppButton $cardLog '화면 지우기' 204 566 140 40 'ghost'

# ===========================================================================
# 채팅방 목록 상태 관리
# ===========================================================================
$script:roomEntries = New-Object System.Collections.Generic.List[object]
$script:roomFilter = '전체'
$script:suppressRoomEvents = $false

function Add-RoomEntry([string]$Name, [string]$Type, [bool]$Checked) {
    $clean = ([string]$Name).Trim()
    if (-not $clean) { return $false }
    foreach ($entry in $script:roomEntries) {
        if ($entry.Name -eq $clean) {
            if ($Type -and $Type -ne $script:RoomTypeUnknown) { $entry.Type = $Type }
            return $false
        }
    }
    $script:roomEntries.Add([pscustomobject]@{ Name = $clean; Type = $Type; Checked = $Checked })
    return $true
}

function Update-RoomCountLabel {
    $checked = @($script:roomEntries | Where-Object { $_.Checked }).Count
    $total = $script:roomEntries.Count
    $normal = @($script:roomEntries | Where-Object { $_.Type -eq $script:RoomTypeNormal }).Count
    $open = @($script:roomEntries | Where-Object { $_.Type -eq $script:RoomTypeOpen }).Count
    $script:lblRoomCount.Text = "선택 $($checked) / 전체 $($total)   ·   일반 $($normal)  오픈 $($open)"
}

function Update-FilterButtons {
    foreach ($pair in @(@($btnFilterAll, '전체'), @($btnFilterChat, $script:RoomTypeNormal), @($btnFilterOpen, $script:RoomTypeOpen))) {
        $button = $pair[0]
        if ($script:roomFilter -eq $pair[1]) {
            $button.BackColor = $Theme.Ink
            $button.ForeColor = [System.Drawing.Color]::White
            $button.FlatAppearance.BorderColor = $Theme.Ink
        } else {
            $button.BackColor = [System.Drawing.Color]::White
            $button.ForeColor = $Theme.Ink
            $button.FlatAppearance.BorderColor = $Theme.FieldEdge
        }
    }
}

function Update-RoomListView {
    $script:suppressRoomEvents = $true
    $script:lstRooms.BeginUpdate()
    $script:lstRooms.Items.Clear()
    foreach ($entry in ($script:roomEntries | Sort-Object -Property Type, Name)) {
        if ($script:roomFilter -ne '전체' -and $entry.Type -ne $script:roomFilter) { continue }
        $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Name)
        [void]$item.SubItems.Add([string]$entry.Type)
        $item.Checked = [bool]$entry.Checked
        if ($entry.Type -eq $script:RoomTypeUnknown) { $item.ForeColor = $Theme.Muted }
        [void]$script:lstRooms.Items.Add($item)
    }
    $script:lstRooms.EndUpdate()
    $script:suppressRoomEvents = $false
    Update-FilterButtons
    Update-RoomCountLabel
}

function Get-RoomEntry([string]$Name) {
    foreach ($entry in $script:roomEntries) { if ($entry.Name -eq $Name) { return $entry } }
    return $null
}

function Sync-ConfigFromForm {
    $script:config.Rooms = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
    $script:config.KnownRooms = @($script:roomEntries | ForEach-Object { [string]$_.Name })
    foreach ($entry in $script:roomEntries) { Set-RoomType $entry.Name $entry.Type }
    $script:config.Message = $script:txtMessage.Text
    $script:config.Attachments = @($script:lstFiles.Items | ForEach-Object { [string]$_ })
    $script:config.ScheduledAt = $script:dtSchedule.Value.ToString('yyyy-MM-dd HH:mm:ss')
    $script:config.IntervalSeconds = [int]$script:numInterval.Value
    $script:config.DryRun = [bool]$script:rdoDry.Checked
    $script:config.ScanPages = [int]$script:numScanPages.Value
    $script:config.TestRoom = $script:txtTestRoom.Text.Trim()
    $script:config.AutoCheckUpdate = [bool]$script:chkAutoUpdate.Checked
    Update-RoomCountLabel
    $script:lblMessageCount.Text = "$($script:txtMessage.Text.Length)자"
    Save-Config $script:config
}

$autoSaveTimer = New-Object System.Windows.Forms.Timer
$autoSaveTimer.Interval = 800
$autoSaveTimer.Add_Tick({
    $autoSaveTimer.Stop()
    try { Sync-ConfigFromForm } catch { }
})
function Request-AutoSave { $autoSaveTimer.Stop(); $autoSaveTimer.Start() }

# 저장된 방 목록 채우기
$selectedSet = @{}
foreach ($room in @($script:config.Rooms)) { $selectedSet[[string]$room] = $true }
foreach ($room in @(@($script:config.KnownRooms) + @($script:config.Rooms) | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)) {
    [void](Add-RoomEntry $room (Get-RoomType $room) ($selectedSet.ContainsKey($room)))
}
Update-RoomListView
$script:lblMessageCount.Text = "$($script:txtMessage.Text.Length)자"

# ===========================================================================
# 동작 연결
# ===========================================================================
$script:txtMessage.Add_TextChanged({ $script:lblMessageCount.Text = "$($script:txtMessage.Text.Length)자"; Request-AutoSave })
$script:txtTestRoom.Add_TextChanged({ Request-AutoSave })
$script:dtSchedule.Add_ValueChanged({ Request-AutoSave })
$script:numInterval.Add_ValueChanged({ Request-AutoSave })
$script:numScanPages.Add_ValueChanged({ Request-AutoSave })
$script:rdoDry.Add_CheckedChanged({ Request-AutoSave })
$script:chkAutoUpdate.Add_CheckedChanged({ Request-AutoSave })
$script:lstRooms.Add_ItemChecked({
    param($sender, $e)
    if ($script:suppressRoomEvents) { return }
    $entry = Get-RoomEntry ([string]$e.Item.Text)
    if ($null -ne $entry) { $entry.Checked = $e.Item.Checked }
    Update-RoomCountLabel
    Request-AutoSave
})

$btnHelp.Add_Click({ Show-GuideTour })

$btnAddFile.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Title = '사진 또는 파일 선택'
    if ($dialog.ShowDialog() -eq 'OK') {
        foreach ($file in $dialog.FileNames) { if (-not $script:lstFiles.Items.Contains($file)) { [void]$script:lstFiles.Items.Add($file) } }
        Sync-ConfigFromForm
    }
})
$btnRemoveFile.Add_Click({
    while ($script:lstFiles.SelectedIndices.Count -gt 0) { $script:lstFiles.Items.RemoveAt($script:lstFiles.SelectedIndices[0]) }
    Sync-ConfigFromForm
})
$btnFileUp.Add_Click({
    $index = $script:lstFiles.SelectedIndex
    if ($index -gt 0) {
        $item = $script:lstFiles.Items[$index]
        $script:lstFiles.Items.RemoveAt($index)
        $script:lstFiles.Items.Insert($index - 1, $item)
        $script:lstFiles.SelectedIndex = $index - 1
        Sync-ConfigFromForm
    }
})
$btnFileDown.Add_Click({
    $index = $script:lstFiles.SelectedIndex
    if ($index -ge 0 -and $index -lt ($script:lstFiles.Items.Count - 1)) {
        $item = $script:lstFiles.Items[$index]
        $script:lstFiles.Items.RemoveAt($index)
        $script:lstFiles.Items.Insert($index + 1, $item)
        $script:lstFiles.SelectedIndex = $index + 1
        Sync-ConfigFromForm
    }
})

$script:txtRoomFilter.Add_TextChanged({
    $query = $script:txtRoomFilter.Text.Trim()
    if (-not $query) { return }
    foreach ($item in $script:lstRooms.Items) {
        if (([string]$item.Text).IndexOf($query, [System.StringComparison]::CurrentCultureIgnoreCase) -ge 0) {
            $item.Selected = $true
            $item.EnsureVisible()
            break
        }
    }
})
$btnFilterAll.Add_Click({ $script:roomFilter = '전체'; Update-RoomListView })
$btnFilterChat.Add_Click({ $script:roomFilter = $script:RoomTypeNormal; Update-RoomListView })
$btnFilterOpen.Add_Click({ $script:roomFilter = $script:RoomTypeOpen; Update-RoomListView })

$btnCheckAll.Add_Click({
    foreach ($item in $script:lstRooms.Items) {
        $entry = Get-RoomEntry ([string]$item.Text)
        if ($null -ne $entry) { $entry.Checked = $true }
    }
    Update-RoomListView
    Sync-ConfigFromForm
})
$btnCheckNone.Add_Click({
    foreach ($entry in $script:roomEntries) { $entry.Checked = $false }
    Update-RoomListView
    Sync-ConfigFromForm
})
$btnAddRoom.Add_Click({
    $name = ([string][Microsoft.VisualBasic.Interaction]::InputBox('카카오톡에 표시되는 채팅방 이름을 정확히 입력하세요.', '채팅방 직접 추가', '')).Trim()
    if (-not $name) { return }
    $type = if ([System.Windows.Forms.MessageBox]::Show("'$name' 은(는) 오픈채팅방인가요?`r`n`r`n예 = 오픈채팅  /  아니오 = 일반 채팅", '채팅방 종류', 'YesNo', 'Question') -eq 'Yes') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
    [void](Add-RoomEntry $name $type $true)
    Update-RoomListView
    Sync-ConfigFromForm
})
$btnEditRoom.Add_Click({
    if ($script:lstRooms.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('수정할 항목을 먼저 선택하세요.', '이름 수정') | Out-Null; return }
    $current = [string]$script:lstRooms.SelectedItems[0].Text
    $entry = Get-RoomEntry $current
    if ($null -eq $entry) { return }
    $name = ([string][Microsoft.VisualBasic.Interaction]::InputBox('채팅방 이름을 수정하세요.', '이름 수정', $current)).Trim()
    if ($name -and $name -ne $current) {
        if ($null -ne (Get-RoomEntry $name)) { [System.Windows.Forms.MessageBox]::Show('같은 이름이 이미 목록에 있습니다.', '이름 수정') | Out-Null; return }
        $entry.Name = $name
        Update-RoomListView
        Sync-ConfigFromForm
    }
})
$btnDeleteRoom.Add_Click({
    if ($script:lstRooms.SelectedItems.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('삭제할 항목을 먼저 선택하세요.', '삭제') | Out-Null; return }
    $names = @($script:lstRooms.SelectedItems | ForEach-Object { [string]$_.Text })
    foreach ($name in $names) {
        $entry = Get-RoomEntry $name
        if ($null -ne $entry) { [void]$script:roomEntries.Remove($entry) }
    }
    Update-RoomListView
    Sync-ConfigFromForm
})

$btnScanRooms.Add_Click({
    try {
        Sync-ConfigFromForm
        $ready = Test-KakaoReady
        if (-not $ready.Ok) {
            [System.Windows.Forms.MessageBox]::Show("$($ready.Reason)`r`n`r`n카카오톡에서 [채팅] 또는 [오픈채팅] 탭을 눌러 목록이 보이게 한 뒤 다시 눌러 주세요.", '먼저 확인해 주세요') | Out-Null
            return
        }
        Set-StatusPill '채팅방 목록 읽는 중' 'run'
        $script:form.Enabled = $false
        Write-RunLog '카카오톡 채팅방 목록을 읽는 중입니다.'
        $scan = Get-KakaoRoomNames ([int]$script:config.ScanPages)
        $script:form.Enabled = $true
        $script:form.Activate()

        $type = $scan.Type
        if ($type -eq $script:RoomTypeUnknown) {
            $answer = [System.Windows.Forms.MessageBox]::Show("방금 읽은 목록이 오픈채팅방인가요?`r`n`r`n예 = 오픈채팅  /  아니오 = 일반 채팅", '채팅방 종류 확인', 'YesNo', 'Question')
            $type = if ($answer -eq 'Yes') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
        }

        $added = 0
        foreach ($name in @($scan.Names)) { if (Add-RoomEntry $name $type $false) { $added++ } }
        Update-RoomListView
        Sync-ConfigFromForm
        Set-StatusPill '준비됨' 'idle'
        Write-RunLog "목록 읽기 완료: $($type) / 화면 $($scan.Pages)개 / 후보 $(@($scan.Names).Count)개 중 새 항목 $($added)개"

        $other = if ($type -eq $script:RoomTypeOpen) { '채팅' } else { '오픈채팅' }
        [System.Windows.Forms.MessageBox]::Show(
            "$($type) 방 $(@($scan.Names).Count)개를 읽었습니다. (새로 추가 $($added)개)`r`n`r`n① 보낼 방만 체크하세요.`r`n② [이름 확인·보정]을 누르면 실제 이름으로 자동 교정됩니다.`r`n`r`n$($other) 방도 보내려면 카카오톡에서 [$($other)] 탭으로 바꾼 뒤 [카카오톡에서 읽기]를 한 번 더 누르세요.",
            '목록 읽기 완료') | Out-Null
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '읽기 실패' 'error'
        Write-RunLog "목록 읽기 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '목록 읽기 실패') | Out-Null
    }
})

$btnVerifyRoom.Add_Click({
    try {
        Sync-ConfigFromForm
        $targets = @($script:roomEntries | Where-Object { $_.Checked })
        if ($targets.Count -eq 0) { throw '확인할 채팅방을 먼저 체크해 주세요.' }
        if ($targets.Count -gt 50) { throw '한 번에 최대 50개까지만 확인합니다.' }
        $body = "체크한 $($targets.Count)개 방을 하나씩 열어 실제 이름으로 교정합니다.`r`n`r`n메시지는 전송하지 않지만 채팅방이 열리므로 읽음 표시가 될 수 있습니다.`r`n진행하는 동안 마우스와 키보드를 사용하지 마세요. 계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($body, '이름 확인·보정', 'YesNo', 'Question') -ne 'Yes') { return }

        $script:form.Enabled = $false
        Set-StatusPill '이름 확인 중' 'run'
        $fixed = 0
        $failed = 0
        foreach ($entry in $targets) {
            $current = [string]$entry.Name
            $type = if ($entry.Type -eq $script:RoomTypeUnknown) { $script:RoomTypeNormal } else { $entry.Type }
            try {
                $actual = Resolve-RoomName $current $type
                if (-not $actual) { $failed++; Write-RunLog "이름 확인 실패: '$current' — 채팅창을 열지 못했습니다."; continue }
                if ($actual -ne $current) {
                    if ($null -ne (Get-RoomEntry $actual)) {
                        Write-RunLog "이름 교정 생략: '$current' → '$actual' (이미 목록에 있음)"
                    } else {
                        $entry.Name = $actual
                        $fixed++
                        Write-RunLog "이름 교정: '$current' → '$actual'"
                    }
                }
            } catch {
                $failed++
                Write-RunLog "이름 확인 오류: '$current' — $($_.Exception.Message)"
            }
            Start-Sleep -Milliseconds 600
        }
        Update-RoomListView
        $script:form.Enabled = $true
        $script:form.Activate()
        Sync-ConfigFromForm
        Set-StatusPill '이름 확인 완료' 'done'
        [System.Windows.Forms.MessageBox]::Show("확인 $($targets.Count)개 · 교정 $($fixed)개 · 실패 $($failed)개`r`n`r`n실패한 방은 카카오톡에 표시되는 이름을 [이름 수정]으로 직접 맞춰 주세요.", '이름 확인·보정 완료') | Out-Null
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '이름 확인 실패' 'error'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '이름 확인·보정 실패') | Out-Null
    }
})

function Confirm-LiveRun([string]$Action) {
    if ([bool]$script:config.DryRun) { return $true }
    $roomCount = @($script:config.Rooms).Count
    $fileCount = @($script:config.Attachments).Count
    $body = "$Action`r`n`r`n대상: $($roomCount)개 방`r`n첨부: $($fileCount)개`r`n방 간격: $($script:config.IntervalSeconds)초`r`n`r`n실제 메시지가 전송됩니다. 계속할까요?"
    return ([System.Windows.Forms.MessageBox]::Show($body, '실제 발송 확인', 'YesNo', 'Warning') -eq 'Yes')
}

function Start-BroadcastAsync {
    if ($script:running) { return }
    $script:running = $true
    $script:armed = $false
    $btnArm.Enabled = $true
    $btnCancelArm.Enabled = $false
    Set-StatusPill '실행 중' 'run'
    $script:form.Enabled = $false
    try {
        $count = Invoke-Broadcast
        Set-StatusPill "작업 완료 · 성공 $($count)개" 'done'
    } catch {
        Write-RunLog "작업 중단: $($_.Exception.Message)"
        Set-StatusPill '오류로 중단' 'error'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '작업 중단') | Out-Null
    } finally {
        $script:form.Enabled = $true
        $script:running = $false
        $script:form.Activate()
    }
}

$btnSave.Add_Click({ Sync-ConfigFromForm; Write-RunLog '설정을 저장했습니다.'; Set-StatusPill '설정 저장됨' 'done' })
$btnRunNow.Add_Click({
    try {
        Sync-ConfigFromForm
        if (Confirm-LiveRun '지금 실행') { Start-BroadcastAsync }
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '실행 실패') | Out-Null }
})
$btnArm.Add_Click({
    try {
        Sync-ConfigFromForm
        if ($script:dtSchedule.Value -le (Get-Date)) { throw '예약 시각을 현재보다 뒤로 설정해 주세요.' }
        if (-not (Confirm-LiveRun ("{0} 예약" -f $script:dtSchedule.Value.ToString('yyyy-MM-dd HH:mm:ss')))) { return }
        $script:armed = $true
        $btnArm.Enabled = $false
        $btnCancelArm.Enabled = $true
        Write-RunLog ("예약 시작: {0}" -f $script:dtSchedule.Value.ToString('yyyy-MM-dd HH:mm:ss'))
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '예약 실패') | Out-Null }
})
$btnCancelArm.Add_Click({
    $script:armed = $false
    $btnArm.Enabled = $true
    $btnCancelArm.Enabled = $false
    $script:lblCountdown.Text = '예약이 취소되었습니다.'
    Set-StatusPill '예약 취소됨' 'idle'
    Write-RunLog '예약을 취소했습니다.'
})

$btnTestSend.Add_Click({
    try {
        Sync-ConfigFromForm
        $room = $script:config.TestRoom
        $body = "테스트 발송`r`n`r`n대상: $room`r`n첨부: $(@($script:config.Attachments).Count)개`r`n`r`n이 방에만 실제로 메시지를 보냅니다. 계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($body, '테스트 발송 확인', 'YesNo', 'Question') -ne 'Yes') { return }
        $script:form.Enabled = $false
        Set-StatusPill '테스트 발송 중' 'run'
        $ok = Invoke-TestSend $false
        $script:form.Enabled = $true
        $script:form.Activate()
        if ($ok) {
            Set-StatusPill '테스트 발송 성공' 'done'
            [System.Windows.Forms.MessageBox]::Show("'$room' 에 테스트 발송했습니다. 카카오톡에서 결과를 확인하세요.", '테스트 완료') | Out-Null
        } else {
            Set-StatusPill '테스트 실패' 'error'
            [System.Windows.Forms.MessageBox]::Show("'$room' 채팅창을 열지 못했습니다.`r`n`r`n· 카카오톡에 그 이름의 방이 있는지`r`n· 이름이 정확히 같은지`r`n확인해 주세요.", '테스트 실패') | Out-Null
        }
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '테스트 실패' 'error'
        Write-RunLog "테스트 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '테스트 실패') | Out-Null
    }
})
$btnTestDry.Add_Click({
    try {
        Sync-ConfigFromForm
        $script:form.Enabled = $false
        Set-StatusPill '방 확인 중' 'run'
        $ok = Invoke-TestSend $true
        $script:form.Enabled = $true
        $script:form.Activate()
        if ($ok) {
            Set-StatusPill '방 확인 성공' 'done'
            [System.Windows.Forms.MessageBox]::Show("'$($script:config.TestRoom)' 채팅창을 정확히 찾았습니다. 전송은 하지 않았습니다.", '확인 완료') | Out-Null
        } else {
            Set-StatusPill '방 확인 실패' 'error'
            [System.Windows.Forms.MessageBox]::Show("'$($script:config.TestRoom)' 채팅창을 열지 못했습니다.", '확인 실패') | Out-Null
        }
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '방 확인 실패' 'error'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '확인 실패') | Out-Null
    }
})

# ----- 카카오톡 연결 확인 및 탭 알려주기 -----
function Update-KakaoStateLabel {
    $lines = New-Object System.Collections.Generic.List[string]
    $ready = Test-KakaoReady
    if ($ready.Ok) {
        $lines.Add("[정상] 카카오톡 연결됨 — 지금 보고 있는 화면: $($ready.Layout.ViewName)")
        $lines.Add("[정상] 채팅 목록과 검색창을 찾았습니다. 좌표 설정은 필요 없습니다.")
    } else {
        $lines.Add("[확인 필요] $($ready.Reason)")
    }
    if (Initialize-Ocr) { $lines.Add('[정상] 한국어 문자 인식 사용 가능') }
    else { $lines.Add("[확인 필요] 한국어 문자 인식 불가 — $($script:ocrError)") }

    $chatTaught = Test-TabTaught 'ChatTab'
    $openTaught = Test-TabTaught 'OpenChatTab'
    $lines.Add("[선택] 채팅 탭 위치: $(if ($chatTaught) { '기억함' } else { '기억 안 함 (직접 탭을 눌러 두면 됩니다)' })")
    $lines.Add("[선택] 오픈채팅 탭 위치: $(if ($openTaught) { '기억함' } else { '기억 안 함 (직접 탭을 눌러 두면 됩니다)' })")

    $script:lblKakaoState.Text = ($lines -join [Environment]::NewLine)
    $script:lblKakaoState.ForeColor = if ($ready.Ok) { $Theme.Sub } else { $Theme.Danger }
    return $ready
}

function Invoke-TabTeach([string]$Which) {
    $label = if ($Which -eq 'OpenChatTab') { '오픈채팅' } else { '채팅' }
    $body = "카카오톡 창이 앞으로 나옵니다.`r`n`r`n카카오톡 왼쪽 세로 줄에서 [$label] 아이콘을 평소처럼 한 번 클릭해 주세요.`r`n`r`n클릭한 자리를 기억해 두었다가 다음부터 자동으로 눌러 줍니다.`r`n(그만두려면 Esc 키를 누르세요.)"
    if ([System.Windows.Forms.MessageBox]::Show($body, "$label 탭 위치 알려주기", 'OKCancel', 'Information') -ne 'OK') { return }

    $main = Get-MainKakaoWindow
    if ($null -eq $main) { throw '카카오톡 창을 찾지 못했습니다. PC 카카오톡을 실행해 주세요.' }

    $script:form.Hide()
    Start-Sleep -Milliseconds 300
    [void](Enter-KakaoForeground $main)
    while (([NativeKakao]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0) { Start-Sleep -Milliseconds 40 }

    $deadline = (Get-Date).AddSeconds(30)
    $captured = $null
    while ((Get-Date) -lt $deadline) {
        if (([NativeKakao]::GetAsyncKeyState(0x1B) -band 0x8000) -ne 0) { break }
        if (([NativeKakao]::GetAsyncKeyState(0x01) -band 0x8000) -ne 0) {
            $point = New-Object NativeKakao+POINT
            [void][NativeKakao]::GetCursorPos([ref]$point)
            $current = [NativeKakao]::GetWindow($main.Handle)
            if ($point.X -ge $current.Rect.Left -and $point.X -le $current.Rect.Right -and
                $point.Y -ge $current.Rect.Top -and $point.Y -le $current.Rect.Bottom) {
                $captured = [pscustomobject]@{ X = $point.X; Y = $point.Y; Window = $current }
                break
            }
        }
        Start-Sleep -Milliseconds 40
        [System.Windows.Forms.Application]::DoEvents()
    }

    Start-Sleep -Milliseconds 900
    $viewName = ''
    $latest = Get-MainKakaoWindow
    if ($null -ne $latest) { $viewName = (Get-KakaoLayout $latest).ViewName }

    $script:form.Show()
    $script:form.Activate()

    if ($null -eq $captured) { throw '클릭을 받지 못했습니다. 다시 시도해 주세요.' }

    $window = $captured.Window
    $xRatio = [Math]::Round(($captured.X - $window.Rect.Left) / $window.Width, 6)
    $yRatio = [Math]::Round(($captured.Y - $window.Rect.Top) / $window.Height, 6)
    $calibration = $script:config.Calibration
    if ($Which -eq 'OpenChatTab') {
        $calibration.OpenChatTabX = $xRatio
        $calibration.OpenChatTabY = $yRatio
        $calibration.OpenChatViewName = $viewName
    } else {
        $calibration.ChatTabX = $xRatio
        $calibration.ChatTabY = $yRatio
        $calibration.ChatViewName = $viewName
    }
    Save-Config $script:config
    Write-RunLog "$label 탭 위치를 기억했습니다. (화면: $viewName)"
    [void](Update-KakaoStateLabel)
    [System.Windows.Forms.MessageBox]::Show("$label 탭 위치를 기억했습니다.`r`n클릭 후 나타난 화면: $viewName", '완료') | Out-Null
}

$btnCheckKakao.Add_Click({
    $ready = Update-KakaoStateLabel
    if ($ready.Ok) { Set-StatusPill '카카오톡 연결됨' 'done' } else { Set-StatusPill '카카오톡 확인 필요' 'error' }
})
$btnTeachChat.Add_Click({
    try { Invoke-TabTeach 'ChatTab' }
    catch { $script:form.Show(); [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '탭 위치 알려주기 실패') | Out-Null }
})
$btnTeachOpen.Add_Click({
    try { Invoke-TabTeach 'OpenChatTab' }
    catch { $script:form.Show(); [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '탭 위치 알려주기 실패') | Out-Null }
})

# ----- 업데이트 -----
function Show-UpdateState([object]$Release, [string]$ErrorText) {
    if ($ErrorText) {
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)`r`n확인 실패: $ErrorText"
        $script:lblUpdateState.ForeColor = $Theme.Danger
        $script:btnDoUpdate.Enabled = $false
        $script:pnlUpdate.Visible = $false
        return
    }
    if ($null -eq $Release) {
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)`r`n아직 배포된 버전이 없습니다."
        $script:lblUpdateState.ForeColor = $Theme.Muted
        $script:btnDoUpdate.Enabled = $false
        $script:pnlUpdate.Visible = $false
        return
    }
    if (Test-UpdateAvailable $Release) {
        $script:latestRelease = $Release
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)  →  새 버전 $($Release.Tag) 이(가) 있습니다.`r`n$($Release.PageUrl)"
        $script:lblUpdateState.ForeColor = $Theme.Info
        $script:btnDoUpdate.Enabled = $true
        $script:pnlUpdate.Visible = $true
        $script:pnlUpdate.Invalidate()
        Write-RunLog "새 버전 확인: $($Release.Tag)"
    } else {
        $script:latestRelease = $null
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)`r`n최신 버전을 사용 중입니다. (배포본 $($Release.Tag))"
        $script:lblUpdateState.ForeColor = $Theme.Success
        $script:btnDoUpdate.Enabled = $false
        $script:pnlUpdate.Visible = $false
    }
}

function Invoke-UpdateCheck([bool]$Silent) {
    try {
        $release = Get-LatestRelease
        Show-UpdateState $release ''
        if (-not $Silent -and -not (Test-UpdateAvailable $release)) {
            [System.Windows.Forms.MessageBox]::Show("이미 최신 버전입니다. (v$($script:AppVersion))", '업데이트 확인') | Out-Null
        }
    } catch {
        $message = $_.Exception.Message
        if ($message -match '404') { Show-UpdateState $null '' }
        else {
            Show-UpdateState $null $message
            if (-not $Silent) { [System.Windows.Forms.MessageBox]::Show("업데이트 정보를 가져오지 못했습니다.`r`n$message", '업데이트 확인 실패') | Out-Null }
        }
    }
}

$btnCheckUpdate.Add_Click({ Set-StatusPill '업데이트 확인 중' 'run'; Invoke-UpdateCheck $false; Set-StatusPill '준비됨' 'idle' })
$btnOpenRepo.Add_Click({ Start-Process $script:RepoUrl })
$script:btnDoUpdate.Add_Click({
    if ($null -eq $script:latestRelease) { return }
    $release = $script:latestRelease
    $body = "새 버전 $($release.Tag) 을(를) 내려받아 설치합니다.`r`n`r`n출처: $($release.PageUrl)`r`n`r`n현재 파일은 backup 폴더에 보관되며, 설정과 로그는 그대로 유지됩니다.`r`n설치 후 프로그램이 다시 시작됩니다. 계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($body, '업데이트 설치', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $script:form.Enabled = $false
        Set-StatusPill '업데이트 설치 중' 'run'
        [void](Install-AppUpdate $release)
        $script:form.Enabled = $true
        if ([System.Windows.Forms.MessageBox]::Show('업데이트를 적용했습니다. 지금 다시 시작할까요?', '업데이트 완료', 'YesNo', 'Information') -eq 'Yes') {
            Restart-App
        } else {
            Set-StatusPill '다시 시작하면 적용됩니다' 'done'
        }
    } catch {
        $script:form.Enabled = $true
        Set-StatusPill '업데이트 실패' 'error'
        Write-RunLog "업데이트 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '업데이트 실패') | Out-Null
    }
})

# ----- 폴더 및 초기화 -----
$btnGuide.Add_Click({ Show-GuideTour })
$btnOpenApp.Add_Click({ Start-Process 'explorer.exe' $AppDir })
$btnOpenLogs.Add_Click({ Start-Process 'explorer.exe' $LogDir })
$btnOpenLogDir.Add_Click({ Start-Process 'explorer.exe' $LogDir })
$btnClearLog.Add_Click({ $script:txtLog.Clear() })
$btnResetConf.Add_Click({
    if ([System.Windows.Forms.MessageBox]::Show("모든 설정(방 목록, 문구, 첨부)을 지우고 처음 상태로 되돌립니다.`r`n계속할까요?", '설정 초기화', 'YesNo', 'Warning') -ne 'Yes') { return }
    $script:config = New-DefaultConfig
    Save-Config $script:config
    [System.Windows.Forms.MessageBox]::Show('초기화했습니다. 프로그램을 다시 시작합니다.', '설정 초기화') | Out-Null
    Restart-App
})

# ----- 가이드 투어 -----
function Show-GuideTour([string]$CaptureDir = '') {
    $script:tourIndex = 0
    $total = $script:TourSteps.Count

    $tour = New-Object System.Windows.Forms.Form
    $tour.FormBorderStyle = 'None'
    $tour.Size = New-Object System.Drawing.Size(600, 440)
    $tour.StartPosition = 'Manual'
    $tour.BackColor = $Theme.Card
    $tour.Font = $FontBase
    $tour.ShowInTaskbar = $false
    $tour.KeyPreview = $true
    $tour.Location = New-Object System.Drawing.Point(
        ($script:form.Left + 320),
        ($script:form.Top + 160))
    $tour.Add_Paint({
        param($sender, $e)
        $pen = New-Object System.Drawing.Pen ($Theme.Border)
        $e.Graphics.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $pen.Dispose()
        $accent = New-Object System.Drawing.SolidBrush ($Theme.Accent)
        $e.Graphics.FillRectangle($accent, 0, 0, $sender.Width, 6)
        $accent.Dispose()
    })

    $lblStep = New-Object System.Windows.Forms.Label
    $lblStep.Location = New-Object System.Drawing.Point(38, 34)
    $lblStep.Size = New-Object System.Drawing.Size(200, 22)
    $lblStep.Font = $FontStrong
    $lblStep.ForeColor = $Theme.Muted
    $lblStep.BackColor = $Theme.Card
    $tour.Controls.Add($lblStep)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(36, 60)
    $lblTitle.Size = New-Object System.Drawing.Size(528, 36)
    $lblTitle.Font = $FontTourTitle
    $lblTitle.ForeColor = $Theme.Ink
    $lblTitle.BackColor = $Theme.Card
    $tour.Controls.Add($lblTitle)

    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Location = New-Object System.Drawing.Point(38, 106)
    $lblBody.Size = New-Object System.Drawing.Size(526, 246)
    $lblBody.Font = $FontTourBody
    $lblBody.ForeColor = $Theme.Sub
    $lblBody.BackColor = $Theme.Card
    $tour.Controls.Add($lblBody)

    $dots = New-Object System.Windows.Forms.Panel
    $dots.Location = New-Object System.Drawing.Point(38, 376)
    $dots.Size = New-Object System.Drawing.Size(170, 26)
    $dots.BackColor = $Theme.Card
    $dots.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        for ($i = 0; $i -lt $script:TourSteps.Count; $i++) {
            $isCurrent = ($i -eq $script:tourIndex)
            $color = if ($isCurrent) { $Theme.Ink } else { (New-Rgb 216 220 226) }
            $brush = New-Object System.Drawing.SolidBrush ($color)
            $size = if ($isCurrent) { 10 } else { 8 }
            $offset = if ($isCurrent) { 8 } else { 9 }
            $e.Graphics.FillEllipse($brush, ($i * 17), $offset, $size, $size)
            $brush.Dispose()
        }
    })
    $tour.Controls.Add($dots)

    $btnSkip = New-AppButton $tour '건너뛰기' 226 370 96 38 'ghost'
    $btnPrev = New-AppButton $tour '이전' 332 370 106 38
    $btnNext = New-AppButton $tour '다음' 448 370 116 38 'primary'

    $renderStep = {
        $step = $script:TourSteps[$script:tourIndex]
        Show-AppPage ([string]$step.Page)
        $lblStep.Text = "{0} / {1}" -f ($script:tourIndex + 1), $total
        $lblTitle.Text = [string]$step.Title
        $lblBody.Text = [string]$step.Body
        $btnPrev.Visible = ($script:tourIndex -gt 0)
        $btnNext.Text = if ($script:tourIndex -eq ($total - 1)) { '시작하기' } else { '다음' }
        $btnSkip.Visible = ($script:tourIndex -lt ($total - 1))
        $dots.Invalidate()
    }

    $finish = {
        $script:config.TourDone = $true
        try { Save-Config $script:config } catch { }
        $tour.Close()
    }

    $btnNext.Add_Click({
        if ($script:tourIndex -ge ($total - 1)) { & $finish; return }
        $script:tourIndex++
        & $renderStep
    })
    $btnPrev.Add_Click({ if ($script:tourIndex -gt 0) { $script:tourIndex--; & $renderStep } })
    $btnSkip.Add_Click({ & $finish })
    $tour.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { & $finish } })

    & $renderStep

    if ($CaptureDir) {
        $tour.Show()
        for ($i = 0; $i -lt $total; $i++) {
            $script:tourIndex = $i
            & $renderStep
            $tour.Refresh()
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 200
            $bitmap = New-Object System.Drawing.Bitmap($tour.Width, $tour.Height)
            $tour.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $tour.Width, $tour.Height)))
            $bitmap.Save((Join-Path $CaptureDir ("tour-{0}.png" -f ($i + 1))), [System.Drawing.Imaging.ImageFormat]::Png)
            $bitmap.Dispose()
        }
        $tour.Close()
        $tour.Dispose()
        return
    }

    [void]$tour.ShowDialog($script:form)
    $tour.Dispose()
    Show-AppPage 'compose'
}

# ----- 타이머 -----
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
    if ($script:armed -and -not $script:running) {
        $remaining = $script:dtSchedule.Value - (Get-Date)
        if ($remaining.TotalSeconds -le 0) {
            $script:lblCountdown.Text = '예약 시각이 되어 실행합니다.'
            Start-BroadcastAsync
        } else {
            $text = "예약까지 " + $remaining.ToString('dd\일\ hh\:mm\:ss')
            $script:lblCountdown.Text = $text
            $script:lblCountdown.ForeColor = $Theme.Info
            Set-StatusPill $text 'wait'
        }
    }
})
$timer.Start()

$script:form.Add_FormClosing({
    if ($script:running) {
        [System.Windows.Forms.MessageBox]::Show('작업이 실행 중입니다. 끝난 뒤에 닫아 주세요.', '종료 불가') | Out-Null
        $_.Cancel = $true
        return
    }
    if ($script:armed) {
        if ([System.Windows.Forms.MessageBox]::Show('창을 닫으면 예약이 취소됩니다. 종료할까요?', '예약 취소 확인', 'YesNo', 'Warning') -ne 'Yes') {
            $_.Cancel = $true
            return
        }
    }
    try { Sync-ConfigFromForm } catch { }
})

$startupTimer = New-Object System.Windows.Forms.Timer
$startupTimer.Interval = 1200
$startupTimer.Add_Tick({
    $startupTimer.Stop()
    try { [void](Update-KakaoStateLabel) } catch { }
    if (-not $NoUpdateCheck -and [bool]$script:config.AutoCheckUpdate) { Invoke-UpdateCheck $true }
})

Show-AppPage 'compose'
Write-RunLog "프로그램 시작 (v$($script:AppVersion)). 설정은 자동 저장됩니다."

if ($ScreenshotDir) {
    if (-not (Test-Path -LiteralPath $ScreenshotDir)) { New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null }
    [void](Add-RoomEntry '우리반 공지방' $script:RoomTypeNormal $true)
    [void](Add-RoomEntry '동네 모임' $script:RoomTypeNormal $true)
    [void](Add-RoomEntry '주말 등산 모임' $script:RoomTypeOpen $false)
    [void](Add-RoomEntry '중고거래 알림방' $script:RoomTypeOpen $false)
    [void](Add-RoomEntry '독서 모임' $script:RoomTypeUnknown $false)
    Update-RoomListView
    $script:txtMessage.Text = "안녕하세요! 이번 주 모임 안내드립니다.`r`n토요일 오후 2시, 시민공원 정문에서 만나요."
    $script:lblKakaoState.Text = "[정상] 카카오톡 연결됨 — 지금 보고 있는 화면: ChatRoomListView`r`n[정상] 채팅 목록과 검색창을 찾았습니다. 좌표 설정은 필요 없습니다.`r`n[정상] 한국어 문자 인식 사용 가능`r`n[선택] 채팅 탭 위치: 기억함`r`n[선택] 오픈채팅 탭 위치: 기억 안 함 (직접 탭을 눌러 두면 됩니다)"
    Set-StatusPill '준비됨' 'idle'
    $script:form.StartPosition = 'Manual'
    $script:form.Location = New-Object System.Drawing.Point(-4000, -4000)
    $script:form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    foreach ($page in $script:NavPages) {
        Show-AppPage $page.Key
        $script:form.Refresh()
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 250
        $bitmap = New-Object System.Drawing.Bitmap($script:form.Width, $script:form.Height)
        $script:form.DrawToBitmap($bitmap, (New-Object System.Drawing.Rectangle(0, 0, $script:form.Width, $script:form.Height)))
        $bitmap.Save((Join-Path $ScreenshotDir ("page-" + $page.Key + ".png")), [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
    }
    Show-GuideTour $ScreenshotDir
    Write-Output 'SCREENSHOT_OK'
    $script:form.Dispose()
    exit 0
}

if ($UiSmokeTest) {
    Write-Output ("UI_SMOKETEST_OK pages={0} nav={1}" -f $script:pages.Count, $script:navItems.Count)
    $script:form.Dispose()
    exit 0
}

$script:form.Add_Shown({
    if (-not [bool]$script:config.TourDone) {
        Write-RunLog '처음 실행이라 사용 가이드를 표시합니다.'
        Show-GuideTour
    }
    $startupTimer.Start()
})

# ShowDialog 로 띄우면 탭 위치를 알려줄 때 form.Hide() 가 모달 루프를 끝내 프로그램이 종료됩니다.
[System.Windows.Forms.Application]::Run($script:form)
