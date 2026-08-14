param(
    [switch]$SelfTest,
    [switch]$UiSmokeTest,
    [switch]$NoUpdateCheck,
    [string]$ScreenshotDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 배포 정보 (CI가 아래 AppVersion 줄을 그대로 치환합니다. 형식을 바꾸지 마세요.)
# ---------------------------------------------------------------------------
$script:AppVersion = '3.0.0'
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
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", EntryPoint = "GetWindowThreadProcessId")] static extern uint GetWindowThreadId(IntPtr hWnd, IntPtr zero);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
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
$script:statusText = '대기 중'
$script:statusKind = 'idle'

function New-DefaultConfig {
    [pscustomobject]@{
        Rooms = @()
        KnownRooms = @()
        Message = ''
        Attachments = @()
        ScheduledAt = (Get-Date).AddMinutes(10).ToString('yyyy-MM-dd HH:mm:ss')
        IntervalSeconds = 8
        DryRun = $true
        ScanPages = 20
        TestRoom = '나와의 채팅'
        AttachmentWaitMs = 1500
        AutoCheckUpdate = $true
        TourDone = $false
        Calibration = [pscustomobject]@{
            WindowClass = ''
            WindowTitle = ''
            Width = 0
            Height = 0
            ChatTabX = -1.0
            ChatTabY = -1.0
            SearchX = -1.0
            SearchY = -1.0
            ResultX = -1.0
            ResultY = -1.0
        }
    }
}

function Save-Config([object]$Config) {
    $Config | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $ConfigPath -Encoding UTF8
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

# ---------------------------------------------------------------------------
# 카카오톡 창 제어
# ---------------------------------------------------------------------------
function Get-KakaoProcesses {
    @(Get-Process -Name KakaoTalk -ErrorAction SilentlyContinue)
}

function Get-MainKakaoWindow([object]$Calibration) {
    $candidates = @()
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if (-not $window.Visible) { continue }
            if ($window.Width -lt 240 -or $window.Height -lt 320) { continue }
            $score = 0
            if ($window.Title -eq '카카오톡' -or $window.Title -eq 'KakaoTalk') { $score += 1000 }
            if ($Calibration.WindowClass -and $window.ClassName -eq $Calibration.WindowClass) { $score += 300 }
            if ([int]$Calibration.Width -gt 0) {
                $delta = [Math]::Abs($window.Width - [int]$Calibration.Width) + [Math]::Abs($window.Height - [int]$Calibration.Height)
                $score += [Math]::Max(0, 250 - $delta)
            }
            # 세로로 긴 창일수록 채팅 목록 창일 가능성이 큽니다.
            if ($window.Height -gt $window.Width) { $score += 120 }
            $candidates += [pscustomobject]@{ Window = $window; Score = $score; Area = ($window.Width * $window.Height) }
        }
    }
    if ($candidates.Count -eq 0) { return $null }
    return ($candidates | Sort-Object -Property Score, Area -Descending | Select-Object -First 1).Window
}

function Enter-KakaoForeground([object]$Window) {
    [void][NativeKakao]::ForceForeground($Window.Handle)
    Start-Sleep -Milliseconds 350
    return ([NativeKakao]::GetForegroundWindow() -eq $Window.Handle)
}

function Invoke-RelativeClick([object]$Window, [double]$XRatio, [double]$YRatio, [bool]$DoubleClick = $false) {
    $x = $Window.Rect.Left + [int]($Window.Width * $XRatio)
    $y = $Window.Rect.Top + [int]($Window.Height * $YRatio)
    [NativeKakao]::Click($x, $y, $DoubleClick)
}

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

function Wait-ChatWindow([string]$Room, [IntPtr]$MainHandle, [int]$TimeoutMs = 4000) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $found = Find-ChatWindow $Room $MainHandle
        if ($null -ne $found) { return $found }
        Start-Sleep -Milliseconds 250
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
# 채팅방 목록 읽기
# ---------------------------------------------------------------------------
$script:RoomNoiseLabels = @(
    '친구', '채팅', '오픈채팅', '더보기', '검색', '설정', '채팅방 검색', '새로운 채팅',
    '쇼핑', '보기', '전체', '즐겨찾기', '알림', '메뉴', '이름', '프로필', '읽지 않음',
    '일반채팅', '광고', '카카오톡', '친구 검색', '채팅 검색', '멀티프로필'
)

function ConvertTo-RoomCandidate([string]$RawName) {
    if ([string]::IsNullOrWhiteSpace($RawName)) { return $null }
    $parts = @($RawName -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -eq 0) { return $null }
    $name = $parts[0].Trim()
    if ($name.Length -lt 1 -or $name.Length -gt 60) { return $null }
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

function Get-ChatListScroller([object]$Root) {
    try {
        $condition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::IsScrollPatternAvailableProperty, $true)
        $found = $Root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
        $best = $null
        $bestArea = 0
        foreach ($element in $found) {
            try {
                $pattern = $element.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
                if (-not $pattern.Current.VerticallyScrollable) { continue }
                $rect = $element.Current.BoundingRectangle
                $area = $rect.Width * $rect.Height
                if ($area -gt $bestArea) { $bestArea = $area; $best = $element }
            } catch { }
        }
        return $best
    } catch { return $null }
}

function Get-VisibleRoomCandidates([object]$MainWindow) {
    $results = New-Object System.Collections.Generic.List[string]
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($MainWindow.Handle)
    if ($null -eq $root) { return @() }

    $listItemCondition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
        [System.Windows.Automation.ControlType]::ListItem)
    try {
        $items = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $listItemCondition)
        foreach ($item in $items) {
            try {
                $candidate = ConvertTo-RoomCandidate ([string]$item.Current.Name)
                if ($candidate -and -not $results.Contains($candidate)) { $results.Add($candidate) }
            } catch { }
        }
    } catch { }

    # 일부 카카오톡 버전은 채팅 행을 ListItem 으로 노출하지 않아 텍스트 요소를 보조로 읽습니다.
    if ($results.Count -lt 2) {
        $textCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::Text)
        try {
            $texts = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $textCondition)
            $leftLimit = $MainWindow.Rect.Left + 55
            $rightLimit = $MainWindow.Rect.Right - 45
            $topLimit = $MainWindow.Rect.Top + 45
            $bottomLimit = $MainWindow.Rect.Bottom - 20
            foreach ($element in $texts) {
                try {
                    $rect = $element.Current.BoundingRectangle
                    if ($rect.Left -lt $leftLimit -or $rect.Left -gt $rightLimit) { continue }
                    if ($rect.Top -lt $topLimit -or $rect.Top -gt $bottomLimit) { continue }
                    $candidate = ConvertTo-RoomCandidate ([string]$element.Current.Name)
                    if ($candidate -and -not $results.Contains($candidate)) { $results.Add($candidate) }
                } catch { }
            }
        } catch { }
    }
    return @($results)
}

function Move-ChatList([object]$Scroller, [object]$MainWindow, [string]$Direction) {
    if ($null -ne $Scroller) {
        try {
            $pattern = $Scroller.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
            $amount = if ($Direction -eq 'down') { [System.Windows.Automation.ScrollAmount]::LargeIncrement } else { [System.Windows.Automation.ScrollAmount]::LargeDecrement }
            $pattern.ScrollVertical($amount)
            return $true
        } catch { }
    }
    $x = $MainWindow.Rect.Left + [int]($MainWindow.Width * 0.70)
    $y = $MainWindow.Rect.Top + [int]($MainWindow.Height * 0.60)
    $delta = if ($Direction -eq 'down') { -720 } else { 720 }
    [NativeKakao]::Scroll($x, $y, $delta)
    return $false
}

