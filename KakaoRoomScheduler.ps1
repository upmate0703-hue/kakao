param(
    [switch]$SelfTest,
    [switch]$UiSmokeTest,
    [switch]$NoUpdateCheck,
    [switch]$ScanTest,
    [switch]$MaskNames,
    [switch]$SendBench,
    [int]$BenchCount = 3,
    [string]$ScreenshotDir = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 배포 정보 (CI가 아래 AppVersion 줄을 그대로 치환합니다. 형식을 바꾸지 마세요.)
# ---------------------------------------------------------------------------
$script:AppVersion = '5.10.0'
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

    [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr dialog, int itemId);

    // 파일 선택창은 윈도우가 만드는 기본 창이라 창 메시지가 그대로 통합니다.
    // 카카오톡이 직접 그린 아이콘과 달라서 여기서는 확실하게 동작합니다.
    public static void ClickButton(IntPtr hWnd) {
        PostMessageW(hWnd, 0x00F5, IntPtr.Zero, IntPtr.Zero);
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")] static extern IntPtr SendMessageText(IntPtr hWnd, uint msg, IntPtr wParam, string lParam);

    // 입력칸에 글을 끼워 넣습니다. EM_REPLACESEL 입니다.
    // 실제로 확인해 보니 카카오톡은 이 방법으로 넣은 글도 사람이 친 것으로 인정합니다.
    // (전송 버튼이 노랗게 켜집니다)
    // 줄바꿈이 있는 글도 한 번에 들어가고, 클립보드도 창 활성화도 필요 없습니다.
    public static void ReplaceSelection(IntPtr hWnd, string text) {
        SendMessageText(hWnd, 0x00C2, (IntPtr)1, text);
    }

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

    [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extraInfo);

    // SendKeys 의 ^v 는 Ctrl 키 상태를 제대로 알리지 못해 카카오톡이 붙여넣기를 무시합니다.
    // 실제 키 눌림 신호를 보내 진짜로 누른 것과 같게 만듭니다.
    public static void PressCtrlKey(byte key) {
        const byte VK_CONTROL = 0x11;
        const uint KEYUP = 0x0002;
        keybd_event(VK_CONTROL, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(40);
        keybd_event(key, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(40);
        keybd_event(key, 0, KEYUP, UIntPtr.Zero);
        System.Threading.Thread.Sleep(20);
        keybd_event(VK_CONTROL, 0, KEYUP, UIntPtr.Zero);
        System.Threading.Thread.Sleep(40);
    }

    public static void PressPlainKey(byte key) {
        const uint KEYUP = 0x0002;
        keybd_event(key, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(30);
        keybd_event(key, 0, KEYUP, UIntPtr.Zero);
        System.Threading.Thread.Sleep(30);
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

    // ---------------------------------------------------------------
    // 창 메시지로 직접 조작합니다.
    // 마우스를 움직이거나 창을 앞으로 가져오지 않아도 되고,
    // 화면 배율·해상도가 달라도 같은 자리를 정확히 누릅니다.
    // ---------------------------------------------------------------
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool PostMessageW(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")] static extern IntPtr SendMessageTextW(IntPtr hWnd, uint msg, IntPtr wParam, string lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")] static extern IntPtr SendMessageBufferW(IntPtr hWnd, uint msg, IntPtr wParam, StringBuilder lParam);
    [DllImport("user32.dll")] static extern bool ScreenToClient(IntPtr hWnd, ref POINT point);
    [DllImport("user32.dll")] static extern IntPtr RealChildWindowFromPoint(IntPtr parent, POINT point);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);

    const uint WM_CLOSE = 0x0010;
    const uint WM_SETTEXT = 0x000C;
    const uint WM_GETTEXT = 0x000D;
    const uint WM_GETTEXTLENGTH = 0x000E;
    const uint WM_KEYDOWN = 0x0100;
    const uint WM_KEYUP = 0x0101;
    const uint WM_CHAR = 0x0102;
    const uint WM_LBUTTONDOWN = 0x0201;
    const uint WM_LBUTTONUP = 0x0202;
    const uint WM_LBUTTONDBLCLK = 0x0203;
    const uint WM_PASTE = 0x0302;

    static IntPtr MakeLParam(int x, int y) { return (IntPtr)((y << 16) | (x & 0xFFFF)); }

    public static POINT ToClient(IntPtr hWnd, int screenX, int screenY) {
        POINT p; p.X = screenX; p.Y = screenY;
        ScreenToClient(hWnd, ref p);
        return p;
    }

    // 화면의 한 점 아래에 실제로 있는 자식 컨트롤을 찾습니다.
    public static IntPtr ChildAtPoint(IntPtr parent, int screenX, int screenY) {
        POINT p = ToClient(parent, screenX, screenY);
        IntPtr child = RealChildWindowFromPoint(parent, p);
        if (child == IntPtr.Zero) { return parent; }
        // 한 단계 더 내려갑니다.
        for (int depth = 0; depth < 4 && child != IntPtr.Zero && child != parent; depth++) {
            POINT inner = ToClient(child, screenX, screenY);
            IntPtr deeper = RealChildWindowFromPoint(child, inner);
            if (deeper == IntPtr.Zero || deeper == child) { break; }
            parent = child;
            child = deeper;
        }
        return child;
    }

    public static void ClickControl(IntPtr hWnd, int screenX, int screenY, bool doubleClick) {
        POINT p = ToClient(hWnd, screenX, screenY);
        IntPtr lp = MakeLParam(p.X, p.Y);
        PostMessageW(hWnd, WM_LBUTTONDOWN, (IntPtr)1, lp);
        PostMessageW(hWnd, WM_LBUTTONUP, IntPtr.Zero, lp);
        if (doubleClick) {
            System.Threading.Thread.Sleep(40);
            PostMessageW(hWnd, WM_LBUTTONDBLCLK, (IntPtr)1, lp);
            PostMessageW(hWnd, WM_LBUTTONUP, IntPtr.Zero, lp);
        }
    }

    public static void TypeText(IntPtr hWnd, string text) {
        foreach (char c in text) {
            PostMessageW(hWnd, WM_CHAR, (IntPtr)c, (IntPtr)1);
            System.Threading.Thread.Sleep(6);
        }
    }

    public static void SetControlText(IntPtr hWnd, string text) {
        SendMessageTextW(hWnd, WM_SETTEXT, IntPtr.Zero, text);
    }

    public static string GetControlText(IntPtr hWnd) {
        int length = (int)SendMessage(hWnd, WM_GETTEXTLENGTH, IntPtr.Zero, IntPtr.Zero);
        if (length <= 0) { return string.Empty; }
        var buffer = new StringBuilder(length + 2);
        SendMessageBufferW(hWnd, WM_GETTEXT, (IntPtr)(length + 1), buffer);
        return buffer.ToString();
    }

    public static void PasteInto(IntPtr hWnd) {
        SendMessage(hWnd, WM_PASTE, IntPtr.Zero, IntPtr.Zero);
    }

    // 입력칸 내용을 전체 선택합니다 (EM_SETSEL).
    public static void SelectAllIn(IntPtr hWnd) {
        SendMessage(hWnd, 0x00B1, IntPtr.Zero, (IntPtr)(-1));
    }

    // 선택 영역을 지웁니다 (WM_CLEAR).
    public static void ClearSelection(IntPtr hWnd) {
        SendMessage(hWnd, 0x0303, IntPtr.Zero, IntPtr.Zero);
    }

    // 글자 하나를 보냅니다. Enter(13) 를 보낼 때도 씁니다.
    public static void SendChar(IntPtr hWnd, int code) {
        PostMessageW(hWnd, WM_CHAR, (IntPtr)code, (IntPtr)1);
    }

    public static void PressKey(IntPtr hWnd, int virtualKey) {
        PostMessageW(hWnd, WM_KEYDOWN, (IntPtr)virtualKey, IntPtr.Zero);
        System.Threading.Thread.Sleep(25);
        PostMessageW(hWnd, WM_KEYUP, (IntPtr)virtualKey, IntPtr.Zero);
    }

    public static void CloseWindow(IntPtr hWnd) {
        PostMessageW(hWnd, WM_CLOSE, IntPtr.Zero, IntPtr.Zero);
    }

    // 제목이 특정 글자로 시작하는 창을 찾습니다. 이미 실행 중인 우리 창을 찾을 때 씁니다.
    public static IntPtr FindWindowByTitlePrefix(string prefix, int excludeProcessId) {
        IntPtr found = IntPtr.Zero;
        EnumWindows(delegate(IntPtr hWnd, IntPtr ignored) {
            if (!IsWindowVisible(hWnd)) { return true; }
            uint pid;
            GetWindowThreadProcessId(hWnd, out pid);
            if ((int)pid == excludeProcessId) { return true; }
            var title = new StringBuilder(512);
            GetWindowText(hWnd, title, title.Capacity);
            if (title.ToString().StartsWith(prefix, StringComparison.Ordinal)) {
                found = hWnd;
                return false;
            }
            return true;
        }, IntPtr.Zero);
        return found;
    }
}
"@
}

# 화면 픽셀을 빠르게 훑습니다. GetPixel 은 한 점마다 오버헤드가 커서
# 사양이 낮은 PC에서 눈에 띄게 느려집니다. LockBits 로 한 번에 읽습니다.
if (-not ('FastImage' -as [type])) {
Add-Type -ReferencedAssemblies 'System.Drawing' -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class FastImage {
    static int[] ReadRows(Bitmap bitmap, Rectangle rect, out int stridePixels) {
        BitmapData data = bitmap.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try {
            stridePixels = data.Stride / 4;
            int[] buffer = new int[stridePixels * rect.Height];
            Marshal.Copy(data.Scan0, buffer, 0, buffer.Length);
            return buffer;
        } finally { bitmap.UnlockBits(data); }
    }

    // 색이 3가지 이하면 아직 그려지지 않은 빈 화면으로 봅니다.
    public static bool IsBlank(Bitmap bitmap) {
        var rect = new Rectangle(0, 0, bitmap.Width, bitmap.Height);
        int stride;
        int[] pixels = ReadRows(bitmap, rect, out stride);
        int seen = 0;
        int[] colors = new int[4];
        for (int y = 0; y < rect.Height; y += 13) {
            int rowStart = y * stride;
            for (int x = 0; x < rect.Width; x += 11) {
                int color = pixels[rowStart + x];
                bool found = false;
                for (int i = 0; i < seen; i++) { if (colors[i] == color) { found = true; break; } }
                if (!found) {
                    if (seen >= 3) { return false; }
                    colors[seen++] = color;
                }
            }
        }
        return true;
    }

    // 세로줄마다 색이 있는 픽셀 수를 셉니다.
    // 채팅창 아래 아이콘 줄에서 아이콘이 어디 있는지 찾는 데 씁니다.
    // 자리를 미리 정해 두면 카카오톡 판이나 해상도가 바뀔 때 틀리므로 화면을 보고 찾습니다.
    public static int[] ColumnInk(Bitmap bitmap, int left, int top, int right, int bottom, double threshold) {
        if (left < 0) left = 0;
        if (top < 0) top = 0;
        if (right >= bitmap.Width) right = bitmap.Width - 1;
        if (bottom >= bitmap.Height) bottom = bitmap.Height - 1;
        if (right <= left || bottom <= top) { return new int[0]; }
        var rect = new Rectangle(left, top, right - left + 1, bottom - top + 1);
        int stride;
        int[] pixels = ReadRows(bitmap, rect, out stride);
        int[] counts = new int[rect.Width];
        for (int y = 0; y < rect.Height; y++) {
            int rowStart = y * stride;
            for (int x = 0; x < rect.Width; x++) {
                int color = pixels[rowStart + x];
                int r = (color >> 16) & 0xFF;
                int g = (color >> 8) & 0xFF;
                int b = color & 0xFF;
                int max = r > g ? (r > b ? r : b) : (g > b ? g : b);
                int min = r < g ? (r < b ? r : b) : (g < b ? g : b);
                double brightness = (max + min) / 510.0;
                if (brightness < threshold) { counts[x]++; }
            }
        }
        return counts;
    }

    // 카카오톡 노란색 비율입니다.
    // 전송 버튼은 보낼 것이 있을 때만 노랗게 켜집니다.
    // 첨부가 실제로 붙었는지 알아내는 가장 확실한 신호라서 이 색을 봅니다.
    // 밝은 화면이든 어두운 화면이든 이 노란색은 그대로입니다.
    public static double YellowRatio(Bitmap bitmap, int left, int top, int right, int bottom) {
        if (left < 0) left = 0;
        if (top < 0) top = 0;
        if (right >= bitmap.Width) right = bitmap.Width - 1;
        if (bottom >= bitmap.Height) bottom = bitmap.Height - 1;
        if (right <= left || bottom <= top) { return 0.0; }
        var rect = new Rectangle(left, top, right - left + 1, bottom - top + 1);
        int stride;
        int[] pixels = ReadRows(bitmap, rect, out stride);
        long yellow = 0, total = 0;
        for (int y = 0; y < rect.Height; y++) {
            int rowStart = y * stride;
            for (int x = 0; x < rect.Width; x++) {
                int color = pixels[rowStart + x];
                int r = (color >> 16) & 0xFF;
                int g = (color >> 8) & 0xFF;
                int b = color & 0xFF;
                total++;
                if (r > 200 && g > 170 && b < 140 && (r - b) > 80 && (g - b) > 60) { yellow++; }
            }
        }
        if (total == 0) { return 0.0; }
        return (double)yellow / (double)total;
    }

    // 지정한 영역에서 어두운 픽셀 비율을 돌려줍니다. 탭 선택 여부 판별에 씁니다.
    public static double DarkRatio(Bitmap bitmap, int left, int top, int right, int bottom, double threshold) {
        if (left < 0) left = 0;
        if (top < 0) top = 0;
        if (right >= bitmap.Width) right = bitmap.Width - 1;
        if (bottom >= bitmap.Height) bottom = bitmap.Height - 1;
        if (right <= left || bottom <= top) { return 0.0; }
        var rect = new Rectangle(left, top, right - left + 1, bottom - top + 1);
        int stride;
        int[] pixels = ReadRows(bitmap, rect, out stride);
        long dark = 0, total = 0;
        for (int y = 0; y < rect.Height; y++) {
            int rowStart = y * stride;
            for (int x = 0; x < rect.Width; x++) {
                int color = pixels[rowStart + x];
                int r = (color >> 16) & 0xFF;
                int g = (color >> 8) & 0xFF;
                int b = color & 0xFF;
                int max = r > g ? (r > b ? r : b) : (g > b ? g : b);
                int min = r < g ? (r < b ? r : b) : (g < b ? g : b);
                double brightness = (max + min) / 510.0;
                total++;
                if (brightness < threshold) { dark++; }
            }
        }
        if (total == 0) { return 0.0; }
        return (double)dark / (double)total;
    }
}
"@
}

# ---------------------------------------------------------------------------
# 경로 및 설정
# ---------------------------------------------------------------------------
# 프로그램(.exe) 으로 만들어 실행하면 $MyInvocation.MyCommand.Path 가 비어 있습니다.
# 그때는 실행 파일이 있는 폴더를 씁니다.
$script:HostPath = ''
try { $script:HostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName } catch { }
$script:IsExe = $false
if ($script:HostPath) {
    $hostName = [System.IO.Path]::GetFileName($script:HostPath)
    if ($hostName -notmatch '^(powershell|pwsh)\.exe$') { $script:IsExe = $true }
}
# 프로그램(.exe) 으로 만들면 $MyInvocation.MyCommand.Path 에
# 프로그램을 만들 때 쓰던 원본 경로가 그대로 남습니다.
# 그 경로는 다른 컴퓨터에 없으므로 절대 쓰면 안 됩니다.
# 그래서 프로그램일 때는 실행 파일 위치를 먼저 봅니다.
$AppDir = ''
if ($script:IsExe) { $AppDir = Split-Path -Parent $script:HostPath }
elseif ($MyInvocation.MyCommand.Path) { $AppDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $AppDir) { $AppDir = (Get-Location).Path }
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
$script:selectedKakaoProcessId = 0
$script:lastTabRatios = ''
$script:activeKakaoWindow = $null

$script:RoomTypeNormal = '일반채팅'
$script:RoomTypeOpen = '오픈채팅'
$script:RoomTypePersonal = '개인채팅'
$script:RoomTypeGroup = '그룹채팅'
$script:RoomTypeUnknown = '미분류'

function New-DefaultConfig {
    [pscustomobject]@{
        Rooms = @()
        KnownRooms = @()
        RoomTypes = [pscustomobject]@{}
        RoomListNames = [pscustomobject]@{}
        Groups = [pscustomobject]@{}
        QuietEnabled = $false
        QuietStart = '21:00'
        QuietEnd = '08:00'
        HolidayMode = '평소대로'
        HolidayIntervalMultiplier = 3
        SkipWeekend = $false
        ExtraHolidays = @()
        AutoDownloadUpdate = $true
        SkipSendConfirm = $false
        RepeatEnabled = $false
        RepeatMinutes = 30
        RepeatCount = 0
        BatchSize = 0
        BatchRestMinutes = 30
        Message = ''
        Attachments = @()
        ScheduledAt = (Get-Date).Date.AddDays(1).ToString('yyyy-MM-dd HH:mm:ss')
        IntervalSeconds = 8
        DryRun = $true
        ScanPages = 30
        TestRoom = '나와의 채팅'
        AttachmentWaitMs = 1500
        OpenTimeoutMs = 8000
        SettleMs = 4000
        PreloadRooms = $true
        PreloadDone = $false
        TruncatedRooms = @()
        AutoCheckUpdate = $true
        TourDone = $false
        Calibration = [pscustomobject]@{
            SearchIconOffset = 0
        }
    }
}

# 설정을 임시 파일에 먼저 쓰고 바꿔치기합니다.
# 저장 도중 프로그램이 꺼지거나 다른 곳에서 읽어도 파일이 깨지지 않습니다.
function Save-Config([object]$Config) {
    $json = $Config | ConvertTo-Json -Depth 8
    $temp = "$ConfigPath.tmp"
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        try {
            Set-Content -LiteralPath $temp -Value $json -Encoding UTF8 -ErrorAction Stop
            Move-Item -LiteralPath $temp -Destination $ConfigPath -Force -ErrorAction Stop
            return
        } catch {
            Start-Sleep -Milliseconds 120
        }
    }
    # 마지막으로 직접 써 봅니다.
    try { Set-Content -LiteralPath $ConfigPath -Value $json -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Add-ConfigPropertyIfMissing([object]$Object, [string]$Name, [object]$Value) {
    if ($null -eq $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

# 예전에 저장된 이름에는 안 읽은 개수 뱃지(0)나 잘림 표시(…)가 그대로 남아 있습니다.
# 그래서 목록에 같은 방이 두 번 보이거나 이름이 이상하게 나옵니다.
#   *자유로운 홍보방*
#   0 *자유로운 홍보방*   <- 같은 방인데 뱃지가 붙어 따로 저장됨
# 프로그램을 켤 때 한 번 정리하고 같은 방은 합칩니다.
# 첨부 목록에는 파일 이름만 보여 주고 전체 경로는 안에 담아 둡니다.
# 긴 경로가 그대로 보이면 목록이 지저분해서 무엇이 들었는지 알아보기 어렵습니다.
function New-AttachmentItem([string]$Path) {
    $name = $Path
    try { $name = [System.IO.Path]::GetFileName($Path) } catch { }
    if (-not $name) { $name = $Path }
    return [pscustomobject]@{ Name = $name; Path = [string]$Path }
}

function Get-AttachmentPaths {
    return @($script:lstFiles.Items | ForEach-Object { [string]$_.Path })
}

function Repair-RoomNames([object]$Config) {
    $order = New-Object System.Collections.Generic.List[string]
    $byKey = @{}
    $cleaned = 0
    $merged = 0

    # 고른 방을 먼저 기억해 둡니다. 합치는 과정에서 잃어버리면 안 됩니다.
    $picked = @{}
    foreach ($raw in @($Config.Rooms)) {
        $name = Remove-RoomNameNoise ([string]$raw)
        if (-not $name) { continue }
        $key = ConvertTo-CompareKey $name
        if ($key) { $picked[$key] = $true }
    }

    foreach ($raw in (@($Config.Rooms) + @($Config.KnownRooms))) {
        $before = [string]$raw
        if ([string]::IsNullOrWhiteSpace($before)) { continue }
        $name = Remove-RoomNameNoise $before
        if (-not $name) { continue }
        if ($name -ne $before) { $cleaned++ }
        $key = ConvertTo-CompareKey $name
        if (-not $key) { continue }
        if ($byKey.ContainsKey($key)) { $merged++; continue }
        $byKey[$key] = $name
        [void]$order.Add($key)
    }

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($key in $order) { [void]$names.Add($byKey[$key]) }

    # 종류 정보를 새 이름으로 옮깁니다.
    $newTypes = [pscustomobject]@{}
    foreach ($prop in @($Config.RoomTypes.PSObject.Properties)) {
        $name = Remove-RoomNameNoise ([string]$prop.Name)
        if (-not $name) { continue }
        $key = ConvertTo-CompareKey $name
        if (-not $key -or -not $byKey.ContainsKey($key)) { continue }
        $target = $byKey[$key]
        if ($null -ne $newTypes.PSObject.Properties[$target]) { continue }
        Add-Member -InputObject $newTypes -NotePropertyName $target -NotePropertyValue ([string]$prop.Value)
    }
    $Config.RoomTypes = $newTypes

    # 그룹에 들어 있는 이름도 옮깁니다.
    $newGroups = [pscustomobject]@{}
    foreach ($prop in @($Config.Groups.PSObject.Properties)) {
        $members = New-Object System.Collections.Generic.List[string]
        foreach ($member in @($prop.Value)) {
            $name = Remove-RoomNameNoise ([string]$member)
            if (-not $name) { continue }
            $key = ConvertTo-CompareKey $name
            if (-not $key -or -not $byKey.ContainsKey($key)) { continue }
            $target = $byKey[$key]
            if (-not $members.Contains($target)) { [void]$members.Add($target) }
        }
        Add-Member -InputObject $newGroups -NotePropertyName ([string]$prop.Name) -NotePropertyValue @($members)
    }
    $Config.Groups = $newGroups

    $Config.KnownRooms = @($names)
    $Config.Rooms = @($names | Where-Object { $picked[(ConvertTo-CompareKey $_)] })
    $script:lastSendProblem = ''
$script:roomRepairNote = ''
    if ($cleaned -gt 0 -or $merged -gt 0) {
        $script:roomRepairNote = "채팅방 목록을 정리했습니다: 이름 다듬음 $($cleaned)개 · 같은 방 합침 $($merged)개"
    }
    return $Config
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
    if ($null -eq $Config.RoomListNames) { $Config.RoomListNames = [pscustomobject]@{} }
    # 예전 버전이 쓰던 표기를 현재 표기로 맞춥니다.
    foreach ($property in @($Config.RoomTypes.PSObject.Properties)) {
        if ([string]$property.Value -eq '확인 필요') { $Config.RoomTypes.($property.Name) = $script:RoomTypeUnknown }
    }
    $Config = Repair-RoomNames $Config
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

# 목록에서 화면 글자로 읽히는 이름입니다.
# [이름 확인·보정] 으로 실제 제목을 알아낸 뒤에도, 목록에서 찾을 때는
# 원래 읽혔던 글자로 찾아야 하므로 따로 보관합니다.
function Get-RoomListName([string]$Name) {
    if ($null -eq $script:config.RoomListNames) { return $Name }
    $property = $script:config.RoomListNames.PSObject.Properties[$Name]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $Name }
    return [string]$property.Value
}

function Set-RoomListName([string]$Name, [string]$ListName) {
    if ([string]::IsNullOrWhiteSpace($Name) -or [string]::IsNullOrWhiteSpace($ListName)) { return }
    if ($null -eq $script:config.RoomListNames) { $script:config.RoomListNames = [pscustomobject]@{} }
    if ($null -eq $script:config.RoomListNames.PSObject.Properties[$Name]) {
        $script:config.RoomListNames | Add-Member -NotePropertyName $Name -NotePropertyValue $ListName
    } else {
        $script:config.RoomListNames.$Name = $ListName
    }
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
# 채팅방 그룹
# ---------------------------------------------------------------------------
function Get-GroupNames {
    if ($null -eq $script:config.Groups) { return @() }
    return @($script:config.Groups.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
}

function Get-GroupRooms([string]$GroupName) {
    if ($null -eq $script:config.Groups) { return @() }
    $property = $script:config.Groups.PSObject.Properties[$GroupName]
    if ($null -eq $property) { return @() }
    return @($property.Value | ForEach-Object { [string]$_ } | Where-Object { $_ })
}

function Set-GroupRooms([string]$GroupName, [string[]]$Rooms) {
    if ([string]::IsNullOrWhiteSpace($GroupName)) { return }
    if ($null -eq $script:config.Groups) { $script:config.Groups = [pscustomobject]@{} }
    $value = @($Rooms | ForEach-Object { [string]$_ } | Where-Object { $_ } | Select-Object -Unique)
    if ($null -eq $script:config.Groups.PSObject.Properties[$GroupName]) {
        $script:config.Groups | Add-Member -NotePropertyName $GroupName -NotePropertyValue $value
    } else {
        $script:config.Groups.$GroupName = $value
    }
}

function Remove-Group([string]$GroupName) {
    if ($null -eq $script:config.Groups) { return }
    if ($null -ne $script:config.Groups.PSObject.Properties[$GroupName]) {
        $script:config.Groups.PSObject.Properties.Remove($GroupName)
    }
}

function Get-GroupsForRoom([string]$RoomName) {
    $names = @()
    foreach ($group in (Get-GroupNames)) {
        if ((Get-GroupRooms $group) -contains $RoomName) { $names += $group }
    }
    return $names
}

function Rename-RoomInGroups([string]$OldName, [string]$NewName) {
    foreach ($group in (Get-GroupNames)) {
        $rooms = @(Get-GroupRooms $group)
        if ($rooms -contains $OldName) {
            Set-GroupRooms $group @($rooms | ForEach-Object { if ($_ -eq $OldName) { $NewName } else { $_ } })
        }
    }
}

function Remove-RoomFromGroups([string]$RoomName) {
    foreach ($group in (Get-GroupNames)) {
        $rooms = @(Get-GroupRooms $group)
        if ($rooms -contains $RoomName) { Set-GroupRooms $group @($rooms | Where-Object { $_ -ne $RoomName }) }
    }
}

# ---------------------------------------------------------------------------
# 공휴일 및 방해금지 시간대
# ---------------------------------------------------------------------------
# 음력 날짜를 양력으로 바꿉니다. 윤달이 있으면 월 번호가 한 칸 밀립니다.
function ConvertFrom-KoreanLunar([int]$LunarYear, [int]$LunarMonth, [int]$LunarDay) {
    try {
        $calendar = New-Object System.Globalization.KoreanLunisolarCalendar
        $leapMonth = $calendar.GetLeapMonth($LunarYear)
        $month = $LunarMonth
        if ($leapMonth -gt 0 -and $LunarMonth -ge $leapMonth) { $month = $LunarMonth + 1 }
        return $calendar.ToDateTime($LunarYear, $month, $LunarDay, 0, 0, 0, 0).Date
    } catch { return $null }
}

$script:holidayCache = @{}

function Get-KoreanHolidays([int]$Year) {
    if ($script:holidayCache.ContainsKey($Year)) { return $script:holidayCache[$Year] }
    $holidays = @{}
    function Add-Holiday([hashtable]$Table, $Date, [string]$Name) {
        if ($null -eq $Date) { return }
        $key = ([datetime]$Date).ToString('yyyy-MM-dd')
        if (-not $Table.ContainsKey($key)) { $Table[$key] = $Name }
    }

    foreach ($fixed in @(
        @{ M = 1;  D = 1;  N = '신정' },
        @{ M = 3;  D = 1;  N = '삼일절' },
        @{ M = 5;  D = 5;  N = '어린이날' },
        @{ M = 6;  D = 6;  N = '현충일' },
        @{ M = 8;  D = 15; N = '광복절' },
        @{ M = 10; D = 3;  N = '개천절' },
        @{ M = 10; D = 9;  N = '한글날' },
        @{ M = 12; D = 25; N = '성탄절' }
    )) {
        Add-Holiday $holidays (Get-Date -Year $Year -Month $fixed.M -Day $fixed.D -Hour 0 -Minute 0 -Second 0) $fixed.N
    }

    $seollal = ConvertFrom-KoreanLunar $Year 1 1
    if ($null -ne $seollal) {
        Add-Holiday $holidays $seollal.AddDays(-1) '설날 연휴'
        Add-Holiday $holidays $seollal '설날'
        Add-Holiday $holidays $seollal.AddDays(1) '설날 연휴'
    }
    $buddha = ConvertFrom-KoreanLunar $Year 4 8
    Add-Holiday $holidays $buddha '부처님오신날'
    $chuseok = ConvertFrom-KoreanLunar $Year 8 15
    if ($null -ne $chuseok) {
        Add-Holiday $holidays $chuseok.AddDays(-1) '추석 연휴'
        Add-Holiday $holidays $chuseok '추석'
        Add-Holiday $holidays $chuseok.AddDays(1) '추석 연휴'
    }

    # 대체공휴일: 주말과 겹치면 다음 평일로 미룹니다.
    $substituteTargets = @('삼일절', '어린이날', '광복절', '개천절', '한글날', '설날', '설날 연휴', '추석', '추석 연휴', '부처님오신날')
    foreach ($entry in @($holidays.GetEnumerator() | Sort-Object -Property Name)) {
        if ($entry.Value -notin $substituteTargets) { continue }
        $date = [datetime]::ParseExact($entry.Key, 'yyyy-MM-dd', $null)
        $isWeekend = ($date.DayOfWeek -eq [DayOfWeek]::Saturday -or $date.DayOfWeek -eq [DayOfWeek]::Sunday)
        # 설날·추석 연휴는 일요일과 겹칠 때만 대체합니다.
        if ($entry.Value -like '설날*' -or $entry.Value -like '추석*') {
            if ($date.DayOfWeek -ne [DayOfWeek]::Sunday) { continue }
        } elseif (-not $isWeekend) { continue }
        $next = $date.AddDays(1)
        while ($next.DayOfWeek -eq [DayOfWeek]::Saturday -or $next.DayOfWeek -eq [DayOfWeek]::Sunday -or
               $holidays.ContainsKey($next.ToString('yyyy-MM-dd'))) {
            $next = $next.AddDays(1)
        }
        Add-Holiday $holidays $next ('대체공휴일(' + $entry.Value + ')')
    }

    $script:holidayCache[$Year] = $holidays
    return $holidays
}

function Get-HolidayName([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    foreach ($extra in @($script:config.ExtraHolidays)) {
        if (([string]$extra).Trim() -eq $key) { return '직접 지정한 휴일' }
    }
    $holidays = Get-KoreanHolidays $Date.Year
    if ($holidays.ContainsKey($key)) { return $holidays[$key] }
    return $null
}

function ConvertTo-DayMinutes([string]$Text, [int]$Fallback) {
    $match = [regex]::Match(([string]$Text).Trim(), '^(\d{1,2})\s*:\s*(\d{2})$')
    if (-not $match.Success) { return $Fallback }
    $hour = [int]$match.Groups[1].Value
    $minute = [int]$match.Groups[2].Value
    if ($hour -gt 23 -or $minute -gt 59) { return $Fallback }
    return ($hour * 60 + $minute)
}

# 방해금지 시간대에 걸리는지 확인합니다. 자정을 넘는 구간(21:00~08:00)도 처리합니다.
function Test-QuietHours([datetime]$When) {
    if (-not [bool]$script:config.QuietEnabled) { return $false }
    $start = ConvertTo-DayMinutes $script:config.QuietStart 1260
    $end = ConvertTo-DayMinutes $script:config.QuietEnd 480
    if ($start -eq $end) { return $false }
    $now = $When.Hour * 60 + $When.Minute
    if ($start -lt $end) { return ($now -ge $start -and $now -lt $end) }
    return ($now -ge $start -or $now -lt $end)
}

function Test-BlockedWeekend([datetime]$When) {
    if (-not [bool]$script:config.SkipWeekend) { return $false }
    return ($When.DayOfWeek -eq [DayOfWeek]::Saturday -or $When.DayOfWeek -eq [DayOfWeek]::Sunday)
}

# 보내면 안 되는 상황이면 이유를, 괜찮으면 $null 을 돌려줍니다.
function Get-SendBlockReason([datetime]$When) {
    if (Test-QuietHours $When) {
        return "방해금지 시간대입니다. ($($script:config.QuietStart) ~ $($script:config.QuietEnd))"
    }
    if (Test-BlockedWeekend $When) { return '주말에는 보내지 않도록 설정되어 있습니다.' }
    $holiday = Get-HolidayName $When
    if ($holiday -and ([string]$script:config.HolidayMode -eq '보내지 않음')) {
        return "오늘은 $holiday 입니다. 공휴일에는 보내지 않도록 설정되어 있습니다."
    }
    return $null
}

function Get-NextAllowedTime([datetime]$From) {
    $candidate = $From
    for ($i = 0; $i -lt 20000; $i++) {
        if ($null -eq (Get-SendBlockReason $candidate)) { return $candidate }
        if (Test-QuietHours $candidate) { $candidate = $candidate.AddMinutes(5); continue }
        # 날짜 문제(주말·공휴일)면 다음 날 같은 시각으로 넘깁니다.
        $candidate = $candidate.Date.AddDays(1).Add($From.TimeOfDay)
    }
    return $null
}

function Get-EffectiveInterval([datetime]$When) {
    $interval = [Math]::Max(0, [int]$script:config.IntervalSeconds)
    $holiday = Get-HolidayName $When
    if ($holiday -and ([string]$script:config.HolidayMode -eq '간격 늘리기')) {
        $multiplier = [Math]::Max(1, [int]$script:config.HolidayIntervalMultiplier)
        return [Math]::Min(600, $interval * $multiplier)
    }
    return $interval
}

# ---------------------------------------------------------------------------
# 카카오톡 창 찾기
# ---------------------------------------------------------------------------
function Get-KakaoProcesses {
    @(Get-Process -Name KakaoTalk -ErrorAction SilentlyContinue)
}

# 카카오톡을 여러 개 켜 두는 경우가 있어, 메인 창을 모두 찾아 목록으로 돌려줍니다.
function Get-KakaoMainWindows {
    $found = @()
    $seen = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($seen.ContainsKey([string]$window.Handle)) { continue }
            $isMain = ($window.Title -eq '카카오톡' -or $window.Title -eq 'KakaoTalk')
            if (-not $isMain) {
                if (-not $window.Visible -or $window.Width -lt 240 -or $window.Height -lt 320) { continue }
                $children = @([NativeKakao]::GetChildWindows($window.Handle))
                if (@($children | Where-Object { $_.Title -match 'ChatRoomListView|ContactListView|OnlineMainView' }).Count -eq 0) { continue }
            }
            $seen[[string]$window.Handle] = $true
            $found += [pscustomobject]@{
                Handle = $window.Handle
                ProcessId = $window.ProcessId
                Title = $window.Title
                Minimized = (Test-WindowMinimized $window)
            }
        }
    }
    return @($found | Sort-Object -Property ProcessId, Handle)
}

function Get-KakaoInstanceLabel([object]$Instance) {
    $state = if ($Instance.Minimized) { '최소화됨' } else { '사용 가능' }
    return "카카오톡 #$($Instance.ProcessId) ($state)"
}

function Find-KakaoMainHandle {
    $instances = @(Get-KakaoMainWindows)
    if ($instances.Count -eq 0) { return [IntPtr]::Zero }
    # 사용자가 고른 카카오톡이 아직 살아 있으면 그것을 씁니다.
    if ($script:selectedKakaoProcessId -gt 0) {
        $chosen = @($instances | Where-Object { $_.ProcessId -eq $script:selectedKakaoProcessId })
        if ($chosen.Count -gt 0) { return $chosen[0].Handle }
    }
    $usable = @($instances | Where-Object { -not $_.Minimized })
    if ($usable.Count -gt 0) { return $usable[0].Handle }
    return $instances[0].Handle
}

# 최소화뿐 아니라 '트레이로 닫아 숨긴' 상태도 사용할 수 없는 상태로 봅니다.
function Test-WindowMinimized([object]$Window) {
    if ($null -eq $Window) { return $false }
    if (-not $Window.Visible) { return $true }
    if ([NativeKakao]::IsWindowMinimized($Window.Handle)) { return $true }
    return ($Window.Rect.Left -le -30000 -or $Window.Width -lt 200 -or $Window.Height -lt 200)
}

function Get-MainKakaoWindow([bool]$Restore = $false) {
    $handle = Find-KakaoMainHandle
    if ($handle -eq [IntPtr]::Zero) { $script:activeKakaoWindow = $null; return $null }
    $window = [NativeKakao]::GetWindow($handle)
    if ($Restore -and (Test-WindowMinimized $window)) {
        # 트레이로 닫아 숨긴 창은 SW_SHOW, 최소화된 창은 SW_RESTORE 로 되살립니다.
        if (-not $window.Visible) { [void][NativeKakao]::ShowWindow($handle, 5); Start-Sleep -Milliseconds 400 }
        [void][NativeKakao]::ShowWindow($handle, 9)
        Start-Sleep -Milliseconds 700
        $window = [NativeKakao]::GetWindow($handle)
        Write-RunLog '카카오톡 창이 닫혀 있거나 최소화되어 있어 다시 열었습니다.'
    }
    $script:activeKakaoWindow = $window
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
    # 오픈채팅처럼 목록 컨트롤 클래스 이름이 다른 화면을 위한 예비 탐색입니다.
    if ($null -eq $list) {
        $fallback = @($children | Where-Object {
            $_.Visible -and $_.Width -ge 200 -and $_.Height -ge 220 -and
            $_.ClassName -notlike '*ScrollCtrl*' -and $_.ClassName -ne 'Edit' -and
            $_.Title -notmatch 'View_0x'
        } | Sort-Object -Property @{ Expression = { $_.Width * $_.Height } } -Descending)
        if ($fallback.Count -gt 0) { $list = $fallback[0] }
    }

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

# ---------------------------------------------------------------------------
# 상단 띠(탭 · 검색 아이콘) 자동 인식
# ---------------------------------------------------------------------------
# 최신 카카오톡은 [채팅] [오픈채팅] 을 창 위쪽 글자 탭으로, 검색을 돋보기 아이콘으로
# 보여 줍니다. 글자를 읽어 위치를 스스로 찾으므로 사용자가 알려 줄 필요가 없습니다.
function Get-TopBandRegion([object]$Layout) {
    if ($null -eq $Layout.List) { return $null }
    $children = @([NativeKakao]::GetChildWindows($Layout.Main.Handle))
    $view = @($children | Where-Object { $_.Visible -and $_.Title -match 'View_0x' -and $_.Title -notmatch 'MainView' } |
        Sort-Object -Property @{ Expression = { $_.Rect.Top } } | Select-Object -First 1)
    $top = if ($view.Count -gt 0) { $view[0].Rect.Top } else { $Layout.Main.Rect.Top + 31 }
    $height = $Layout.List.Rect.Top - $top
    if ($height -lt 24) { return $null }
    return [pscustomobject]@{
        Left = $Layout.List.Rect.Left
        Top = $top
        Width = $Layout.List.Width
        Height = $height
    }
}

# 상단 띠를 확대해 글자와 그 화면 좌표를 읽습니다.
function Get-TopBandWords([object]$Layout, [int]$Scale = 3) {
    if ($null -eq $Layout -or $null -eq $Layout.Main) { return @() }
    $band = Get-TopBandRegion $Layout
    if ($null -eq $band) { return @() }
    if (-not (Initialize-Ocr)) { return @() }
    $full = Get-WindowImage $Layout.Main
    $cropped = $null
    $scaled = $null
    $stream = $null
    try {
        $rect = New-Object System.Drawing.Rectangle(
            ($band.Left - $Layout.Main.Rect.Left), ($band.Top - $Layout.Main.Rect.Top), $band.Width, $band.Height)
        if ($rect.X -lt 0 -or $rect.Y -lt 0 -or
            ($rect.X + $rect.Width) -gt $full.Width -or ($rect.Y + $rect.Height) -gt $full.Height) { return @() }
        $cropped = $full.Clone($rect, $full.PixelFormat)
        $scaled = New-Object System.Drawing.Bitmap(($band.Width * $Scale), ($band.Height * $Scale))
        $graphics = [System.Drawing.Graphics]::FromImage($scaled)
        $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $graphics.DrawImage($cropped, 0, 0, $scaled.Width, $scaled.Height)
        $graphics.Dispose()

        $stream = New-Object System.IO.MemoryStream
        $scaled.Save($stream, [System.Drawing.Imaging.ImageFormat]::Bmp)
        [void]$stream.Seek(0, 'Begin')
        $random = [System.IO.WindowsRuntimeStreamExtensions]::AsRandomAccessStream($stream)
        $decoder = Wait-WinRt ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($random)) ([Windows.Graphics.Imaging.BitmapDecoder])
        $software = Wait-WinRt ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
        $recognized = Wait-WinRt ($script:ocrEngine.RecognizeAsync($software)) ([Windows.Media.Ocr.OcrResult])

        $words = @()
        foreach ($line in $recognized.Lines) {
            foreach ($word in $line.Words) {
                $r = $word.BoundingRect
                $words += [pscustomobject]@{
                    Text = [string]$word.Text
                    X = $band.Left + [int](($r.X + $r.Width / 2) / $Scale)
                    Y = $band.Top + [int](($r.Y + $r.Height / 2) / $Scale)
                }
            }
        }
        return $words
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
        if ($null -ne $scaled) { $scaled.Dispose() }
        if ($null -ne $cropped) { $cropped.Dispose() }
        $full.Dispose()
    }
}

# OCR 이 '오픈치|팅' 처럼 흘려 읽어도 알아보도록 느슨하게 비교합니다.
function Test-TabWord([string]$Text, [string]$Kind) {
    $clean = ([string]$Text) -replace '[^가-힣]', ''
    if (-not $clean) { return $false }
    if ($Kind -eq 'open') { return ($clean -like '오픈*') }
    return ($clean -like '채팅*' -and $clean -notlike '오픈*')
}

function Find-TabPoint([object[]]$Words, [string]$Kind) {
    $matched = @($Words | Where-Object { Test-TabWord $_.Text $Kind } | Sort-Object Y, X)
    if ($matched.Count -eq 0) { return $null }
    return $matched[0]
}

# 지금 선택된 탭이 [채팅] 인지 [오픈채팅] 인지 글자 진하기로 판별합니다.
# 카카오톡은 선택된 탭을 진한 검정으로, 선택되지 않은 탭을 회색으로 그립니다.
function Get-DarkPixelRatio([System.Drawing.Bitmap]$Bitmap, [object]$MainWindow, [object]$Word, [int]$HalfWidth = 26, [int]$HalfHeight = 10) {
    $centerX = $Word.X - $MainWindow.Rect.Left
    $centerY = $Word.Y - $MainWindow.Rect.Top
    $left = [Math]::Max(0, $centerX - $HalfWidth)
    $right = [Math]::Min($Bitmap.Width - 1, $centerX + $HalfWidth)
    $top = [Math]::Max(0, $centerY - $HalfHeight)
    $bottom = [Math]::Min($Bitmap.Height - 1, $centerY + $HalfHeight)
    if ($right -le $left -or $bottom -le $top) { return 0.0 }
    try { return [FastImage]::DarkRatio($Bitmap, $left, $top, $right, $bottom, 0.42) }
    catch {
        $dark = 0
        $total = 0
        for ($y = $top; $y -le $bottom; $y += 2) {
            for ($x = $left; $x -le $right; $x += 2) {
                $total++
                if ($Bitmap.GetPixel($x, $y).GetBrightness() -lt 0.42) { $dark++ }
            }
        }
        if ($total -eq 0) { return 0.0 }
        return ([double]$dark / [double]$total)
    }
}

function Get-ActiveKakaoTab([object]$Layout) {
    # 1순위: 카카오톡 내부 화면 이름
    $byName = Get-RoomTypeFromViewName $Layout.ViewName
    if ($byName -eq $script:RoomTypeOpen) { return $script:RoomTypeOpen }

    # 2순위: 위쪽 탭 글자의 진하기 비교
    try {
        $words = @(Get-TopBandWords $Layout)
        $chatWord = Find-TabPoint $words 'chat'
        $openWord = Find-TabPoint $words 'open'
        if ($null -eq $chatWord -and $null -eq $openWord) { return $byName }
        $image = Get-WindowImage $Layout.Main
        try {
            $chatRatio = if ($null -ne $chatWord) { Get-DarkPixelRatio $image $Layout.Main $chatWord } else { 0.0 }
            $openRatio = if ($null -ne $openWord) { Get-DarkPixelRatio $image $Layout.Main $openWord } else { 0.0 }
            $script:lastTabRatios = "채팅 $([Math]::Round($chatRatio, 3)) / 오픈채팅 $([Math]::Round($openRatio, 3))"
            # 차이가 뚜렷할 때만 판정합니다.
            if ([Math]::Abs($chatRatio - $openRatio) -lt 0.04) { return $byName }
            if ($openRatio -gt $chatRatio) { return $script:RoomTypeOpen }
            return $script:RoomTypeNormal
        } finally { $image.Dispose() }
    } catch { return $byName }
}

# 돋보기 아이콘은 글자가 없어 위치를 확정할 수 없습니다.
# 몇 군데를 눌러 보고 검색 입력칸이 나타나는 자리를 찾아 기억합니다.
function Get-VisibleSearchEdit([object]$MainWindow) {
    $edits = @([NativeKakao]::GetChildWindows($MainWindow.Handle) |
        Where-Object { $_.ClassName -eq 'Edit' -and $_.Visible -and $_.Width -ge 60 -and $_.Height -ge 14 })
    if ($edits.Count -eq 0) { return $null }
    return $edits[0]
}

function Open-KakaoSearchBox([object]$Layout, [object[]]$Words) {
    $main = $Layout.Main
    if ($null -ne (Get-VisibleSearchEdit $main)) { return $true }

    $band = Get-TopBandRegion $Layout
    if ($null -eq $band) { return $false }
    $tabChat = Find-TabPoint $Words 'chat'
    $rowY = if ($null -ne $tabChat) { $tabChat.Y } else { $band.Top + [int]($band.Height * 0.30) }
    $right = $band.Left + $band.Width

    $offsets = New-Object System.Collections.Generic.List[int]
    $saved = [int]$script:config.Calibration.SearchIconOffset
    if ($saved -gt 0) { $offsets.Add($saved) }
    foreach ($candidate in @(105, 112, 98, 120, 92, 128, 85)) {
        if (-not $offsets.Contains($candidate)) { $offsets.Add($candidate) }
    }

    foreach ($offset in $offsets) {
        $x = $right - $offset
        if ($x -le $band.Left) { continue }
        Invoke-PointClick $x $rowY
        Start-Sleep -Milliseconds 320
        if ($null -ne (Get-VisibleSearchEdit $main)) {
            if ($script:config.Calibration.SearchIconOffset -ne $offset) {
                $script:config.Calibration.SearchIconOffset = $offset
                try { Save-Config $script:config } catch { }
                Write-RunLog "검색 아이콘 위치를 찾았습니다. (오른쪽 끝에서 $($offset)px)"
            }
            return $true
        }
    }
    return $false
}

# 검색 결과에는 '친구' '채팅방' 같은 구분 머리글이 섞여 있어 첫 줄이 방이 아닐 수 있습니다.
# 읽은 글자 중 검색어와 가장 비슷한 줄을 찾아 그 줄을 누릅니다.
# 이름을 견주기 위한 형태로 다듬습니다.
# ☆ ♥ 이모지 같은 기호는 화면에서 읽히지 않는 경우가 많아,
# 양쪽 모두에서 떼어 내고 글자와 숫자만으로 견줍니다.
function ConvertTo-CompareKey([string]$Text) {
    $clean = ([string]$Text) -replace '[^0-9A-Za-z가-힣]', ''
    return $clean.ToLowerInvariant()
}

# OCR 은 글자를 조금씩 틀리게 읽습니다. 겹치는 글자 비율로 비슷한 정도를 봅니다.
# 여기서 비슷하다고 판단해도, 방을 연 뒤 창 제목이 정확히 일치하지 않으면
# 전송하지 않으므로 잘못된 방에 보내지는 일은 없습니다.
function Get-NameSimilarity([string]$A, [string]$B) {
    $x = ConvertTo-CompareKey $A
    $y = ConvertTo-CompareKey $B
    if (-not $x -or -not $y) { return 0.0 }
    $pool = New-Object System.Collections.Generic.List[char]
    foreach ($ch in $y.ToCharArray()) { $pool.Add($ch) }
    $hits = 0
    foreach ($ch in $x.ToCharArray()) {
        $index = $pool.IndexOf($ch)
        if ($index -ge 0) { $pool.RemoveAt($index); $hits++ }
    }
    $longest = [Math]::Max($x.Length, $y.Length)
    if ($longest -le 0) { return 0.0 }
    return ([double]$hits / [double]$longest)
}

function Find-SearchResultLine([object[]]$Lines, [string]$Query, [int]$Width) {
    $all = @($Lines)
    if ($all.Count -eq 0) { return $null }
    $target = ConvertTo-CompareKey $Query
    if (-not $target) { return $null }
    $best = $null
    $bestScore = 0
    foreach ($line in $all) {
        if ($line.Left -lt ($Width * 0.10) -or $line.Left -gt ($Width * 0.55)) { continue }
        $candidate = ConvertTo-CompareKey $line.Text
        if (-not $candidate) { continue }
        # 짧은 조각이 우연히 겹쳐 엉뚱한 줄을 고르지 않도록, 길이가 비슷할 때만 인정합니다.
        $minLength = [Math]::Max(2, [int]([Math]::Ceiling($target.Length * 0.5)))
        if ($candidate.Length -lt $minLength) { continue }
        $score = 0
        if ($candidate -eq $target) { $score = 100 }
        elseif ($candidate.StartsWith($target) -or $target.StartsWith($candidate)) { $score = 80 }
        elseif ($candidate.Contains($target) -or $target.Contains($candidate)) { $score = 65 }
        else {
            $similarity = Get-NameSimilarity $candidate $target
            if ($similarity -ge 0.6) { $score = 50 + [int](($similarity - 0.6) * 30) }
        }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $line }
    }
    if ($bestScore -ge 50) { return $best }
    return $null
}

function Close-KakaoSearchBox {
    $main = $script:activeKakaoWindow
    if ($null -eq $main) { return }
    $edit = Get-VisibleSearchEdit $main
    if ($null -ne $edit) {
        [NativeKakao]::SetControlText($edit.Handle, '')
        [NativeKakao]::PressKey($edit.Handle, 0x1B)
    }
    Start-Sleep -Milliseconds 150
}

# 검색칸에 검색어를 넣습니다. 창을 앞으로 가져오지 않고 컨트롤에 직접 보냅니다.
function Set-KakaoSearchQuery([object]$Layout, [string]$Query, [bool]$Fresh) {
    $main = $Layout.Main
    $edit = Get-VisibleSearchEdit $main
    if ($null -eq $edit) {
        $words = @(Get-TopBandWords $Layout)
        if (-not (Open-KakaoSearchBox $Layout $words)) { return $false }
        Start-Sleep -Milliseconds 240
        $edit = Get-VisibleSearchEdit $main
        if ($null -eq $edit) { return $false }
    }

    # 입력칸을 눌러 활성화한 뒤 글자를 하나씩 보냅니다.
    # 카카오톡이 글자마다 검색을 다시 하므로 WM_CHAR 방식이 가장 확실합니다.
    [NativeKakao]::ClickControl($edit.Handle, ($edit.Rect.Left + [int]($edit.Width / 2)), ($edit.Rect.Top + [int]($edit.Height / 2)), $false)
    Start-Sleep -Milliseconds 120
    [NativeKakao]::SetControlText($edit.Handle, '')
    Start-Sleep -Milliseconds 60
    [NativeKakao]::TypeText($edit.Handle, $Query)
    Start-Sleep -Milliseconds 120

    # 실제로 들어갔는지 확인합니다.
    $written = [NativeKakao]::GetControlText($edit.Handle)
    if (($written -replace '\s', '') -ne ($Query -replace '\s', '')) {
        # 한 번 더: 붙여넣기로 시도
        Set-ClipboardTextSafe $Query
        [NativeKakao]::SetControlText($edit.Handle, '')
        Start-Sleep -Milliseconds 60
        [NativeKakao]::PasteInto($edit.Handle)
        Start-Sleep -Milliseconds 200
        $written = [NativeKakao]::GetControlText($edit.Handle)
    }
    return (($written -replace '\s', '') -eq ($Query -replace '\s', ''))
}

# 목록을 읽는 데는 검색창이 필요하지 않습니다. 보낼 때만 필요합니다.
# 이 둘을 구분하지 않아 오픈채팅 탭에서 읽기가 막히던 문제가 있었습니다.
function Test-KakaoReady([bool]$Restore = $false, [bool]$NeedSearch = $false) {
    $main = Get-MainKakaoWindow $Restore
    if ($null -eq $main) {
        return [pscustomobject]@{ Ok = $false; Reason = 'PC 카카오톡이 실행되어 있지 않습니다. 카카오톡을 먼저 실행해 주세요.'; Layout = $null }
    }
    if (Test-WindowMinimized $main) {
        $reason = if (-not $main.Visible) {
            '카카오톡 창이 닫혀 있습니다. 화면 오른쪽 아래 트레이(시계 옆)의 카카오톡 아이콘을 눌러 창을 열어 주세요.'
        } else {
            '카카오톡 창이 최소화되어 있습니다. 작업 표시줄에서 카카오톡 창을 열어 주세요.'
        }
        return [pscustomobject]@{ Ok = $false; Reason = $reason; Layout = $null }
    }
    $layout = Get-KakaoLayout $main
    if ($null -eq $layout.List) {
        return [pscustomobject]@{ Ok = $false; Reason = '채팅방 목록 영역을 찾지 못했습니다. 카카오톡에서 채팅 또는 오픈채팅 탭을 눌러 목록이 보이게 해 주세요.'; Layout = $layout }
    }
    if ($NeedSearch -and $null -eq (Get-TopBandRegion $layout)) {
        return [pscustomobject]@{ Ok = $false; Reason = '카카오톡 위쪽 탭 영역을 찾지 못했습니다. 창을 조금 더 크게 해 보세요.'; Layout = $layout }
    }
    return [pscustomobject]@{ Ok = $true; Reason = ''; Layout = $layout }
}

# 화면 좌표를 그 자리에 있는 컨트롤에 대한 메시지로 바꿔 보냅니다.
# 마우스를 움직이지 않고, 카카오톡이 뒤에 있어도 동작합니다.
# 주의: 이 함수는 값을 돌려주지 않습니다.
# 예전에 $true 를 돌려주다가 그 값이 호출한 함수의 반환값에 섞여
# 채팅창 대신 배열이 넘어가는 문제가 있었습니다.
function Invoke-PointClick([int]$X, [int]$Y, [bool]$DoubleClick = $false) {
    $main = $script:activeKakaoWindow
    if ($null -eq $main) { $main = Get-MainKakaoWindow }
    if ($null -eq $main) { return }
    $target = [NativeKakao]::ChildAtPoint($main.Handle, $X, $Y)
    if ($target -eq [IntPtr]::Zero) { $target = $main.Handle }
    [NativeKakao]::ClickControl($target, $X, $Y, $DoubleClick)
}

# 특정 컨트롤에 직접 누르기 (좌표를 아는 컨트롤이 있을 때)
function Invoke-ControlClick([object]$Control, [int]$X, [int]$Y, [bool]$DoubleClick = $false) {
    [NativeKakao]::ClickControl($Control.Handle, $X, $Y, $DoubleClick)
}

function Invoke-RatioClick([object]$Window, [double]$XRatio, [double]$YRatio) {
    $x = $Window.Rect.Left + [int]($Window.Width * $XRatio)
    $y = $Window.Rect.Top + [int]($Window.Height * $YRatio)
    [NativeKakao]::Click($x, $y, $false)
}

# 필요한 탭으로 전환합니다. 이미 그 탭이면 아무것도 하지 않습니다.
function Enter-KakaoTab([string]$Type) {
    $main = Get-MainKakaoWindow $true
    if ($null -eq $main) { throw 'PC 카카오톡이 실행되어 있지 않습니다. 카카오톡을 먼저 실행해 주세요.' }
    if (Test-WindowMinimized $main) {
        if (-not $main.Visible) {
            throw "카카오톡 창이 닫혀 있습니다.`r`n화면 오른쪽 아래 트레이(시계 옆)의 카카오톡 아이콘을 눌러 창을 열어 둔 뒤 다시 시도해 주세요."
        }
        throw "카카오톡 창이 최소화되어 있습니다.`r`n작업 표시줄에서 카카오톡 창을 열어 둔 뒤 다시 시도해 주세요."
    }
    $layout = Get-KakaoLayout $main
    $wantOpen = ($Type -eq $script:RoomTypeOpen)
    if ($wantOpen -and $layout.IsOpenChatList) { return $layout }
    if (-not $wantOpen -and $layout.IsChatList) { return $layout }

    $label = if ($wantOpen) { '오픈채팅' } else { '채팅' }
    $words = @(Get-TopBandWords $layout)
    $tab = Find-TabPoint $words $(if ($wantOpen) { 'open' } else { 'chat' })
    if ($null -eq $tab) {
        throw "카카오톡 위쪽에서 [$label] 탭을 찾지 못했습니다.`r`n카카오톡에서 직접 [$label] 탭을 눌러 목록이 보이게 해 주세요."
    }
    Invoke-PointClick $tab.X $tab.Y
    Start-Sleep -Milliseconds 650
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

# 창 제목이 목표 방과 같은지 봅니다.
# 목록에 보이는 이름은 길면 뒤가 잘립니다. 그래서 저장된 이름이 창 제목보다 짧을 수 있습니다.
# 앞부분만 같으면 맞다고 볼 수도 있지만, 그러면 이름이 비슷한 다른 방에 보낼 위험이 있습니다.
# 그래서 앞부분이 같은 방이 딱 하나일 때만 맞다고 봅니다. 둘 이상이면 보내지 않습니다.
function Test-RoomTitle([string]$Actual, [string]$Expected) {
    $a = ([string]$Actual).Trim()
    $e = ([string]$Expected).Trim()
    if (-not $a -or -not $e) { return $false }
    if ($a -eq $e) { return $true }
    # 카카오톡은 인원수를 붙여 "방이름 (12)" 형태로 창 제목을 표시하기도 합니다.
    if ($a -match ('^' + [regex]::Escape($e) + '\s*\(\d+\)$')) { return $true }

    $keyActual = ConvertTo-CompareKey $a
    $keyExpected = ConvertTo-CompareKey $e
    if (-not $keyActual -or -not $keyExpected) { return $false }
    if ($keyActual -eq $keyExpected) { return $true }
    # 인원수가 붙은 경우를 한 번 더 봅니다.
    if ($keyActual -match ('^' + [regex]::Escape($keyExpected) + '\d{1,4}$')) { return $true }

    # 여기부터는 잘린 이름 처리입니다.
    # 실제로 잘려 있던 이름에만 씁니다. 그러지 않으면
    # "우리반 공지방" 이 "우리반 공지방 2기" 와 같은 방으로 보입니다.
    if (-not (Test-TruncatedRoom $e)) { return $false }
    if ($keyExpected.Length -lt 6) { return $false }
    if (-not $keyActual.StartsWith($keyExpected)) { return $false }
    # 저장된 방 중에 같은 앞부분을 가진 방이 딱 하나일 때만 인정합니다.
    # 하나도 없으면 우리가 모르는 방이고, 둘 이상이면 어느 방인지 알 수 없습니다.
    # 둘 다 보내면 안 되는 상황입니다.
    $sameStart = 0
    try {
        foreach ($known in @($script:config.KnownRooms)) {
            $keyKnown = ConvertTo-CompareKey ([string]$known)
            if (-not $keyKnown) { continue }
            # 저장된 이름이 잘린 이름으로 시작하는 경우만 셉니다.
            # 반대 방향까지 세면 짧은 이름의 다른 방까지 걸려들어
            # 엉뚱한 방을 같은 방으로 볼 수 있습니다.
            if ($keyKnown.StartsWith($keyExpected)) { $sameStart++ }
        }
    } catch { return $false }
    if ($sameStart -ne 1) { return $false }
    return $true
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

# 함수가 값을 여럿 돌려줘도 채팅창 하나만 골라냅니다.
function Get-SingleChatWindow([object]$Value) {
    foreach ($item in @($Value)) {
        if ($null -eq $item) { continue }
        if ($item -is [NativeKakao+WindowInfo]) { return $item }
    }
    return $null
}

function Close-ChatWindow([object]$Window) {
    # 창을 앞으로 가져오지 않고 닫습니다.
    [NativeKakao]::CloseWindow($Window.Handle)
    $deadline = (Get-Date).AddMilliseconds(1500)
    while ((Get-Date) -lt $deadline) {
        $still = [NativeKakao]::GetWindow($Window.Handle)
        if ($null -eq $still -or -not $still.Visible) { return }
        Start-Sleep -Milliseconds 60
    }
}

# 채팅창의 글 입력칸(RICHEDIT50W)을 찾습니다.
# 창이나 컨트롤이 아직 살아 있는지 확인합니다.
# 사라진 컨트롤에서 글자를 읽으면 빈 값이 나오는데,
# 그걸 '입력칸이 비었다 = 전송 성공' 으로 오해하면 안 됩니다.
function Test-ControlAlive([object]$Control) {
    if ($null -eq $Control) { return $false }
    try {
        $window = [NativeKakao]::GetWindow($Control.Handle)
        return ($null -ne $window -and $window.Width -gt 0 -and $window.Height -gt 0)
    } catch { return $false }
}

# 방이 완전히 열릴 때까지 기다립니다.
# 제목이 목표 방과 일치하고, 그 제목이 흔들리지 않고, 입력칸까지 준비돼야 통과입니다.
function Wait-ChatWindowReady([object]$Chat, [string]$Room, [int]$TimeoutMs = 8000) {
    if ($TimeoutMs -le 0) { $TimeoutMs = 8000 }
    $started = Get-Date
    $deadline = $started.AddMilliseconds($TimeoutMs)
    $lastTitle = ''
    $stable = 0
    $sawTitle = ''
    while ((Get-Date) -lt $deadline) {
        $fresh = $null
        try { $fresh = [NativeKakao]::GetWindow($Chat.Handle) } catch { }
        if ($null -eq $fresh -or $fresh.Width -le 0 -or $fresh.Height -le 0) { return $null }

        $title = ([string]$fresh.Title).Trim()
        if ($title -and $title -eq $lastTitle) { $stable++ } else { $stable = 0 }
        $lastTitle = $title
        if ($title) { $sawTitle = $title }

        # 제목이 두 번 연속 같고(=바뀌는 중이 아니고) 목표 방과 맞을 때만 봅니다.
        if ($stable -ge 2 -and (Test-RoomTitle $title $Room)) {
            $box = Get-ChatInputControl $fresh
            if ($null -ne $box -and (Test-ControlAlive $box)) {
                # 여기까지는 창이 준비된 것이고, 대화 내용은 아직 불러오는 중일 수 있습니다.
                # 남은 시간만큼 화면이 멈추기를 기다립니다. 못 기다려도 실패로 보지 않고
                # 전송할 때 다시 확인하고 필요하면 다시 보냅니다.
                $left = [int]($deadline - (Get-Date)).TotalMilliseconds
                $settled = $true
                if ($left -gt 400) { $settled = Wait-ChatContentSettled $fresh $left }
                return [pscustomobject]@{ Window = $fresh; InputBox = $box; Settled = $settled }
            }
        }
        Start-Sleep -Milliseconds 200
    }
    if ($sawTitle -and -not (Test-RoomTitle $sawTitle $Room)) {
        Write-RunLog "  (열린 창 제목은 '$sawTitle' 이었습니다)"
    }
    return $null
}

# 대화 목록(말풍선이 보이는 곳) 컨트롤을 찾습니다.
function Get-ChatListControl([object]$Chat) {
    if ($null -eq $Chat) { return $null }
    try {
        foreach ($child in [NativeKakao]::GetChildWindows($Chat.Handle)) {
            if ($child.ClassName -eq 'EVA_VH_ListControl_Dblclk' -and $child.Visible -and $child.Height -gt 100) { return $child }
        }
    } catch { }
    return $null
}

# 대화 영역의 모습을 숫자로 요약합니다. 네 칸으로 나눠 봐서 조금만 바뀌어도 알아챕니다.
function Get-ChatListSignature([object]$List) {
    $window = [NativeKakao]::GetWindow($List.Handle)
    if ($null -eq $window -or $window.Width -le 0 -or $window.Height -le 0) { return '' }
    $image = $null
    try { $image = Get-WindowImage $window } catch { return '' }
    try {
        $parts = @()
        for ($i = 0; $i -lt 4; $i++) {
            $top = [int]($image.Height * $i / 4)
            $bottom = [int]($image.Height * ($i + 1) / 4) - 1
            $parts += [Math]::Round([FastImage]::DarkRatio($image, 0, $top, ($image.Width - 1), $bottom, 0.72), 5)
        }
        return ($parts -join '|')
    } catch { return '' }
    finally { if ($null -ne $image) { try { $image.Dispose() } catch { } } }
}

# 대화 내용을 아직 불러오는 중이면 Enter 를 눌러도 전송되지 않습니다.
# 실제로 재 보니 제목과 입력칸은 0.4초면 준비되는데,
# 대화 내용은 방에 따라 12초까지 계속 그려지고 있었습니다.
# 그 사이에 보내면 아무 일도 일어나지 않습니다. 그래서 화면이 멈출 때까지 기다립니다.
# 대화가 계속 올라오는 방은 영영 안 멈추므로, 정해진 시간까지만 기다리고 넘어갑니다.
function Wait-ChatContentSettled([object]$Chat, [int]$TimeoutMs) {
    if ($TimeoutMs -le 0) { return $true }
    $list = Get-ChatListControl $Chat
    if ($null -eq $list) { return $true }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    $last = ''
    $same = 0
    while ((Get-Date) -lt $deadline) {
        $signature = Get-ChatListSignature $list
        if ($signature -and $signature -eq $last) { $same++ } else { $same = 0 }
        $last = $signature
        if ($same -ge 2) { return $true }
        Start-Sleep -Milliseconds 220
    }
    return $false
}

function Get-ChatInputControl([object]$ChatWindow) {
    $children = @([NativeKakao]::GetChildWindows($ChatWindow.Handle))
    $rich = @($children | Where-Object {
        $_.Visible -and $_.ClassName -like 'RICHEDIT*' -and $_.Width -ge 80 -and $_.Height -ge 16
    } | Sort-Object -Property @{ Expression = { $_.Rect.Top } } -Descending)
    if ($rich.Count -gt 0) { return $rich[0] }
    $edits = @($children | Where-Object {
        $_.Visible -and ($_.ClassName -eq 'Edit' -or $_.ClassName -like '*Edit*') -and $_.Width -ge 80
    } | Sort-Object -Property @{ Expression = { $_.Rect.Top } } -Descending)
    if ($edits.Count -gt 0) { return $edits[0] }
    return $null
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

# 채팅 목록의 아이콘·표시가 글자로 잘못 읽혀 이름 앞에 '0 ' 같은 잡티가 붙습니다.
# 실제 이름이 숫자로 시작하는 경우(05K-니자인 등)는 건드리지 않습니다.
function Remove-RoomNameNoise([string]$RawName) {
    $name = ([string]$RawName).Trim()
    if (-not $name) { return '' }
    # 안 읽은 개수 뱃지가 이름 앞에 붙어 읽힙니다. '0 홍보방' → '홍보방'
    # 진짜 이름이 숫자로 시작하는 방도 있어서, 뱃지로 확실한 0 과 O 만 뗍니다.
    $name = $name -replace '^[0OoＯ]\s+', ''
    $name = $name -replace '^0(?=[가-힣A-Za-z])', ''
    # 이름이 길면 카카오톡이 뒤를 … 로 줄여 보여 줍니다. 그 표시를 뗍니다.
    $name = $name -replace '[…⋯]+\s*$', ''
    # 화면 글자 인식이 줄 끝에 남기는 찌꺼기입니다.
    $name = $name -replace '[′`´ˊˋ˙·,]+$', ''
    # 이모티콘이나 그림 문자는 이름에서 뺍니다. 목록이 읽기 어려워집니다.
    # 뺀 뒤에도 방을 찾는 데는 문제가 없습니다. 방 찾기는 한글·영문·숫자만 견줍니다.
    $kept = New-Object System.Text.StringBuilder
    foreach ($ch in $name.ToCharArray()) {
        $code = [int][char]$ch
        $isEmoji = ($code -ge 0x1F000 -and $code -le 0x1FAFF) -or ($code -ge 0x2600 -and $code -le 0x27BF)
        $isSurrogate = ($code -ge 0xD800 -and $code -le 0xDFFF)
        $isMark = ($code -ge 0xFE00 -and $code -le 0xFE0F) -or $code -eq 0x20E3
        if ($isEmoji -or $isSurrogate -or $isMark) { continue }
        [void]$kept.Append($ch)
    }
    $name = $kept.ToString()
    $name = $name -replace '\s{2,}', ' '
    return $name.Trim()
}

# 카카오톡 목록은 긴 이름의 뒤를 … 로 줄여 보여 줍니다.
# 그렇게 잘린 이름은 창 제목과 정확히 같을 수가 없어서 앞부분으로 견줘야 합니다.
# 다만 앞부분 비교는 위험합니다. "우리반 공지방" 과 "우리반 공지방 2기" 를
# 같은 방으로 볼 수 있기 때문입니다.
# 그래서 실제로 잘려 있던 이름만 따로 기억해 두고, 그 이름에만 앞부분 비교를 씁니다.
function Add-TruncatedRoom([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return }
    try {
        $list = @($script:config.TruncatedRooms)
        if ($list -contains $Name) { return }
        $script:config.TruncatedRooms = @($list + $Name)
    } catch { }
}

function Test-TruncatedRoom([string]$Name) {
    try { return (@($script:config.TruncatedRooms) -contains $Name) } catch { return $false }
}

function ConvertTo-RoomCandidate([string]$RawName) {
    if ([string]::IsNullOrWhiteSpace($RawName)) { return $null }
    $parts = @($RawName -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($parts.Count -eq 0) { return $null }
    $wasTruncated = ($parts[0] -match '[…⋯]\s*$')
    $name = Remove-RoomNameNoise $parts[0]
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
    if ($wasTruncated) { Add-TruncatedRoom $name }
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
    try { return [FastImage]::IsBlank($Bitmap) }
    catch {
        $seen = @{}
        for ($y = 0; $y -lt $Bitmap.Height; $y += 17) {
            for ($x = 0; $x -lt $Bitmap.Width; $x += 13) {
                $seen[$Bitmap.GetPixel($x, $y).ToArgb()] = $true
                if ($seen.Keys.Count -gt 3) { return $false }
            }
        }
        return $true
    }
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
    if ($null -eq $Window) { return @() }
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
    $ready = Test-KakaoReady $true $false
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
# 목록을 위에서부터 훑어 방을 찾아 엽니다.
# 검색보다 느리지만, 검색창이 열리지 않는 환경에서도 확실히 동작합니다.
function Open-RoomFromList([string]$Query, [object]$Layout, [int]$MaxPages = 40) {
    $list = $Layout.List
    if ($null -eq $list) { return $null }
    $main = $Layout.Main

    # 맨 위로 올립니다.
    for ($i = 0; $i -lt ($MaxPages + 4); $i++) { Move-ListByWheel $list 'up' 8; Start-Sleep -Milliseconds 20 }
    Start-Sleep -Milliseconds 250

    $existing = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($window.Visible) { $existing[[string]$window.Handle] = $true }
        }
    }

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $lines = @(Get-OcrLines $list 2)
        $matched = Find-SearchResultLine $lines $Query $list.Width
        if ($null -ne $matched) {
            $x = $list.Rect.Left + [int]($list.Width * 0.35)
            $y = $list.Rect.Top + $matched.Top + 8
            Invoke-ControlClick $list $x $y $true
            $deadline = (Get-Date).AddMilliseconds(3500)
            while ((Get-Date) -lt $deadline) {
                foreach ($process in (Get-KakaoProcesses)) {
                    foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                        if (-not $window.Visible -or $window.Handle -eq $main.Handle) { continue }
                        if ($existing.ContainsKey([string]$window.Handle)) { continue }
                        if ([string]::IsNullOrWhiteSpace($window.Title)) { continue }
                        return $window
                    }
                }
                Start-Sleep -Milliseconds 60
            }
            return $null
        }
        $names = @(Get-RoomNamesFromOcrLines $lines $list.Width)
        $notches = [Math]::Max(3, [Math]::Min(8, $names.Count - 1))
        Move-ListByWheel $list 'down' $notches
        Start-Sleep -Milliseconds 170
    }
    return $null
}

function Open-RoomBySearch([string]$Query, [string]$RoomType, [int]$TimeoutMs = 5000) {
    $layout = Enter-KakaoTab $RoomType
    if ($null -eq $layout.List) {
        throw '채팅 목록을 찾지 못했습니다. 카카오톡 창을 조금 더 크게 하고, 목록이 보이게 해 주세요.'
    }
    $main = $layout.Main
    $existing = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($window.Visible) { $existing[[string]$window.Handle] = $true }
        }
    }

    # 붙여넣기 직전에 포커스가 흔들리지 않도록 클립보드를 먼저 준비합니다.
    Set-ClipboardTextSafe $Query

    # 검색어를 넣고, 결과에서 검색어와 맞는 줄을 찾습니다. 한 번 실패하면 검색창을 새로 열어 다시 시도합니다.
    $matchedLine = $null
    $list = $layout.List
    $searchUsable = $true
    for ($attempt = 0; $attempt -lt 2; $attempt++) {
        if (-not (Set-KakaoSearchQuery $layout $Query ($attempt -gt 0))) {
            $searchUsable = $false
            break
        }
        $current = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -ne $current.List) { $list = $current.List }
        if ($null -eq $list) { continue }
        $searchDeadline = (Get-Date).AddMilliseconds(2200)
        while ((Get-Date) -lt $searchDeadline) {
            Start-Sleep -Milliseconds 200
            try {
                $refreshed = Get-KakaoLayout (Get-MainKakaoWindow)
                if ($null -ne $refreshed.List) { $list = $refreshed.List }
                $lines = @(Get-OcrLines $list 2)
                $matchedLine = Find-SearchResultLine $lines $Query $list.Width
                if ($null -ne $matchedLine) { break }
            } catch { }
        }
        if ($null -ne $matchedLine) { break }
    }

    if ($null -eq $matchedLine) {
        # 검색이 안 되는 환경이면 목록을 훑어 찾습니다.
        Close-KakaoSearchBox
        Start-Sleep -Milliseconds 200
        if (-not $searchUsable) { Write-RunLog "검색창을 쓸 수 없어 목록에서 찾습니다: '$Query'" }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        return (Open-RoomFromList $Query $fresh)
    }

    $resultX = $list.Rect.Left + [int]($list.Width * 0.35)
    $resultY = $list.Rect.Top + $matchedLine.Top + 8
    Invoke-PointClick $resultX $resultY $true

    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible -or $window.Handle -eq $main.Handle) { continue }
                if ($existing.ContainsKey([string]$window.Handle)) { continue }
                if ([string]::IsNullOrWhiteSpace($window.Title)) { continue }
                Close-KakaoSearchBox
                return $window
            }
        }
        Start-Sleep -Milliseconds 80
    }

    Close-KakaoSearchBox
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

# 첨부가 실제로 붙는지만 확인합니다.
# 붙여 본 뒤 바로 치우고 보내지 않습니다.
# 카카오톡 판이나 화면 배율이 사람마다 달라서, 실제로 보내기 전에
# 이 확인을 한 번 해 보면 첨부가 될 환경인지 미리 알 수 있습니다.
function Invoke-AttachmentCheck([string]$Room, [string]$Path) {
    $report = @()
    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { return [pscustomobject]@{ Ok = $false; Text = [string]$ready.Reason } }
    $chat = Get-SingleChatWindow (Open-RoomBySearch $Room (Get-RoomType $Room))
    if ($null -eq $chat) {
        return [pscustomobject]@{ Ok = $false; Text = "'$Room' 채팅창을 열지 못했습니다." }
    }
    try {
        $state = Wait-ChatWindowReady $chat $Room ([Math]::Max(3000, [int]$script:config.OpenTimeoutMs))
        if ($null -eq $state) {
            return [pscustomobject]@{ Ok = $false; Text = "'$Room' 방이 다 열리지 않았습니다. 설정에서 [방 열림 대기]를 늘려 보세요." }
        }
        $icons = @(Find-ChatToolbarIcons $state.Window $state.InputBox)
        $report += "채팅창 아래 아이콘 $($icons.Count)개를 찾았습니다."
        if ($icons.Count -lt 3) {
            $report += '아이콘을 3개 찾지 못했습니다. 채팅창을 조금 크게 키우면 나아집니다.'
        }
        $waitMs = [Math]::Max(500, [int]$script:config.AttachmentWaitMs)
        $outcome = Send-ChatAttachment $state.Window $state.InputBox $Path $waitMs $false
        if ($outcome.Ok) {
            $report += "붙이기 성공 — $($outcome.Method)"
            $report += '붙였던 첨부는 다시 치웠습니다. 보내지 않았습니다.'
        } else {
            $report += "붙이기 실패 — $($outcome.Reason)"
        }
        return [pscustomobject]@{ Ok = [bool]$outcome.Ok; Text = ($report -join "`r`n") }
    } finally {
        Close-ChatWindow $chat
    }
}