function Reset-ChatList([object]$Scroller, [object]$MainWindow, [int]$Pages) {
    if ($null -ne $Scroller) {
        try {
            $pattern = $Scroller.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
            $pattern.SetScrollPercent(-1, 0)
            return
        } catch { }
    }
    for ($i = 0; $i -lt ($Pages + 3); $i++) { [void](Move-ChatList $null $MainWindow 'up') }
}

function Get-KakaoRoomNames([object]$Config) {
    $main = Get-MainKakaoWindow $Config.Calibration
    if ($null -eq $main) { throw '카카오톡 메인 창을 찾지 못했습니다. PC 카카오톡을 실행하고 채팅 목록을 화면에 띄워 주세요.' }
    [void](Enter-KakaoForeground $main)

    # 채팅 탭이 보정되어 있으면 채팅 목록으로 먼저 이동합니다.
    if ([double]$Config.Calibration.ChatTabX -ge 0 -and [double]$Config.Calibration.ChatTabY -ge 0) {
        Invoke-RelativeClick $main ([double]$Config.Calibration.ChatTabX) ([double]$Config.Calibration.ChatTabY)
        Start-Sleep -Milliseconds 600
    }

    $root = [System.Windows.Automation.AutomationElement]::FromHandle($main.Handle)
    $scroller = if ($null -ne $root) { Get-ChatListScroller $root } else { $null }

    $all = New-Object System.Collections.Generic.List[string]
    $noChangeCount = 0
    $maxPages = [Math]::Max(1, [Math]::Min(50, [int]$Config.ScanPages))
    for ($page = 0; $page -lt $maxPages; $page++) {
        $before = $all.Count
        foreach ($candidate in @(Get-VisibleRoomCandidates $main)) {
            if (-not $all.Contains([string]$candidate)) { $all.Add([string]$candidate) }
        }
        if ($all.Count -eq $before) { $noChangeCount++ } else { $noChangeCount = 0 }
        if ($noChangeCount -ge 2) { break }
        [void](Move-ChatList $scroller $main 'down')
        Start-Sleep -Milliseconds 650
    }

    Reset-ChatList $scroller $main $maxPages
    Start-Sleep -Milliseconds 300
    return @($all | Sort-Object -Unique)
}