function Invoke-OneRoom([string]$Room, [string]$RoomType, [object]$Content) {
    $chat = Get-SingleChatWindow (Open-RoomBySearch $Room $RoomType)
    if ($null -eq $chat) {
        Write-RunLog "건너뜀: '$Room' — 채팅창을 열지 못했습니다."
        return $false
    }
    return (Send-ToChatWindow $chat $Room $Content)
}

# 이미 열린 채팅창에 보냅니다. 제목이 정확히 일치할 때만 전송합니다.
function Send-ToChatWindow([object]$Chat, [string]$Room, [object]$Content) {
    # 대화가 많이 쌓인 방은 창이 뜬 뒤에도 한참 뒤에야 내용이 채워집니다.
    # 그 사이에 판단하면 제목이 아직 이전 방이거나 입력칸이 준비되지 않은 상태라
    # 엉뚱한 방에 보내거나, 보내지도 않고 보낸 것으로 착각합니다.
    # 그래서 방이 완전히 열릴 때까지 기다린 뒤에만 손을 댑니다.
    $ready = Wait-ChatWindowReady $Chat $Room ([int]$Content.OpenTimeoutMs)
    if ($null -eq $ready) {
        Write-RunLog "건너뜀: '$Room' — 방이 다 열리지 않았습니다. (대화가 많으면 오래 걸립니다)"
        Close-ChatWindow $Chat
        return $false
    }
    $chat = $ready.Window

    if ([bool]$Content.DryRun) {
        Write-RunLog "확인 성공: '$Room' (전송하지 않음)"
        Close-ChatWindow $chat
        return $true
    }

    $inputBox = $ready.InputBox

    $message = [string]$Content.Message
    if (-not [string]::IsNullOrWhiteSpace($message)) {
        $how = Send-ChatText $chat $inputBox $message ([int]$Content.SettleMs)
        if (-not $how) {
            $why = $script:lastSendProblem
            if (-not $why) { $why = '까닭을 알 수 없습니다.' }
            Write-RunLog "실패: '$Room' — $why 입력칸을 비우고 넘어갑니다."
            Clear-ChatInput $inputBox
            Close-ChatWindow $chat
            return $false
        }
        if ($script:sendMethodLogged -ne $how) {
            $script:sendMethodLogged = $how
            Write-RunLog "전송 방식: $how"
        }
    }

    $waitMs = [Math]::Max(500, [int]$Content.AttachmentWaitMs)
    foreach ($attachment in @($Content.Attachments)) {
        $path = [string]$attachment
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-RunLog "첨부 건너뜀: 파일 없음 — $path"
            continue
        }
        $name = [System.IO.Path]::GetFileName($path)
        $outcome = $null
        try { $outcome = Send-ChatAttachment $chat $inputBox $path $waitMs $true } catch { $outcome = $null }
        if ($null -eq $outcome) {
            Write-RunLog "첨부 실패: '$name' — 알 수 없는 문제가 생겨 보내지 않았습니다."
        } elseif ($outcome.Sent) {
            Write-RunLog "첨부 보냄: $name  [$($outcome.Method) / $($outcome.SendWay)]"
        } else {
            Write-RunLog "첨부 실패: '$name' — $($outcome.Reason) (보내지 않았습니다)"
        }
    }

    Write-RunLog "발송 완료: '$Room'"
    Close-ChatWindow $chat
    return $true
}

# 채팅창을 앞으로 가져오고 입력칸에 포커스를 줍니다.
# 카카오톡은 창 메시지로 넣은 글자를 '사용자 입력'으로 인정하지 않아
# 전송 버튼이 회색으로 남습니다. 그래서 전송할 때만 실제 키보드 입력을 씁니다.
function Enter-ChatForeground([object]$Chat, [object]$InputBox) {
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        [void][NativeKakao]::ForceForeground($Chat.Handle)
        $deadline = (Get-Date).AddMilliseconds(900)
        while ((Get-Date) -lt $deadline) {
            if ([NativeKakao]::GetForegroundWindow() -eq $Chat.Handle) {
                # 마우스를 움직이지 않고 입력칸에 포커스를 줍니다.
                if (-not (Set-ChatInputFocus $Chat)) {
                    [NativeKakao]::ClickControl($InputBox.Handle,
                        ($InputBox.Rect.Left + [int]($InputBox.Width / 2)),
                        ($InputBox.Rect.Top + [int]($InputBox.Height / 2)), $false)
                }
                Start-Sleep -Milliseconds 120
                return $true
            }
            Start-Sleep -Milliseconds 60
        }
    }
    return $false
}

# 실제 키보드 입력으로 붙여넣고 보냅니다. 성공은 입력칸이 비워졌는지로 판단합니다.
# 입력칸에 우리가 넣은 글이 그대로 남아 있는지 봅니다.
# 비어 있으면 이미 전송된 것이므로 다시 보내면 안 됩니다. 두 번 가 버립니다.
# 입력칸에 우리가 넣은 글이 그대로 남아 있는지 봅니다.
# 비어 있으면 이미 전송된 것이므로 다시 보내면 안 됩니다. 두 번 가 버립니다.
function Get-ChatInputState([object]$InputBox, [string]$Message) {
    if (-not (Test-ControlAlive $InputBox)) { return '사라짐' }
    $written = [string](Get-ChatInputText $InputBox)
    if ([string]::IsNullOrWhiteSpace($written)) { return '비어있음' }
    if (($written -replace '\s', '') -eq ($Message -replace '\s', '')) { return '그대로' }
    return '다름'
}

# 입력칸을 비웁니다. 창을 앞으로 가져오지 않습니다.
function Reset-ChatInput([object]$InputBox) {
    if ([string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) { return }
    [NativeKakao]::SelectAllIn($InputBox.Handle)
    [NativeKakao]::ReplaceSelection($InputBox.Handle, '')
    Start-Sleep -Milliseconds 120
    if (-not [string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) {
        [NativeKakao]::SelectAllIn($InputBox.Handle)
        [NativeKakao]::ClearSelection($InputBox.Handle)
        Start-Sleep -Milliseconds 120
    }
}

# 대화창 아래쪽만 자세히 봅니다. 새 말풍선은 항상 맨 아래에 생깁니다.
# 전체를 보면 작은 변화를 놓치므로 아래쪽을 따로 잘라 봅니다.
function Get-ChatTailSignature([object]$List) {
    if ($null -eq $List) { return '' }
    $window = [NativeKakao]::GetWindow($List.Handle)
    if ($null -eq $window -or $window.Width -le 0 -or $window.Height -le 0) { return '' }
    $image = $null
    try { $image = Get-WindowImage $window } catch { return '' }
    try {
        $parts = @()
        $from = [int]($image.Height * 0.55)
        for ($i = 0; $i -lt 5; $i++) {
            $top = $from + [int](($image.Height - $from) * $i / 5)
            $bottom = $from + [int](($image.Height - $from) * ($i + 1) / 5) - 1
            if ($bottom -le $top) { continue }
            $parts += [Math]::Round([FastImage]::DarkRatio($image, 0, $top, ($image.Width - 1), $bottom, 0.72), 6)
        }
        return ($parts -join '|')
    } catch { return '' }
    finally { if ($null -ne $image) { try { $image.Dispose() } catch { } } }
}

# 입력칸이 비었다고 해서 보낸 것이 아닙니다.
# 카카오톡은 프로그램이 넣은 글을 Enter 를 누르는 순간 그냥 지워 버리기도 합니다.
# 그러면 입력칸은 비지만 아무것도 가지 않습니다.
# 예전에 이것을 성공으로 잘못 판단해서, 보내지 않고도 완료라고 알렸습니다.
# 이제 대화창에 새 말풍선이 생겼는지까지 확인합니다.
function Test-ChatMessageLanded([object]$List, [string]$Before, [int]$TimeoutMs) {
    # 확인할 방법이 없으면 막지 않습니다. 다만 이때는 확신할 수 없습니다.
    if ($null -eq $List -or [string]::IsNullOrEmpty($Before)) { return $true }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $now = Get-ChatTailSignature $List
        if ($now -and $now -ne $Before) { return $true }
        Start-Sleep -Milliseconds 150
    }
    return $false
}

# 글을 입력칸에 넣습니다.
# 카카오톡은 사람이 직접 친 것처럼 들어온 글만 실제로 보냅니다.
# 창 메시지로 넣으면 전송 버튼이 노랗게 켜지기까지 하지만,
# Enter 를 누르면 글을 지우고 보내지 않는 경우가 있습니다.
# 그래서 실제 입력(붙여넣기, 키보드)을 먼저 쓰고, 창 메시지는 마지막에 씁니다.
function Add-ChatMessageText([object]$Chat, [object]$InputBox, [string]$Message, [string]$Way) {
    Reset-ChatInput $InputBox
    switch ($Way) {
        '실제 붙여넣기' {
            if (-not (Enter-ChatForeground $Chat $InputBox)) { return $false }
            try { Set-ClipboardTextSafe $Message } catch { return $false }
            [NativeKakao]::PressCtrlKey(0x56)
            Start-Sleep -Milliseconds 380
        }
        '실제 키보드' {
            if (-not (Enter-ChatForeground $Chat $InputBox)) { return $false }
            [System.Windows.Forms.SendKeys]::SendWait((ConvertTo-SendKeysText $Message))
            Start-Sleep -Milliseconds 440
        }
        '창 붙여넣기' {
            try { Set-ClipboardTextSafe $Message } catch { return $false }
            [NativeKakao]::PasteInto($InputBox.Handle)
            Start-Sleep -Milliseconds 340
        }
        '창 메시지' {
            [NativeKakao]::ReplaceSelection($InputBox.Handle, $Message)
            Start-Sleep -Milliseconds 280
        }
        default { return $false }
    }
    return ((Get-ChatInputState $InputBox $Message) -eq '그대로')
}

# 글을 보냅니다.
# 넣는 방법을 확실한 것부터 시도하고, 보낸 뒤에는 대화창을 보고 진짜 갔는지 확인합니다.
# 갔는지 확인되지 않으면 성공이라고 하지 않습니다.
function Send-ChatText([object]$Chat, [object]$InputBox, [string]$Message, [int]$SettleMs = 4000) {
    # 대화를 아직 불러오는 중이면 Enter 가 먹지 않습니다.
    [void](Wait-ChatContentSettled $Chat $SettleMs)
    $list = Get-ChatListControl $Chat
    $script:lastSendProblem = ''

    $ways = @('실제 붙여넣기', '실제 키보드', '창 붙여넣기', '창 메시지')
    foreach ($way in $ways) {
        $before = ''
        if ($null -ne $list) { $before = Get-ChatTailSignature $list }

        $ready = $false
        try { $ready = Add-ChatMessageText $Chat $InputBox $Message $way }
        catch { $script:lastSendProblem = "글을 넣는 중 문제가 생겼습니다: $($_.Exception.Message)"; continue }
        if (-not $ready) {
            $script:lastSendProblem = "'$way' 로는 입력칸에 글을 넣지 못했습니다."
            continue
        }

        $presses = @('입력칸에 Enter', '창을 앞으로 가져와 Enter')
        foreach ($press in $presses) {
            if ((Get-ChatInputState $InputBox $Message) -ne '그대로') { break }
            if ($press -eq '입력칸에 Enter') {
                [NativeKakao]::PressKey($InputBox.Handle, 0x0D)
            } else {
                if (-not (Enter-ChatForeground $Chat $InputBox)) { continue }
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            }
            if (-not (Wait-ChatInputCleared $InputBox 2200)) {
                $script:lastSendProblem = "'$way' 로 넣고 Enter 를 눌렀지만 입력칸이 그대로입니다."
                continue
            }
            if (Test-ChatMessageLanded $list $before 3000) { return "$way + $press" }
            # 입력칸은 비워졌는데 대화창에 아무것도 안 올라왔습니다.
            # 카카오톡이 글을 지운 것입니다. 다른 방법으로 다시 해 봅니다.
            $script:lastSendProblem = "'$way' 로 넣은 글을 카카오톡이 지웠습니다. 보내지지 않았습니다."
            break
        }
    }
    if (-not $script:lastSendProblem) { $script:lastSendProblem = '전송되지 않았습니다.' }
    try { Reset-ChatInput $InputBox } catch { }
    return ''
}

# 사진은 '파일 목록'이 아니라 '그림 자체'를 클립보드에 넣어야 붙습니다.
# 파일 목록만 넣으면 카카오톡이 받아들이지 않아 전송 버튼이 회색으로 남습니다.
function Test-IsImageFile([string]$Path) {
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    return ($ext -in @('.png', '.jpg', '.jpeg', '.gif', '.bmp', '.webp'))
}

function Set-ClipboardImageSafe([string]$Path) {
    $source = [System.Drawing.Image]::FromFile($Path)
    $copy = $null
    try {
        $copy = New-Object System.Drawing.Bitmap($source)
    } finally { $source.Dispose() }
    if ($null -eq $copy) { return $false }
    try {
        for ($attempt = 0; $attempt -lt 6; $attempt++) {
            try {
                # copy=$true 로 클립보드에 실제로 복사해 둡니다.
                # 그냥 SetImage 를 쓰면 우리가 그림 객체를 버리는 순간 클립보드 내용도 사라집니다.
                [System.Windows.Forms.Clipboard]::SetDataObject($copy, $true, 5, 150)
                Start-Sleep -Milliseconds 120
                return $true
            } catch { Start-Sleep -Milliseconds 200 }
        }
    } finally {
        # 클립보드로 복사가 끝난 뒤에 정리합니다.
        Start-Sleep -Milliseconds 80
        try { $copy.Dispose() } catch { }
    }
    return $false
}

# 채팅창 아래쪽(입력 영역)의 모습을 숫자로 요약합니다.
# 붙여넣기 전후를 견주어 첨부가 실제로 붙었는지 확인합니다.
function Get-InputAreaSignature([object]$Chat, [object]$InputBox) {
    try {
        $window = [NativeKakao]::GetWindow($Chat.Handle)
        if ($null -eq $window -or $window.Width -le 0 -or $window.Height -le 0) { return '' }
        $image = Get-WindowImage $window
        try {
            # 입력칸과 그 바로 위(첨부 미리보기가 나타나는 자리)만 봅니다.
            # 대화 내용까지 넣으면 새 메시지가 와도 바뀐 것으로 오해합니다.
            $top = [int]($image.Height * 0.80)
            if ($null -ne $InputBox) {
                $relative = $InputBox.Rect.Top - $window.Rect.Top - 100
                if ($relative -gt 0 -and $relative -lt ($image.Height - 20)) { $top = $relative }
            }
            $ratio = [FastImage]::DarkRatio($image, 0, $top, ($image.Width - 1), ($image.Height - 1), 0.5)
            return ('{0}x{1}:{2}' -f $image.Width, $image.Height, [Math]::Round($ratio, 4))
        } finally { $image.Dispose() }
    } catch { return '' }
}

# 실제 키 신호는 '지금 앞에 있는 창'으로 갑니다.
# 카카오톡 채팅창이 앞에 있는지 확인하지 않고 보내면 엉뚱한 프로그램에
# Ctrl+A 나 Delete 가 들어갈 수 있어 위험합니다. 반드시 확인하고 보냅니다.
function Test-ChatIsForeground([object]$Chat) {
    $window = [NativeKakao]::GetWindow($Chat.Handle)
    if ($null -eq $window -or $window.Width -le 0) { return $false }
    return ([NativeKakao]::GetForegroundWindow() -eq $Chat.Handle)
}

function Send-KeyToChat([object]$Chat, [scriptblock]$Action) {
    if (-not (Test-ChatIsForeground $Chat)) { return $false }
    & $Action
    return $true
}

# 첨부가 오래 안 되던 진짜 이유를 찾았습니다.
# 카카오톡은 사진을 붙여넣으면 채팅창에 바로 붙이지 않고
# [클립보드 이미지 전송] 이라는 미리보기 창을 따로 띄웁니다.
# 그 창에서 [전송] 을 눌러야 실제로 갑니다.
# 예전 코드는 이 창을 몰랐습니다. 채팅창만 보고 "안 붙었다" 고 판단해
# 전송을 누르지 않았고, 그래서 사진이 한 장도 가지 않았습니다.

# 미리보기 창은 제목이 없는 별도 창입니다.
# 누르기 전에 있던 창은 빼고 세어서, 원래 열려 있던 창을 잘못 잡지 않습니다.
function Wait-KakaoPreviewWindow([hashtable]$Before, [int]$TimeoutMs) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible) { continue }
                if ($Before.ContainsKey([string]$window.Handle)) { continue }
                if (-not [string]::IsNullOrWhiteSpace($window.Title)) { continue }
                if ($window.Width -lt 220 -or $window.Height -lt 220) { continue }
                if ($window.Width -gt 1200 -or $window.Height -gt 1200) { continue }
                return $window
            }
        }
        Start-Sleep -Milliseconds 120
    }
    return $null
}

# 미리보기 창을 보내지 않고 닫습니다. 확인만 할 때와 실패했을 때 씁니다.
# 열린 채로 두면 다음 방에서 엉뚱하게 딸려 갈 수 있어 반드시 닫습니다.
function Close-KakaoPreview([object]$Preview) {
    if ($null -eq $Preview) { return $true }
    for ($i = 0; $i -lt 3; $i++) {
        [NativeKakao]::CloseWindow($Preview.Handle)
        Start-Sleep -Milliseconds 400
        $still = [NativeKakao]::GetWindow($Preview.Handle)
        if ($null -eq $still -or -not $still.Visible) { return $true }
    }
    return $false
}

# 미리보기 창의 [전송] 을 누릅니다. 창 아래 가운데에 넓게 있는 단추입니다.
# 한 가지 방법만 쓰면 컴퓨터에 따라 안 눌립니다.
# 창 메시지 클릭 → 실제 마우스 클릭 → Enter 순서로 해 보고, 창이 닫히면 성공입니다.
function Submit-KakaoPreview([object]$Preview, [int]$TimeoutMs) {
    $window = [NativeKakao]::GetWindow($Preview.Handle)
    if ($null -eq $window -or $window.Width -le 0) { return '미리보기 창이 사라짐' }
    $x = $window.Rect.Left + [int]($window.Width / 2)
    $y = $window.Rect.Bottom - 24
    $each = [Math]::Max(1200, [int]($TimeoutMs / 3))
    $lastReason = '전송을 눌렀지만 미리보기 창이 닫히지 않음'

    $ways = @(
        [pscustomobject]@{ Name = '창 메시지 클릭'; Act = {
            [NativeKakao]::ClickControl($window.Handle, $x, $y, $false) } },
        [pscustomobject]@{ Name = '실제 마우스 클릭'; Act = {
            if ([NativeKakao]::ForceForeground($window.Handle)) {
                Start-Sleep -Milliseconds 250
                if ([NativeKakao]::GetForegroundWindow() -eq $window.Handle) { Invoke-PointClick $x $y $false }
            } } },
        [pscustomobject]@{ Name = 'Enter'; Act = {
            [NativeKakao]::PressKey($window.Handle, 0x0D) } }
    )
    foreach ($way in $ways) {
        try { & $way.Act } catch { $lastReason = $way.Name + ' 도중 문제: ' + $_.Exception.Message; continue }
        $deadline = (Get-Date).AddMilliseconds($each)
        while ((Get-Date) -lt $deadline) {
            $still = [NativeKakao]::GetWindow($Preview.Handle)
            if ($null -eq $still -or -not $still.Visible) { return '' }
            Start-Sleep -Milliseconds 120
        }
        $lastReason = $way.Name + ' 으로는 닫히지 않음'
    }
    return $lastReason
}

# 입력칸 아래 아이콘 줄의 위치입니다. (창 안에서의 좌표)
function Get-ChatToolbarBand([object]$Chat, [object]$InputBox) {
    if ($null -eq $Chat -or $null -eq $InputBox) { return $null }
    $top = $InputBox.Rect.Bottom - $Chat.Rect.Top
    $bottom = $Chat.Height - 1
    if (($bottom - $top) -lt 16) { return $null }
    return [pscustomobject]@{ Top = ($top + 3); Bottom = ($bottom - 5) }
}

# 아이콘 줄에서 아이콘들의 가로 위치를 찾습니다.
# 좌표를 코드에 박아 두면 카카오톡 판이나 화면 배율이 바뀔 때 엉뚱한 곳을 누르므로
# 그때그때 화면을 보고 찾습니다.
function Find-ChatToolbarIcons([object]$Chat, [object]$InputBox) {
    $band = Get-ChatToolbarBand $Chat $InputBox
    if ($null -eq $band) { return @() }
    $window = [NativeKakao]::GetWindow($Chat.Handle)
    if ($null -eq $window -or $window.Width -le 0 -or $window.Height -le 0) { return @() }
    $image = $null
    try { $image = Get-WindowImage $window } catch { return @() }
    try {
        $rightEdge = [int]($window.Width * 0.5)
        $counts = [FastImage]::ColumnInk($image, 6, $band.Top, $rightEdge, $band.Bottom, 0.86)
        if ($null -eq $counts -or $counts.Count -eq 0) { return @() }
        $groups = @()
        $start = -1
        $gap = 0
        for ($x = 0; $x -lt $counts.Count; $x++) {
            if ($counts[$x] -ge 2) {
                if ($start -lt 0) { $start = $x }
                $gap = 0
            } elseif ($start -ge 0) {
                $gap++
                if ($gap -ge 5) {
                    $groups += ,@($start, ($x - $gap))
                    $start = -1
                    $gap = 0
                }
            }
        }
        if ($start -ge 0) { $groups += ,@($start, ($counts.Count - 1)) }
        $centerY = $window.Rect.Top + [int](($band.Top + $band.Bottom) / 2)
        $icons = @()
        foreach ($group in $groups) {
            $width = $group[1] - $group[0] + 1
            if ($width -lt 7 -or $width -gt 44) { continue }
            $icons += [pscustomobject]@{
                X = ($window.Rect.Left + 6 + [int](($group[0] + $group[1]) / 2))
                Y = $centerY
                Width = $width
            }
        }
        return @($icons)
    } catch { return @() }
    finally { if ($null -ne $image) { try { $image.Dispose() } catch { } } }
}

# 전송 버튼이 켜졌는지 봅니다. 보낼 것이 있으면 노랗게 켜집니다.
# 파일이 채팅창에 바로 붙는 경우에 이걸로 확인합니다.
# 'yes' 켜짐, 'no' 꺼짐, 'unknown' 판단 못 함
function Test-ChatSendReady([object]$Chat, [object]$InputBox) {
    $band = Get-ChatToolbarBand $Chat $InputBox
    if ($null -eq $band) { return 'unknown' }
    $window = [NativeKakao]::GetWindow($Chat.Handle)
    if ($null -eq $window -or $window.Width -le 0 -or $window.Height -le 0) { return 'unknown' }
    $image = $null
    try { $image = Get-WindowImage $window } catch { return 'unknown' }
    try {
        $left = $window.Width - 100
        $right = $window.Width - 12
        if ($left -lt 0 -or $right -le $left) { return 'unknown' }
        $ratio = [FastImage]::YellowRatio($image, $left, $band.Top, $right, $band.Bottom)
        if ($ratio -ge 0.15) { return 'yes' }
        return 'no'
    } catch { return 'unknown' }
    finally { if ($null -ne $image) { try { $image.Dispose() } catch { } } }
}

# 채팅창에 바로 붙은 첨부를 취소합니다.
# 카카오톡은 Escape 로 채팅창 자체가 닫히므로, 붙은 것이 있을 때만 누릅니다.
function Clear-ChatAttachmentDraft([object]$Chat, [object]$InputBox) {
    for ($i = 0; $i -lt 3; $i++) {
        if ((Test-ChatSendReady $Chat $InputBox) -ne 'yes') { return $true }
        if (Enter-ChatForeground $Chat $InputBox) {
            [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
        } else {
            [NativeKakao]::PressKey($InputBox.Handle, 0x1B)
        }
        Start-Sleep -Milliseconds 350
    }
    return ((Test-ChatSendReady $Chat $InputBox) -ne 'yes')
}

# 아이콘을 눌렀는데 아무 창도 안 뜨면 메뉴가 열렸을 수 있습니다.
# 이때 Escape 를 쓰면 안 됩니다. 카카오톡은 Escape 로 채팅창이 닫힙니다.
# 입력칸을 눌러 메뉴만 닫습니다.
function Hide-ChatPopup([object]$Chat, [object]$InputBox) {
    try {
        [NativeKakao]::ClickControl($InputBox.Handle,
            ($InputBox.Rect.Left + [int]($InputBox.Width / 2)),
            ($InputBox.Rect.Top + [int]($InputBox.Height / 2)), $false)
    } catch { }
    Start-Sleep -Milliseconds 200
}

# 새로 뜬 파일 선택창을 기다립니다.
function Wait-FileDialog([hashtable]$Before, [int]$TimeoutMs) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible) { continue }
                if ($window.ClassName -ne '#32770') { continue }
                if ($Before.ContainsKey([string]$window.Handle)) { continue }
                if ($window.Width -lt 200 -or $window.Height -lt 150) { continue }
                return $window
            }
        }
        Start-Sleep -Milliseconds 120
    }
    return $null
}

# 파일 선택창에 경로를 적어 넣고 [열기] 를 누릅니다.
# 이 창은 윈도우 기본 창이라 창 메시지가 그대로 통합니다.
function Submit-FileDialog([object]$Dialog, [string]$Path, [int]$TimeoutMs) {
    $edit = $null
    foreach ($child in [NativeKakao]::GetChildWindows($Dialog.Handle)) {
        if ($child.ClassName -eq 'Edit' -and $child.Visible -and $child.Width -gt 40) { $edit = $child; break }
    }
    if ($null -eq $edit) { return '파일 이름 칸을 찾지 못함' }
    [NativeKakao]::SetControlText($edit.Handle, $Path)
    Start-Sleep -Milliseconds 150
    if ([NativeKakao]::GetControlText($edit.Handle) -ne $Path) { return '파일 이름 칸에 경로가 들어가지 않음' }
    $okButton = [NativeKakao]::GetDlgItem($Dialog.Handle, 1)
    if ($okButton -ne [IntPtr]::Zero) { [NativeKakao]::ClickButton($okButton) }
    else { [NativeKakao]::PressKey($edit.Handle, 0x0D) }
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        $still = [NativeKakao]::GetWindow($Dialog.Handle)
        if ($null -eq $still -or -not $still.Visible) { return '' }
        Start-Sleep -Milliseconds 100
    }
    return '파일 선택창이 닫히지 않음'
}

# 열어 둔 파일 선택창을 반드시 닫습니다. 열린 채로 두면 다음 방부터 전부 막힙니다.
function Close-FileDialog([object]$Dialog) {
    if ($null -eq $Dialog) { return }
    try {
        $cancel = [NativeKakao]::GetDlgItem($Dialog.Handle, 2)
        if ($cancel -ne [IntPtr]::Zero) { [NativeKakao]::ClickButton($cancel) }
        else { [NativeKakao]::CloseWindow($Dialog.Handle) }
    } catch { }
    Start-Sleep -Milliseconds 300
    try {
        $still = [NativeKakao]::GetWindow($Dialog.Handle)
        if ($null -ne $still -and $still.Visible) { [NativeKakao]::CloseWindow($Dialog.Handle) }
    } catch { }
}

# 붙이기 결과입니다.
#   Problem : 비어 있으면 붙이기 단계까지는 성공
#   Preview : 미리보기 창이 떴으면 그 창. 여기서 [전송] 을 눌러야 갑니다.
function New-AttachStage([string]$Problem, [object]$Preview) {
    return [pscustomobject]@{ Problem = $Problem; Preview = $Preview }
}

# 1순위: 클립보드로 붙여넣습니다. 사진은 이 길이 가장 확실합니다.
function Add-AttachmentByClipboard([object]$Chat, [object]$InputBox, [string]$Path, [int]$WaitMs) {
    $methods = if (Test-IsImageFile $Path) { @('image', 'file') } else { @('file', 'image') }
    $lastReason = '클립보드로 붙지 않음'
    foreach ($method in $methods) {
        $ready = $false
        try {
            if ($method -eq 'image') { $ready = Set-ClipboardImageSafe $Path }
            else { Set-ClipboardFileSafe $Path; $ready = $true }
        } catch { $ready = $false }
        if (-not $ready) { $lastReason = '클립보드에 넣지 못함'; continue }
        $before = Get-VisibleWindowHandles
        if (-not (Enter-ChatForeground $Chat $InputBox)) { return (New-AttachStage '채팅창을 앞으로 가져오지 못함' $null) }
        [NativeKakao]::PressCtrlKey(0x56)
        # 사진은 미리보기 창이 뜹니다. 파일은 채팅창에 바로 붙기도 합니다.
        $preview = Wait-KakaoPreviewWindow $before ([Math]::Max(2500, $WaitMs + 1200))
        if ($null -ne $preview) { return (New-AttachStage '' $preview) }
        if ((Test-ChatSendReady $Chat $InputBox) -eq 'yes') { return (New-AttachStage '' $null) }
    }
    return (New-AttachStage $lastReason $null)
}

# 2순위: 채팅창 아래 [파일] 아이콘으로 파일 선택창을 띄워 넣습니다.
# 클립보드를 다른 프로그램이 쓰고 있을 때도 이 길은 막히지 않습니다.
function Add-AttachmentByDialog([object]$Chat, [object]$InputBox, [string]$Path, [int]$WaitMs) {
    $icons = @(Find-ChatToolbarIcons $Chat $InputBox)
    if ($icons.Count -eq 0) { return (New-AttachStage '채팅창 아래 아이콘 줄을 찾지 못함' $null) }
    # 왼쪽부터 [+] [이모티콘] [파일] 순서입니다.
    $targets = @()
    if ($icons.Count -ge 3) { $targets += $icons[2] }
    $targets += $icons[0]
    $lastReason = '파일 선택창이 뜨지 않음'
    foreach ($icon in $targets) {
        $modes = if ($script:toolbarClickNeedsMouse) { @($true) } else { @($false, $true) }
        foreach ($useMouse in $modes) {
            $before = Get-VisibleWindowHandles
            if ($useMouse) {
                # 실제 마우스는 지금 앞에 있는 창으로 갑니다.
                # 엉뚱한 프로그램을 누르지 않도록 채팅창이 앞인지 반드시 확인합니다.
                if (-not (Enter-ChatForeground $Chat $InputBox)) { return (New-AttachStage '채팅창을 앞으로 가져오지 못함' $null) }
                Invoke-PointClick $icon.X $icon.Y $false
            } else {
                [NativeKakao]::ClickControl($Chat.Handle, $icon.X, $icon.Y, $false)
            }
            $waitFor = 3000
            if (-not $useMouse) { $waitFor = 1200 }
            $dialog = Wait-FileDialog $before $waitFor
            if ($null -eq $dialog) {
                if (-not $useMouse) { $script:toolbarClickNeedsMouse = $true }
                Hide-ChatPopup $Chat $InputBox
                continue
            }
            $seen = Get-VisibleWindowHandles
            $problem = Submit-FileDialog $dialog $Path 8000
            if ($problem) {
                $lastReason = $problem
                Close-FileDialog $dialog
                continue
            }
            $preview = Wait-KakaoPreviewWindow $seen ([Math]::Max(2500, $WaitMs + 1200))
            return (New-AttachStage '' $preview)
        }
    }
    return (New-AttachStage $lastReason $null)
}

# 채팅창에 바로 붙은 첨부를 보냅니다.
# 첨부는 입력칸이 처음부터 비어 있어서, 입력칸으로는 성공을 알 수 없습니다.
# 전송 버튼이 다시 꺼지는 것으로 확인합니다.
function Invoke-ChatSendAttachment([object]$Chat, [object]$InputBox, [int]$WaitMs) {
    $ways = @(
        [pscustomobject]@{ Name = '입력칸에 Enter 키'; Act = { [NativeKakao]::PressKey($InputBox.Handle, 0x0D) } },
        [pscustomobject]@{ Name = '채팅창에 Enter 키'; Act = { [NativeKakao]::PressKey($Chat.Handle, 0x0D) } },
        [pscustomobject]@{ Name = '창을 앞으로 가져와 Enter'; Act = {
            if (Enter-ChatForeground $Chat $InputBox) { [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') } } }
    )
    foreach ($way in $ways) {
        try { & $way.Act } catch { continue }
        $deadline = (Get-Date).AddMilliseconds([Math]::Max(2000, $WaitMs + 1200))
        while ((Get-Date) -lt $deadline) {
            if (-not (Test-ControlAlive $InputBox)) { break }
            if ((Test-ChatSendReady $Chat $InputBox) -eq 'no') { return [string]$way.Name }
            Start-Sleep -Milliseconds 180
        }
    }
    return ''
}

# 첨부 하나를 붙이고 보냅니다.
# 붙은 것이 확인되지 않으면 보내지 않습니다. 잘못 보내는 것보다 안 보내는 것이 낫습니다.
# SendIt 을 $false 로 주면 붙이기만 해 보고 치웁니다. (첨부 시험)
function Send-ChatAttachment([object]$Chat, [object]$InputBox, [string]$Path, [int]$WaitMs, [bool]$SendIt = $true) {
    $result = [pscustomobject]@{ Ok = $false; Sent = $false; Method = ''; SendWay = ''; Reason = '' }
    $reasons = @()
    # 사진은 클립보드가 확실하고, 문서는 파일 선택창이 확실합니다.
    $ways = @()
    if (Test-IsImageFile $Path) {
        $ways += [pscustomobject]@{ Name = '붙여넣기'; Act = { Add-AttachmentByClipboard $Chat $InputBox $Path $WaitMs } }
        $ways += [pscustomobject]@{ Name = '파일 선택창'; Act = { Add-AttachmentByDialog $Chat $InputBox $Path $WaitMs } }
    } else {
        $ways += [pscustomobject]@{ Name = '파일 선택창'; Act = { Add-AttachmentByDialog $Chat $InputBox $Path $WaitMs } }
        $ways += [pscustomobject]@{ Name = '붙여넣기'; Act = { Add-AttachmentByClipboard $Chat $InputBox $Path $WaitMs } }
    }
    $preview = $null
    foreach ($way in $ways) {
        $stage = $null
        try { $stage = & $way.Act } catch { $stage = New-AttachStage $_.Exception.Message $null }
        if ($null -eq $stage) { $reasons += ($way.Name + ': 알 수 없는 문제'); continue }
        if ($stage.Problem) { $reasons += ($way.Name + ': ' + $stage.Problem); continue }
        $preview = $stage.Preview
        $result.Ok = $true
        if ($null -ne $preview) { $result.Method = $way.Name + ' (미리보기 창 확인)' }
        else { $result.Method = $way.Name + ' (전송 버튼 켜짐 확인)' }
        break
    }
    $result.Reason = ($reasons -join ' / ')
    if (-not $result.Ok) { return $result }

    if (-not $SendIt) {
        # 시험일 때는 붙인 것을 그대로 치웁니다. 보내지 않습니다.
        if ($null -ne $preview) { [void](Close-KakaoPreview $preview) }
        else { [void](Clear-ChatAttachmentDraft $Chat $InputBox) }
        return $result
    }

    if ($null -ne $preview) {
        $problem = Submit-KakaoPreview $preview ([Math]::Max(4000, $WaitMs + 2500))
        if ($problem) {
            $result.Reason = $problem
            [void](Close-KakaoPreview $preview)
        } else {
            $result.Sent = $true
            $result.SendWay = '미리보기 창의 전송 누름'
        }
        return $result
    }

    $how = Invoke-ChatSendAttachment $Chat $InputBox $WaitMs
    if ($how) {
        $result.Sent = $true
        $result.SendWay = $how
    } else {
        $result.Reason = '붙이기는 됐지만 전송이 확인되지 않아 치웠습니다'
        [void](Clear-ChatAttachmentDraft $Chat $InputBox)
    }
    return $result
}

# SendKeys 는 + ^ % ~ ( ) { } [ ] 를 특수 기호로 해석하므로 감싸 줍니다.
# 줄바꿈은 반드시 Shift+Enter 로 보냅니다. 그냥 Enter 를 보내면
# 줄마다 따로 전송되어 메시지가 여러 개로 쪼개집니다.
function ConvertTo-SendKeysText([string]$Text) {
    $escaped = [regex]::Replace($Text, '[+^%~(){}\[\]]', { param($m) '{' + $m.Value + '}' })
    $escaped = $escaped -replace "`r`n", "`n"
    return ($escaped -replace "`n", '+{ENTER}')
}

# ---------------------------------------------------------------------------
# 입력과 전송
# ---------------------------------------------------------------------------
# 채팅창 아래 아이콘이 창 메시지를 받아 주는지 한 번만 확인하고 기억합니다.
# 안 받아 주는데 방마다 다시 시도하면 방 300개에서 몇 분을 그냥 버립니다.
$script:toolbarClickNeedsMouse = $false
$script:lastSendProblem = ''
$script:roomRepairNote = ''
$script:pendingSwap = ''
$script:sendMethodLogged = ''

function Clear-ChatInput([object]$InputBox) {
    [NativeKakao]::SelectAllIn($InputBox.Handle)
    [NativeKakao]::ClearSelection($InputBox.Handle)
    Start-Sleep -Milliseconds 80
    if (-not [string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) {
        [NativeKakao]::SetControlText($InputBox.Handle, '')
    }
}

# 붙여넣기로 넣습니다. WM_SETTEXT 만 쓰면 카카오톡 내부 상태가 갱신되지 않아
# Enter 를 눌러도 전송되지 않는 경우가 있습니다.
function Set-ChatInputText([object]$InputBox, [string]$Text) {
    [NativeKakao]::ClickControl($InputBox.Handle, ($InputBox.Rect.Left + [int]($InputBox.Width / 2)), ($InputBox.Rect.Top + [int]($InputBox.Height / 2)), $false)
    Start-Sleep -Milliseconds 140

    # 1순위: 붙여넣기. 실제 Ctrl+V 와 같은 경로라 카카오톡 내부 상태가 정상 갱신됩니다.
    # 클립보드는 다른 프로그램이 잡고 있을 수 있으므로 실패해도 멈추지 않고 넘어갑니다.
    $clipboardReady = $false
    try { Set-ClipboardTextSafe $Text; $clipboardReady = $true } catch { Write-RunLog "클립보드를 쓰지 못해 직접 입력으로 넘어갑니다." }
    if ($clipboardReady) {
        [NativeKakao]::SelectAllIn($InputBox.Handle)
        [NativeKakao]::PasteInto($InputBox.Handle)
        Start-Sleep -Milliseconds 220
        if (-not [string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) { return $true }
    }

    # 2순위: 글자를 하나씩 보냅니다. 붙여넣기와 마찬가지로 변경 알림이 발생합니다.
    [NativeKakao]::SelectAllIn($InputBox.Handle)
    [NativeKakao]::ClearSelection($InputBox.Handle)
    [NativeKakao]::TypeText($InputBox.Handle, $Text)
    Start-Sleep -Milliseconds 250
    if (-not [string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) { return $true }

    # 3순위: 마지막 수단
    [NativeKakao]::SetControlText($InputBox.Handle, $Text)
    Start-Sleep -Milliseconds 150
    return (-not [string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox)))
}

# 입력칸이 비면 카카오톡이 '메시지 입력' 같은 안내글을 대신 보여 줍니다.
# 이걸 내용으로 오해하면 전송 성공을 영영 확인하지 못합니다.
$script:InputPlaceholders = @('메시지 입력', '메시지를 입력하세요', 'Enter message', '메세지 입력')

function Get-ChatInputText([object]$InputBox) {
    $text = [string][NativeKakao]::GetControlText($InputBox.Handle)
    $trimmed = $text.Trim()
    if ($trimmed -in $script:InputPlaceholders) { return '' }
    return $text
}

# 입력칸이 비워졌는지로 전송 성공을 판단합니다.
# 단, 컨트롤이 사라졌거나 읽을 수 없는 상태에서 나오는 빈 값은 성공이 아닙니다.
# 예전에는 이걸 구분하지 않아, 방이 덜 열린 상태에서 '보낸 것'으로 착각했습니다.
function Wait-ChatInputCleared([object]$InputBox, [int]$TimeoutMs) {
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        if (-not (Test-ControlAlive $InputBox)) { return $false }
        if ([string]::IsNullOrWhiteSpace((Get-ChatInputText $InputBox))) { return $true }
        Start-Sleep -Milliseconds 70
    }
    return $false
}

# 전송을 여러 방법으로 시도하고, 입력칸이 비워졌는지로 성공을 판단합니다.
# 카카오톡은 전송에 성공하면 입력칸을 비우므로 확실한 신호가 됩니다.
# 이미 전송되어 입력칸이 비었으면 다음 시도는 빈 내용이라 아무 일도 하지 않습니다.
function Invoke-ChatSend([object]$Chat, [object]$InputBox) {
    [NativeKakao]::PressKey($InputBox.Handle, 0x0D)
    if (Wait-ChatInputCleared $InputBox 1400) { return '입력칸에 Enter 키' }

    [NativeKakao]::SendChar($InputBox.Handle, 13)
    if (Wait-ChatInputCleared $InputBox 1200) { return '입력칸에 Enter 문자' }

    [NativeKakao]::PressKey($Chat.Handle, 0x0D)
    if (Wait-ChatInputCleared $InputBox 1200) { return '채팅창에 Enter 키' }

    # 마지막으로 실제 키보드 입력을 시도합니다. 이때만 창을 앞으로 가져옵니다.
    if (Enter-KakaoForeground $Chat) {
        [void](Set-ChatInputFocus $Chat)
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        if (Wait-ChatInputCleared $InputBox 1500) { return '창을 앞으로 가져와 Enter' }
    }
    return ''
}

# ---------------------------------------------------------------------------
# 목록 한 번 훑기 발송
# ---------------------------------------------------------------------------
# 카카오톡 상단의 돋보기·탭 아이콘은 직접 그린 요소라 창 메시지를 무시합니다.
# 반대로 채팅 목록 컨트롤은 메시지를 정확히 받습니다.
# 그래서 검색을 쓰지 않고, 목록을 위에서 아래로 한 번 훑으며 대상 방을 처리합니다.
# 방 300개도 목록 한 바퀴로 끝나므로 가장 빠르고 안정적입니다.
function Get-ListNameLines([object]$List) {
    $lines = @(Get-OcrLines $List 2)
    return @($lines | Where-Object {
        $_.Left -ge ($List.Width * 0.13) -and $_.Left -le ($List.Width * 0.46)
    } | Sort-Object Top)
}

function Move-ListToTop([object]$List, [int]$Pages) {
    for ($i = 0; $i -lt ($Pages + 5); $i++) {
        Move-ListByWheel $List 'up' 8
        Start-Sleep -Milliseconds 20
    }
    Start-Sleep -Milliseconds 250
}

function Get-VisibleWindowHandles {
    $set = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
            if ($window.Visible) { $set[[string]$window.Handle] = $true }
        }
    }
    return $set
}

function Open-RoomAtLine([object]$List, [object]$Line, [IntPtr]$MainHandle, [int]$TimeoutMs = 0) {
    if ($TimeoutMs -le 0) { $TimeoutMs = [Math]::Max(3000, [int]$script:config.OpenTimeoutMs) }
    $before = Get-VisibleWindowHandles
    $x = $List.Rect.Left + [int]($List.Width * 0.35)
    $y = $List.Rect.Top + $Line.Top + 8
    Invoke-ControlClick $List $x $y $true
    $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
    while ((Get-Date) -lt $deadline) {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible -or $window.Handle -eq $MainHandle) { continue }
                if ($before.ContainsKey([string]$window.Handle)) { continue }
                if ([string]::IsNullOrWhiteSpace($window.Title)) { continue }
                return $window
            }
        }
        Start-Sleep -Milliseconds 60
    }
    return $null
}

# 목록을 훑어 대상 방들을 처리합니다. 결과를 돌려줍니다.
function Invoke-SweepOverList([string[]]$Targets, [object]$Content, [int]$MaxPages, [int]$IntervalSeconds, [int]$BatchSize, [int]$BatchRestMinutes) {
    $remaining = @{}
    foreach ($name in $Targets) { $remaining[[string]$name] = $true }
    $sent = 0
    $failed = 0
    $processed = 0

    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { throw $ready.Reason }
    $layout = $ready.Layout
    $main = $layout.Main
    Move-ListToTop $layout.List $MaxPages

    for ($page = 0; $page -lt $MaxPages; $page++) {
        if ($remaining.Count -eq 0) { break }

        # 한 화면에서 처리할 수 있는 방을 모두 처리한 뒤 다음 화면으로 넘어갑니다.
        $guard = 0
        while ($remaining.Count -gt 0 -and $guard -lt 30) {
            $guard++
            $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
            if ($null -eq $fresh.List) { break }
            $list = $fresh.List
            $nameLines = @(Get-ListNameLines $list)
            if ($nameLines.Count -eq 0) { break }

            $hit = $null
            $hitName = ''
            foreach ($line in $nameLines) {
                foreach ($candidate in @($remaining.Keys)) {
                    # 저장된 이름과, 목록에서 글자로 읽히던 이름 둘 다로 찾습니다.
                    $listName = Get-RoomListName $candidate
                    $matchedHere = ($null -ne (Find-SearchResultLine @($line) $candidate $list.Width))
                    if (-not $matchedHere -and $listName -ne $candidate) {
                        $matchedHere = ($null -ne (Find-SearchResultLine @($line) $listName $list.Width))
                    }
                    if ($matchedHere) {
                        $hit = $line
                        $hitName = [string]$candidate
                        break
                    }
                }
                if ($null -ne $hit) { break }
            }
            if ($null -eq $hit) { break }

            if (Test-RunInterrupted) { break }
            $remaining.Remove($hitName)
            $processed++
            Set-StatusPill ("발송 중 $($processed)/$($Targets.Count) — $($hitName)") 'run'

            $chat = Get-SingleChatWindow (Open-RoomAtLine $list $hit $main.Handle)
            if ($null -eq $chat) {
                $failed++
                Write-RunLog "건너뜀: '$hitName' — 채팅창을 열지 못했습니다."
            } else {
                if (Send-ToChatWindow $chat $hitName $Content) { $sent++ } else { $failed++ }
            }

            # 방 간격
            if ($remaining.Count -gt 0) {
                if ($BatchSize -gt 0 -and $BatchRestMinutes -gt 0 -and ($processed % $BatchSize) -eq 0) {
                    Write-RunLog "묶음 $($BatchSize)개를 처리했습니다. $($BatchRestMinutes)분 쉽니다."
                    Set-StatusPill "$($BatchRestMinutes)분 쉬는 중 — $($processed)/$($Targets.Count)" 'wait'
                    if (Wait-Interruptible ($BatchRestMinutes * 60)) { break }
                } elseif ($IntervalSeconds -gt 0) {
                    if (Wait-Interruptible $IntervalSeconds) { break }
                } else {
                    if (Test-RunInterrupted) { break }
                }
            }
        }

        if ($remaining.Count -eq 0) { break }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -eq $fresh.List) { break }
        $names = @(Get-RoomNamesFromOcrLines (Get-OcrLines $fresh.List 2) $fresh.List.Width)
        $notches = [Math]::Max(3, [Math]::Min(8, $names.Count - 1))
        Move-ListByWheel $fresh.List 'down' $notches
        Start-Sleep -Milliseconds 200
    }

    return [pscustomobject]@{
        Sent = $sent
        Failed = $failed
        NotFound = @($remaining.Keys)
    }
}