# ---------------------------------------------------------------------------
# 발송
# ---------------------------------------------------------------------------
function Invoke-OneRoom([string]$Room, [object]$Config) {
    $main = Get-MainKakaoWindow $Config.Calibration
    if ($null -eq $main) { throw '카카오톡 메인 창을 찾지 못했습니다. 채팅 목록을 열어 주세요.' }

    if (-not (Enter-KakaoForeground $main)) {
        Write-RunLog "경고: 카카오톡 창을 앞으로 가져오지 못했습니다. 계속 시도합니다."
    }

    Invoke-RelativeClick $main ([double]$Config.Calibration.ChatTabX) ([double]$Config.Calibration.ChatTabY)
    Start-Sleep -Milliseconds 450
    Invoke-RelativeClick $main ([double]$Config.Calibration.SearchX) ([double]$Config.Calibration.SearchY)
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Set-ClipboardTextSafe $Room
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 1200
    Invoke-RelativeClick $main ([double]$Config.Calibration.ResultX) ([double]$Config.Calibration.ResultY) $true

    $chat = Wait-ChatWindow $Room $main.Handle 5000
    if ($null -eq $chat) {
        Write-RunLog "건너뜀: '$Room' — 열린 채팅창 제목이 정확히 일치하지 않습니다."
        return $false
    }

    if ([bool]$Config.DryRun) {
        Write-RunLog "확인 성공: '$Room' (전송하지 않음)"
        Close-ChatWindow $chat
        return $true
    }

    [void][NativeKakao]::ForceForeground($chat.Handle)
    Start-Sleep -Milliseconds 400
    [void](Set-ChatInputFocus $chat)

    $message = [string]$Config.Message
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        Set-ClipboardTextSafe $message
        [System.Windows.Forms.SendKeys]::SendWait('^v')
        Start-Sleep -Milliseconds 300
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Start-Sleep -Milliseconds 800
    }

    $waitMs = [Math]::Max(600, [int]$Config.AttachmentWaitMs)
    foreach ($attachment in @($Config.Attachments)) {
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

function Test-Calibration([object]$Config) {
    return ([double]$Config.Calibration.ChatTabX -ge 0 -and
            [double]$Config.Calibration.SearchX -ge 0 -and
            [double]$Config.Calibration.ResultX -ge 0)
}

function Invoke-Broadcast([object]$Config) {
    $rooms = @($Config.Rooms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($rooms.Count -eq 0) { throw '채팅방을 한 개 이상 선택해 주세요.' }
    if ($rooms.Count -gt 50) { throw '안전을 위해 한 번에 최대 50개 방까지만 처리합니다.' }
    if (-not (Test-Calibration $Config)) { throw '설정 화면에서 채팅탭, 검색창, 첫 검색 결과 위치를 모두 보정해 주세요.' }
    foreach ($attachment in @($Config.Attachments)) {
        if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
    }

    $mode = if ([bool]$Config.DryRun) { '확인 전용' } else { '실제 발송' }
    Write-RunLog ("작업 시작: 방 {0}개 / 모드={1}" -f $rooms.Count, $mode)
    $success = 0
    for ($i = 0; $i -lt $rooms.Count; $i++) {
        try { if (Invoke-OneRoom $rooms[$i] $Config) { $success++ } }
        catch { Write-RunLog "오류: '$($rooms[$i])' — $($_.Exception.Message)" }
        if ($i -lt ($rooms.Count - 1)) { Start-Sleep -Seconds ([Math]::Max(5, [int]$Config.IntervalSeconds)) }
    }
    Write-RunLog ("작업 종료: 성공 {0}/{1}" -f $success, $rooms.Count)
    return $success
}

function Invoke-TestSend([object]$Config, [bool]$DryRun) {
    $room = ([string]$Config.TestRoom).Trim()
    if (-not $room) { throw '테스트 채팅방 이름을 입력해 주세요.' }
    if (-not (Test-Calibration $Config)) { throw '설정 화면에서 세 위치를 먼저 보정해 주세요.' }
    if (-not $DryRun) {
        foreach ($attachment in @($Config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }
    $testConfig = [pscustomobject]@{
        Message = $Config.Message
        Attachments = @($Config.Attachments)
        DryRun = $DryRun
        AttachmentWaitMs = $Config.AttachmentWaitMs
        Calibration = $Config.Calibration
    }
    $label = if ($DryRun) { '테스트(확인만)' } else { '테스트 발송' }
    Write-RunLog "$label 시작: '$room'"
    $ok = Invoke-OneRoom $room $testConfig
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
        if ($file.Name -in @('config.json')) { continue }
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
# 첫 사용자 가이드 투어 내용
# ---------------------------------------------------------------------------
$script:TourSteps = @(
    @{
        Page = 'compose'
        Title = '카카오 발송기에 오신 것을 환영합니다'
        Body  = "선택한 카카오톡 채팅방에 같은 문구와 사진을 한 번에, 또는 예약한 시각에 보내 주는 프로그램입니다.`r`n`r`n처음 준비는 5분이면 끝납니다. 다음을 눌러 순서대로 따라와 주세요."
    },
    @{
        Page = 'settings'
        Title = '1단계 · 화면 위치 보정'
        Body  = "이 프로그램은 카카오톡을 사람처럼 클릭해서 동작합니다. 그래서 카카오톡 창의 어디를 눌러야 하는지 딱 세 곳만 알려 주면 됩니다.`r`n`r`n[설정] 화면에서 ① 채팅탭 ② 검색창 ③ 첫 검색결과 버튼을 차례로 누르고, 안내에 따라 그 위치에 마우스를 올린 뒤 F8을 누르세요.`r`n`r`n처음 한 번만 하면 되고, 카카오톡 창 크기를 바꾸면 다시 하면 됩니다."
    },
    @{
        Page = 'rooms'
        Title = '2단계 · 보낼 채팅방 고르기'
        Body  = "[채팅방 선택] 화면에서 [카카오톡에서 읽기]를 누르면 채팅 목록을 훑어 방 이름을 가져옵니다. 읽는 동안에는 마우스와 키보드를 사용하지 마세요.`r`n`r`n카카오톡 버전에 따라 최근 메시지 미리보기가 방 이름처럼 섞여 들어올 수 있습니다. 체크하기 전에 눈으로 확인하고, 틀린 이름은 [이름 수정]으로 고치거나 [직접 추가]로 정확히 입력하세요."
    },
    @{
        Page = 'compose'
        Title = '3단계 · 문구와 사진 준비'
        Body  = "[발송 준비] 화면에 보낼 문구를 적고, 사진이나 파일을 추가합니다.`r`n`r`n문구가 먼저 한 개의 메시지로 전송되고, 그다음 첨부가 목록 순서대로 하나씩 전송됩니다. 순서는 [위로] [아래로] 버튼으로 바꿀 수 있습니다.`r`n`r`n입력한 내용은 자동으로 저장되니 따로 저장하지 않아도 됩니다."
    },
    @{
        Page = 'run'
        Title = '4단계 · 먼저 테스트해 보기'
        Body  = "가장 중요한 단계입니다. 여러 방에 한꺼번에 보내기 전에 [테스트 모드]로 한 방에만 똑같이 보내 결과를 확인하세요.`r`n`r`n기본값은 '나와의 채팅'이라 아무에게도 가지 않습니다. [테스트 발송]을 누르면 실제와 똑같은 방식으로 문구와 사진이 전송되므로, 줄바꿈이나 사진 순서를 미리 눈으로 볼 수 있습니다.`r`n`r`n[방 확인만]은 채팅창을 열어 이름만 맞는지 확인하고 전송은 하지 않습니다."
    },
    @{
        Page = 'run'
        Title = '5단계 · 지금 실행 또는 예약'
        Body  = "[지금 실행]은 바로 보내고, [예약 시작]은 지정한 시각에 자동으로 보냅니다.`r`n`r`n예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 하고, 화면 잠금이나 절전 상태에서는 동작하지 않습니다.`r`n`r`n방 사이 간격은 최소 5초이며, 한 번에 최대 50개 방까지만 처리합니다."
    },
    @{
        Page = 'log'
        Title = '마지막 · 안전하게 쓰기'
        Body  = "실행 중에는 마우스와 키보드를 사용하지 마세요. 클릭이 엉뚱한 곳으로 가면 잘못된 방에 전송될 수 있습니다.`r`n`r`n성공·건너뜀·오류는 모두 [실행 기록]에 남고 날짜별 파일로도 저장됩니다.`r`n`r`n수신에 동의한 분들이 있는 채팅방에서만 사용하세요. 반복적인 대량 발송은 카카오톡 이용 제한의 원인이 될 수 있습니다.`r`n`r`n이 가이드는 [설정] → [가이드 다시 보기]에서 언제든 다시 볼 수 있습니다."
    }
)

# ---------------------------------------------------------------------------
# 자체 점검
# ---------------------------------------------------------------------------
$script:config = Import-AppConfig

if ($SelfTest) {
    $required = @('Rooms', 'KnownRooms', 'Message', 'Attachments', 'ScheduledAt', 'IntervalSeconds', 'DryRun', 'ScanPages', 'TestRoom', 'AttachmentWaitMs', 'AutoCheckUpdate', 'TourDone', 'Calibration')
    foreach ($name in $required) {
        if ($null -eq $script:config.PSObject.Properties[$name]) { throw "필수 설정 항목 누락: $name" }
    }
    foreach ($name in @('WindowClass', 'WindowTitle', 'Width', 'Height', 'ChatTabX', 'ChatTabY', 'SearchX', 'SearchY', 'ResultX', 'ResultY')) {
        if ($null -eq $script:config.Calibration.PSObject.Properties[$name]) { throw "필수 보정 항목 누락: $name" }
    }
    if ($null -ne (ConvertTo-RoomCandidate '오후 3:20')) { throw '후보 필터 자체 점검 실패 (시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '12:30')) { throw '후보 필터 자체 점검 실패 (숫자 시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '채팅')) { throw '후보 필터 자체 점검 실패 (메뉴)' }
    if ((ConvertTo-RoomCandidate "테스트 채팅방`r`n안녕하세요") -ne '테스트 채팅방') { throw '후보 추출 자체 점검 실패' }
    if (-not (Test-RoomTitle '우리반 공지방 (24)' '우리반 공지방')) { throw '창 제목 비교 자체 점검 실패' }
    if (Test-RoomTitle '우리반 공지방 2기' '우리반 공지방') { throw '창 제목 비교가 너무 느슨합니다' }
    if ((ConvertTo-AppVersion 'v3.1.0') -le (ConvertTo-AppVersion '3.0.0')) { throw '버전 비교 자체 점검 실패' }
    if ($null -ne (ConvertTo-AppVersion 'nightly')) { throw '버전 파싱 자체 점검 실패' }
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

# ---------------------------------------------------------------------------
# 디자인 토큰
# ---------------------------------------------------------------------------
function New-Rgb([int]$R, [int]$G, [int]$B) { [System.Drawing.Color]::FromArgb($R, $G, $B) }

$Theme = @{
    Sidebar    = (New-Rgb 28 29 34)
    SidebarHi  = (New-Rgb 44 46 55)
    NavIdle    = (New-Rgb 156 161 170)
    Accent     = (New-Rgb 254 229 0)
    AccentInk  = (New-Rgb 26 26 30)
    Bg         = (New-Rgb 244 245 247)
    Card       = [System.Drawing.Color]::White
    Border     = (New-Rgb 226 229 233)
    Ink        = (New-Rgb 23 23 28)
    Muted      = (New-Rgb 118 124 134)
    Success    = (New-Rgb 22 163 74)
    Danger     = (New-Rgb 214 62 66)
    Info       = (New-Rgb 37 99 235)
    FieldEdge  = (New-Rgb 214 218 224)
}

$FontBase   = New-Object System.Drawing.Font('Malgun Gothic', 9)
$FontSmall  = New-Object System.Drawing.Font('Malgun Gothic', 8.5)
$FontStrong = New-Object System.Drawing.Font('Malgun Gothic', 9, [System.Drawing.FontStyle]::Bold)
$FontCard   = New-Object System.Drawing.Font('Malgun Gothic', 10.5, [System.Drawing.FontStyle]::Bold)
$FontPage   = New-Object System.Drawing.Font('Malgun Gothic', 14, [System.Drawing.FontStyle]::Bold)
$FontLogo   = New-Object System.Drawing.Font('Malgun Gothic', 11, [System.Drawing.FontStyle]::Bold)
$FontMono   = New-Object System.Drawing.Font('Consolas', 9)

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
        $label.Location = New-Object System.Drawing.Point(20, 16)
        $label.Size = New-Object System.Drawing.Size(($W - 40), 24)
        $panel.Controls.Add($label)
    }
    if ($Subtitle) {
        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = $Subtitle
        $sub.Font = $FontSmall
        $sub.ForeColor = $Theme.Muted
        $sub.BackColor = $Theme.Card
        $sub.Location = New-Object System.Drawing.Point(20, 40)
        $sub.Size = New-Object System.Drawing.Size(($W - 40), 20)
        $panel.Controls.Add($sub)
    }
    return $panel
}

function New-CardLabel([object]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 22, [object]$Font = $null, [object]$Color = $null) {
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
        $box.Location = New-Object System.Drawing.Point(12, 10)
        $box.Size = New-Object System.Drawing.Size(($W - 26), ($H - 20))
    } else {
        $box.Location = New-Object System.Drawing.Point(12, 0)
        $box.Width = $W - 24
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
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 245 220 0)
            # 비활성 상태에서도 노란색이 남아 눌러도 되는 것처럼 보이는 문제를 막습니다.
            $button.Add_EnabledChanged({
                if ($this.Enabled) { $this.BackColor = $Theme.Accent; $this.ForeColor = $Theme.AccentInk }
                else { $this.BackColor = (New-Rgb 236 238 241); $this.ForeColor = (New-Rgb 158 163 171) }
            })
        }
        'danger' {
            $button.BackColor = [System.Drawing.Color]::White
            $button.ForeColor = $Theme.Danger
            $button.FlatAppearance.BorderSize = 1
            $button.FlatAppearance.BorderColor = (New-Rgb 240 200 200)
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 253 242 242)
        }
        'ghost' {
            $button.BackColor = $Theme.Card
            $button.ForeColor = $Theme.Muted
            $button.FlatAppearance.BorderSize = 0
            $button.FlatAppearance.MouseOverBackColor = $Theme.Bg
        }
        default {
            $button.BackColor = [System.Drawing.Color]::White
            $button.ForeColor = $Theme.Ink
            $button.FlatAppearance.BorderSize = 1
            $button.FlatAppearance.BorderColor = $Theme.FieldEdge
            $button.FlatAppearance.MouseOverBackColor = (New-Rgb 246 247 249)
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
$script:form = New-Object System.Windows.Forms.Form
$script:form.Text = "카카오 발송기  ·  v$($script:AppVersion)"
$script:form.ClientSize = New-Object System.Drawing.Size(1000, 700)
$script:form.StartPosition = 'CenterScreen'
$script:form.FormBorderStyle = 'FixedSingle'
$script:form.MaximizeBox = $false
$script:form.AutoScaleMode = 'None'
$script:form.BackColor = $Theme.Bg
$script:form.Font = $FontBase

# ----- 사이드바 -----
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = New-Object System.Drawing.Point(0, 0)
$sidebar.Size = New-Object System.Drawing.Size(210, 700)
$sidebar.BackColor = $Theme.Sidebar
$script:form.Controls.Add($sidebar)

$logo = New-Object System.Windows.Forms.Panel
$logo.Location = New-Object System.Drawing.Point(0, 0)
$logo.Size = New-Object System.Drawing.Size(210, 96)
$logo.BackColor = $Theme.Sidebar
$logo.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $e.Graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
    $rect = New-Object System.Drawing.Rectangle(24, 26, 40, 40)
    $path = Get-RoundedPath $rect 12
    $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
    $e.Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
    $inkBrush = New-Object System.Drawing.SolidBrush ($Theme.AccentInk)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
    $e.Graphics.DrawString('톡', $FontLogo, $inkBrush, (New-Object System.Drawing.RectangleF(24, 26, 40, 40)), $format)
    $inkBrush.Dispose()
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::White)
    $e.Graphics.DrawString('카카오 발송기', $FontLogo, $white, 76, 30)
    $white.Dispose()
    $muted = New-Object System.Drawing.SolidBrush ($Theme.NavIdle)
    $e.Graphics.DrawString("v$($script:AppVersion)", $FontSmall, $muted, 78, 54)
    $muted.Dispose()
})
$sidebar.Controls.Add($logo)