# 카카오톡을 막 켰거나 이 프로그램을 처음 쓰는 경우,
# 채팅방마다 대화를 처음부터 새로 불러옵니다. 방에 따라 12초까지 걸립니다.
# 다 불러오기 전에는 Enter 를 눌러도 전송이 되지 않습니다.
# 그래서 보내기 전에 대상 방을 한 번씩 열어 두면 이후가 훨씬 안정적입니다.
# 한 번 열어 둔 방은 카카오톡이 기억하고 있어서 다음부터는 금방 열립니다.
function Invoke-RoomPreload([string[]]$Rooms) {
    $targets = @($Rooms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($targets.Count -eq 0) { return $false }
    Write-RunLog "방 미리 열기: $($targets.Count)개를 한 번씩 열어 대화가 다 불러와지는지 봅니다."
    Write-RunLog '보내지 않습니다. 처음 한 번만 하면 되고, 이후 발송이 훨씬 안정적입니다.'
    $content = New-SendContent $true
    # 미리 열 때는 넉넉히 기다립니다. 여기서 오래 걸려도 실제 발송이 빨라집니다.
    $content.OpenTimeoutMs = [Math]::Max(12000, [int]$content.OpenTimeoutMs)
    $content.SettleMs = [Math]::Max(8000, [int]$content.SettleMs)
    $outcome = $null
    try {
        $outcome = Invoke-SweepOverList $targets $content ([int]$script:config.ScanPages) 0 0 0
    } catch {
        Write-RunLog "방 미리 열기 중단: $($_.Exception.Message)"
        return $false
    }
    if ($null -eq $outcome) { return $false }
    $missed = @($outcome.NotFound)
    Write-RunLog "방 미리 열기 끝: 확인 $($outcome.Sent)개 / 열지 못함 $($outcome.Failed)개 / 목록에서 못 찾음 $($missed.Count)개"
    if ($missed.Count -gt 0) {
        Write-RunLog "  못 찾은 방: $(($missed | Select-Object -First 5) -join ', ')$(if ($missed.Count -gt 5) { ' 외 ' + ($missed.Count - 5) + '개' } else { '' })"
    }
    return $true
}

function New-SendContent([bool]$DryRun) {
    return [pscustomobject]@{
        Message = [string]$script:config.Message
        Attachments = @($script:config.Attachments)
        AttachmentWaitMs = [int]$script:config.AttachmentWaitMs
        OpenTimeoutMs = [Math]::Max(3000, [int]$script:config.OpenTimeoutMs)
        SettleMs = [Math]::Max(0, [Math]::Min(30000, [int]$script:config.SettleMs))
        DryRun = $DryRun
    }
}

function Get-TabLabelForType([string]$Type) {
    if ($Type -eq $script:RoomTypeOpen) { return '오픈채팅' }
    return '채팅'
}

function Invoke-Broadcast {
    $rooms = @($script:config.Rooms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
    if ($rooms.Count -eq 0) { throw '보낼 채팅방을 한 개 이상 선택해 주세요.' }
    if ($rooms.Count -gt 500) { throw '안전을 위해 한 번에 최대 500개 방까지만 처리합니다.' }
    $dryRun = [bool]$script:config.DryRun
    if (-not $dryRun) {
        foreach ($attachment in @($script:config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }

    $content = New-SendContent $dryRun
    $mode = if ($dryRun) { '확인 전용' } else { '실제 발송' }
    $interval = Get-EffectiveInterval (Get-Date)
    $holiday = Get-HolidayName (Get-Date)
    if ($holiday) { Write-RunLog "오늘은 $holiday 입니다. 방 간격 $($interval)초로 진행합니다." }
    $batchSize = [int]$script:config.BatchSize
    $batchRest = [int]$script:config.BatchRestMinutes
    if ($batchSize -gt 0 -and $batchRest -gt 0) {
        Write-RunLog "묶음 발송: $($batchSize)개마다 $($batchRest)분 쉽니다."
    }
    Write-RunLog ("작업 시작: 방 {0}개 / 모드={1} / 간격 {2}초" -f $rooms.Count, $mode, $interval)

    # PC 카카오톡의 [채팅] 목록에는 일반 채팅방과 오픈채팅방이 함께 들어 있습니다.
    # 그래서 종류로 나누지 않고, 지금 보이는 목록을 한 번 훑어 찾을 수 있는 방을 모두 처리합니다.
    # 그러고도 못 찾은 방이 있으면 다른 탭으로 바꿔 한 번 더 훑습니다.
    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { throw $ready.Reason }

    # 처음 보내는 경우에는 대상 방을 먼저 한 번씩 열어 둡니다.
    # 대화를 불러오는 중에는 전송이 먹지 않기 때문입니다.
    if ((-not $dryRun) -and [bool]$script:config.PreloadRooms -and (-not [bool]$script:config.PreloadDone)) {
        [void](Invoke-RoomPreload $rooms)
        $script:config.PreloadDone = $true
        try { Save-Config $script:config } catch { }
        Write-RunLog '이제 실제 발송을 시작합니다.'
    }

    $totalSent = 0
    $totalFailed = 0
    $pending = @($rooms)

    for ($round = 1; $round -le 3; $round++) {
        if (@($pending).Count -eq 0) { break }

        if ($round -gt 1) {
            $nowTab = ''
            try { $nowTab = Get-ActiveKakaoTab (Test-KakaoReady $false $false).Layout } catch { }
            $nowText = if (-not $nowTab -or $nowTab -eq $script:RoomTypeUnknown) { '알 수 없음' } else { "$nowTab 탭" }
            $otherText = if ($nowTab -eq $script:RoomTypeOpen) { '[채팅]' } else { '[오픈채팅]' }
            $ask = "아직 못 찾은 방이 $(@($pending).Count)개 있습니다.`r`n`r`n지금 카카오톡은 $nowText 을(를) 보고 있습니다.`r`n$otherText 탭으로 바꾸거나, 목록 위 분류를 [전체]로 바꿔 주신 뒤 [확인]을 눌러 주세요.`r`n`r`n[취소]를 누르면 남은 방은 건너뜁니다."
            if ([System.Windows.Forms.MessageBox]::Show($ask, '남은 방을 다른 목록에서 찾기', 'OKCancel', 'Information') -ne 'OK') {
                Write-RunLog "남은 $(@($pending).Count)개는 사용자가 건너뛰었습니다."
                break
            }
            $check = Test-KakaoReady $true $false
            if (-not $check.Ok) { Write-RunLog "중단: $($check.Reason)"; break }
        }

        if (-not $dryRun) {
            $blocked = Get-SendBlockReason (Get-Date)
            if ($blocked) { Write-RunLog "발송 중단: $blocked"; break }
        }

        $layoutNow = (Test-KakaoReady $false $false).Layout
        $tabNow = Get-ActiveKakaoTab $layoutNow
        Write-RunLog "$($round)회차: 방 $(@($pending).Count)개 찾기 (현재 탭 $tabNow / 화면 $($layoutNow.ViewName))"
        $result = Invoke-SweepOverList @($pending) $content ([int]$script:config.ScanPages) $interval $batchSize $batchRest
        $totalSent += $result.Sent
        $totalFailed += $result.Failed
        $pending = @($result.NotFound)
        Write-RunLog "$($round)회차 결과: 성공 $($result.Sent) / 실패 $($result.Failed) / 못 찾음 $(@($pending).Count)"
    }

    if (@($pending).Count -gt 0) {
        Write-RunLog "처리하지 못한 방 $(@($pending).Count)개: 이름이 카카오톡 표시와 다를 수 있습니다. 체크한 뒤 [이름 확인·보정]을 실행해 보세요."
    }
    Write-RunLog ("작업 종료: 성공 {0} / 실패 {1} / 미처리 {2} (전체 {3})" -f $totalSent, $totalFailed, @($pending).Count, $rooms.Count)
    return $totalSent
}

function Invoke-TestSend([bool]$DryRun) {
    $room = ([string]$script:config.TestRoom).Trim()
    if (-not $room) { throw '테스트 채팅방 이름을 입력해 주세요.' }
    if (-not $DryRun) {
        foreach ($attachment in @($script:config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }
    $label = if ($DryRun) { '테스트(확인만)' } else { '테스트 발송' }
    Write-RunLog "$label 시작: '$room'"
    $result = Invoke-SweepOverList @($room) (New-SendContent $DryRun) ([int]$script:config.ScanPages) 5 0 0
    $ok = ($result.Sent -gt 0)
    if (-not $ok -and @($result.NotFound).Count -gt 0) {
        Write-RunLog "'$room' 을(를) 목록에서 찾지 못했습니다. 카카오톡에 보이는 이름과 정확히 같은지 확인해 주세요."
    }
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
    foreach ($name in @('KakaoRoomScheduler.ps1', 'README.md', 'Publish-Release.ps1')) {
        $existing = Join-Path $AppDir $name
        if (Test-Path -LiteralPath $existing) { Copy-Item -LiteralPath $existing -Destination $backup -Force }
    }
    # 실행용 .cmd 는 이름을 바꿔 쓰는 경우가 있어 폴더의 모든 .cmd 를 백업합니다.
    foreach ($cmd in @(Get-ChildItem -LiteralPath $AppDir -Filter '*.cmd' -File -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $cmd.FullName -Destination $backup -Force
    }

    $copied = 0
    $script:pendingSwap = ''
    foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -File)) {
        if ($file.Name -eq 'config.json') { continue }
        $target = Join-Path $AppDir $file.Name
        # 지금 돌고 있는 프로그램 파일은 덮어쓸 수 없습니다. 옆에 두고 나중에 바꿉니다.
        if ($script:IsExe -and $script:HostPath -and ($target -eq $script:HostPath)) {
            $staged = $target + '.new'
            Copy-Item -LiteralPath $file.FullName -Destination $staged -Force
            $script:pendingSwap = New-ExeSwapHelper $staged $target
            Write-RunLog '새 프로그램 파일을 받아 두었습니다. 다시 시작하면 바뀝니다.'
            $copied++
            continue
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied++
    }
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    Write-RunLog "업데이트 적용 완료: 파일 $copied 개 교체, 이전 파일은 backup\$stamp 에 보관"
    return $backup
}

# 실행 중인 .exe 는 자기 자신을 덮어쓸 수 없습니다.
# 그래서 새 파일을 옆에 두고, 프로그램이 꺼지기를 기다렸다 바꿔치기하는
# 작은 배치 파일을 만들어 둡니다. 프로그램을 다시 켜면서 이 파일이 돕니다.
function New-ExeSwapHelper([string]$NewFile, [string]$TargetFile) {
    $helper = Join-Path $AppDir '업데이트-적용.cmd'
    $lines = @(
        '@echo off',
        'chcp 65001 > nul',
        'set TRY=0',
        ':retry',
        'set /a TRY+=1',
        ('move /y "' + $NewFile + '" "' + $TargetFile + '" > nul 2>&1'),
        'if not errorlevel 1 goto done',
        'if %TRY% GEQ 30 goto fail',
        'timeout /t 1 /nobreak > nul',
        'goto retry',
        ':done',
        ('start "" "' + $TargetFile + '"'),
        'del "%~f0"',
        'exit /b 0',
        ':fail',
        'echo 업데이트를 적용하지 못했습니다.',
        'echo 프로그램을 끄고 아래 파일 이름을 바꿔 주세요.',
        ('echo   ' + $NewFile),
        'pause'
    )
    [System.IO.File]::WriteAllLines($helper, $lines, (New-Object System.Text.UTF8Encoding($false)))
    return $helper
}

# 실행용 .cmd 파일을 찾습니다. 사용자가 이름을 바꿔도 동작하도록 폴더에서 찾습니다.
function Find-Launcher {
    $preferred = Join-Path $AppDir 'Start-KakaoRoomScheduler.cmd'
    if (Test-Path -LiteralPath $preferred) { return $preferred }
    $found = @(Get-ChildItem -LiteralPath $AppDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.exe', '.cmd') -and $_.Name -notlike '*.new' } | Sort-Object Extension, Name)
    if ($found.Count -gt 0) { return $found[0].FullName }
    return $null
}

function Restart-App {
    if ($script:pendingSwap -and (Test-Path -LiteralPath $script:pendingSwap)) {
        # 새 프로그램 파일로 바꿔치기한 뒤 다시 켜 줍니다.
        Start-Process -FilePath $script:pendingSwap -WorkingDirectory $AppDir -WindowStyle Hidden
        $script:armed = $false
        $script:form.Close()
        return
    }
    if ($script:IsExe -and $script:HostPath) {
        Start-Process -FilePath $script:HostPath -WorkingDirectory $AppDir
    } else {
        $launcher = Find-Launcher
        if ($launcher) { Start-Process -FilePath $launcher -WorkingDirectory $AppDir }
        else { Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-File', (Join-Path $AppDir 'KakaoRoomScheduler.ps1')) -WorkingDirectory $AppDir }
    }
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
        Body  = "먼저 카카오톡에서 [채팅] 탭을 눌러 채팅방 목록이 보이게 해 주세요. 최소화되어 있으면 안 됩니다.`r`n`r`n그 상태로 [카카오톡에서 읽기]를 누르면, 지금 보고 있는 목록이 일반 채팅인지 오픈채팅인지 물어봅니다. 답하면 목록을 훑어 방 이름을 가져옵니다.`r`n`r`n오픈채팅방은 카카오톡에서 [오픈채팅] 탭으로 바꾼 뒤 한 번 더 읽으면 됩니다.`r`n`r`n읽는 동안에는 마우스와 키보드를 사용하지 마세요."
    },
    @{
        Page = 'rooms'
        Title = '그룹으로 묶어 쓰기'
        Body  = "자주 보내는 방들을 그룹으로 묶어 두면 다음부터 한 번에 고를 수 있습니다.`r`n`r`n① 보낼 방들을 체크합니다.`r`n② [새 그룹 만들기]를 누르고 이름을 정합니다. (예: 학부모, 홍보방)`r`n`r`n다음에는 그룹을 고르고 [이 그룹 체크]만 누르면 그 방들이 한 번에 체크됩니다.`r`n`r`n이미 있는 그룹에 더 넣으려면 방을 체크한 뒤 [체크한 방 넣기]를 누르세요."
    },
    @{
        Page = 'rooms'
        Title = '2단계 · 이름 정확하게 맞추기'
        Body  = "방 이름은 화면의 글자를 읽어 오기 때문에 가끔 틀리게 들어옵니다.`r`n`r`n보낼 방만 체크한 다음 [이름 확인·보정]을 누르세요. 체크한 방을 하나씩 열어 실제 이름으로 자동으로 고쳐 줍니다.`r`n`r`n안 잡히는 방은 [직접 추가]로 카카오톡에 보이는 이름 그대로 입력하면 됩니다."
    },
    @{
        Page = 'compose'
        Title = '3단계 · 문구와 사진 준비'
        Body  = "[1. 보낼 내용] 화면에 보낼 문구를 적고, 사진이나 파일을 추가합니다.`r`n`r`n문구가 먼저 한 개의 메시지로 전송되고, 그다음 첨부가 목록 순서대로 하나씩 전송됩니다. 순서는 [위로] [아래로] 버튼으로 바꿀 수 있습니다.`r`n`r`n입력한 내용은 자동으로 저장되니 따로 저장하지 않아도 됩니다."
    },
    @{
        Page = 'run'
        Title = '4단계 · 먼저 테스트해 보기'
        Body  = "가장 중요한 단계입니다. 여러 방에 한꺼번에 보내기 전에 [테스트 모드]로 한 방에만 똑같이 보내 결과를 확인하세요.`r`n`r`n방 이름은 직접 입력해도 되고, [목록에서 고르기]로 저장된 목록에서 골라도 됩니다. [나와의 채팅] 버튼을 누르면 기본값으로 돌아갑니다.`r`n`r`n[테스트 발송]은 실제와 똑같은 방식으로 보내므로 줄바꿈이나 사진 순서를 미리 볼 수 있습니다.`r`n[방 확인만]은 채팅창을 열어 이름만 맞는지 확인하고 전송은 하지 않습니다."
    },
    @{
        Page = 'run'
        Title = '5단계 · 보내면 안 되는 때 정하기'
        Body  = "[발송 제한]에서 보내지 않을 시간과 날짜를 정할 수 있습니다.`r`n`r`n· 방해금지 시간대 — 예를 들어 21:00 부터 08:00 까지는 보내지 않습니다. 자정을 넘는 구간도 됩니다.`r`n· 주말에는 보내지 않기`r`n· 공휴일에는 [평소대로 / 보내지 않음 / 간격 늘리기] 중 선택`r`n`r`n예약 발송이 제한 시간에 걸리면 취소하지 않고 보낼 수 있는 다음 시각으로 미룹니다. 공휴일은 음력 명절까지 계산하며 [올해 공휴일 보기]로 확인할 수 있습니다."
    },
    @{
        Page = 'run'
        Title = '6단계 · 지금 실행 또는 예약'
        Body  = "[지금 실행]은 바로 보내고, [예약 시작]은 지정한 시각에 자동으로 보냅니다.`r`n`r`n예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 하고, 화면 잠금이나 절전 상태에서는 동작하지 않습니다.`r`n`r`n방 사이 간격은 최소 5초이며, 한 번에 최대 50개 방까지만 처리합니다."
    },
    @{
        Page = 'log'
        Title = '끝 · 안전하게 쓰기'
        Body  = "실행 중에는 마우스와 키보드를 사용하지 마세요. 클릭이 엉뚱한 곳으로 가면 잘못된 방에 전송될 수 있습니다.`r`n`r`n성공·건너뜀·오류는 모두 [실행 기록]에 남고 날짜별 파일로도 저장됩니다.`r`n`r`n수신에 동의한 분들이 있는 채팅방에서만 사용하세요. 반복적인 대량 발송은 카카오톡 이용 제한의 원인이 될 수 있습니다.`r`n`r`n이 가이드는 오른쪽 위 [?] 버튼으로 언제든 다시 볼 수 있습니다."
    }
)

# ---------------------------------------------------------------------------
# 자체 점검 및 진단 모드
# ---------------------------------------------------------------------------
$script:config = Import-AppConfig

if ($SelfTest) {
    $required = @('Rooms', 'KnownRooms', 'RoomTypes', 'RoomListNames', 'Groups', 'QuietEnabled', 'QuietStart', 'QuietEnd', 'HolidayMode', 'HolidayIntervalMultiplier', 'SkipWeekend', 'ExtraHolidays', 'AutoDownloadUpdate', 'SkipSendConfirm', 'RepeatEnabled', 'RepeatMinutes', 'RepeatCount', 'BatchSize', 'BatchRestMinutes', 'Message', 'Attachments', 'ScheduledAt', 'IntervalSeconds', 'DryRun', 'ScanPages', 'TestRoom', 'AttachmentWaitMs', 'OpenTimeoutMs', 'SettleMs', 'PreloadRooms', 'PreloadDone', 'TruncatedRooms', 'AutoCheckUpdate', 'TourDone', 'Calibration')
    foreach ($name in $required) {
        if ($null -eq $script:config.PSObject.Properties[$name]) { throw "필수 설정 항목 누락: $name" }
    }
    foreach ($name in @('SearchIconOffset')) {
        if ($null -eq $script:config.Calibration.PSObject.Properties[$name]) { throw "필수 보정 항목 누락: $name" }
    }
    if ($null -ne (ConvertTo-RoomCandidate '오후 3:20')) { throw '후보 필터 자체 점검 실패 (시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '12:30')) { throw '후보 필터 자체 점검 실패 (숫자 시각)' }
    if ($null -ne (ConvertTo-RoomCandidate '채팅')) { throw '후보 필터 자체 점검 실패 (메뉴)' }
    if ($null -ne (ConvertTo-RoomCandidate '·')) { throw '후보 필터 자체 점검 실패 (기호)' }
    if ((ConvertTo-RoomCandidate "테스트 채팅방`r`n안녕하세요") -ne '테스트 채팅방') { throw '후보 추출 자체 점검 실패' }
    if (-not (Test-RoomTitle '우리반 공지방 (24)' '우리반 공지방')) { throw '창 제목 비교 자체 점검 실패' }
    if (Test-RoomTitle '우리반 공지방 2기' '우리반 공지방') { throw '창 제목 비교가 너무 느슨합니다' }
    # 창 메시지로 글을 넣는 기능을 진짜로 불러 봅니다.
    # 예전에 user32.dll 에 없는 이름으로 선언해 두어 부를 때마다 터졌는데,
    # 코드만 봐서는 알 수 없었습니다. 실제로 넣어 보고 확인합니다.
    $probe = New-Object System.Windows.Forms.TextBox
    try {
        [void]$probe.Handle
        [NativeKakao]::ReplaceSelection($probe.Handle, '확인용')
        [System.Windows.Forms.Application]::DoEvents()
        if ($probe.Text -ne '확인용') { throw "창 메시지로 글을 넣지 못합니다 (넣은 결과: '$($probe.Text)')" }
        $probe.Text = ''
        [NativeKakao]::ReplaceSelection($probe.Handle, ('가' * 3000))
        [System.Windows.Forms.Application]::DoEvents()
        if ($probe.Text.Length -lt 3000) { throw "긴 글이 잘립니다 ($($probe.Text.Length)자만 들어감)" }
    } finally { $probe.Dispose() }
    # 이름이 잘린 방은 앞부분으로 찾을 수 있어야 합니다.
    $savedTrunc = @($script:config.TruncatedRooms)
    $savedKnown = @($script:config.KnownRooms)
    try {
        $script:config.TruncatedRooms = @('길게 쓴 방이름')
        $script:config.KnownRooms = @('길게 쓴 방이름')
        if (-not (Test-RoomTitle '길게 쓴 방이름입니다 진짜' '길게 쓴 방이름')) { throw '잘린 이름을 찾지 못합니다' }
        $script:config.KnownRooms = @('길게 쓴 방이름', '길게 쓴 방이름 둘째')
        if (Test-RoomTitle '길게 쓴 방이름입니다 진짜' '길게 쓴 방이름') { throw '헷갈리는 방인데도 같다고 합니다' }
    } finally {
        $script:config.TruncatedRooms = $savedTrunc
        $script:config.KnownRooms = $savedKnown
    }
    if ((Remove-RoomNameNoise '0 홍보방') -ne '홍보방') { throw '이름 다듬기 자체 점검 실패 (안읽음 뱃지)' }
    if ((Remove-RoomNameNoise '긴 방이름입니다…') -ne '긴 방이름입니다') { throw '이름 다듬기 자체 점검 실패 (잘림 표시)' }
    # 진짜 이름이 숫자로 시작하는 방을 잘못 깎으면 안 됩니다.
    if ((Remove-RoomNameNoise '5K 디자인') -ne '5K 디자인') { throw '이름 다듬기가 진짜 이름을 깎았습니다' }
    if ((Remove-RoomNameNoise '95 비와이') -ne '95 비와이') { throw '이름 다듬기가 진짜 이름을 깎았습니다 (숫자)' }
    foreach ($fn in @('Wait-ChatContentSettled', 'Get-ChatListControl', 'Get-ChatInputState')) {
        if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { throw "필수 기능 누락: $fn" }
    }
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

    # 그룹
    Set-GroupRooms '점검그룹' @('가', '나', '가')
    if ((Get-GroupRooms '점검그룹').Count -ne 2) { throw '그룹 중복 제거 실패' }
    Rename-RoomInGroups '가' '가나다'
    if ((Get-GroupRooms '점검그룹') -notcontains '가나다') { throw '그룹 내 이름 변경 실패' }
    Remove-RoomFromGroups '나'
    if ((Get-GroupRooms '점검그룹') -contains '나') { throw '그룹에서 방 제거 실패' }
    if ((Get-GroupsForRoom '가나다') -notcontains '점검그룹') { throw '방의 그룹 조회 실패' }
    Remove-Group '점검그룹'
    if ((Get-GroupNames) -contains '점검그룹') { throw '그룹 삭제 실패' }

    # 시각 파싱과 방해금지 시간대
    if ((ConvertTo-DayMinutes '21:00' 0) -ne 1260) { throw '시각 파싱 실패' }
    if ((ConvertTo-DayMinutes '8:05' 0) -ne 485) { throw '한 자리 시각 파싱 실패' }
    if ((ConvertTo-DayMinutes '25:00' 777) -ne 777) { throw '잘못된 시각 처리 실패' }
    if ((ConvertTo-DayMinutes '엉뚱' 777) -ne 777) { throw '숫자 아닌 시각 처리 실패' }
    $script:config.QuietEnabled = $true
    $script:config.QuietStart = '21:00'
    $script:config.QuietEnd = '08:00'
    if (-not (Test-QuietHours ([datetime]'2026-08-14 22:30'))) { throw '자정 넘는 방해금지 시간대 판정 실패 (밤)' }
    if (-not (Test-QuietHours ([datetime]'2026-08-14 03:00'))) { throw '자정 넘는 방해금지 시간대 판정 실패 (새벽)' }
    if (Test-QuietHours ([datetime]'2026-08-14 12:00')) { throw '방해금지 시간대 오판정 (낮)' }
    $script:config.QuietStart = '09:00'
    $script:config.QuietEnd = '18:00'
    if (-not (Test-QuietHours ([datetime]'2026-08-14 10:00'))) { throw '같은 날 구간 방해금지 판정 실패' }
    if (Test-QuietHours ([datetime]'2026-08-14 20:00')) { throw '같은 날 구간 방해금지 오판정' }
    $script:config.QuietEnabled = $false
    if (Test-QuietHours ([datetime]'2026-08-14 22:30')) { throw '방해금지 끄기 실패' }

    # 공휴일 (음력 명절은 Windows 음력 달력으로 계산)
    foreach ($check in @(
        @{ Date = '2026-01-01'; Name = '신정' },
        @{ Date = '2026-03-01'; Name = '삼일절' },
        @{ Date = '2026-08-15'; Name = '광복절' },
        @{ Date = '2026-12-25'; Name = '성탄절' }
    )) {
        if ($null -eq (Get-HolidayName ([datetime]$check.Date))) { throw "공휴일 인식 실패: $($check.Date) $($check.Name)" }
    }
    if ($null -ne (Get-HolidayName ([datetime]'2026-08-14'))) { throw '평일을 공휴일로 오판정' }
    $seollal2026 = ConvertFrom-KoreanLunar 2026 1 1
    if ($null -eq $seollal2026) { throw '음력 변환 실패' }
    if ($seollal2026.Year -ne 2026) { throw '음력 변환 연도 오류' }
    $script:config.HolidayMode = '보내지 않음'
    if ($null -eq (Get-SendBlockReason ([datetime]'2026-01-01 12:00'))) { throw '공휴일 발송 차단 실패' }
    $script:config.HolidayMode = '간격 늘리기'
    $script:config.IntervalSeconds = 10
    $script:config.HolidayIntervalMultiplier = 3
    if ((Get-EffectiveInterval ([datetime]'2026-01-01 12:00')) -ne 30) { throw '공휴일 간격 배수 적용 실패' }
    if ((Get-EffectiveInterval ([datetime]'2026-08-14 12:00')) -ne 10) { throw '평일 간격이 잘못 늘어남' }
    $script:config.HolidayMode = '평소대로'
    $script:config.SkipWeekend = $true
    if ($null -eq (Get-SendBlockReason ([datetime]'2026-08-15 12:00'))) { throw '주말 차단 실패' }
    $script:config.SkipWeekend = $false
    if ($null -ne (Get-SendBlockReason ([datetime]'2026-08-14 12:00'))) { throw '평일을 잘못 차단' }
    $script:config.QuietEnabled = $true
    $script:config.QuietStart = '21:00'
    $script:config.QuietEnd = '08:00'
    $nextAllowed = Get-NextAllowedTime ([datetime]'2026-08-14 22:00')
    if ($null -eq $nextAllowed) { throw '다음 발송 가능 시각 계산 실패' }
    if ((Test-QuietHours $nextAllowed)) { throw '다음 발송 가능 시각이 여전히 방해금지 구간' }
    $script:config.QuietEnabled = $false

    # 줄바꿈이 Enter 로 바뀌면 메시지가 줄마다 쪼개져 전송됩니다. 반드시 Shift+Enter 여야 합니다.
    $multiline = ConvertTo-SendKeysText "첫째 줄`r`n둘째 줄"
    if ($multiline -ne '첫째 줄+{ENTER}둘째 줄') { throw "줄바꿈 변환 실패: $multiline" }
    if ($multiline -match '(?<!\+)\{ENTER\}') { throw '줄바꿈이 그냥 Enter 로 변환되었습니다' }
    $special = ConvertTo-SendKeysText '가격(1+2) 100% ^표시 {중괄호} [대괄호] ~물결'
    foreach ($token in @('{(}', '{)}', '{+}', '{%}', '{^}', '{{}', '{}}', '{[}', '{]}', '{~}')) {
        if (-not $special.Contains($token)) { throw "특수 기호 변환 실패: $token 이 없습니다 — $special" }
    }
    if ((ConvertTo-SendKeysText '보통 문구') -ne '보통 문구') { throw '일반 문구가 잘못 변환되었습니다' }

    # 특수문자가 섞인 방 이름도 찾아야 합니다. 화면에서는 ☆ 같은 기호가 안 읽힙니다.
    if ((ConvertTo-CompareKey '☆자유로운 홍보방☆') -ne '자유로운홍보방') { throw '기호 제거 실패' }
    if ((ConvertTo-CompareKey '마케팅 초이스&핫소스') -ne '마케팅초이스핫소스') { throw '앰퍼샌드 제거 실패' }
    if ((ConvertTo-CompareKey '[공지] A/S 문의') -ne '공지as문의') { throw '괄호·슬래시 제거 실패' }
    $starSample = @([pscustomobject]@{ Text = '자유로운 홍보방'; Left = 80; Top = 20 })
    if ($null -eq (Find-SearchResultLine $starSample '☆자유로운 홍보방☆' 325)) { throw '기호 있는 이름 매칭 실패' }
    $ampSample = @([pscustomobject]@{ Text = '마케팅 초이스 핫소스'; Left = 80; Top = 20 })
    if ($null -eq (Find-SearchResultLine $ampSample '마케팅 초이스&핫소스' 325)) { throw '앰퍼샌드 이름 매칭 실패' }
    $wrongSample = @([pscustomobject]@{ Text = '전혀 다른 방'; Left = 80; Top = 20 })
    if ($null -ne (Find-SearchResultLine $wrongSample '☆자유로운 홍보방☆' 325)) { throw '다른 방을 잘못 매칭' }

    # 입력칸이 비면 카카오톡이 안내글을 보여 줍니다. 이걸 내용으로 오해하면 안 됩니다.
    if ($script:InputPlaceholders -notcontains '메시지 입력') { throw '입력칸 안내글 목록 누락' }
    foreach ($ext in @('.png', '.JPG', '.jpeg', '.gif', '.bmp')) {
        if (-not (Test-IsImageFile "사진$ext")) { throw "사진 확장자 인식 실패: $ext" }
    }
    foreach ($ext in @('.pdf', '.zip', '.hwp', '.txt')) {
        if (Test-IsImageFile "문서$ext") { throw "사진이 아닌 파일을 사진으로 봤습니다: $ext" }
    }

    # 목록에서 읽을 때 이름 앞에 붙는 '0 ' 잡티를 떼어냅니다.
    if ((Remove-RoomNameNoise '0 우리반 공지방') -ne '우리반 공지방') { throw '이름 앞 잡티 제거 실패' }
    if ((Remove-RoomNameNoise '0홍보방') -ne '홍보방') { throw '붙어 있는 잡티 제거 실패' }
    if ((Remove-RoomNameNoise '05K-니자인') -ne '05K-니자인') { throw '진짜 숫자 이름을 잘못 건드렸습니다' }
    if ((Remove-RoomNameNoise '95 비와이') -ne '95 비와이') { throw '숫자로 시작하는 이름을 잘못 건드렸습니다' }
    if ((ConvertTo-RoomCandidate '0 동네 모임') -ne '동네 모임') { throw '후보 추출에서 잡티가 남았습니다' }

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

# 발송 한 건당 걸리는 시간을 단계별로 재는 진단 모드입니다.
# 메시지는 보내지 않고 '나와의 채팅' 창을 열고 닫기만 반복합니다.
if ($SendBench) {
    $room = if ($env:KAKAO_BENCH_ROOM) { $env:KAKAO_BENCH_ROOM } else { '나와의 채팅' }
    $ready = Test-KakaoReady $true $true
    if (-not $ready.Ok) { Write-Output "준비 안 됨: $($ready.Reason)"; exit 1 }
    Write-Output ("대상: {0} / 반복 {1}회 (전송하지 않음)" -f $room, $BenchCount)
    $openTimes = @()
    $closeTimes = @()
    for ($i = 1; $i -le $BenchCount; $i++) {
        $watch = [System.Diagnostics.Stopwatch]::StartNew()
        $chat = Open-RoomBySearch $room $script:RoomTypeNormal
        $watch.Stop()
        $openMs = $watch.ElapsedMilliseconds
        if ($null -eq $chat) { Write-Output ("  {0}회: 창을 열지 못했습니다 ({1}ms)" -f $i, $openMs); continue }
        $watch.Restart()
        Close-ChatWindow $chat
        $watch.Stop()
        $closeMs = $watch.ElapsedMilliseconds
        $openTimes += $openMs
        $closeTimes += $closeMs
        Write-Output ("  {0}회: 열기 {1}ms + 닫기 {2}ms = {3}ms" -f $i, $openMs, $closeMs, ($openMs + $closeMs))
        Start-Sleep -Milliseconds 400
    }
    if ($openTimes.Count -gt 0) {
        $avgOpen = [int](($openTimes | Measure-Object -Average).Average)
        $avgClose = [int](($closeTimes | Measure-Object -Average).Average)
        Write-Output ("평균: 열기 {0}ms + 닫기 {1}ms = 방 하나당 약 {2:N1}초 (메시지 전송 시간 제외)" -f $avgOpen, $avgClose, (($avgOpen + $avgClose) / 1000))
    }
    Write-Output 'SENDBENCH_OK'
    exit 0
}

# ---------------------------------------------------------------------------
# 중복 실행 막기
# ---------------------------------------------------------------------------
# 두 개가 동시에 돌면 같은 config.json 을 서로 덮어쓰고,
# 무엇보다 같은 카카오톡을 동시에 조작해 엉뚱한 방에 보내질 수 있습니다.
# 그래서 한 번에 하나만 실행되도록 막고, 이미 있으면 그 창을 앞으로 가져옵니다.
$script:instanceLock = $null

function Enter-SingleInstance {
    $createdNew = $false
    try {
        $script:instanceLock = New-Object System.Threading.Mutex($true, 'Local\KakaoRoomScheduler.SingleInstance', [ref]$createdNew)
    } catch {
        return $true
    }
    if ($createdNew) { return $true }

    # 이미 실행 중입니다. 기존 창을 찾아 앞으로 가져옵니다.
    $existing = [IntPtr]::Zero
    try { $existing = [NativeKakao]::FindWindowByTitlePrefix('카카오 발송기', $PID) } catch { }
    if ($existing -ne [IntPtr]::Zero) {
        [void][NativeKakao]::ForceForeground($existing)
        [System.Windows.Forms.MessageBox]::Show(
            "카카오 발송기가 이미 실행 중입니다.`r`n`r`n실행 중인 창을 앞으로 가져왔습니다.`r`n`r`n두 개를 동시에 켜면 설정이 서로 덮어써지고, 같은 카카오톡을 동시에 조작해 잘못 발송될 수 있어 막았습니다.",
            '이미 실행 중입니다', 'OK', 'Information') | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show(
            "카카오 발송기가 이미 실행 중입니다.`r`n`r`n작업 표시줄에서 기존 창을 찾아 주세요.`r`n창이 보이지 않으면 작업 관리자에서 powershell 을 종료한 뒤 다시 실행해 주세요.",
            '이미 실행 중입니다', 'OK', 'Warning') | Out-Null
    }
    return $false
}

function Exit-SingleInstance {
    if ($null -ne $script:instanceLock) {
        try { $script:instanceLock.ReleaseMutex() } catch { }
        try { $script:instanceLock.Dispose() } catch { }
        $script:instanceLock = $null
    }
}

# 진단용 실행은 막지 않습니다.
# 점검 모드는 화면을 만들어 보기만 하고 카카오톡을 건드리지 않습니다.
# 실행 중인 앱과 겹쳐도 문제가 없으므로 중복 실행 검사를 건너뜁니다.
# 이걸 안 하면 앱을 켜 둔 채로는 점검을 돌릴 수 없습니다.
if (-not $UiSmokeTest -and -not $ScreenshotDir) {
    if (-not (Enter-SingleInstance)) { exit 0 }
}

# ---------------------------------------------------------------------------
# 디자인 토큰
# ---------------------------------------------------------------------------
function New-Rgb([int]$R, [int]$G, [int]$B) { [System.Drawing.Color]::FromArgb($R, $G, $B) }

# 색은 적게 쓰고 밝게 갑니다.
# 노란색은 [발송 시작] 같은 진짜 중요한 단추 하나에만 씁니다.
# 나머지는 흰색과 회색으로만 만들어 눈이 어디를 봐야 하는지 분명하게 합니다.
$Theme = @{
    Sidebar    = [System.Drawing.Color]::White
    SidebarHi  = (New-Rgb 241 243 247)
    NavIdle    = (New-Rgb 108 116 128)
    Accent     = (New-Rgb 254 229 0)
    AccentInk  = (New-Rgb 26 26 26)
    Bg         = (New-Rgb 247 248 250)
    Card       = [System.Drawing.Color]::White
    Border     = (New-Rgb 237 239 243)
    Ink        = (New-Rgb 22 24 29)
    Sub        = (New-Rgb 91 98 112)
    Muted      = (New-Rgb 152 160 172)
    Success    = (New-Rgb 22 120 70)
    Danger     = (New-Rgb 198 55 60)
    Info       = (New-Rgb 37 88 200)
    FieldEdge  = (New-Rgb 227 231 237)
    Soft       = (New-Rgb 243 245 248)
    SoftHover  = (New-Rgb 234 238 243)
}

$FontBase   = New-Object System.Drawing.Font('Malgun Gothic', 10)
$FontSmall  = New-Object System.Drawing.Font('Malgun Gothic', 9)
$FontStrong = New-Object System.Drawing.Font('Malgun Gothic', 10, [System.Drawing.FontStyle]::Bold)
$FontCard   = New-Object System.Drawing.Font('Malgun Gothic', 11.5, [System.Drawing.FontStyle]::Bold)
$FontPage   = New-Object System.Drawing.Font('Malgun Gothic', 17, [System.Drawing.FontStyle]::Bold)
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
        # 테두리를 그리지 않습니다. 흰 면과 여백만으로 구역을 나누는 편이 깔끔합니다.
        $path = Get-RoundedPath $rect 14
        $brush = New-Object System.Drawing.SolidBrush ($Theme.Card)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
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
        'strong' {
            # 중요하지만 발송은 아닌 동작입니다. 짙은 면에 흰 글씨로 눈에 띄게 합니다.
            $button.BackColor = $Theme.Ink
            $button.ForeColor = [System.Drawing.Color]::White
            $button.Font = $FontStrong
            $button.FlatAppearance.BorderSize = 0
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
    # Region 으로 모서리를 깎으면 계단현상이 생겨 둥근 모서리가 지저분해 보입니다.
    # 부모 배경색으로 칠한 뒤 부드럽게 둥근 사각형을 직접 그립니다.
    $button.Tag = [pscustomobject]@{ Label = $Text; Kind = $Kind; Hover = $false }
    $button.Text = ''
    $button.AccessibleName = $Text
    $button.Add_MouseEnter({ $this.Tag.Hover = $true; $this.Invalidate() })
    $button.Add_MouseLeave({ $this.Tag.Hover = $false; $this.Invalidate() })
    $button.Add_Paint({
        param($sender, $e)
        $info = $sender.Tag
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $parentColor = if ($null -ne $sender.Parent) { $sender.Parent.BackColor } else { $Theme.Card }
        $e.Graphics.Clear($parentColor)
        $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $path = Get-RoundedPath $rect 8

        $enabled = $sender.Enabled
        $fill = $Theme.Card
        $edge = $Theme.FieldEdge
        $ink = $Theme.Ink
        $drawEdge = $true
        switch ($info.Kind) {
            'primary' {
                if ($enabled) { $fill = if ($info.Hover) { (New-Rgb 246 222 0) } else { $Theme.Accent }; $ink = $Theme.AccentInk }
                else { $fill = (New-Rgb 236 238 241); $ink = (New-Rgb 158 163 171) }
                $drawEdge = $false
            }
            'danger' {
                # 지우는 단추는 글자색만 붉게 합니다. 면까지 붉히면 시끄럽습니다.
                $fill = if ($info.Hover -and $enabled) { (New-Rgb 253 243 243) } else { $parentColor }
                $ink = if ($enabled) { $Theme.Danger } else { $Theme.Muted }
                $drawEdge = $false
            }
            'strong' {
                $fill = if ($info.Hover -and $enabled) { (New-Rgb 48 52 60) } else { $Theme.Ink }
                if (-not $enabled) { $fill = $Theme.Soft }
                $ink = if ($enabled) { [System.Drawing.Color]::White } else { $Theme.Muted }
                $drawEdge = $false
            }
            'ghost' {
                $fill = if ($info.Hover -and $enabled) { $Theme.Bg } else { $parentColor }
                $ink = if ($enabled) { $Theme.Sub } else { $Theme.Muted }
                $drawEdge = $false
            }
            default {
                # 테두리를 그리지 않고 옅은 회색 면으로 단추임을 알립니다.
                $fill = if ($info.Hover -and $enabled) { $Theme.SoftHover } else { $Theme.Soft }
                $ink = if ($enabled) { $Theme.Ink } else { $Theme.Muted }
                $drawEdge = $false
            }
        }
        $brush = New-Object System.Drawing.SolidBrush ($fill)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose()
        if ($drawEdge) {
            $pen = New-Object System.Drawing.Pen ($edge)
            $e.Graphics.DrawPath($pen, $path)
            $pen.Dispose()
        }
        $path.Dispose()
        Write-Text $e.Graphics $info.Label $sender.Font $ink (New-Object System.Drawing.Rectangle(2, 0, ($sender.Width - 4), $sender.Height)) $TextCenter
    })
    $button.Add_EnabledChanged({ $this.Invalidate() })
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
    Write-Text $e.Graphics '카카오 발송기' $FontLogo $Theme.Ink (New-Object System.Drawing.Rectangle(82, 32, 130, 22)) $TextLeft
    Write-Text $e.Graphics "v$($script:AppVersion)" $FontSmall $Theme.NavIdle (New-Object System.Drawing.Rectangle(82, 54, 130, 20)) $TextLeft
})
$sidebar.Controls.Add($logo)

# 자주 쓰는 순서대로 위에 두고, 설정과 기록은 아래로 내립니다.
$script:NavPages = @(
    @{ Key = 'compose';  Text = '1. 보낼 내용';   Title = '보낼 내용';   Group = 'main' },
    @{ Key = 'rooms';    Text = '2. 받을 채팅방'; Title = '받을 채팅방'; Group = 'main' },
    @{ Key = 'run';      Text = '3. 보내기';      Title = '보내기';      Group = 'main' },
    @{ Key = 'settings'; Text = '설정';           Title = '설정';        Group = 'bottom' },
    @{ Key = 'log';      Text = '실행 기록';      Title = '실행 기록';   Group = 'bottom' }
)

$navY = 122
$bottomY = 470
foreach ($page in $script:NavPages) {
    if ($page.Group -eq 'bottom' -and $navY -lt $bottomY) { $navY = $bottomY }
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
        # 고른 항목은 둥근 회색 면으로만 알립니다. 색 막대까지 두면 시끄럽습니다.
        if ($isActive -or $isHover) {
            $inner = New-Object System.Drawing.Rectangle(14, 4, ($sender.Width - 28), ($sender.Height - 8))
            $shape = Get-RoundedPath $inner 10
            $fill = New-Object System.Drawing.SolidBrush ($Theme.SidebarHi)
            $e.Graphics.FillPath($fill, $shape)
            $fill.Dispose(); $shape.Dispose()
        }
        $color = if ($isActive) { $Theme.Ink } else { $Theme.NavIdle }
        $font = if ($isActive) { $FontStrong } else { $FontBase }
        Write-Text $e.Graphics $script:navText[$key] $font $color (New-Object System.Drawing.Rectangle(32, 0, 174, $sender.Height)) $TextLeft
    })
    $item.Add_Click({ Show-AppPage ([string]$this.Tag) })
    $item.Add_MouseEnter({ $script:hoverNav = [string]$this.Tag; $this.Invalidate() })
    $item.Add_MouseLeave({ $script:hoverNav = ''; $this.Invalidate() })
    $sidebar.Controls.Add($item)
    $script:navItems += $item
    $navY += 48
}

# 위쪽 작업 묶음과 아래쪽 보조 메뉴를 구분하는 선
$navDivider = New-Object System.Windows.Forms.Panel
$navDivider.Location = New-Object System.Drawing.Point(28, ($bottomY - 18))
$navDivider.Size = New-Object System.Drawing.Size(164, 1)
$navDivider.BackColor = $Theme.Border
$sidebar.Controls.Add($navDivider)

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
$lblHint.ForeColor = $Theme.Muted
$lblHint.Font = $FontSmall
$sidebar.Controls.Add($lblHint)


# 사이드바와 본문을 나누는 얇은 선입니다. 밝은 바탕끼리는 이 선 하나면 충분합니다.
$sideEdge = New-Object System.Windows.Forms.Panel
$sideEdge.Location = New-Object System.Drawing.Point(219, 0)
$sideEdge.Size = New-Object System.Drawing.Size(1, 740)
$sideEdge.BackColor = $Theme.Border
$script:form.Controls.Add($sideEdge)
$sideEdge.BringToFront()

# ----- 헤더 -----
$header = New-Object System.Windows.Forms.Panel
$header.Location = New-Object System.Drawing.Point(220, 0)
$header.Size = New-Object System.Drawing.Size(840, 96)
$header.BackColor = $Theme.Bg
$script:form.Controls.Add($header)

$script:lblPageTitle = New-Object System.Windows.Forms.Label
$script:lblPageTitle.Text = '발송 준비'
$script:lblPageTitle.Font = $FontPage
$script:lblPageTitle.ForeColor = $Theme.Ink
$script:lblPageTitle.BackColor = $Theme.Bg
$script:lblPageTitle.Location = New-Object System.Drawing.Point(28, 12)
$script:lblPageTitle.Size = New-Object System.Drawing.Size(440, 32)
$header.Controls.Add($script:lblPageTitle)

$script:pillStatus = New-Object System.Windows.Forms.Panel
$script:pillStatus.Location = New-Object System.Drawing.Point(28, 50)
$script:pillStatus.Size = New-Object System.Drawing.Size(184, 32)
$script:pillStatus.BackColor = $Theme.Bg
$script:pillStatus.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    switch ($script:statusKind) {
        'run'   { $fill = New-Rgb 255 248 219; $ink = New-Rgb 141 100 0 }
        'wait'  { $fill = New-Rgb 229 239 255; $ink = $Theme.Info }
        'done'  { $fill = New-Rgb 227 246 233; $ink = $Theme.Success }
        'error' { $fill = New-Rgb 253 237 237; $ink = $Theme.Danger }
        default { $fill = $Theme.Soft; $ink = $Theme.Sub }
    }
    $rect = New-Object System.Drawing.Rectangle(0, 0, ($sender.Width - 1), ($sender.Height - 1))
    $path = Get-RoundedPath $rect 16
    $brush = New-Object System.Drawing.SolidBrush ($fill)
    $e.Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
    $dot = New-Object System.Drawing.SolidBrush ($ink)
    $e.Graphics.FillEllipse($dot, 17, ([int]($sender.Height / 2) - 4), 9, 9)
    $dot.Dispose()
    Write-Text $e.Graphics $script:statusText $FontBase $ink (New-Object System.Drawing.Rectangle(34, 0, ($sender.Width - 46), $sender.Height)) $TextLeft
})
$header.Controls.Add($script:pillStatus)

# 지금 예약과 반복 설정을 위쪽에 한 줄로 보여 줍니다.
$script:lblHeaderPlan = New-Object System.Windows.Forms.Label
$script:lblHeaderPlan.Font = $FontSmall
$script:lblHeaderPlan.ForeColor = $Theme.Sub
$script:lblHeaderPlan.BackColor = $Theme.Bg
$script:lblHeaderPlan.Location = New-Object System.Drawing.Point(222, 46)
$script:lblHeaderPlan.Size = New-Object System.Drawing.Size(268, 40)
$script:lblHeaderPlan.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($script:lblHeaderPlan)

# 어느 화면에 있든 바로 누를 수 있게 위쪽에 둡니다.
$btnHeaderEdit  = New-AppButton $header '내용 수정' 498 26 104 46
$btnHeaderStart = New-AppButton $header '발송 시작' 610 26 132 46 'primary'
# 예약 대기 중이거나 발송 중일 때 [발송 시작] 자리에 나타납니다.
$script:btnHeaderStop = New-AppButton $header '중지' 610 26 132 46 'danger'
$script:btnHeaderStop.Visible = $false

$btnHelp = New-AppButton $header '?' 750 26 36 46 'default'
$btnHelp.Font = $FontStrong
$tipHelp = New-Object System.Windows.Forms.ToolTip
$tipHelp.SetToolTip($btnHelp, '사용 가이드 다시 보기')
$tipHelp.SetToolTip($btnHeaderStart, '지금 발송을 시작합니다')
$tipHelp.SetToolTip($btnHeaderEdit, '보낼 문구와 첨부를 고칩니다')

# ----- 페이지 컨테이너 -----
$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Location = New-Object System.Drawing.Point(220, 96)
$pageHost.Size = New-Object System.Drawing.Size(840, 644)
$pageHost.BackColor = $Theme.Bg
$script:form.Controls.Add($pageHost)

$script:pages = @{}
function New-Page([string]$Key) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = New-Object System.Drawing.Point(0, 0)
    $panel.Size = New-Object System.Drawing.Size(840, 644)
    $panel.BackColor = $Theme.Bg
    $panel.Visible = $false
    # 카드가 화면보다 길어지면 스크롤로 볼 수 있게 합니다.
    $panel.AutoScroll = $true
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

$cardFiles = New-Card $pageCompose 28 292 784 312 '첨부 사진 · 파일' '문구를 보낸 뒤 아래 순서대로 하나씩 전송합니다. [첨부 시험]은 붙는지만 확인하고 보내지 않습니다.'
$frameFiles = New-FieldFrame $cardFiles 24 78 576 212
$script:lstFiles = New-Object System.Windows.Forms.ListBox
$script:lstFiles.BorderStyle = 'None'
$script:lstFiles.Font = $FontBase
$script:lstFiles.Location = New-Object System.Drawing.Point(12, 12)
$script:lstFiles.Size = New-Object System.Drawing.Size(552, 188)
$script:lstFiles.DisplayMember = 'Name'
$script:lstFiles.ItemHeight = 24
$frameFiles.Controls.Add($script:lstFiles)
foreach ($file in @($script:config.Attachments)) { [void]$script:lstFiles.Items.Add((New-AttachmentItem ([string]$file))) }

$btnAddFile    = New-AppButton $cardFiles '파일 추가' 616 78 144 40 'strong'
$btnFileUp     = New-AppButton $cardFiles '위로' 616 128 144 36
$btnFileDown   = New-AppButton $cardFiles '아래로' 616 170 144 36
$btnRemoveFile = New-AppButton $cardFiles '선택 제거' 616 218 144 36 'danger'
$btnCheckAttach = New-AppButton $cardFiles '첨부 시험' 616 262 144 36

$lblComposeHint = New-CardLabel $pageCompose '내용은 자동 저장됩니다. 실제 발송 전에 [3. 보내기] 화면에서 테스트 발송으로 결과를 먼저 확인하세요.' 28 618 784 30 $FontSmall $Theme.Muted
$lblComposeHint.BackColor = $Theme.Bg

# ===========================================================================
# 페이지 2 — 채팅방 선택
# ===========================================================================
$pageRooms = New-Page 'rooms'
$cardRooms = New-Card $pageRooms 28 12 784 700 '발송 대상 채팅방' '[오픈채팅] 탭을 먼저 읽고 그다음 [채팅] 탭을 읽으면 종류가 정확히 나뉩니다.'

$btnScanRooms  = New-AppButton $cardRooms '카카오톡에서 읽기' 24 80 170 38 'strong'
$btnVerifyRoom = New-AppButton $cardRooms '이름 확인·보정' 202 80 140 38
$btnAddRoom    = New-AppButton $cardRooms '직접 추가' 350 80 90 38
$btnEditRoom   = New-AppButton $cardRooms '이름 수정' 448 80 84 38

# 방이 많을 때를 위한 검색칸
[void](New-CardLabel $cardRooms '검색' 24 134 38 26 $FontSmall $Theme.Muted)
$script:txtRoomSearch = New-AppTextBox $cardRooms 62 128 236 36
$btnSearchClear = New-AppButton $cardRooms '지우기' 306 128 74 36 'ghost'

[void](New-CardLabel $cardRooms '보기' 396 134 34 26 $FontSmall $Theme.Muted)
$btnFilterAll    = New-AppButton $cardRooms '전체' 428 128 58 36
$btnFilterPerson = New-AppButton $cardRooms '개인' 492 128 58 36
$btnFilterChat   = New-AppButton $cardRooms '그룹' 556 128 58 36
$btnFilterOpen   = New-AppButton $cardRooms '오픈채팅' 620 128 84 36
$script:lblRoomCount = New-CardLabel $cardRooms '선택 0 / 전체 0' 24 172 480 24 $FontStrong $Theme.Ink
$script:lblSearchState = New-CardLabel $cardRooms '' 24 196 736 22 $FontSmall $Theme.Info

$frameRooms = New-FieldFrame $cardRooms 24 222 736 324
$script:lstRooms = New-Object System.Windows.Forms.ListView
$script:lstRooms.View = 'Details'
$script:lstRooms.CheckBoxes = $true
$script:lstRooms.FullRowSelect = $true
$script:lstRooms.HideSelection = $false
$script:lstRooms.BorderStyle = 'None'
$script:lstRooms.Font = $FontBase
$script:lstRooms.Location = New-Object System.Drawing.Point(12, 12)
$script:lstRooms.Size = New-Object System.Drawing.Size(712, 300)
[void]$script:lstRooms.Columns.Add('채팅방 이름', 560)
[void]$script:lstRooms.Columns.Add('종류', 130)
$frameRooms.Controls.Add($script:lstRooms)

$btnCheckAll  = New-AppButton $cardRooms '보이는 항목 모두 체크' 24 560 168 34
$btnCheckNone = New-AppButton $cardRooms '체크 모두 해제' 200 560 130 34
$btnDeleteRoom = New-AppButton $cardRooms '체크한 항목 삭제' 338 560 140 34 'danger'
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

# ----- 그룹 -----
[void](New-CardLabel $cardRooms '그룹' 24 606 42 26 $FontSmall $Theme.Muted)
$script:cmbGroup = New-Object System.Windows.Forms.ComboBox
$script:cmbGroup.DropDownStyle = 'DropDownList'
$script:cmbGroup.Font = $FontBase
$script:cmbGroup.Location = New-Object System.Drawing.Point(68, 604)
$script:cmbGroup.Size = New-Object System.Drawing.Size(174, 30)
$cardRooms.Controls.Add($script:cmbGroup)
$btnGroupCheck  = New-AppButton $cardRooms '이 그룹 체크' 250 602 116 32
$btnGroupNew    = New-AppButton $cardRooms '새 그룹 만들기' 374 602 130 32
$btnGroupAdd    = New-AppButton $cardRooms '체크한 방 넣기' 512 602 130 32
$btnGroupDelete = New-AppButton $cardRooms '그룹 삭제' 650 602 110 32 'danger'

[void](New-CardLabel $cardRooms '이름이 틀려도 안전합니다. 발송 직전에 채팅창 제목이 정확히 같은지 다시 확인하고, 다르면 보내지 않고 건너뜁니다.' 24 644 736 24 $FontSmall $Theme.Muted)

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

$cardTest = New-Card $pageRun 28 174 784 214 '테스트 모드' '실제 발송 전에 지정한 한 방에만 똑같이 보내 결과를 확인합니다.'
[void](New-CardLabel $cardTest '테스트로 보낼 채팅방 (직접 입력하거나 목록에서 고르세요)' 24 82 460 22 $FontSmall $Theme.Muted)
$script:txtTestRoom = New-AppTextBox $cardTest 24 108 414 38
$script:txtTestRoom.Text = [string]$script:config.TestRoom
$btnPickTestRoom = New-AppButton $cardTest '목록에서 고르기' 454 108 150 38
$btnTestMyChat   = New-AppButton $cardTest '나와의 채팅' 614 108 146 38 'ghost'
$btnTestSend = New-AppButton $cardTest '테스트 발송' 24 156 200 40 'primary'
$btnTestDry  = New-AppButton $cardTest '방 확인만 (전송 안 함)' 236 156 200 40
[void](New-CardLabel $cardTest '기본값은 나와의 채팅이라 아무에게도 가지 않습니다.' 452 162 308 30 $FontSmall $Theme.Muted)

$cardSchedule = New-Card $pageRun 28 400 784 350 '지금 실행 및 예약'
[void](New-CardLabel $cardSchedule '예약 시각' 24 56 100 22 $FontSmall $Theme.Muted)
$script:dtSchedule = New-Object System.Windows.Forms.DateTimePicker
$script:dtSchedule.Format = 'Custom'
$script:dtSchedule.CustomFormat = 'yyyy-MM-dd  HH:mm:ss'
$script:dtSchedule.ShowUpDown = $true
$script:dtSchedule.Location = New-Object System.Drawing.Point(24, 80)
$script:dtSchedule.Size = New-Object System.Drawing.Size(222, 32)
$script:dtSchedule.Font = $FontBase
try { $script:dtSchedule.Value = [datetime]::ParseExact([string]$script:config.ScheduledAt, 'yyyy-MM-dd HH:mm:ss', $null) }
catch { $script:dtSchedule.Value = (Get-Date).Date.AddDays(1) }
if ($script:dtSchedule.Value -lt $script:dtSchedule.MinDate -or $script:dtSchedule.Value -le (Get-Date)) { $script:dtSchedule.Value = (Get-Date).Date.AddDays(1) }
$cardSchedule.Controls.Add($script:dtSchedule)

$btnPickSchedule = New-AppButton $cardSchedule '달력에서 고르기' 254 78 148 32
$btnRunNow    = New-AppButton $cardSchedule '지금 실행' 24 134 164 46 'primary'
$btnArm       = New-AppButton $cardSchedule '예약 시작' 200 134 164 46
$btnCancelArm = New-AppButton $cardSchedule '예약 취소' 376 134 164 46
$btnSave      = New-AppButton $cardSchedule '설정 저장' 552 134 164 46 'ghost'
$btnCancelArm.Enabled = $false

# 간격과 반복은 [설정] 화면 한 곳에서만 정합니다.
# 두 화면에 같은 항목이 있으면 어느 쪽이 진짜인지 헷갈립니다.
# 여기서는 지금 어떻게 설정돼 있는지만 보여 줍니다.
$script:lblRunPace = New-CardLabel $cardSchedule '' 24 194 540 52 $FontBase $Theme.Sub
$btnGoPaceSettings = New-AppButton $cardSchedule '설정에서 바꾸기' 576 196 184 44
$script:lblCountdown = New-CardLabel $cardSchedule '예약이 설정되지 않았습니다.' 24 250 736 26 $FontStrong $Theme.Muted
[void](New-CardLabel $cardSchedule '발송 간격, 반복, 방해금지, 묶음 발송 등 모든 설정은 [설정] 화면 한 곳에 있습니다.' 24 282 736 22 $FontSmall $Theme.Muted)
[void](New-CardLabel $cardSchedule '예약 시각까지 이 프로그램과 PC 카카오톡을 모두 켜 두어야 합니다. 화면 잠금·절전 상태에서는 동작하지 않습니다.' 24 304 736 22 $FontSmall $Theme.Muted)

# ===========================================================================
# 페이지 4 — 설정
# ===========================================================================
$pageSettings = New-Page 'settings'

$cardStatus = New-Card $pageSettings 28 12 784 240 '카카오톡 연결 상태' '좌표를 맞출 필요는 없습니다. 카카오톡 화면 구조를 그때그때 읽어 자동으로 찾습니다.'
$script:lblKakaoState = New-CardLabel $cardStatus '확인 중입니다...' 24 78 736 104 $FontBase $Theme.Sub
$btnCheckKakao = New-AppButton $cardStatus '지금 확인' 24 190 150 40 'strong'
$btnOpenKakao = New-AppButton $cardStatus '카카오톡 창 앞으로 가져오기' 184 190 220 40

$cardUpdate = New-Card $pageSettings 28 264 784 236 '업데이트' '최신 배포를 확인합니다.'
$script:lblUpdateState = New-CardLabel $cardUpdate "현재 버전 v$($script:AppVersion)" 24 76 736 46 $FontBase $Theme.Ink
$btnCheckUpdate  = New-AppButton $cardUpdate '업데이트 확인' 24 130 160 40
$script:btnDoUpdate = New-AppButton $cardUpdate '지금 업데이트' 194 130 160 40 'strong'
$script:btnDoUpdate.Enabled = $false
$btnClearLogFiles = New-AppButton $cardUpdate '로그 파일 모두 지우기' 364 130 200 40 'danger'
$script:chkAutoUpdate = New-Object System.Windows.Forms.CheckBox
$script:chkAutoUpdate.Text = '시작할 때 자동 확인'
$script:chkAutoUpdate.Checked = [bool]$script:config.AutoCheckUpdate
$script:chkAutoUpdate.Location = New-Object System.Drawing.Point(24, 182)
$script:chkAutoUpdate.Size = New-Object System.Drawing.Size(240, 28)
$script:chkAutoUpdate.BackColor = $Theme.Card
$script:chkAutoUpdate.Font = $FontBase
$cardUpdate.Controls.Add($script:chkAutoUpdate)

$script:chkAutoDownload = New-Object System.Windows.Forms.CheckBox
$script:chkAutoDownload.Text = '새 버전이 있으면 물어보고 바로 받기'
$script:chkAutoDownload.Checked = [bool]$script:config.AutoDownloadUpdate
$script:chkAutoDownload.Location = New-Object System.Drawing.Point(280, 182)
$script:chkAutoDownload.Size = New-Object System.Drawing.Size(320, 28)
$script:chkAutoDownload.BackColor = $Theme.Card
$script:chkAutoDownload.Font = $FontBase
$cardUpdate.Controls.Add($script:chkAutoDownload)

$cardFolders = New-Card $pageSettings 28 512 784 176 '도움말 및 관리'
$btnGuide      = New-AppButton $cardFolders '가이드 다시 보기' 24 62 160 40 'strong'
$btnOpenApp    = New-AppButton $cardFolders '프로그램 폴더 열기' 194 62 170 40
$btnOpenLogs   = New-AppButton $cardFolders '로그 폴더 열기' 374 62 150 40
$btnResetConf  = New-AppButton $cardFolders '처음 상태로 되돌리기' 534 62 200 40 'danger'
[void](New-CardLabel $cardFolders "설정 파일 위치: $ConfigPath" 24 114 736 22 $FontSmall $Theme.Muted)
[void](New-CardLabel $cardFolders '카카오 계정, 비밀번호, 인증 정보는 저장하지 않습니다. 설정은 이 PC 안에만 보관됩니다.' 24 136 736 22 $FontSmall $Theme.Muted)

# ===========================================================================

# 발송이 어떤 속도로 진행되는지 정하는 곳입니다.
# 예전에는 간격과 반복이 [보내기] 화면에, 나머지가 [설정] 화면에 흩어져 있어서
# 어디서 바꿔야 하는지 헷갈렸습니다. 이제 모두 여기 모았습니다.
$cardPace = New-Card $pageSettings 28 704 784 316 '발송 진행 방식' '방 사이 간격, 기다리는 시간, 반복을 여기서 정합니다. [보내기] 화면에는 요약만 보입니다.'

[void](New-CardLabel $cardPace '방 사이 간격' 24 82 110 24 $FontSmall $Theme.Muted)
$script:numInterval = New-Object System.Windows.Forms.NumericUpDown
$script:numInterval.Minimum = 0
$script:numInterval.Maximum = 300
$script:numInterval.Value = [Math]::Max(0, [Math]::Min(300, [int]$script:config.IntervalSeconds))
$script:numInterval.Location = New-Object System.Drawing.Point(144, 78)
$script:numInterval.Size = New-Object System.Drawing.Size(80, 30)
$script:numInterval.Font = $FontBase
$script:numInterval.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numInterval)
[void](New-CardLabel $cardPace '초 — 0이면 쉬지 않고 바로 다음 방으로 갑니다' 234 82 520 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '방 열림 대기' 24 124 110 24 $FontSmall $Theme.Muted)
$script:numOpenTimeout = New-Object System.Windows.Forms.NumericUpDown
$script:numOpenTimeout.Minimum = 3
$script:numOpenTimeout.Maximum = 60
$script:numOpenTimeout.Value = [Math]::Max(3, [Math]::Min(60, [int]([Math]::Round([int]$script:config.OpenTimeoutMs / 1000))))
$script:numOpenTimeout.Location = New-Object System.Drawing.Point(144, 120)
$script:numOpenTimeout.Size = New-Object System.Drawing.Size(80, 30)
$script:numOpenTimeout.Font = $FontBase
$script:numOpenTimeout.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numOpenTimeout)
[void](New-CardLabel $cardPace '초까지 방이 열리기를 기다립니다 (대화가 많은 방은 늘리세요)' 234 124 520 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '대화 로딩 대기' 24 166 110 24 $FontSmall $Theme.Muted)
$script:numSettle = New-Object System.Windows.Forms.NumericUpDown
$script:numSettle.Minimum = 0
$script:numSettle.Maximum = 30
$script:numSettle.Value = [Math]::Max(0, [Math]::Min(30, [int]([Math]::Round([int]$script:config.SettleMs / 1000))))
$script:numSettle.Location = New-Object System.Drawing.Point(144, 162)
$script:numSettle.Size = New-Object System.Drawing.Size(80, 30)
$script:numSettle.Font = $FontBase
$script:numSettle.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numSettle)
[void](New-CardLabel $cardPace '초 동안 화면이 멈추기를 기다린 뒤 보냅니다 (오픈채팅은 늘리세요)' 234 166 520 24 $FontSmall $Theme.Muted)

$script:chkPreload = New-Object System.Windows.Forms.CheckBox
$script:chkPreload.Text = '처음 보내기 전에 대상 채팅방을 모두 한 번씩 열어 둡니다'
$script:chkPreload.Checked = [bool]$script:config.PreloadRooms
$script:chkPreload.Location = New-Object System.Drawing.Point(24, 208)
$script:chkPreload.Size = New-Object System.Drawing.Size(500, 28)
$script:chkPreload.BackColor = $Theme.Card
$script:chkPreload.Font = $FontBase
$cardPace.Controls.Add($script:chkPreload)
$btnPreloadNow = New-AppButton $cardPace '지금 미리 열기' 576 204 184 36

$script:chkRepeat = New-Object System.Windows.Forms.CheckBox
$script:chkRepeat.Text = '다 보낸 뒤 일정 시간마다 다시 보내기'
$script:chkRepeat.Checked = [bool]$script:config.RepeatEnabled
$script:chkRepeat.Location = New-Object System.Drawing.Point(24, 250)
$script:chkRepeat.Size = New-Object System.Drawing.Size(330, 28)
$script:chkRepeat.BackColor = $Theme.Card
$script:chkRepeat.Font = $FontBase
$cardPace.Controls.Add($script:chkRepeat)

$script:numRepeatMinutes = New-Object System.Windows.Forms.NumericUpDown
$script:numRepeatMinutes.Minimum = 1
$script:numRepeatMinutes.Maximum = 1440
$script:numRepeatMinutes.Value = [Math]::Max(1, [Math]::Min(1440, [int]$script:config.RepeatMinutes))
$script:numRepeatMinutes.Location = New-Object System.Drawing.Point(364, 248)
$script:numRepeatMinutes.Size = New-Object System.Drawing.Size(80, 30)
$script:numRepeatMinutes.Font = $FontBase
$script:numRepeatMinutes.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numRepeatMinutes)
[void](New-CardLabel $cardPace '분마다 ·  최대' 452 252 96 24 $FontSmall $Theme.Muted)

$script:numRepeatCount = New-Object System.Windows.Forms.NumericUpDown
$script:numRepeatCount.Minimum = 0
$script:numRepeatCount.Maximum = 999
$script:numRepeatCount.Value = [Math]::Max(0, [Math]::Min(999, [int]$script:config.RepeatCount))
$script:numRepeatCount.Location = New-Object System.Drawing.Point(552, 248)
$script:numRepeatCount.Size = New-Object System.Drawing.Size(74, 30)
$script:numRepeatCount.Font = $FontBase
$script:numRepeatCount.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numRepeatCount)
[void](New-CardLabel $cardPace '회 (0이면 멈출 때까지 계속)' 634 252 130 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '방 300개를 10분 안에 보내려면 간격을 0~1초로 두세요. 간격 8초면 300개에 약 48분 걸립니다.' 24 286 736 24 $FontSmall $Theme.Muted)

$cardLimit = New-Card $pageSettings 28 1036 784 306 '발송 제한 및 묶음 발송' '보내면 안 되는 시간과 날짜, 그리고 몇 개마다 쉴지 정할 수 있습니다.'
$script:chkQuiet = New-Object System.Windows.Forms.CheckBox
$script:chkQuiet.Text = '방해금지 시간대에는 보내지 않기'
$script:chkQuiet.Checked = [bool]$script:config.QuietEnabled
$script:chkQuiet.Location = New-Object System.Drawing.Point(24, 78)
$script:chkQuiet.Size = New-Object System.Drawing.Size(280, 26)
$script:chkQuiet.BackColor = $Theme.Card
$script:chkQuiet.Font = $FontBase
$cardLimit.Controls.Add($script:chkQuiet)

$script:txtQuietStart = New-AppTextBox $cardLimit 316 74 90 34
$script:txtQuietStart.Text = [string]$script:config.QuietStart
[void](New-CardLabel $cardLimit '부터' 412 80 38 22 $FontSmall $Theme.Muted)
$script:txtQuietEnd = New-AppTextBox $cardLimit 452 74 90 34
$script:txtQuietEnd.Text = [string]$script:config.QuietEnd
[void](New-CardLabel $cardLimit '까지 (예: 21:00 ~ 08:00)' 548 80 212 22 $FontSmall $Theme.Muted)

$script:chkSkipWeekend = New-Object System.Windows.Forms.CheckBox
$script:chkSkipWeekend.Text = '주말(토·일)에는 보내지 않기'
$script:chkSkipWeekend.Checked = [bool]$script:config.SkipWeekend
$script:chkSkipWeekend.Location = New-Object System.Drawing.Point(24, 116)
$script:chkSkipWeekend.Size = New-Object System.Drawing.Size(280, 26)
$script:chkSkipWeekend.BackColor = $Theme.Card
$script:chkSkipWeekend.Font = $FontBase
$cardLimit.Controls.Add($script:chkSkipWeekend)

[void](New-CardLabel $cardLimit '공휴일에는' 24 158 90 24 $FontSmall $Theme.Muted)
$script:cmbHoliday = New-Object System.Windows.Forms.ComboBox
$script:cmbHoliday.DropDownStyle = 'DropDownList'
$script:cmbHoliday.Font = $FontBase
$script:cmbHoliday.Location = New-Object System.Drawing.Point(116, 154)
$script:cmbHoliday.Size = New-Object System.Drawing.Size(190, 30)
[void]$script:cmbHoliday.Items.AddRange(@('평소대로', '보내지 않음', '간격 늘리기'))
$holidayMode = [string]$script:config.HolidayMode
if ($script:cmbHoliday.Items.IndexOf($holidayMode) -ge 0) { $script:cmbHoliday.SelectedItem = $holidayMode }
else { $script:cmbHoliday.SelectedIndex = 0 }
$cardLimit.Controls.Add($script:cmbHoliday)

[void](New-CardLabel $cardLimit '간격 늘릴 때 배수' 316 158 130 24 $FontSmall $Theme.Muted)
$script:numHolidayMultiplier = New-Object System.Windows.Forms.NumericUpDown
$script:numHolidayMultiplier.Minimum = 1
$script:numHolidayMultiplier.Maximum = 20
$script:numHolidayMultiplier.Value = [Math]::Max(1, [Math]::Min(20, [int]$script:config.HolidayIntervalMultiplier))
$script:numHolidayMultiplier.Location = New-Object System.Drawing.Point(452, 154)
$script:numHolidayMultiplier.Size = New-Object System.Drawing.Size(78, 30)
$script:numHolidayMultiplier.Font = $FontBase
$script:numHolidayMultiplier.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numHolidayMultiplier)
$btnShowHolidays = New-AppButton $cardLimit '올해 공휴일 보기' 548 152 150 34

[void](New-CardLabel $cardLimit '묶음 발송' 24 200 80 24 $FontSmall $Theme.Muted)
$script:numBatchSize = New-Object System.Windows.Forms.NumericUpDown
$script:numBatchSize.Minimum = 0
$script:numBatchSize.Maximum = 500
$script:numBatchSize.Value = [Math]::Max(0, [Math]::Min(500, [int]$script:config.BatchSize))
$script:numBatchSize.Location = New-Object System.Drawing.Point(108, 196)
$script:numBatchSize.Size = New-Object System.Drawing.Size(84, 30)
$script:numBatchSize.Font = $FontBase
$script:numBatchSize.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numBatchSize)
[void](New-CardLabel $cardLimit '개 보낸 뒤' 198 200 84 24 $FontSmall $Theme.Muted)
$script:numBatchRest = New-Object System.Windows.Forms.NumericUpDown
$script:numBatchRest.Minimum = 1
$script:numBatchRest.Maximum = 240
$script:numBatchRest.Value = [Math]::Max(1, [Math]::Min(240, [int]$script:config.BatchRestMinutes))
$script:numBatchRest.Location = New-Object System.Drawing.Point(286, 196)
$script:numBatchRest.Size = New-Object System.Drawing.Size(84, 30)
$script:numBatchRest.Font = $FontBase
$script:numBatchRest.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numBatchRest)
[void](New-CardLabel $cardLimit '분 쉬기  (0개면 쉬지 않고 계속)' 376 200 384 24 $FontSmall $Theme.Muted)

$script:lblLimitState = New-CardLabel $cardLimit '' 24 236 736 56 $FontSmall $Theme.Sub

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
            # [채팅] 목록에는 오픈채팅방도 함께 들어 있습니다.
            # 그래서 이미 오픈채팅으로 확인된 방을 일반채팅으로 덮어쓰지 않습니다.
            if ($Type -and $Type -ne $script:RoomTypeUnknown) {
                if (-not ($entry.Type -eq $script:RoomTypeOpen -and $Type -eq $script:RoomTypeNormal)) {
                    $entry.Type = $Type
                }
            }
            return $false
        }
    }
    $script:roomEntries.Add([pscustomobject]@{ Name = $clean; Type = $Type; Checked = $Checked })
    return $true
}

function Update-RoomCountLabel {
    $checked = @($script:roomEntries | Where-Object { $_.Checked }).Count
    $total = $script:roomEntries.Count
    $shown = $script:lstRooms.Items.Count
    $text = "선택 $($checked) / 전체 $($total)"
    if ($shown -ne $total) { $text += "   ·   보이는 것 $($shown)" }
    $script:lblRoomCount.Text = $text
}

# 검색어를 견주기 좋게 다듬습니다. 띄어쓰기와 기호는 무시합니다.
function Test-RoomMatchesSearch([string]$Name, [string]$Key) {
    if (-not $Key) { return $true }
    return ((ConvertTo-CompareKey $Name).Contains($Key))
}

function Update-FilterButtons {
    foreach ($pair in @(@($btnFilterAll, '전체'), @($btnFilterPerson, $script:RoomTypePersonal), @($btnFilterChat, $script:RoomTypeGroup), @($btnFilterOpen, $script:RoomTypeOpen))) {
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
    $query = ''
    if ($null -ne $script:txtRoomSearch) { $query = $script:txtRoomSearch.Text.Trim() }
    $key = ConvertTo-CompareKey $query

    $script:suppressRoomEvents = $true
    $script:lstRooms.BeginUpdate()
    $script:lstRooms.Items.Clear()
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($entry in ($script:roomEntries | Sort-Object -Property Name)) {
        if ($script:roomFilter -ne '전체' -and $entry.Type -ne $script:roomFilter) { continue }
        if (-not (Test-RoomMatchesSearch $entry.Name $key)) { continue }
        $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Name)
        [void]$item.SubItems.Add([string]$entry.Type)
        $item.Checked = [bool]$entry.Checked
        if ($entry.Type -eq $script:RoomTypeUnknown) { $item.ForeColor = $Theme.Muted }
        $items.Add($item)
    }
    if ($items.Count -gt 0) { $script:lstRooms.Items.AddRange($items.ToArray()) }
    $script:lstRooms.EndUpdate()
    $script:suppressRoomEvents = $false
    Update-FilterButtons
    Update-RoomCountLabel
    if ($null -ne $script:lblSearchState) {
        if ($key) {
            $script:lblSearchState.Text = "'$query' 검색 결과 $($items.Count)개 — [보이는 항목 모두 체크]로 한 번에 고를 수 있습니다"
            $script:lblSearchState.ForeColor = if ($items.Count -gt 0) { $Theme.Info } else { $Theme.Danger }
        } else {
            $script:lblSearchState.Text = ''
        }
    }
}

function Get-RoomEntry([string]$Name) {
    foreach ($entry in $script:roomEntries) { if ($entry.Name -eq $Name) { return $entry } }
    return $null
}

function Update-GroupCombo {
    $script:suppressRoomEvents = $true
    $current = [string]$script:cmbGroup.SelectedItem
    $script:cmbGroup.Items.Clear()
    [void]$script:cmbGroup.Items.Add('(그룹 없음)')
    foreach ($name in (Get-GroupNames)) { [void]$script:cmbGroup.Items.Add($name) }
    $index = $script:cmbGroup.Items.IndexOf($current)
    $script:cmbGroup.SelectedIndex = if ($index -ge 0) { $index } else { 0 }
    $script:suppressRoomEvents = $false
}

function Get-SelectedGroupName {
    $name = [string]$script:cmbGroup.SelectedItem
    if (-not $name -or $name -eq '(그룹 없음)') { return '' }
    return $name
}

# 저장된 목록에서 방 하나를 골라 이름을 돌려줍니다.
function Show-RoomPicker([string]$Title) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Title
    $dialog.ClientSize = New-Object System.Drawing.Size(520, 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Theme.Card
    $dialog.Font = $FontBase

    $lblFind = New-Object System.Windows.Forms.Label
    $lblFind.Text = '찾기'
    $lblFind.Location = New-Object System.Drawing.Point(20, 22)
    $lblFind.Size = New-Object System.Drawing.Size(40, 24)
    $lblFind.BackColor = $Theme.Card
    $dialog.Controls.Add($lblFind)

    $txtFind = New-AppTextBox $dialog 62 16 438 34

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.Font = $FontBase
    $list.Location = New-Object System.Drawing.Point(20, 62)
    $list.Size = New-Object System.Drawing.Size(480, 388)
    [void]$list.Columns.Add('채팅방 이름', 330)
    [void]$list.Columns.Add('종류', 120)
    $dialog.Controls.Add($list)

    $fill = {
        param($query)
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($entry in ($script:roomEntries | Sort-Object -Property Name)) {
            if ($query -and ([string]$entry.Name).IndexOf($query, [System.StringComparison]::CurrentCultureIgnoreCase) -lt 0) { continue }
            $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Name)
            [void]$item.SubItems.Add([string]$entry.Type)
            [void]$list.Items.Add($item)
        }
        $list.EndUpdate()
    }
    & $fill ''
    $txtFind.Add_TextChanged({ & $fill $txtFind.Text.Trim() })

    $script:pickedRoom = ''
    $btnOk = New-AppButton $dialog '이 방으로 정하기' 262 466 148 38 'strong'
    $btnCancelPick = New-AppButton $dialog '취소' 420 466 80 38
    $btnOk.Add_Click({
        if ($list.SelectedItems.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('목록에서 방을 한 개 골라 주세요.', '선택 필요') | Out-Null
            return
        }
        $script:pickedRoom = [string]$list.SelectedItems[0].Text
        $dialog.DialogResult = 'OK'
        $dialog.Close()
    })
    $btnCancelPick.Add_Click({ $script:pickedRoom = ''; $dialog.DialogResult = 'Cancel'; $dialog.Close() })
    $list.Add_DoubleClick({
        if ($list.SelectedItems.Count -gt 0) {
            $script:pickedRoom = [string]$list.SelectedItems[0].Text
            $dialog.DialogResult = 'OK'
            $dialog.Close()
        }
    })

    [void]$dialog.ShowDialog($script:form)
    $dialog.Dispose()
    return $script:pickedRoom
}