$script:NavPages = @(
    @{ Key = 'compose';  Text = '발송 준비';   Title = '발송 준비' },
    @{ Key = 'rooms';    Text = '채팅방 선택'; Title = '채팅방 선택' },
    @{ Key = 'run';      Text = '실행 · 예약'; Title = '실행 · 예약' },
    @{ Key = 'settings'; Text = '설정';        Title = '설정' },
    @{ Key = 'log';      Text = '실행 기록';   Title = '실행 기록' }
)

$navY = 112
foreach ($page in $script:NavPages) {
    $script:navText[$page.Key] = $page.Text
    $item = New-Object System.Windows.Forms.Panel
    $item.Location = New-Object System.Drawing.Point(0, $navY)
    $item.Size = New-Object System.Drawing.Size(210, 46)
    $item.BackColor = $Theme.Sidebar
    $item.Cursor = [System.Windows.Forms.Cursors]::Hand
    $item.Tag = $page.Key
    $item.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $key = [string]$sender.Tag
        $isActive = ($script:activePage -eq $key)
        if ($isActive) {
            $fill = New-Object System.Drawing.SolidBrush ($Theme.SidebarHi)
            $e.Graphics.FillRectangle($fill, 0, 0, $sender.Width, $sender.Height)
            $fill.Dispose()
            $bar = New-Object System.Drawing.SolidBrush ($Theme.Accent)
            $e.Graphics.FillRectangle($bar, 0, 8, 4, ($sender.Height - 16))
            $bar.Dispose()
        }
        $color = if ($isActive) { [System.Drawing.Color]::White } else { $Theme.NavIdle }
        $font = if ($isActive) { $FontStrong } else { $FontBase }
        $brush = New-Object System.Drawing.SolidBrush ($color)
        $format = New-Object System.Drawing.StringFormat
        $format.LineAlignment = 'Center'
        $e.Graphics.DrawString($script:navText[$key], $font, $brush, (New-Object System.Drawing.RectangleF(28, 0, 170, $sender.Height)), $format)
        $brush.Dispose()
    })
    $item.Add_Click({ Show-AppPage ([string]$this.Tag) })
    $sidebar.Controls.Add($item)
    $script:navItems += $item
    $navY += 46
}

$script:pnlUpdate = New-Object System.Windows.Forms.Panel
$script:pnlUpdate.Location = New-Object System.Drawing.Point(16, 596)
$script:pnlUpdate.Size = New-Object System.Drawing.Size(178, 44)
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
    $ink = New-Object System.Drawing.SolidBrush ($Theme.AccentInk)
    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = 'Center'; $format.LineAlignment = 'Center'
    $text = if ($script:latestRelease) { "새 버전 $($script:latestRelease.Tag) 받기" } else { '업데이트 확인' }
    $e.Graphics.DrawString($text, $FontStrong, $ink, (New-Object System.Drawing.RectangleF(0, 0, $sender.Width, $sender.Height)), $format)
    $ink.Dispose()
})
$script:pnlUpdate.Add_Click({ Show-AppPage 'settings' })
$sidebar.Controls.Add($script:pnlUpdate)

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "수신에 동의한 채팅방에서만`r`n사용하세요."
$lblHint.Location = New-Object System.Drawing.Point(24, 650)
$lblHint.Size = New-Object System.Drawing.Size(170, 40)
$lblHint.BackColor = $Theme.Sidebar
$lblHint.ForeColor = (New-Rgb 110 115 124)
$lblHint.Font = $FontSmall
$sidebar.Controls.Add($lblHint)

# ----- 헤더 -----
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(210, 0)
$header.Size = New-Object System.Drawing.Size(790, 72)
$header.BackColor = $Theme.Bg
$script:form.Controls.Add($header)

$script:lblPageTitle = New-Object System.Windows.Forms.Label
$script:lblPageTitle.Text = '발송 준비'
$script:lblPageTitle.Font = $FontPage
$script:lblPageTitle.ForeColor = $Theme.Ink
$script:lblPageTitle.BackColor = $Theme.Bg
$script:lblPageTitle.Location = New-Object System.Drawing.Point(24, 22)
$script:lblPageTitle.Size = New-Object System.Drawing.Size(420, 34)
$header.Controls.Add($script:lblPageTitle)