# 방 하나를 처리하는 데 걸리는 시간(실측 기준: 열기·전송·닫기 약 1.6초)
$script:SecondsPerRoom = 1.6

function Get-EstimatedRunText {
    $count = @($script:roomEntries | Where-Object { $_.Checked }).Count
    if ($count -eq 0) { return '보낼 방을 체크하면 예상 소요 시간을 알려 드립니다.' }
    $interval = Get-EffectiveInterval (Get-Date)
    $seconds = $count * $script:SecondsPerRoom + [Math]::Max(0, $count - 1) * $interval
    $batchSize = [int]$script:config.BatchSize
    $batchRest = [int]$script:config.BatchRestMinutes
    $restText = ''
    if ($batchSize -gt 0 -and $batchRest -gt 0 -and $count -gt $batchSize) {
        $rests = [Math]::Floor(($count - 1) / $batchSize)
        $seconds += $rests * $batchRest * 60
        $restText = " (쉬는 시간 $($rests)회 포함)"
    }
    $span = [TimeSpan]::FromSeconds([Math]::Round($seconds))
    $text = if ($span.TotalHours -ge 1) { "{0}시간 {1}분" -f [int]$span.TotalHours, $span.Minutes }
            elseif ($span.TotalMinutes -ge 1) { "{0}분 {1}초" -f [int]$span.TotalMinutes, $span.Seconds }
            else { "{0}초" -f [int]$span.TotalSeconds }
    return "체크한 $($count)개 · 간격 $($interval)초 → 예상 소요 약 $text$restText"
}

# 위쪽 요약: 언제 보내고, 몇 분마다 반복하는지
function Update-HeaderSummary {
    if ($null -eq $script:lblHeaderPlan) { return }
    $when = if ($script:armed) {
        "예약  $($script:dtSchedule.Value.ToString('MM-dd HH:mm')) 대기 중"
    } else {
        "예약  $($script:dtSchedule.Value.ToString('MM-dd HH:mm')) (시작 안 함)"
    }
    $repeat = if ([bool]$script:chkRepeat.Checked) {
        $limit = [int]$script:numRepeatCount.Value
        $limitText = if ($limit -gt 0) { "최대 $($limit)회" } else { '계속' }
        "반복  $([int]$script:numRepeatMinutes.Value)분마다 · $limitText"
    } else {
        "반복  안 함 · 방 간격 $([int]$script:numInterval.Value)초"
    }
    $script:lblHeaderPlan.Text = "$when`r`n$repeat"
    $script:lblHeaderPlan.ForeColor = if ($script:armed) { $Theme.Info } else { $Theme.Muted }

    # [보내기] 화면의 요약도 같이 맞춥니다.
    # 설정은 [설정] 화면 한 곳에서만 바꾸고, 여기는 그 결과를 보여 주기만 합니다.
    if ($null -ne $script:lblRunPace) {
        $gap = [int]$script:numInterval.Value
        $gapText = if ($gap -le 0) { '방 사이 간격  쉬지 않음' } else { "방 사이 간격  $($gap)초" }
        $waitText = "방 열림 대기  $([int]$script:numOpenTimeout.Value)초 · 대화 로딩 대기  $([int]$script:numSettle.Value)초"
        $repeatLine = if ([bool]$script:chkRepeat.Checked) {
            $limit = [int]$script:numRepeatCount.Value
            $limitText = if ($limit -gt 0) { "최대 $($limit)회" } else { '멈출 때까지' }
            "반복  $([int]$script:numRepeatMinutes.Value)분마다 · $limitText"
        } else { '반복  안 함' }
        $script:lblRunPace.Text = "$gapText`r`n$waitText`r`n$repeatLine"
    }
}

function Update-LimitStateLabel {
    $now = Get-Date
    $lines = New-Object System.Collections.Generic.List[string]
    $holiday = Get-HolidayName $now
    $lines.Add("오늘 $($now.ToString('yyyy-MM-dd')) ($(('일','월','화','수','목','금','토')[[int]$now.DayOfWeek])요일)" + $(if ($holiday) { " · $holiday" } else { '' }))
    $blocked = Get-SendBlockReason $now
    if ($blocked) {
        $next = Get-NextAllowedTime $now
        $lines.Add("지금은 보낼 수 없습니다 — $blocked")
        if ($null -ne $next) { $lines.Add("다음 발송 가능 시각: $($next.ToString('yyyy-MM-dd HH:mm'))") }
        $script:lblLimitState.ForeColor = $Theme.Danger
    } else {
        $lines.Add("지금은 보낼 수 있습니다.")
        $script:lblLimitState.ForeColor = $Theme.Success
    }
    try { $lines.Add((Get-EstimatedRunText)) } catch { }
    $script:lblLimitState.Text = ($lines -join [Environment]::NewLine)
}

function Sync-ConfigFromForm {
    $script:config.Rooms = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
    $script:config.KnownRooms = @($script:roomEntries | ForEach-Object { [string]$_.Name })
    foreach ($entry in $script:roomEntries) { Set-RoomType $entry.Name $entry.Type }
    $script:config.Message = $script:txtMessage.Text
    $script:config.Attachments = @(Get-AttachmentPaths)
    $script:config.ScheduledAt = $script:dtSchedule.Value.ToString('yyyy-MM-dd HH:mm:ss')
    $script:config.IntervalSeconds = [int]$script:numInterval.Value
    $script:config.DryRun = [bool]$script:rdoDry.Checked
    $script:config.ScanPages = [int]$script:numScanPages.Value
    $script:config.TestRoom = $script:txtTestRoom.Text.Trim()
    $script:config.AutoCheckUpdate = [bool]$script:chkAutoUpdate.Checked
    $script:config.AutoDownloadUpdate = [bool]$script:chkAutoDownload.Checked
    $script:config.QuietEnabled = [bool]$script:chkQuiet.Checked
    $script:config.QuietStart = $script:txtQuietStart.Text.Trim()
    $script:config.QuietEnd = $script:txtQuietEnd.Text.Trim()
    $script:config.SkipWeekend = [bool]$script:chkSkipWeekend.Checked
    $script:config.HolidayMode = [string]$script:cmbHoliday.SelectedItem
    $script:config.HolidayIntervalMultiplier = [int]$script:numHolidayMultiplier.Value
    $script:config.BatchSize = [int]$script:numBatchSize.Value
    $script:config.BatchRestMinutes = [int]$script:numBatchRest.Value
    $script:config.OpenTimeoutMs = [int]$script:numOpenTimeout.Value * 1000
    $script:config.SettleMs = [int]$script:numSettle.Value * 1000
    $script:config.PreloadRooms = [bool]$script:chkPreload.Checked
    $script:config.RepeatEnabled = [bool]$script:chkRepeat.Checked
    $script:config.RepeatMinutes = [int]$script:numRepeatMinutes.Value
    $script:config.RepeatCount = [int]$script:numRepeatCount.Value
    Update-LimitStateLabel
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
Update-GroupCombo
Update-LimitStateLabel
Update-HeaderSummary
$script:lblMessageCount.Text = "$($script:txtMessage.Text.Length)자"

# ===========================================================================
# 동작 연결
# ===========================================================================
$script:txtMessage.Add_TextChanged({ $script:lblMessageCount.Text = "$($script:txtMessage.Text.Length)자"; Request-AutoSave })
$script:txtTestRoom.Add_TextChanged({ Request-AutoSave })
$script:dtSchedule.Add_ValueChanged({ Request-AutoSave })
$script:numInterval.Add_ValueChanged({ $script:config.IntervalSeconds = [int]$script:numInterval.Value; try { Update-LimitStateLabel } catch { }; Request-AutoSave })
$script:numScanPages.Add_ValueChanged({ Request-AutoSave })
$script:rdoDry.Add_CheckedChanged({ Request-AutoSave })
$script:chkAutoUpdate.Add_CheckedChanged({ Request-AutoSave })
$script:chkAutoDownload.Add_CheckedChanged({ Request-AutoSave })
$script:chkQuiet.Add_CheckedChanged({ Request-AutoSave })
$script:txtQuietStart.Add_TextChanged({ Request-AutoSave })
$script:txtQuietEnd.Add_TextChanged({ Request-AutoSave })
$script:chkSkipWeekend.Add_CheckedChanged({ Request-AutoSave })
$script:cmbHoliday.Add_SelectedIndexChanged({ Request-AutoSave })
$script:numHolidayMultiplier.Add_ValueChanged({ Request-AutoSave })
$script:numBatchSize.Add_ValueChanged({ Request-AutoSave })
$script:numBatchRest.Add_ValueChanged({ Request-AutoSave })
$script:numOpenTimeout.Add_ValueChanged({ Request-AutoSave })
$script:numSettle.Add_ValueChanged({ Request-AutoSave })
$script:chkPreload.Add_CheckedChanged({ Request-AutoSave })
$script:chkRepeat.Add_CheckedChanged({ Request-AutoSave })
$script:numRepeatMinutes.Add_ValueChanged({ Request-AutoSave })
$script:numRepeatCount.Add_ValueChanged({ Request-AutoSave })
$btnPickSchedule.Add_Click({
    $picked = Show-SchedulePicker $script:dtSchedule.Value
    if ($null -ne $picked) { $script:dtSchedule.Value = $picked; Sync-ConfigFromForm }
})

$btnShowHolidays.Add_Click({
    $year = (Get-Date).Year
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($entry in (Get-KoreanHolidays $year).GetEnumerator() | Sort-Object -Property Name) {
        $date = [datetime]::ParseExact($entry.Key, 'yyyy-MM-dd', $null)
        $lines.Add("$($entry.Key) ($(('일','월','화','수','목','금','토')[[int]$date.DayOfWeek]))  $($entry.Value)")
    }
    [System.Windows.Forms.MessageBox]::Show(
        "$($year)년 공휴일 ($($lines.Count)일)`r`n`r`n$($lines -join [Environment]::NewLine)`r`n`r`n음력 명절은 Windows 음력 달력으로 계산합니다. 임시공휴일은 포함되지 않습니다.",
        "$($year)년 공휴일") | Out-Null
})

$btnTestMyChat.Add_Click({ $script:txtTestRoom.Text = '나와의 채팅'; Sync-ConfigFromForm })
$btnPickTestRoom.Add_Click({
    if ($script:roomEntries.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("아직 채팅방 목록이 비어 있습니다.`r`n[2. 받을 채팅방] 화면에서 먼저 목록을 읽어 주세요.", '목록 없음') | Out-Null
        return
    }
    $picked = Show-RoomPicker '테스트로 보낼 채팅방 고르기'
    if ($picked) { $script:txtTestRoom.Text = $picked; Sync-ConfigFromForm }
})
$script:lstRooms.Add_ItemChecked({
    param($sender, $e)
    if ($script:suppressRoomEvents) { return }
    $entry = Get-RoomEntry ([string]$e.Item.Text)
    if ($null -ne $entry) { $entry.Checked = $e.Item.Checked }
    Update-RoomCountLabel
    Request-AutoSave
})

$btnHelp.Add_Click({ Show-GuideTour })
$script:btnHeaderStop.Add_Click({
    if ($script:running) {
        if ($script:pauseRequested) {
            $script:pauseRequested = $false
            Write-RunLog '발송을 다시 진행합니다.'
            Set-StatusPill '실행 중' 'run'
            Update-RunButtons
            return
        }
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "발송을 어떻게 할까요?`r`n`r`n[예] 잠깐 멈추기 (나중에 이어서 진행)`r`n[아니오] 완전히 중지 (남은 방은 보내지 않음)`r`n[취소] 계속 진행",
            '발송 중지', 'YesNoCancel', 'Warning')
        if ($answer -eq 'Yes') {
            $script:pauseRequested = $true
            Write-RunLog '발송을 잠깐 멈췄습니다.'
            Update-RunButtons
        } elseif ($answer -eq 'No') {
            $script:pauseRequested = $false
            $script:cancelRequested = $true
            Write-RunLog '발송을 완전히 중지했습니다.'
            Set-StatusPill '중지됨' 'error'
        }
        return
    }
    if ($script:armed) {
        if ([System.Windows.Forms.MessageBox]::Show('예약을 취소할까요?', '예약 취소', 'YesNo', 'Question') -ne 'Yes') { return }
        $script:armed = $false
        $script:repeatDone = 0
        $btnArm.Enabled = $true
        $btnCancelArm.Enabled = $false
        $script:lblCountdown.Text = '예약이 취소되었습니다.'
        Set-StatusPill '예약 취소됨' 'idle'
        Write-RunLog '예약을 취소했습니다.'
        Update-RunButtons
    }
})
$btnHeaderEdit.Add_Click({ Show-AppPage 'compose' })

# 설정은 [설정] 화면 한 곳에서만 바꿉니다. 여기서는 그리로 보내 줍니다.
$btnGoPaceSettings.Add_Click({ Show-AppPage 'settings' })

$btnPreloadNow.Add_Click({
    try {
        Sync-ConfigFromForm
        $rooms = @($script:config.Rooms | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_ } | Select-Object -Unique)
        if ($rooms.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('먼저 [2. 받을 채팅방]에서 보낼 방을 골라 주세요.', '방 미리 열기') | Out-Null
            return
        }
        $ask = "방 $($rooms.Count)개를 한 번씩 열어 대화가 다 불러와지는지 봅니다." + "`r`n`r`n" +
               '메시지는 보내지 않습니다.' + "`r`n" +
               '방이 많으면 시간이 걸립니다. 계속할까요?'
        if ([System.Windows.Forms.MessageBox]::Show($ask, '방 미리 열기 (보내지 않음)', 'YesNo', 'Question') -ne 'Yes') { return }
        $script:form.Enabled = $false
        Set-StatusPill '방 미리 여는 중' 'run'
        $ok = $false
        try { $ok = Invoke-RoomPreload $rooms } catch { Write-RunLog "방 미리 열기 실패: $($_.Exception.Message)" }
        $script:config.PreloadDone = $true
        try { Save-Config $script:config } catch { }
        $script:form.Enabled = $true
        $script:form.Activate()
        if ($ok) { Set-StatusPill '방 미리 열기 끝' 'done' } else { Set-StatusPill '방 미리 열기 실패' 'error' }
        [System.Windows.Forms.MessageBox]::Show('끝났습니다. 어떤 방이 잘 열렸는지는 [기록] 화면에서 볼 수 있습니다.', '방 미리 열기') | Out-Null
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '방 미리 열기 실패' 'error'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '방 미리 열기 실패') | Out-Null
    }
})
$btnHeaderStart.Add_Click({
    try {
        Sync-ConfigFromForm
        Show-AppPage 'run'
        if (Confirm-LiveRun '지금 발송 시작') { Start-BroadcastAsync }
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '실행 실패') | Out-Null }
})

$btnCheckAttach.Add_Click({
    try {
        Sync-ConfigFromForm
        $files = @(Get-AttachmentPaths)
        if ($files.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('먼저 [파일 추가]로 첨부할 파일을 넣어 주세요.', '첨부 시험') | Out-Null
            return
        }
        $path = $files[0]
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            [System.Windows.Forms.MessageBox]::Show("파일을 찾을 수 없습니다." + "`r`n" + $path, '첨부 시험') | Out-Null
            return
        }
        $room = [string]$script:config.TestRoom
        if ([string]::IsNullOrWhiteSpace($room)) { $room = '나와의 채팅' }
        $ask = "'$room' 방을 열어 첨부가 붙는지만 확인합니다." + "`r`n`r`n" +
               '붙여 본 뒤 바로 치웁니다. 메시지는 보내지 않습니다.' + "`r`n`r`n" +
               "파일: $([System.IO.Path]::GetFileName($path))" + "`r`n`r`n" + '진행할까요?'
        if ([System.Windows.Forms.MessageBox]::Show($ask, '첨부 시험 (보내지 않음)', 'YesNo', 'Question') -ne 'Yes') { return }
        $script:form.Enabled = $false
        Set-StatusPill '첨부 시험 중' 'run'
        $outcome = $null
        try { $outcome = Invoke-AttachmentCheck $room $path } catch { $outcome = [pscustomobject]@{ Ok = $false; Text = $_.Exception.Message } }
        $script:form.Enabled = $true
        $script:form.Activate()
        Write-RunLog "첨부 시험 ($room): $($outcome.Text)"
        if ($outcome.Ok) {
            Set-StatusPill '첨부 시험 성공' 'done'
            [System.Windows.Forms.MessageBox]::Show($outcome.Text + "`r`n`r`n" + '이 환경에서는 첨부가 됩니다.', '첨부 시험 성공') | Out-Null
        } else {
            Set-StatusPill '첨부 시험 실패' 'error'
            [System.Windows.Forms.MessageBox]::Show($outcome.Text + "`r`n`r`n" + '실행 기록에 그대로 남겨 두었습니다.', '첨부 시험 실패') | Out-Null
        }
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '첨부 시험 실패' 'error'
        Write-RunLog "첨부 시험 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '첨부 시험 실패') | Out-Null
    }
})

$btnAddFile.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Title = '사진 또는 파일 선택'
    if ($dialog.ShowDialog() -eq 'OK') {
        $already = @(Get-AttachmentPaths)
    foreach ($file in $dialog.FileNames) {
        if ($already -contains [string]$file) { continue }
        [void]$script:lstFiles.Items.Add((New-AttachmentItem ([string]$file)))
    }
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

# 글자를 칠 때마다 목록을 다시 그리면 방이 많을 때 느려집니다.
# 잠깐 멈춘 뒤 한 번만 그리도록 합니다.
$script:searchTimer = New-Object System.Windows.Forms.Timer
$script:searchTimer.Interval = 220
$script:searchTimer.Add_Tick({
    $script:searchTimer.Stop()
    try { Update-RoomListView } catch { }
})
$script:txtRoomSearch.Add_TextChanged({ $script:searchTimer.Stop(); $script:searchTimer.Start() })
$script:txtRoomSearch.Add_KeyDown({
    if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
        $script:txtRoomSearch.Clear()
        $_.SuppressKeyPress = $true
    }
})
$btnSearchClear.Add_Click({ $script:txtRoomSearch.Clear(); $script:txtRoomSearch.Focus() })
$btnGroupNew.Add_Click({
    $name = ([string][Microsoft.VisualBasic.Interaction]::InputBox('새 그룹 이름을 입력하세요. (예: 학부모, 홍보방)', '새 그룹 만들기', '')).Trim()
    if (-not $name) { return }
    if ($name -eq '(그룹 없음)') { [System.Windows.Forms.MessageBox]::Show('그 이름은 사용할 수 없습니다.', '새 그룹') | Out-Null; return }
    if ((Get-GroupNames) -contains $name) { [System.Windows.Forms.MessageBox]::Show('같은 이름의 그룹이 이미 있습니다.', '새 그룹') | Out-Null; return }
    $checked = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
    Set-GroupRooms $name $checked
    Save-Config $script:config
    Update-GroupCombo
    $script:cmbGroup.SelectedItem = $name
    Write-RunLog "그룹 '$name' 을(를) 만들었습니다. (방 $($checked.Count)개)"
    [System.Windows.Forms.MessageBox]::Show("그룹 '$name' 을(를) 만들었습니다.`r`n현재 체크된 방 $($checked.Count)개가 들어갔습니다.", '새 그룹') | Out-Null
})
$btnGroupAdd.Add_Click({
    $group = Get-SelectedGroupName
    if (-not $group) { [System.Windows.Forms.MessageBox]::Show('먼저 그룹을 고르거나 새로 만들어 주세요.', '그룹에 넣기') | Out-Null; return }
    $checked = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
    if ($checked.Count -eq 0) { [System.Windows.Forms.MessageBox]::Show('그룹에 넣을 방을 먼저 체크해 주세요.', '그룹에 넣기') | Out-Null; return }
    Set-GroupRooms $group @(@(Get-GroupRooms $group) + $checked)
    Save-Config $script:config
    Write-RunLog "그룹 '$group' 에 방 $($checked.Count)개를 넣었습니다."
    [System.Windows.Forms.MessageBox]::Show("그룹 '$group' 에 $($checked.Count)개를 넣었습니다.`r`n지금 그룹 전체는 $((Get-GroupRooms $group).Count)개입니다.", '그룹에 넣기') | Out-Null
})
$btnGroupCheck.Add_Click({
    $group = Get-SelectedGroupName
    if (-not $group) { [System.Windows.Forms.MessageBox]::Show('먼저 그룹을 골라 주세요.', '그룹 체크') | Out-Null; return }
    $rooms = @(Get-GroupRooms $group)
    foreach ($entry in $script:roomEntries) { $entry.Checked = ($rooms -contains $entry.Name) }
    Update-RoomListView
    Sync-ConfigFromForm
    $missing = @($rooms | Where-Object { $null -eq (Get-RoomEntry $_) })
    $message = "그룹 '$group' 의 방 $($rooms.Count)개를 체크했습니다."
    if ($missing.Count -gt 0) { $message += "`r`n`r`n목록에 없는 방 $($missing.Count)개는 건너뛰었습니다." }
    [System.Windows.Forms.MessageBox]::Show($message, '그룹 체크') | Out-Null
})
$btnGroupDelete.Add_Click({
    $group = Get-SelectedGroupName
    if (-not $group) { [System.Windows.Forms.MessageBox]::Show('삭제할 그룹을 먼저 골라 주세요.', '그룹 삭제') | Out-Null; return }
    if ([System.Windows.Forms.MessageBox]::Show("그룹 '$group' 을(를) 지웁니다.`r`n채팅방 목록 자체는 그대로 남습니다. 계속할까요?", '그룹 삭제', 'YesNo', 'Warning') -ne 'Yes') { return }
    Remove-Group $group
    Save-Config $script:config
    Update-GroupCombo
    Write-RunLog "그룹 '$group' 을(를) 지웠습니다."
})

$btnFilterAll.Add_Click({ $script:roomFilter = '전체'; Update-RoomListView })
$btnFilterPerson.Add_Click({ $script:roomFilter = $script:RoomTypePersonal; Update-RoomListView })
$btnFilterChat.Add_Click({ $script:roomFilter = $script:RoomTypeGroup; Update-RoomListView })
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
        Rename-RoomInGroups $current $name
        $entry.Name = $name
        Update-RoomListView
        Sync-ConfigFromForm
    }
})
$btnDeleteRoom.Add_Click({
    # 체크한 항목을 먼저 쓰고, 체크가 없으면 클릭으로 선택한 줄을 씁니다.
    $names = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
    if ($names.Count -eq 0) { $names = @($script:lstRooms.SelectedItems | ForEach-Object { [string]$_.Text }) }
    if ($names.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("지울 항목을 체크하거나 줄을 클릭해 선택해 주세요.", '삭제할 항목이 없습니다') | Out-Null
        return
    }
    $body = "목록에서 $($names.Count)개 항목을 지웁니다.`r`n`r`n카카오톡의 실제 채팅방은 지워지지 않습니다. 이 프로그램의 목록에서만 빠집니다.`r`n계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($body, '목록에서 삭제', 'YesNo', 'Warning') -ne 'Yes') { return }
    foreach ($name in $names) {
        $entry = Get-RoomEntry $name
        if ($null -ne $entry) { [void]$script:roomEntries.Remove($entry) }
        Remove-RoomFromGroups $name
    }
    Update-RoomListView
    Sync-ConfigFromForm
    Write-RunLog "목록에서 $($names.Count)개 항목을 지웠습니다."
})

$btnScanRooms.Add_Click({
    try {
        Sync-ConfigFromForm
        $ready = Test-KakaoReady $true $false
        if (-not $ready.Ok) {
            [System.Windows.Forms.MessageBox]::Show("$($ready.Reason)`r`n`r`n카카오톡에서 [채팅] 또는 [오픈채팅] 탭을 눌러 목록이 보이게 한 뒤 다시 눌러 주세요.", '먼저 확인해 주세요') | Out-Null
            return
        }

        # 카카오톡 위쪽에서 지금 선택된 탭이 [채팅] 인지 [오픈채팅] 인지 직접 확인합니다.
        Set-StatusPill '어떤 탭인지 확인 중' 'run'
        $detected = Get-ActiveKakaoTab $ready.Layout
        Set-StatusPill '준비됨' 'idle'
        $guess = if ($detected -eq $script:RoomTypeUnknown) { '판별하지 못했습니다' } else { "$detected 탭" }
        $ask = "지금 카카오톡에서 보고 있는 목록을 읽습니다.`r`n`r`n· 위쪽 탭 확인 결과: $guess`r`n· 카카오톡 화면 이름: $($ready.Layout.ViewName)`r`n`r`n맞으면 그대로 진행하시고, 다르면 아래에서 골라 주세요.`r`n`r`n[예] 오픈채팅으로 저장`r`n[아니오] 일반채팅으로 저장`r`n[취소] 그만두기"
        $answer = [System.Windows.Forms.MessageBox]::Show($ask, "읽을 목록 확인 — $guess", 'YesNoCancel', 'Question')
        if ($answer -eq 'Cancel') { return }
        $type = if ($answer -eq 'Yes') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
        if ($detected -ne $script:RoomTypeUnknown -and $detected -ne $type) {
            Write-RunLog "주의: 화면은 $detected 로 보였는데 $type 으로 저장합니다."
        }

        Set-StatusPill "$type 목록 읽는 중" 'run'
        $script:form.Enabled = $false
        Write-RunLog "카카오톡 $type 목록을 읽는 중입니다. (화면: $($ready.Layout.ViewName))"
        $scan = Get-KakaoRoomNames ([int]$script:config.ScanPages)
        $script:form.Enabled = $true
        $script:form.Activate()

        $added = 0
        foreach ($name in @($scan.Names)) { if (Add-RoomEntry $name $type $false) { $added++ } }
        Update-RoomListView
        Sync-ConfigFromForm
        Set-StatusPill '준비됨' 'idle'
        Write-RunLog "목록 읽기 완료: $($type) / 화면 $($scan.Pages)개 / 후보 $(@($scan.Names).Count)개 중 새 항목 $($added)개"

        $result = "$($type) 방 $(@($scan.Names).Count)개를 읽었습니다. (새로 추가 $($added)개)"
        if (@($scan.Names).Count -eq 0) {
            $result += "`r`n`r`n한 개도 읽지 못했습니다. 카카오톡에서 목록이 실제로 보이는 상태인지 확인하고, 창을 조금 크게 한 뒤 다시 시도해 보세요."
        } else {
            $result += "`r`n`r`n① 보낼 방만 체크하세요.`r`n② [이름 확인·보정]을 누르면 실제 이름으로 자동 교정됩니다."
        }
        # 카카오톡 [채팅] 목록에는 오픈채팅방도 섞여 있어, 탭만으로는 방마다 종류를 알 수 없습니다.
        # [오픈채팅] 탭을 먼저 읽어 두면 그 방들이 오픈으로 표시되고,
        # 그다음 [채팅] 탭을 읽을 때 나머지만 일반채팅이 됩니다.
        if ($type -eq $script:RoomTypeNormal) {
            $openCount = @($script:roomEntries | Where-Object { $_.Type -eq $script:RoomTypeOpen }).Count
            if ($openCount -eq 0) {
                $result += "`r`n`r`n[종류를 정확히 나누려면]`r`n[채팅] 목록에는 오픈채팅방도 함께 들어 있습니다."
                $result += "`r`n카카오톡에서 [오픈채팅] 탭으로 바꿔 한 번 더 읽으면, 그 방들만 오픈채팅으로 바뀌고 나머지는 일반채팅으로 남습니다."
            } else {
                $result += "`r`n`r`n오픈채팅으로 표시된 방 $($openCount)개는 그대로 유지했습니다."
            }
        } else {
            $result += "`r`n`r`n오픈채팅으로 표시했습니다. 아직 [채팅] 탭을 읽지 않으셨다면, 그쪽도 한 번 읽어 두시면 목록이 완성됩니다."
        }
        [System.Windows.Forms.MessageBox]::Show($result, '목록 읽기 완료') | Out-Null
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
                $result = Resolve-RoomName $current $type
                if ($null -eq $result) { $failed++; Write-RunLog "이름 확인 실패: '$current' — 채팅창을 열지 못했습니다."; continue }
                $actual = [string]$result.Name
                # 개인/그룹 구분을 함께 기록합니다.
                if ($entry.Type -ne $result.Type) {
                    $entry.Type = $result.Type
                    $detail = if ($result.Members -gt 0) { " (인원 $($result.Members)명)" } else { '' }
                    Write-RunLog "종류 확인: '$actual' → $($result.Type)$detail"
                }
                if ($actual -and $actual -ne $current) {
                    if ($null -ne (Get-RoomEntry $actual)) {
                        Write-RunLog "이름 교정 생략: '$current' → '$actual' (이미 목록에 있음)"
                    } else {
                        Rename-RoomInGroups $current $actual
                        # 목록에서 찾을 때는 원래 읽혔던 글자를 써야 합니다.
                        Set-RoomListName $actual $current
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

# 달력에서 예약 시각을 고릅니다.
function Show-SchedulePicker([datetime]$Current) {
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = '예약 시각 고르기'
    $dialog.ClientSize = New-Object System.Drawing.Size(560, 470)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Theme.Card
    $dialog.Font = $FontBase

    $title = New-Object System.Windows.Forms.Label
    $title.Text = '언제 보낼까요?'
    $title.Font = $FontTourTitle
    $title.ForeColor = $Theme.Ink
    $title.BackColor = $Theme.Card
    $title.Location = New-Object System.Drawing.Point(26, 22)
    $title.Size = New-Object System.Drawing.Size(508, 32)
    $dialog.Controls.Add($title)

    $calendar = New-Object System.Windows.Forms.MonthCalendar
    $calendar.Location = New-Object System.Drawing.Point(26, 62)
    $calendar.MaxSelectionCount = 1
    $calendar.MinDate = (Get-Date).Date
    $calendar.SetDate($Current.Date)
    $dialog.Controls.Add($calendar)

    [void](New-CardLabel $dialog '시' 300 80 24 26 $FontSmall $Theme.Muted)
    $numHour = New-Object System.Windows.Forms.NumericUpDown
    $numHour.Minimum = 0; $numHour.Maximum = 23; $numHour.Value = $Current.Hour
    $numHour.Location = New-Object System.Drawing.Point(326, 76)
    $numHour.Size = New-Object System.Drawing.Size(66, 30)
    $numHour.Font = $FontBase; $numHour.BorderStyle = 'FixedSingle'
    $dialog.Controls.Add($numHour)

    [void](New-CardLabel $dialog '분' 400 80 24 26 $FontSmall $Theme.Muted)
    $numMinute = New-Object System.Windows.Forms.NumericUpDown
    $numMinute.Minimum = 0; $numMinute.Maximum = 59; $numMinute.Value = $Current.Minute
    $numMinute.Location = New-Object System.Drawing.Point(426, 76)
    $numMinute.Size = New-Object System.Drawing.Size(66, 30)
    $numMinute.Font = $FontBase; $numMinute.BorderStyle = 'FixedSingle'
    $dialog.Controls.Add($numMinute)

    [void](New-CardLabel $dialog '자주 쓰는 시각' 300 124 200 24 $FontSmall $Theme.Muted)
    $btnTonight  = New-AppButton $dialog '오늘 밤 9시' 300 150 196 36
    $btnTomorrow = New-AppButton $dialog '내일 0시' 300 192 196 36
    $btnMorning  = New-AppButton $dialog '내일 아침 9시' 300 234 196 36
    $btnIn10     = New-AppButton $dialog '10분 뒤' 300 276 196 36

    $lblPreview = New-CardLabel $dialog '' 26 320 508 30 $FontStrong $Theme.Info

    $script:pickedSchedule = $Current
    $refresh = {
        $picked = $calendar.SelectionStart.Date.AddHours([int]$numHour.Value).AddMinutes([int]$numMinute.Value)
        $script:pickedSchedule = $picked
        $weekday = ('일','월','화','수','목','금','토')[[int]$picked.DayOfWeek]
        $gap = $picked - (Get-Date)
        $gapText = if ($gap.TotalSeconds -le 0) { '이미 지난 시각입니다' }
                   elseif ($gap.TotalHours -ge 24) { "약 {0}일 {1}시간 뒤" -f [int]$gap.TotalDays, $gap.Hours }
                   elseif ($gap.TotalMinutes -ge 60) { "약 {0}시간 {1}분 뒤" -f [int]$gap.TotalHours, $gap.Minutes }
                   else { "약 {0}분 뒤" -f [int]$gap.TotalMinutes }
        $lblPreview.Text = "$($picked.ToString('yyyy-MM-dd')) ($weekday) $($picked.ToString('HH:mm'))  ·  $gapText"
        $lblPreview.ForeColor = if ($gap.TotalSeconds -le 0) { $Theme.Danger } else { $Theme.Info }
    }
    $setTo = {
        param($target)
        $calendar.SetDate($target.Date)
        $numHour.Value = $target.Hour
        $numMinute.Value = $target.Minute
        & $refresh
    }
    $calendar.Add_DateChanged({ & $refresh })
    $numHour.Add_ValueChanged({ & $refresh })
    $numMinute.Add_ValueChanged({ & $refresh })
    $btnTonight.Add_Click({ & $setTo ((Get-Date).Date.AddHours(21)) })
    $btnTomorrow.Add_Click({ & $setTo ((Get-Date).Date.AddDays(1)) })
    $btnMorning.Add_Click({ & $setTo ((Get-Date).Date.AddDays(1).AddHours(9)) })
    $btnIn10.Add_Click({ & $setTo ((Get-Date).AddMinutes(10)) })
    & $refresh

    $script:scheduleConfirmed = $false
    $btnOk = New-AppButton $dialog '이 시각으로 정하기' 322 402 152 42 'strong'
    $btnCancelPick = New-AppButton $dialog '취소' 482 402 52 42
    $btnOk.Add_Click({ $script:scheduleConfirmed = $true; $dialog.Close() })
    $btnCancelPick.Add_Click({ $script:scheduleConfirmed = $false; $dialog.Close() })

    [void]$dialog.ShowDialog($script:form)
    $dialog.Dispose()
    if ($script:scheduleConfirmed) { return $script:pickedSchedule }
    return $null
}

# 보내기 전에 '누구에게 무엇을' 보내는지 한 화면에서 보여 줍니다.
function Show-SendConfirm([string]$Action) {
    $rooms = @($script:roomEntries | Where-Object { $_.Checked })
    $dialog = New-Object System.Windows.Forms.Form
    $dialog.Text = $Action
    $dialog.ClientSize = New-Object System.Drawing.Size(600, 620)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Theme.Card
    $dialog.Font = $FontBase

    $title = New-Object System.Windows.Forms.Label
    $title.Text = $Action
    $title.Font = $FontTourTitle
    $title.ForeColor = $Theme.Ink
    $title.BackColor = $Theme.Card
    $title.Location = New-Object System.Drawing.Point(28, 24)
    $title.Size = New-Object System.Drawing.Size(544, 34)
    $dialog.Controls.Add($title)

    $dryRun = [bool]$script:config.DryRun
    $mode = if ($dryRun) { '확인 전용 — 방만 열어 보고 전송하지 않습니다.' } else { '실제로 메시지가 전송됩니다.' }
    $summary = New-Object System.Windows.Forms.Label
    $summary.Font = $FontBase
    $summary.ForeColor = if ($dryRun) { $Theme.Sub } else { $Theme.Danger }
    $summary.BackColor = $Theme.Card
    $summary.Location = New-Object System.Drawing.Point(28, 62)
    $summary.Size = New-Object System.Drawing.Size(544, 46)
    $summary.Text = "$mode`r`n$(Get-EstimatedRunText)"
    $dialog.Controls.Add($summary)

    $lblTo = New-Object System.Windows.Forms.Label
    $lblTo.Text = "받는 채팅방 $($rooms.Count)개"
    $lblTo.Font = $FontStrong
    $lblTo.ForeColor = $Theme.Ink
    $lblTo.BackColor = $Theme.Card
    $lblTo.Location = New-Object System.Drawing.Point(28, 116)
    $lblTo.Size = New-Object System.Drawing.Size(544, 24)
    $dialog.Controls.Add($lblTo)

    $listFrame = New-FieldFrame $dialog 28 144 544 224
    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.BorderStyle = 'None'
    $list.Font = $FontBase
    $list.Location = New-Object System.Drawing.Point(12, 12)
    $list.Size = New-Object System.Drawing.Size(520, 200)
    [void]$list.Columns.Add('채팅방 이름', 380)
    [void]$list.Columns.Add('종류', 120)
    # 보내기 전 확인 목록도 종류로 묶지 않고 이름 순서로 보여 줍니다.
    foreach ($entry in ($rooms | Sort-Object -Property Name)) {
        $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Name)
        [void]$item.SubItems.Add([string]$entry.Type)
        [void]$list.Items.Add($item)
    }
    $listFrame.Controls.Add($list)

    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text = '보낼 문구'
    $lblMsg.Font = $FontStrong
    $lblMsg.ForeColor = $Theme.Ink
    $lblMsg.BackColor = $Theme.Card
    $lblMsg.Location = New-Object System.Drawing.Point(28, 380)
    $lblMsg.Size = New-Object System.Drawing.Size(544, 24)
    $dialog.Controls.Add($lblMsg)

    $msgFrame = New-FieldFrame $dialog 28 408 544 104
    $preview = New-Object System.Windows.Forms.TextBox
    $preview.Multiline = $true
    $preview.ReadOnly = $true
    $preview.ScrollBars = 'Vertical'
    $preview.BorderStyle = 'None'
    $preview.BackColor = [System.Drawing.Color]::White
    $preview.Font = $FontBase
    $preview.Location = New-Object System.Drawing.Point(12, 10)
    $preview.Size = New-Object System.Drawing.Size(518, 82)
    $preview.Text = if ([string]::IsNullOrWhiteSpace($script:config.Message)) { '(문구 없음)' } else { [string]$script:config.Message }
    $msgFrame.Controls.Add($preview)

    $lblFiles = New-Object System.Windows.Forms.Label
    $lblFiles.Text = "첨부 $(@($script:config.Attachments).Count)개"
    $lblFiles.Font = $FontSmall
    $lblFiles.ForeColor = $Theme.Muted
    $lblFiles.BackColor = $Theme.Card
    $lblFiles.Location = New-Object System.Drawing.Point(28, 518)
    $lblFiles.Size = New-Object System.Drawing.Size(300, 22)
    $dialog.Controls.Add($lblFiles)

    $chkSkip = New-Object System.Windows.Forms.CheckBox
    $chkSkip.Text = '다음부터 이 확인 창 보지 않기'
    $chkSkip.Font = $FontSmall
    $chkSkip.BackColor = $Theme.Card
    $chkSkip.Location = New-Object System.Drawing.Point(28, 548)
    $chkSkip.Size = New-Object System.Drawing.Size(280, 26)
    $dialog.Controls.Add($chkSkip)

    $script:sendConfirmResult = $false
    $btnGo = New-AppButton $dialog $(if ($dryRun) { '확인 시작' } else { '보내기' }) 372 542 118 42 'primary'
    $btnNo = New-AppButton $dialog '취소' 498 542 74 42
    $btnGo.Add_Click({
        if ($chkSkip.Checked) { $script:config.SkipSendConfirm = $true; try { Save-Config $script:config } catch { } }
        $script:sendConfirmResult = $true
        $dialog.Close()
    })
    $btnNo.Add_Click({ $script:sendConfirmResult = $false; $dialog.Close() })

    if ($rooms.Count -eq 0) { $btnGo.Enabled = $false; $lblTo.Text = '받는 채팅방이 없습니다. [2. 받을 채팅방]에서 체크해 주세요.' }

    [void]$dialog.ShowDialog($script:form)
    $dialog.Dispose()
    return $script:sendConfirmResult
}

function Confirm-LiveRun([string]$Action) {
    # 보낼 대상을 한 번 보여 줍니다. '다음부터 보지 않기'를 고르면 건너뜁니다.
    if (-not [bool]$script:config.SkipSendConfirm) {
        if (-not (Show-SendConfirm $Action)) { return $false }
    }
    # 방해금지·주말·공휴일 설정을 먼저 확인합니다.
    if (-not [bool]$script:config.DryRun) {
        $blocked = Get-SendBlockReason (Get-Date)
        if ($blocked) {
            $next = Get-NextAllowedTime (Get-Date)
            $nextText = if ($null -ne $next) { "`r`n다음 발송 가능 시각: $($next.ToString('yyyy-MM-dd HH:mm'))" } else { '' }
            $body = "지금은 보내지 않도록 설정되어 있습니다.`r`n`r`n$blocked$nextText`r`n`r`n그래도 지금 보낼까요?"
            if ([System.Windows.Forms.MessageBox]::Show($body, '발송 제한 확인', 'YesNo', 'Warning') -ne 'Yes') { return $false }
        }
    }
    if ([bool]$script:config.DryRun) { return $true }
    # 확인 창을 껐다면 여기서 마지막으로 한 번만 묻습니다.
    if ([bool]$script:config.SkipSendConfirm) {
        $roomCount = @($script:config.Rooms).Count
        $interval = Get-EffectiveInterval (Get-Date)
        $body = "$Action`r`n`r`n대상 $($roomCount)개 방 · 간격 $($interval)초`r`n`r`n실제 메시지가 전송됩니다. 계속할까요?"
        return ([System.Windows.Forms.MessageBox]::Show($body, '실제 발송 확인', 'YesNo', 'Warning') -eq 'Yes')
    }
    return $true
}

$script:repeatDone = 0
$script:cancelRequested = $false
$script:pauseRequested = $false

# 발송 중에도 위쪽 [중지] 버튼이 눌리도록 화면을 갱신하고, 멈춤 요청을 확인합니다.
# $true 를 돌려주면 그만두라는 뜻입니다.
function Test-RunInterrupted {
    [System.Windows.Forms.Application]::DoEvents()
    if ($script:cancelRequested) { return $true }
    while ($script:pauseRequested -and -not $script:cancelRequested) {
        Set-StatusPill '일시정지 중 — [계속]을 누르면 이어서 진행합니다' 'wait'
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.Application]::DoEvents()
    }
    return $script:cancelRequested
}

# 잠깐 기다리는 동안에도 중지 버튼이 동작하게 합니다.
function Wait-Interruptible([int]$Seconds) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-RunInterrupted) { return $true }
        Start-Sleep -Milliseconds 150
    }
    return $false
}