$script:pillStatus = New-Object System.Windows.Forms.Panel
$script:pillStatus.Location = New-Object System.Drawing.Point(486, 20)
$script:pillStatus.Size = New-Object System.Drawing.Size(280, 36)
$script:pillStatus.BackColor = $Theme.Bg
$script:pillStatus.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    switch ($script:statusKind) {
        'run'   { $fill = New-Rgb 255 247 214; $ink = New-Rgb 146 104 0 }
        'wait'  { $fill = New-Rgb 227 238 255; $ink = $Theme.Info }
        'done'  { $fill = New-Rgb 226 246 232; $ink = $Theme.Success }
        'error' { $fill = New-Rgb 253 235 235; $ink = $Theme.Danger }
        default { $fill = [System.Drawing.Color]::White; $ink = $Theme.Muted }
    }
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $path = Get-RoundedPath $rect 18
    $brush = New-Object System.Drawing.SolidBrush ($fill)
    $pen = New-Object System.Drawing.Pen ($Theme.Border)
    $e.Graphics.FillPath($brush, $path)
    $e.Graphics.DrawPath($pen, $path)
    $brush.Dispose(); $pen.Dispose(); $path.Dispose()
    $dot = New-Object System.Drawing.SolidBrush ($ink)
    $e.Graphics.FillEllipse($dot, 16, ([int]($sender.Height / 2) - 4), 8, 8)
    $format = New-Object System.Drawing.StringFormat
    $format.LineAlignment = 'Center'
    $e.Graphics.DrawString($script:statusText, $FontBase, $dot, (New-Object System.Drawing.RectangleF(32, 0, ($sender.Width - 40), $sender.Height)), $format)
    $dot.Dispose()
})
$header.Controls.Add($script:pillStatus)

# ----- 페이지 컨테이너 -----
$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Location = New-Object System.Drawing.Point(210, 72)
$pageHost.Size = New-Object System.Drawing.Size(790, 628)
$pageHost.BackColor = $Theme.Bg
$script:form.Controls.Add($pageHost)

$script:pages = @{}
function New-Page([string]$Key) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 0)
    $panel.Size = New-Object System.Drawing.Size(790, 628)
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

$cardMessage = New-Card $pageCompose 24 8 742 250 '발송 문구' '카카오톡에 붙여넣기로 전송됩니다. 줄바꿈도 그대로 유지됩니다.'
$script:txtMessage = New-AppTextBox $cardMessage 20 74 702 156 $true
$script:txtMessage.Text = [string]$script:config.Message
$script:lblMessageCount = New-CardLabel $cardMessage '' 20 232 702 18 $FontSmall $Theme.Muted

$cardFiles = New-Card $pageCompose 24 270 742 300 '첨부 사진 · 파일' '문구를 보낸 뒤 아래 순서대로 하나씩 전송합니다.'
$frameFiles = New-FieldFrame $cardFiles 20 74 560 206
$script:lstFiles = New-Object System.Windows.Forms.ListBox
$script:lstFiles.BorderStyle = 'None'
$script:lstFiles.Font = $FontBase
$script:lstFiles.Location = New-Object System.Drawing.Point(10, 10)
$script:lstFiles.Size = New-Object System.Drawing.Size(540, 186)
$frameFiles.Controls.Add($script:lstFiles)
foreach ($file in @($script:config.Attachments)) { [void]$script:lstFiles.Items.Add([string]$file) }

$btnAddFile    = New-AppButton $cardFiles '파일 추가' 596 74 126 38 'primary'
$btnFileUp     = New-AppButton $cardFiles '위로' 596 120 126 34
$btnFileDown   = New-AppButton $cardFiles '아래로' 596 158 126 34
$btnRemoveFile = New-AppButton $cardFiles '선택 제거' 596 202 126 34 'danger'
[void](New-CardLabel $cardFiles "사진은 미리보기 확인 후 전송됩니다." 596 242 126 50 $FontSmall $Theme.Muted)

$lblComposeHint = New-CardLabel $pageCompose '입력한 내용은 자동 저장됩니다. 실제 발송 전에 [실행 · 예약] 화면에서 테스트 발송으로 결과를 먼저 확인하세요.' 24 582 742 36 $FontSmall $Theme.Muted
$lblComposeHint.BackColor = $Theme.Bg

# ===========================================================================
# 페이지 2 — 채팅방 선택
# ===========================================================================
$pageRooms = New-Page 'rooms'
$cardRooms = New-Card $pageRooms 24 8 742 600 '발송 대상 채팅방' '카카오톡 채팅 목록을 읽어옵니다. 읽는 동안 마우스와 키보드를 사용하지 마세요.'

$script:txtRoomFilter = New-AppTextBox $cardRooms 20 74 240 38
$btnScanRooms  = New-AppButton $cardRooms '카카오톡에서 읽기' 272 74 158 38 'primary'
$btnAddRoom    = New-AppButton $cardRooms '직접 추가' 438 74 90 38
$btnEditRoom   = New-AppButton $cardRooms '이름 수정' 536 74 90 38
$btnDeleteRoom = New-AppButton $cardRooms '삭제' 634 74 88 38 'danger'

$frameRooms = New-FieldFrame $cardRooms 20 124 702 372
$script:lstRooms = New-Object System.Windows.Forms.CheckedListBox
$script:lstRooms.BorderStyle = 'None'
$script:lstRooms.CheckOnClick = $true
$script:lstRooms.Font = $FontBase
$script:lstRooms.Location = New-Object System.Drawing.Point(10, 10)
$script:lstRooms.Size = New-Object System.Drawing.Size(682, 352)
$frameRooms.Controls.Add($script:lstRooms)

$btnCheckAll  = New-AppButton $cardRooms '전체 선택' 20 508 96 34
$btnCheckNone = New-AppButton $cardRooms '전체 해제' 124 508 96 34
$script:lblRoomCount = New-CardLabel $cardRooms '선택 0개 / 전체 0개' 232 512 200 26 $FontStrong $Theme.Ink
[void](New-CardLabel $cardRooms '최대 탐색 페이지' 470 512 110 26 $FontSmall $Theme.Muted)
$script:numScanPages = New-Object System.Windows.Forms.NumericUpDown
$script:numScanPages.Minimum = 1
$script:numScanPages.Maximum = 50
$script:numScanPages.Value = [Math]::Max(1, [Math]::Min(50, [int]$script:config.ScanPages))
$script:numScanPages.Location = New-Object System.Drawing.Point(586, 510)
$script:numScanPages.Size = New-Object System.Drawing.Size(66, 28)
$script:numScanPages.Font = $FontBase
$script:numScanPages.BorderStyle = 'FixedSingle'
$cardRooms.Controls.Add($script:numScanPages)