function Update-RunButtons {
    $busy = ($script:running -or $script:armed)
    $script:btnHeaderStop.Visible = $busy
    $btnHeaderStart.Visible = -not $busy
    $script:btnHeaderStop.Tag.Label = if ($script:pauseRequested) { '계속하기' } else { '중지' }
    $script:btnHeaderStop.Invalidate()
    Update-HeaderSummary
}

# 반복 발송이 켜져 있으면 다음 차례를 예약합니다.
function Start-RepeatIfNeeded {
    if (-not [bool]$script:config.RepeatEnabled) { return }
    $limit = [int]$script:config.RepeatCount
    $script:repeatDone++
    if ($limit -gt 0 -and $script:repeatDone -ge $limit) {
        Write-RunLog "반복 발송을 $($script:repeatDone)회 마쳤습니다. (설정한 최대 횟수 도달)"
        $script:repeatDone = 0
        return
    }
    $minutes = [Math]::Max(1, [int]$script:config.RepeatMinutes)
    $next = (Get-Date).AddMinutes($minutes)
    $script:dtSchedule.Value = $next
    $script:armed = $true
    $btnArm.Enabled = $false
    $btnCancelArm.Enabled = $true
    $limitText = if ($limit -gt 0) { "$($script:repeatDone)/$limit 회" } else { "$($script:repeatDone)회째" }
    Write-RunLog "반복 발송: $($minutes)분 뒤 다시 보냅니다. ($limitText) → $($next.ToString('yyyy-MM-dd HH:mm'))"
    Set-StatusPill "반복 대기 — $($next.ToString('HH:mm')) 에 다시" 'wait'
}

function Start-BroadcastAsync {
    if ($script:running) { return }
    $script:running = $true
    $script:armed = $false
    $btnArm.Enabled = $true
    $btnCancelArm.Enabled = $false
    $script:cancelRequested = $false
    $script:pauseRequested = $false
    Set-StatusPill '실행 중' 'run'
    $pageHost.Enabled = $false
    $sidebar.Enabled = $false
    $btnHeaderEdit.Enabled = $false
    Update-RunButtons
    try {
        $count = Invoke-Broadcast
        Set-StatusPill "작업 완료 · 성공 $($count)개" 'done'
        Start-RepeatIfNeeded
    } catch {
        Write-RunLog "작업 중단: $($_.Exception.Message)"
        Set-StatusPill '오류로 중단' 'error'
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '작업 중단') | Out-Null
    } finally {
        $pageHost.Enabled = $true
        $sidebar.Enabled = $true
        $btnHeaderEdit.Enabled = $true
        $script:running = $false
        $script:pauseRequested = $false
        Update-RunButtons
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
        Update-RunButtons
    } catch { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '예약 실패') | Out-Null }
})
$btnCancelArm.Add_Click({
    $script:armed = $false
    $script:repeatDone = 0
    $btnArm.Enabled = $true
    $btnCancelArm.Enabled = $false
    $script:lblCountdown.Text = '예약이 취소되었습니다.'
    Set-StatusPill '예약 취소됨' 'idle'
    Write-RunLog '예약을 취소했습니다.'
    Update-RunButtons
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

# ----- 카카오톡 연결 확인 -----
function Update-KakaoStateLabel {
    $lines = New-Object System.Collections.Generic.List[string]
    $ready = Test-KakaoReady
    if ($ready.Ok) {
        $tab = Get-ActiveKakaoTab $ready.Layout
        $tabText = if ($tab -eq $script:RoomTypeUnknown) { '판별하지 못함' } else { "$tab 탭" }
        $lines.Add("[정상] 카카오톡 연결됨 - 지금 선택된 탭: $tabText")
        $lines.Add("[정상] 채팅방 목록을 찾았습니다. (화면 $($ready.Layout.ViewName))")
    } else {
        $lines.Add("[확인 필요] $($ready.Reason)")
    }
    if (Initialize-Ocr) { $lines.Add('[정상] 한국어 문자 인식 사용 가능') }
    else { $lines.Add("[확인 필요] 한국어 문자 인식 불가 - $($script:ocrError)") }
    $lines.Add('[안내] 채팅/오픈채팅 탭과 검색 아이콘은 자동으로 찾습니다. 따로 설정할 것이 없습니다.')

    $script:lblKakaoState.Text = ($lines -join [Environment]::NewLine)
    $script:lblKakaoState.ForeColor = if ($ready.Ok) { $Theme.Sub } else { $Theme.Danger }
    return $ready
}

$btnCheckKakao.Add_Click({
    $ready = Update-KakaoStateLabel
    if ($ready.Ok) { Set-StatusPill '카카오톡 연결됨' 'done' } else { Set-StatusPill '카카오톡 확인 필요' 'error' }
})
$btnOpenKakao.Add_Click({
    $main = Get-MainKakaoWindow $true
    if ($null -eq $main) {
        [System.Windows.Forms.MessageBox]::Show('PC 카카오톡이 실행되어 있지 않습니다. 카카오톡을 먼저 실행해 주세요.', '카카오톡 없음') | Out-Null
        return
    }
    [void](Enter-KakaoForeground $main)
    Start-Sleep -Milliseconds 400
    $script:form.Activate()
    [void](Update-KakaoStateLabel)
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

# 확인 한 번으로 내려받기·설치·재시작까지 진행합니다.
function Start-UpdateInstall([object]$Release) {
    if ($null -eq $Release) { return }
    $notes = ([string]$Release.Notes).Trim()
    if ($notes.Length -gt 400) { $notes = $notes.Substring(0, 400) + '...' }
    $body = "새 버전 $($Release.Tag) 이(가) 있습니다.`r`n`r`n"
    if ($notes) { $body += "$notes`r`n`r`n" }
    $body += "지금 내려받아 설치할까요?`r`n`r`n· 현재 파일은 backup 폴더에 보관됩니다.`r`n· 설정과 실행 기록은 그대로 유지됩니다.`r`n· 설치가 끝나면 프로그램이 다시 시작됩니다."
    if ([System.Windows.Forms.MessageBox]::Show($body, '업데이트 설치', 'YesNo', 'Question') -ne 'Yes') { return }
    try {
        $script:form.Enabled = $false
        Set-StatusPill '업데이트 내려받는 중' 'run'
        [void](Install-AppUpdate $Release)
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
        [System.Windows.Forms.MessageBox]::Show("업데이트에 실패했습니다.`r`n$($_.Exception.Message)`r`n`r`n인터넷 연결을 확인한 뒤 다시 시도해 주세요.", '업데이트 실패') | Out-Null
    }
}

$btnCheckUpdate.Add_Click({
    Set-StatusPill '업데이트 확인 중' 'run'
    Invoke-UpdateCheck $false
    Set-StatusPill '준비됨' 'idle'
    if ($null -ne $script:latestRelease) { Start-UpdateInstall $script:latestRelease }
})
$btnClearLogFiles.Add_Click({
    $files = @(Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue)
    if ($files.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('지울 로그 파일이 없습니다.', '로그 지우기') | Out-Null
        return
    }
    $body = "로그 파일 $($files.Count)개를 지웁니다.`r`n`r`n실행 기록이 모두 사라지고 되돌릴 수 없습니다. 계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($body, '로그 파일 지우기', 'YesNo', 'Warning') -ne 'Yes') { return }
    $removed = 0
    foreach ($file in $files) {
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $removed++ } catch { }
    }
    if ($script:txtLog) { $script:txtLog.Clear() }
    Write-RunLog "로그 파일 $($removed)개를 지웠습니다."
    [System.Windows.Forms.MessageBox]::Show("로그 파일 $($removed)개를 지웠습니다.", '로그 지우기') | Out-Null
})
$script:btnDoUpdate.Add_Click({ Start-UpdateInstall $script:latestRelease })
$script:pnlUpdate.Add_Click({
    Show-AppPage 'settings'
    if ($null -ne $script:latestRelease) { Start-UpdateInstall $script:latestRelease }
})

# ----- 폴더 및 초기화 -----
$btnGuide.Add_Click({ Show-GuideTour })
$btnOpenApp.Add_Click({ Start-Process 'explorer.exe' $AppDir })
$btnOpenLogs.Add_Click({ Start-Process 'explorer.exe' $LogDir })
$btnOpenLogDir.Add_Click({ Start-Process 'explorer.exe' $LogDir })
$btnClearLog.Add_Click({ $script:txtLog.Clear() })
$btnResetConf.Add_Click({
    # 이 PC 에 쌓인 것을 모두 지웁니다. 다른 사람에게 폴더를 넘길 때도 이 버튼을 쓰면 됩니다.
    $msg = '이 프로그램을 처음 받은 상태로 되돌립니다.' + "`r`n`r`n" +
           '아래를 모두 지웁니다.' + "`r`n" +
           '  - 받을 채팅방 목록과 그룹' + "`r`n" +
           '  - 보낼 문구와 첨부 파일' + "`r`n" +
           '  - 예약, 반복, 발송 간격 등 모든 설정' + "`r`n" +
           '  - 지난 실행 기록 (logs 폴더의 기록 파일)' + "`r`n`r`n" +
           '지운 것은 되돌릴 수 없습니다. 계속할까요?'
    if ([System.Windows.Forms.MessageBox]::Show($msg, '처음 상태로 되돌리기', 'YesNo', 'Warning') -ne 'Yes') { return }
    $script:config = New-DefaultConfig
    Save-Config $script:config
    $removed = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File -ErrorAction SilentlyContinue)) {
        try { Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop; $removed++ } catch { }
    }
    try { $script:txtLog.Clear() } catch { }
    [System.Windows.Forms.MessageBox]::Show("처음 상태로 되돌렸습니다. 지난 실행 기록 $($removed)개도 지웠습니다." + "`r`n" + '프로그램을 다시 시작합니다.', '처음 상태로 되돌리기') | Out-Null
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
    $btnNext = New-AppButton $tour '다음' 448 370 116 38 'strong'

    $renderStep = {
        $step = $script:TourSteps[$script:tourIndex]
        Show-AppPage ([string]$step.Page)
        $lblStep.Text = "{0} / {1}" -f ($script:tourIndex + 1), $total
        $lblTitle.Text = [string]$step.Title
        $lblBody.Text = [string]$step.Body
        $btnPrev.Visible = ($script:tourIndex -gt 0)
        $btnNext.Tag.Label = if ($script:tourIndex -eq ($total - 1)) { '시작하기' } else { '다음' }
        $btnNext.Invalidate()
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
            # 방해금지·주말·공휴일에 걸리면 보내지 않고 다음 가능한 시각으로 미룹니다.
            $blocked = if ([bool]$script:config.DryRun) { $null } else { Get-SendBlockReason (Get-Date) }
            if ($blocked) {
                $next = Get-NextAllowedTime (Get-Date)
                if ($null -eq $next) {
                    $script:armed = $false
                    $btnArm.Enabled = $true
                    $btnCancelArm.Enabled = $false
                    $script:lblCountdown.Text = '보낼 수 있는 시각을 찾지 못해 예약을 해제했습니다.'
                    Set-StatusPill '예약 해제됨' 'error'
                    Write-RunLog "예약 해제: $blocked (다음 가능 시각을 찾지 못했습니다.)"
                } else {
                    $script:dtSchedule.Value = $next
                    $script:lblCountdown.Text = "발송을 미뤘습니다 → $($next.ToString('yyyy-MM-dd HH:mm'))"
                    Set-StatusPill '발송 시각 미룸' 'wait'
                    Write-RunLog "예약 미룸: $blocked → $($next.ToString('yyyy-MM-dd HH:mm')) 로 변경"
                }
                return
            }
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
    Exit-SingleInstance
})

$startupTimer = New-Object System.Windows.Forms.Timer
$startupTimer.Interval = 1200
$startupTimer.Add_Tick({
    $startupTimer.Stop()
    try { [void](Update-KakaoStateLabel) } catch { }
    try { Update-LimitStateLabel } catch { }
    if (-not $NoUpdateCheck -and [bool]$script:config.AutoCheckUpdate) {
        Invoke-UpdateCheck $true
        # 새 버전이 있으면 확인 한 번으로 바로 받아 설치합니다.
        if ($null -ne $script:latestRelease -and [bool]$script:config.AutoDownloadUpdate) {
            Start-UpdateInstall $script:latestRelease
        }
    }
})

# 방해금지·공휴일 안내를 1분마다 갱신합니다.
$limitTimer = New-Object System.Windows.Forms.Timer
$limitTimer.Interval = 60000
$limitTimer.Add_Tick({ try { Update-LimitStateLabel } catch { } })
$limitTimer.Start()

# ---------------------------------------------------------------------------
# 시작 화면 (순차 점검)
# ---------------------------------------------------------------------------
function Show-SplashScreen {
    $splash = New-Object System.Windows.Forms.Form
    $splash.FormBorderStyle = 'None'
    $splash.StartPosition = 'CenterScreen'
    $splash.Size = New-Object System.Drawing.Size(560, 420)
    $splash.BackColor = $Theme.Card
    $splash.Font = $FontBase
    $splash.TopMost = $true
    $splash.ShowInTaskbar = $false
    $splash.Add_Paint({
        param($sender, $e)
        $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $pen = New-Object System.Drawing.Pen ($Theme.Border)
        $e.Graphics.DrawRectangle($pen, 0, 0, ($sender.Width - 1), ($sender.Height - 1))
        $pen.Dispose()
        $accent = New-Object System.Drawing.SolidBrush ($Theme.Accent)
        $e.Graphics.FillRectangle($accent, 0, 0, $sender.Width, 6)
        $accent.Dispose()
        $mark = New-Object System.Drawing.Rectangle(40, 40, 52, 52)
        $path = Get-RoundedPath $mark 15
        $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
        Write-Text $e.Graphics '톡' $FontTourTitle $Theme.AccentInk $mark $TextCenter
        Write-Text $e.Graphics '카카오 발송기' $FontTourTitle $Theme.Ink (New-Object System.Drawing.Rectangle(108, 42, 300, 30)) $TextLeft
        Write-Text $e.Graphics "버전 $($script:AppVersion)" $FontSmall $Theme.Muted (New-Object System.Drawing.Rectangle(110, 70, 300, 22)) $TextLeft
    })

    $steps = @(
        @{ Key = 'os';       Label = '운영체제 확인' },
        @{ Key = 'kakao';    Label = '카카오톡 실행 확인' },
        @{ Key = 'instance'; Label = '카카오톡 창 선택' },
        @{ Key = 'ocr';      Label = '한국어 문자 인식 확인' },
        @{ Key = 'update';   Label = '최신 배포 확인' }
    )
    $script:splashState = @{}
    foreach ($step in $steps) { $script:splashState[$step.Key] = @{ Status = '대기'; Detail = '' } }

    $labels = @{}
    $y = 120
    foreach ($step in $steps) {
        $row = New-Object System.Windows.Forms.Label
        $row.Location = New-Object System.Drawing.Point(42, $y)
        $row.Size = New-Object System.Drawing.Size(478, 44)
        $row.Font = $FontBase
        $row.ForeColor = $Theme.Muted
        $row.BackColor = $Theme.Card
        $row.Text = "· $($step.Label)"
        $splash.Controls.Add($row)
        $labels[$step.Key] = $row
        $y += 46
    }

    $btnRetry = New-AppButton $splash '다시 확인' 42 356 130 40
    $btnStart = New-AppButton $splash '시작하기' 306 356 96 40 'strong'
    $btnQuit  = New-AppButton $splash '종료' 412 356 106 40
    $btnRetry.Visible = $false
    $btnStart.Visible = $false
    $btnQuit.Visible = $false

    $render = {
        foreach ($step in $steps) {
            $state = $script:splashState[$step.Key]
            $mark = switch ($state.Status) {
                '확인' { '[정상]' }
                '실패' { '[확인 필요]' }
                '진행' { '· 확인 중...' }
                default { '·' }
            }
            $color = switch ($state.Status) {
                '확인' { $Theme.Success }
                '실패' { $Theme.Danger }
                '진행' { $Theme.Info }
                default { $Theme.Muted }
            }
            $text = "$mark $($step.Label)"
            if ($state.Detail) { $text += "`r`n     $($state.Detail)" }
            $labels[$step.Key].Text = $text
            $labels[$step.Key].ForeColor = $color
        }
        [System.Windows.Forms.Application]::DoEvents()
    }

    $setStep = {
        param($key, $status, $detail)
        $script:splashState[$key].Status = $status
        $script:splashState[$key].Detail = $detail
        & $render
    }

    $splash.Show()
    & $render
    Start-Sleep -Milliseconds 200

    # 1) 운영체제
    & $setStep 'os' '진행' ''
    Start-Sleep -Milliseconds 200
    $osName = 'Windows'
    try { $osName = (Get-CimInstance Win32_OperatingSystem).Caption } catch { }
    $osOk = ([Environment]::OSVersion.Version.Major -ge 6)
    & $setStep 'os' $(if ($osOk) { '확인' } else { '실패' }) "$osName / PowerShell $($PSVersionTable.PSVersion)"

    # 2) 카카오톡 실행
    & $setStep 'kakao' '진행' ''
    Start-Sleep -Milliseconds 200
    $instances = @(Get-KakaoMainWindows)
    if ($instances.Count -eq 0) {
        & $setStep 'kakao' '실패' 'PC 카카오톡을 실행해 주세요.'
    } else {
        & $setStep 'kakao' '확인' "카카오톡 $($instances.Count)개를 찾았습니다."
    }

    # 3) 창 선택 (여러 개면 사용자가 고릅니다)
    & $setStep 'instance' '진행' ''
    Start-Sleep -Milliseconds 150
    if ($instances.Count -eq 0) {
        & $setStep 'instance' '실패' '카카오톡을 먼저 실행해 주세요.'
    } else {
        if ($instances.Count -gt 1) {
            $names = @($instances | ForEach-Object { Get-KakaoInstanceLabel $_ })
            $pick = [Microsoft.VisualBasic.Interaction]::InputBox(
                "카카오톡이 여러 개 실행 중입니다. 사용할 번호를 입력하세요.`r`n`r`n" +
                (($names | ForEach-Object -Begin { $i = 0 } -Process { $i++; "$i. $_" }) -join "`r`n"),
                '카카오톡 창 선택', '1')
            $index = 0
            if ([int]::TryParse(([string]$pick).Trim(), [ref]$index) -and $index -ge 1 -and $index -le $instances.Count) {
                $script:selectedKakaoProcessId = $instances[$index - 1].ProcessId
            } else {
                $script:selectedKakaoProcessId = $instances[0].ProcessId
            }
        } else {
            $script:selectedKakaoProcessId = $instances[0].ProcessId
        }
        $main = Get-MainKakaoWindow $true
        if ($null -eq $main) {
            & $setStep 'instance' '실패' '카카오톡 창을 찾지 못했습니다.'
        } elseif (Test-WindowMinimized $main) {
            & $setStep 'instance' '실패' '창이 닫혀 있습니다. 트레이의 카카오톡 아이콘을 눌러 창을 열어 주세요.'
        } else {
            $layout = Get-KakaoLayout $main
            if ($null -eq $layout.List) {
                & $setStep 'instance' '실패' '채팅 목록이 보이지 않습니다. 카카오톡에서 채팅 탭을 눌러 주세요.'
            } else {
                $tab = ''
                try { $tab = Get-ActiveKakaoTab $layout } catch { }
                $tabText = if (-not $tab -or $tab -eq $script:RoomTypeUnknown) { '탭 판별 못함' } else { "$tab 탭" }
                & $setStep 'instance' '확인' "카카오톡 #$($script:selectedKakaoProcessId) / 지금 $tabText"
            }
        }
    }

    # 4) 문자 인식
    & $setStep 'ocr' '진행' ''
    Start-Sleep -Milliseconds 150
    if (Initialize-Ocr) { & $setStep 'ocr' '확인' '한국어 문자 인식 사용 가능' }
    else { & $setStep 'ocr' '실패' $script:ocrError }

    # 5) 최신 배포 확인
    & $setStep 'update' '진행' '최신 배포를 확인합니다...'
    $release = $null
    if (-not $NoUpdateCheck) {
        try { $release = Get-LatestRelease } catch { }
    }
    if ($null -eq $release) {
        & $setStep 'update' '확인' '지금은 확인하지 않았습니다.'
    } elseif (Test-UpdateAvailable $release) {
        $script:latestRelease = $release
        & $setStep 'update' '실패' "새 버전 $($release.Tag) 이(가) 있습니다. 업데이트해야 사용할 수 있습니다."
    } else {
        & $setStep 'update' '확인' "최신 버전입니다. ($($release.Tag))"
    }

    $allOk = $true
    foreach ($step in $steps) { if ($script:splashState[$step.Key].Status -ne '확인') { $allOk = $false } }
    $mustUpdate = ($null -ne $script:latestRelease)

    $btnRetry.Visible = $true
    $btnQuit.Visible = $true
    $btnStart.Visible = ($allOk -and -not $mustUpdate)
    if ($mustUpdate) {
        $btnRetry.Tag.Label = '지금 업데이트'
        $btnRetry.Invalidate()
    }

    $script:splashResult = ''
    $btnStart.Add_Click({ $script:splashResult = 'start'; $splash.Close() })
    $btnQuit.Add_Click({ $script:splashResult = 'quit'; $splash.Close() })
    $btnRetry.Add_Click({ $script:splashResult = 'retry'; $splash.Close() })

    while ($splash.Visible) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }
    $splash.Dispose()
    return $script:splashResult
}

Show-AppPage 'compose'
Write-RunLog "프로그램 시작 (v$($script:AppVersion)). 설정은 자동 저장됩니다."
if ($script:roomRepairNote) { Write-RunLog $script:roomRepairNote }

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

# 화면 요소가 서로 겹치는지 검사합니다.
# 설정 화면에 칸을 더하다가 기존 항목 위에 겹쳐 놓은 적이 있어서,
# 눈으로 보지 않고도 알 수 있게 검사를 넣었습니다.
function Get-LayoutOverlaps {
    $found = New-Object System.Collections.Generic.List[string]
    function Test-Container([object]$Container, [string]$Path) {
        $kids = @($Container.Controls | Where-Object { $_.Visible -or $_ -is [System.Windows.Forms.Control] })
        for ($i = 0; $i -lt $kids.Count; $i++) {
            for ($j = $i + 1; $j -lt $kids.Count; $j++) {
                $a = $kids[$i]; $b = $kids[$j]
                if ($a.Bounds.Width -le 0 -or $a.Bounds.Height -le 0) { continue }
                if ($b.Bounds.Width -le 0 -or $b.Bounds.Height -le 0) { continue }
                $hit = [System.Drawing.Rectangle]::Intersect($a.Bounds, $b.Bounds)
                if ($hit.Width -gt 2 -and $hit.Height -gt 2) {
                    $ta = if ($a.Text) { $a.Text } else { $a.GetType().Name }
                    $tb = if ($b.Text) { $b.Text } else { $b.GetType().Name }
                    if ($ta.Length -gt 24) { $ta = $ta.Substring(0,24) }
                    if ($tb.Length -gt 24) { $tb = $tb.Substring(0,24) }
                    $found.Add(("{0}: [{1}] {2} <-> [{3}] {4}" -f $Path, $ta, $a.Bounds, $tb, $b.Bounds))
                }
            }
        }
        foreach ($kid in $kids) {
            if ($kid.Controls.Count -gt 0) { Test-Container $kid ($Path + " > " + $kid.GetType().Name) }
        }
    }
    foreach ($key in $script:pages.Keys) { Test-Container $script:pages[$key] $key }
    return $found
}

if ($UiSmokeTest) {
    $overlaps = @(Get-LayoutOverlaps)
    if ($overlaps.Count -gt 0) {
        Write-Output ("LAYOUT_OVERLAP " + $overlaps.Count + "건")
        foreach ($line in ($overlaps | Select-Object -First 20)) { Write-Output ("  " + $line) }
    } else {
        Write-Output 'LAYOUT_OK 겹치는 화면 요소 없음'
    }
    Write-Output ("UI_SMOKETEST_OK pages={0} nav={1}" -f $script:pages.Count, $script:navItems.Count)
    $script:form.Dispose()
    exit 0
}

$script:form.Add_Shown({
    # 시작 화면에서 순서대로 점검합니다. 문제가 있으면 다음 화면으로 넘어가지 않습니다.
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $result = Show-SplashScreen
        if ($result -eq 'start') { break }
        if ($result -eq 'quit') { $script:armed = $false; $script:form.Close(); return }
        if ($result -eq 'retry' -and $null -ne $script:latestRelease) {
            Start-UpdateInstall $script:latestRelease
            if ($null -ne $script:latestRelease) {
                # 업데이트를 하지 않으면 사용할 수 없습니다.
                if ([System.Windows.Forms.MessageBox]::Show(
                    "새 버전으로 업데이트해야 사용할 수 있습니다.`r`n`r`n다시 시도할까요? [아니오]를 누르면 종료합니다.",
                    '업데이트 필요', 'YesNo', 'Warning') -ne 'Yes') {
                    $script:armed = $false
                    $script:form.Close()
                    return
                }
            }
        }
    }
    [void](Update-KakaoStateLabel)
    Update-LimitStateLabel
    if (-not [bool]$script:config.TourDone) {
        Write-RunLog '처음 실행이라 사용 가이드를 표시합니다.'
        Show-GuideTour
    }
    $startupTimer.Start()
})

# ShowDialog 로 띄우면 탭 위치를 알려줄 때 form.Hide() 가 모달 루프를 끝내 프로그램이 종료됩니다.
[System.Windows.Forms.Application]::Run($script:form)