[void](New-CardLabel $cardRooms '자동 인식 결과에는 최근 메시지 미리보기가 섞일 수 있습니다. 체크하기 전에 방 이름이 맞는지 확인하고, 틀리면 [이름 수정]으로 고치세요. 동명 채팅방은 구분되지 않으니 카카오톡에서 이름을 다르게 바꿔 주세요.' 20 548 702 40 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 3 — 실행 · 예약
# ===========================================================================
$pageRun = New-Page 'run'

$cardMode = New-Card $pageRun 24 8 742 146 '발송 방식'
$script:rdoLive = New-Object System.Windows.Forms.RadioButton
$script:rdoLive.Text = '실제 발송 — 선택한 모든 방에 문구와 첨부를 보냅니다.'
$script:rdoLive.Location = New-Object System.Drawing.Point(20, 54)
$script:rdoLive.Size = New-Object System.Drawing.Size(690, 26)
$script:rdoLive.BackColor = $Theme.Card
$script:rdoLive.Font = $FontBase
$cardMode.Controls.Add($script:rdoLive)

$script:rdoDry = New-Object System.Windows.Forms.RadioButton
$script:rdoDry.Text = '확인 전용 — 방을 하나씩 열어 이름만 확인하고 전송하지 않습니다.'
$script:rdoDry.Location = New-Object System.Drawing.Point(20, 86)
$script:rdoDry.Size = New-Object System.Drawing.Size(690, 26)
$script:rdoDry.BackColor = $Theme.Card
$script:rdoDry.Font = $FontBase
$cardMode.Controls.Add($script:rdoDry)
if ([bool]$script:config.DryRun) { $script:rdoDry.Checked = $true } else { $script:rdoLive.Checked = $true }

$cardTest = New-Card $pageRun 24 166 742 164 '테스트 모드' '실제 발송 전에 지정한 한 방에만 똑같이 보내 결과를 확인합니다.'
[void](New-CardLabel $cardTest '테스트 채팅방 이름' 20 76 160 22 $FontSmall $Theme.Muted)
$script:txtTestRoom = New-AppTextBox $cardTest 20 100 400 38
$script:txtTestRoom.Text = [string]$script:config.TestRoom
$btnTestSend = New-AppButton $cardTest '테스트 발송' 438 100 136 38 'primary'
$btnTestDry  = New-AppButton $cardTest '방 확인만' 582 100 140 38

$cardSchedule = New-Card $pageRun 24 342 742 278 '지금 실행 및 예약'
[void](New-CardLabel $cardSchedule '예약 시각' 20 54 100 22 $FontSmall $Theme.Muted)
$script:dtSchedule = New-Object System.Windows.Forms.DateTimePicker
$script:dtSchedule.Format = 'Custom'
$script:dtSchedule.CustomFormat = 'yyyy-MM-dd  HH:mm:ss'
$script:dtSchedule.ShowUpDown = $true
$script:dtSchedule.Location = New-Object System.Drawing.Point(20, 78)
$script:dtSchedule.Size = New-Object System.Drawing.Size(214, 30)
$script:dtSchedule.Font = $FontBase
try { $script:dtSchedule.Value = [datetime]::ParseExact([string]$script:config.ScheduledAt, 'yyyy-MM-dd HH:mm:ss', $null) }
catch { $script:dtSchedule.Value = (Get-Date).AddMinutes(10) }
if ($script:dtSchedule.Value -lt $script:dtSchedule.MinDate) { $script:dtSchedule.Value = (Get-Date).AddMinutes(10) }
$cardSchedule.Controls.Add($script:dtSchedule)

[void](New-CardLabel $cardSchedule '방 사이 간격(초)' 260 54 120 22 $FontSmall $Theme.Muted)
$script:numInterval = New-Object System.Windows.Forms.NumericUpDown
$script:numInterval.Minimum = 5
$script:numInterval.Maximum = 300
$script:numInterval.Value = [Math]::Max(5, [Math]::Min(300, [int]$script:config.IntervalSeconds))
$script:numInterval.Location = New-Object System.Drawing.Point(260, 78)
$script:numInterval.Size = New-Object System.Drawing.Size(84, 28)
$script:numInterval.Font = $FontBase
$script:numInterval.BorderStyle = 'FixedSingle'
$cardSchedule.Controls.Add($script:numInterval)

$btnRunNow    = New-AppButton $cardSchedule '지금 실행' 20 130 152 44 'primary'
$btnArm       = New-AppButton $cardSchedule '예약 시작' 184 130 152 44
$btnCancelArm = New-AppButton $cardSchedule '예약 취소' 348 130 152 44
$btnSave      = New-AppButton $cardSchedule '설정 저장' 512 130 152 44 'ghost'
$btnCancelArm.Enabled = $false

$script:lblCountdown = New-CardLabel $cardSchedule '예약이 설정되지 않았습니다.' 20 188 702 24 $FontStrong $Theme.Muted
[void](New-CardLabel $cardSchedule '예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 합니다. 화면 잠금·절전 상태에서는 동작하지 않으며, 실행 중에는 마우스와 키보드를 사용하지 마세요.' 20 216 702 44 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 4 — 설정
# ===========================================================================
$pageSettings = New-Page 'settings'

$cardCalib = New-Card $pageSettings 24 8 742 210 '화면 위치 보정' '카카오톡 창 크기나 화면 배율을 바꿨다면 다시 보정하세요.'
[void](New-CardLabel $cardCalib '각 버튼을 누른 뒤 안내에 따라 카카오톡의 해당 위치에 마우스를 올리고 F8을 누르세요.' 20 66 702 24 $FontSmall $Theme.Muted)
$btnCalibChat   = New-AppButton $cardCalib '① 채팅탭' 20 98 150 42
$btnCalibSearch = New-AppButton $cardCalib '② 검색창' 182 98 150 42
$btnCalibResult = New-AppButton $cardCalib '③ 첫 검색결과' 344 98 160 42
$script:lblCalibState = New-CardLabel $cardCalib '' 20 152 702 44 $FontSmall $Theme.Muted

$cardUpdate = New-Card $pageSettings 24 226 742 202 '업데이트' "GitHub 저장소 $($script:RepoOwner)/$($script:RepoName) 의 최신 배포본을 확인합니다."
$script:lblUpdateState = New-CardLabel $cardUpdate "현재 버전 v$($script:AppVersion)" 20 70 500 44 $FontBase $Theme.Ink
$btnCheckUpdate  = New-AppButton $cardUpdate '업데이트 확인' 20 122 150 40
$script:btnDoUpdate = New-AppButton $cardUpdate '지금 업데이트' 182 122 150 40 'primary'
$script:btnDoUpdate.Enabled = $false
$btnOpenRepo     = New-AppButton $cardUpdate '저장소 열기' 344 122 150 40
$script:chkAutoUpdate = New-Object System.Windows.Forms.CheckBox
$script:chkAutoUpdate.Text = '시작할 때 자동 확인'
$script:chkAutoUpdate.Checked = [bool]$script:config.AutoCheckUpdate
$script:chkAutoUpdate.Location = New-Object System.Drawing.Point(510, 130)
$script:chkAutoUpdate.Size = New-Object System.Drawing.Size(200, 26)
$script:chkAutoUpdate.BackColor = $Theme.Card
$script:chkAutoUpdate.Font = $FontBase
$cardUpdate.Controls.Add($script:chkAutoUpdate)

$cardFolders = New-Card $pageSettings 24 436 742 172 '도움말 및 관리'
$btnGuide      = New-AppButton $cardFolders '가이드 다시 보기' 20 60 150 40
$btnOpenApp    = New-AppButton $cardFolders '프로그램 폴더 열기' 182 60 170 40
$btnOpenLogs   = New-AppButton $cardFolders '로그 폴더 열기' 364 60 150 40
$btnResetConf  = New-AppButton $cardFolders '설정 초기화' 526 60 150 40 'danger'
[void](New-CardLabel $cardFolders "설정 파일: $ConfigPath" 20 112 702 22 $FontSmall $Theme.Muted)
[void](New-CardLabel $cardFolders '카카오 계정, 비밀번호, 인증 정보는 저장하지 않습니다. 설정은 이 PC 안에만 보관됩니다.' 20 134 702 22 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 5 — 실행 기록
# ===========================================================================
$pageLog = New-Page 'log'
$cardLog = New-Card $pageLog 24 8 742 600 '실행 기록' '날짜별 파일로도 저장됩니다.'
$frameLog = New-FieldFrame $cardLog 20 74 702 456
$script:txtLog = New-Object System.Windows.Forms.TextBox
$script:txtLog.Multiline = $true
$script:txtLog.ReadOnly = $true
$script:txtLog.ScrollBars = 'Vertical'
$script:txtLog.BorderStyle = 'None'
$script:txtLog.BackColor = [System.Drawing.Color]::White
$script:txtLog.Font = $FontMono
$script:txtLog.Location = New-Object System.Drawing.Point(12, 10)
$script:txtLog.Size = New-Object System.Drawing.Size(678, 436)
$frameLog.Controls.Add($script:txtLog)
$btnOpenLogDir = New-AppButton $cardLog '로그 폴더 열기' 20 546 160 38
$btnClearLog   = New-AppButton $cardLog '화면 지우기' 192 546 140 38 'ghost'

# ===========================================================================
# 상태 동기화
# ===========================================================================
function Update-RoomCountLabel {
    $checked = @($script:lstRooms.CheckedItems).Count
    $total = $script:lstRooms.Items.Count
    $script:lblRoomCount.Text = "선택 $($checked)개 / 전체 $($total)개"
}

function Update-CalibrationLabel {
    if (Test-Calibration $script:config) {
        $calibration = $script:config.Calibration
        $script:lblCalibState.Text = "보정 완료 · 기준 창 크기 $([int]$calibration.Width) × $([int]$calibration.Height)"
        $script:lblCalibState.ForeColor = $Theme.Success
    } else {
        $script:lblCalibState.Text = '아직 보정되지 않았습니다. 세 위치를 모두 보정해야 발송할 수 있습니다.'
        $script:lblCalibState.ForeColor = $Theme.Danger
    }
}

function Sync-ConfigFromForm {
    $script:config.Rooms = @($script:lstRooms.CheckedItems | ForEach-Object { [string]$_ })
    $script:config.KnownRooms = @($script:lstRooms.Items | ForEach-Object { [string]$_ })
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
$allRooms = @(@($script:config.KnownRooms) + @($script:config.Rooms) | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object -Unique)
foreach ($room in $allRooms) {
    $index = $script:lstRooms.Items.Add($room)
    if ($selectedSet.ContainsKey($room)) { $script:lstRooms.SetItemChecked($index, $true) }
}
Update-RoomCountLabel
Update-CalibrationLabel
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
$script:lstRooms.Add_ItemCheck({ $script:form.BeginInvoke([Action]{ Sync-ConfigFromForm }) | Out-Null })

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
    for ($i = 0; $i -lt $script:lstRooms.Items.Count; $i++) {
        if (([string]$script:lstRooms.Items[$i]).IndexOf($query, [System.StringComparison]::CurrentCultureIgnoreCase) -ge 0) {
            $script:lstRooms.SelectedIndex = $i
            $script:lstRooms.TopIndex = $i
            break
        }
    }
})
$btnCheckAll.Add_Click({ for ($i = 0; $i -lt $script:lstRooms.Items.Count; $i++) { $script:lstRooms.SetItemChecked($i, $true) }; Sync-ConfigFromForm })
$btnCheckNone.Add_Click({ for ($i = 0; $i -lt $script:lstRooms.Items.Count; $i++) { $script:lstRooms.SetItemChecked($i, $false) }; Sync-ConfigFromForm })
$btnAddRoom.Add_Click({
    $name = [Microsoft.VisualBasic.Interaction]::InputBox('카카오톡에 표시되는 채팅방 이름을 정확히 입력하세요.', '채팅방 직접 추가', '')
    $name = ([string]$name).Trim()
    if ($name -and -not $script:lstRooms.Items.Contains($name)) {
        $index = $script:lstRooms.Items.Add($name)
        $script:lstRooms.SetItemChecked($index, $true)
        Sync-ConfigFromForm
    }
})
$btnEditRoom.Add_Click({
    $index = $script:lstRooms.SelectedIndex
    if ($index -lt 0) { [System.Windows.Forms.MessageBox]::Show('수정할 항목을 먼저 선택하세요.', '이름 수정') | Out-Null; return }
    $current = [string]$script:lstRooms.Items[$index]
    $checked = $script:lstRooms.GetItemChecked($index)
    $name = ([string][Microsoft.VisualBasic.Interaction]::InputBox('채팅방 이름을 수정하세요.', '이름 수정', $current)).Trim()
    if ($name -and $name -ne $current) {
        $script:lstRooms.Items[$index] = $name
        $script:lstRooms.SetItemChecked($index, $checked)
        Sync-ConfigFromForm
    }
})
$btnDeleteRoom.Add_Click({
    $index = $script:lstRooms.SelectedIndex
    if ($index -ge 0) { $script:lstRooms.Items.RemoveAt($index); Sync-ConfigFromForm }
})
$btnScanRooms.Add_Click({
    try {
        Sync-ConfigFromForm
        Set-StatusPill '채팅방 목록 읽는 중' 'run'
        $script:form.Enabled = $false
        Write-RunLog '카카오톡 채팅방 목록을 읽는 중입니다.'
        $rooms = @(Get-KakaoRoomNames $script:config)
        $added = 0
        foreach ($room in $rooms) {
            if (-not $script:lstRooms.Items.Contains($room)) { [void]$script:lstRooms.Items.Add($room); $added++ }
        }
        $script:form.Enabled = $true
        $script:form.Activate()
        Sync-ConfigFromForm
        Set-StatusPill '대기 중' 'idle'
        Write-RunLog "목록 읽기 완료: 후보 $($rooms.Count)개 중 새 항목 $($added)개 추가"
        [System.Windows.Forms.MessageBox]::Show("후보 $($rooms.Count)개를 읽었습니다. (새로 추가 $($added)개)`r`n`r`n방 이름이 아닌 미리보기 문구가 섞였는지 확인한 뒤 발송할 방만 체크하세요.", '목록 읽기 완료') | Out-Null
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '읽기 실패' 'error'
        Write-RunLog "목록 읽기 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '목록 읽기 실패') | Out-Null
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
        $count = Invoke-Broadcast $script:config
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
        $ok = Invoke-TestSend $script:config $false
        $script:form.Enabled = $true
        $script:form.Activate()
        if ($ok) {
            Set-StatusPill '테스트 발송 성공' 'done'
            [System.Windows.Forms.MessageBox]::Show("'$room' 에 테스트 발송했습니다. 카카오톡에서 결과를 확인하세요.", '테스트 완료') | Out-Null
        } else {
            Set-StatusPill '테스트 실패' 'error'
            [System.Windows.Forms.MessageBox]::Show("'$room' 채팅창을 열지 못했습니다. 방 이름과 위치 보정을 확인하세요.", '테스트 실패') | Out-Null
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
        $ok = Invoke-TestSend $script:config $true
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

# ----- 보정 -----
function Invoke-CalibrationCapture([string]$Name, [string]$Instruction) {
    [System.Windows.Forms.MessageBox]::Show($Instruction + "`r`n`r`n마우스를 그 위치에 올린 뒤 F8을 누르세요. 제한시간은 30초입니다.", '위치 보정') | Out-Null
    $script:form.Hide()
    Start-Sleep -Milliseconds 500
    while (([NativeKakao]::GetAsyncKeyState(0x77) -band 0x8000) -ne 0) { Start-Sleep -Milliseconds 50 }
    $deadline = (Get-Date).AddSeconds(30)
    $captured = $false
    while ((Get-Date) -lt $deadline) {
        if (([NativeKakao]::GetAsyncKeyState(0x77) -band 0x8000) -ne 0) { $captured = $true; break }
        Start-Sleep -Milliseconds 50
        [System.Windows.Forms.Application]::DoEvents()
    }
    $script:form.Show()
    $script:form.Activate()
    if (-not $captured) { throw '보정 시간이 초과되었습니다. 다시 시도해 주세요.' }

    $point = New-Object NativeKakao+POINT
    [void][NativeKakao]::GetCursorPos([ref]$point)
    $handle = [NativeKakao]::GetForegroundWindow()
    $processId = [NativeKakao]::GetProcessId($handle)
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -eq $process -or $process.ProcessName -ne 'KakaoTalk') {
        throw 'F8을 누를 때 카카오톡 창이 활성화되어 있지 않았습니다. 카카오톡을 클릭해 활성화한 상태로 다시 시도하세요.'
    }

    $windowInfo = [NativeKakao]::GetWindow($handle)
    if ($windowInfo.Width -le 0 -or $windowInfo.Height -le 0) { throw '카카오톡 창 크기를 읽지 못했습니다.' }

    $script:config.Calibration.WindowClass = $windowInfo.ClassName
    $script:config.Calibration.WindowTitle = $windowInfo.Title
    $script:config.Calibration.Width = $windowInfo.Width
    $script:config.Calibration.Height = $windowInfo.Height
    $script:config.Calibration.("${Name}X") = [Math]::Round(($point.X - $windowInfo.Rect.Left) / $windowInfo.Width, 6)
    $script:config.Calibration.("${Name}Y") = [Math]::Round(($point.Y - $windowInfo.Rect.Top) / $windowInfo.Height, 6)
    Save-Config $script:config
    Update-CalibrationLabel
    Write-RunLog "위치 보정 완료: $Name"
}

$btnCalibChat.Add_Click({
    try { Invoke-CalibrationCapture 'ChatTab' '카카오톡 메인 창 왼쪽의 채팅(말풍선) 탭 중앙에 마우스를 올리세요.' }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '보정 실패') | Out-Null }
})
$btnCalibSearch.Add_Click({
    try { Invoke-CalibrationCapture 'Search' '채팅 목록 상단의 채팅방 검색 입력칸 중앙에 마우스를 올리세요.' }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '보정 실패') | Out-Null }
})
$btnCalibResult.Add_Click({
    try { Invoke-CalibrationCapture 'Result' '검색창에 실제 채팅방 이름을 입력한 뒤, 첫 번째 검색 결과의 이름 중앙에 마우스를 올리세요.' }
    catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '보정 실패') | Out-Null }
})

# ----- 업데이트 -----
function Show-UpdateState([object]$Release, [string]$Error) {
    if ($Error) {
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)`r`n확인 실패: $Error"
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
        $script:lblUpdateState.Text = "현재 버전 v$($script:AppVersion)  →  새 버전 $($Release.Tag) 이 있습니다.`r`n$($Release.PageUrl)"
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

$btnCheckUpdate.Add_Click({ Set-StatusPill '업데이트 확인 중' 'run'; Invoke-UpdateCheck $false; Set-StatusPill '대기 중' 'idle' })
$btnOpenRepo.Add_Click({ Start-Process $script:RepoUrl })
$script:btnDoUpdate.Add_Click({
    if ($null -eq $script:latestRelease) { return }
    $release = $script:latestRelease
    $body = "새 버전 $($release.Tag) 을 내려받아 설치합니다.`r`n`r`n출처: $($release.PageUrl)`r`n`r`n현재 파일은 backup 폴더에 보관되며, 설정과 로그는 그대로 유지됩니다.`r`n설치 후 프로그램이 다시 시작됩니다. 계속할까요?"
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
    if ([System.Windows.Forms.MessageBox]::Show("모든 설정(방 목록, 문구, 첨부, 보정)을 지우고 처음 상태로 되돌립니다.`r`n계속할까요?", '설정 초기화', 'YesNo', 'Warning') -ne 'Yes') { return }
    $script:config = New-DefaultConfig
    Save-Config $script:config
    [System.Windows.Forms.MessageBox]::Show('초기화했습니다. 프로그램을 다시 시작합니다.', '설정 초기화') | Out-Null
    Restart-App
})

# ----- 첫 사용자 가이드 투어 -----
function Show-GuideTour([string]$CaptureDir = '') {
    $script:tourIndex = 0
    $total = $script:TourSteps.Count

    $tour = New-Object System.Windows.Forms.Form
    $tour.FormBorderStyle = 'None'
    $tour.Size = New-Object System.Drawing.Size(560, 420)
    $tour.StartPosition = 'Manual'
    $tour.BackColor = $Theme.Card
    $tour.Font = $FontBase
    $tour.ShowInTaskbar = $false
    $tour.KeyPreview = $true
    # 본 창의 사이드바가 보이도록 오른쪽에 겹쳐 띄웁니다.
    $tour.Location = New-Object System.Drawing.Point(
        ($script:form.Left + 300),
        ($script:form.Top + 150))
    $tour.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen ($Theme.Border)
        $e.Graphics.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $pen.Dispose()
        $accent = New-Object System.Drawing.SolidBrush ($Theme.Accent)
        $e.Graphics.FillRectangle($accent, 0, 0, $sender.Width, 6)
        $accent.Dispose()
    })

    $lblStep = New-Object System.Windows.Forms.Label
    $lblStep.Location = New-Object System.Drawing.Point(36, 34)
    $lblStep.Size = New-Object System.Drawing.Size(200, 20)
    $lblStep.Font = $FontStrong
    $lblStep.ForeColor = $Theme.Muted
    $lblStep.BackColor = $Theme.Card
    $tour.Controls.Add($lblStep)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = New-Object System.Drawing.Point(34, 60)
    $lblTitle.Size = New-Object System.Drawing.Size(490, 34)
    $lblTitle.Font = New-Object System.Drawing.Font('Malgun Gothic', 13, [System.Drawing.FontStyle]::Bold)
    $lblTitle.ForeColor = $Theme.Ink
    $lblTitle.BackColor = $Theme.Card
    $tour.Controls.Add($lblTitle)

    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Location = New-Object System.Drawing.Point(36, 104)
    $lblBody.Size = New-Object System.Drawing.Size(488, 232)
    $lblBody.Font = New-Object System.Drawing.Font('Malgun Gothic', 9.5)
    $lblBody.ForeColor = (New-Rgb 62 66 74)
    $lblBody.BackColor = $Theme.Card
    $tour.Controls.Add($lblBody)

    $dots = New-Object System.Windows.Forms.Panel
    $dots.Location = New-Object System.Drawing.Point(36, 356)
    $dots.Size = New-Object System.Drawing.Size(160, 24)
    $dots.BackColor = $Theme.Card
    $dots.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        for ($i = 0; $i -lt $script:TourSteps.Count; $i++) {
            $color = if ($i -eq $script:tourIndex) { $Theme.Ink } else { (New-Rgb 214 218 224) }
            $brush = New-Object System.Drawing.SolidBrush ($color)
            $size = if ($i -eq $script:tourIndex) { 9 } else { 7 }
            $offset = if ($i -eq $script:tourIndex) { 7 } else { 8 }
            $e.Graphics.FillEllipse($brush, ($i * 16), $offset, $size, $size)
            $brush.Dispose()
        }
    })
    $tour.Controls.Add($dots)

    $btnSkip = New-AppButton $tour '건너뛰기' 210 350 90 36 'ghost'
    $btnPrev = New-AppButton $tour '이전' 316 350 90 36
    $btnNext = New-AppButton $tour '다음' 418 350 106 36 'primary'

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
    $btnPrev.Add_Click({
        if ($script:tourIndex -gt 0) { $script:tourIndex--; & $renderStep }
    })
    $btnSkip.Add_Click({ & $finish })
    $tour.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { & $finish }
    })

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
    if (-not $NoUpdateCheck -and [bool]$script:config.AutoCheckUpdate) { Invoke-UpdateCheck $true }
})

Show-AppPage 'compose'
Write-RunLog "프로그램 시작 (v$($script:AppVersion)). 설정은 자동 저장됩니다."
if (-not (Test-Calibration $script:config)) {
    Write-RunLog '첫 사용입니다. [설정] 화면에서 세 위치를 먼저 보정하세요.'
    Set-StatusPill '위치 보정이 필요합니다' 'error'
}

if ($ScreenshotDir) {
    if (-not (Test-Path -LiteralPath $ScreenshotDir)) { New-Item -ItemType Directory -Path $ScreenshotDir -Force | Out-Null }
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
[void]$script:form.ShowDialog()
