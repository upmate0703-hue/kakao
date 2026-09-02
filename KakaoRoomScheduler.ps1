param(
    [switch]$SelfTest,
    [switch]$UiSmokeTest,
    [switch]$NoUpdateCheck,
    [switch]$ScanTest,
    [switch]$ScanExact,
    [switch]$OpenTest,
    [switch]$MaskNames,
    [switch]$SendBench,
    [int]$BenchCount = 3,
    [string]$ScreenshotDir = ''
    ,
    # 화면 배율을 일부러 바꿔 화면이 깨지지 않는지 보는 용도입니다.
    # 100% 컴퓨터에서도 125%, 150% 모습을 확인할 수 있습니다.
    [double]$UiScaleTest = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 배포 정보 (CI가 아래 AppVersion 줄을 그대로 치환합니다. 형식을 바꾸지 마세요.)
# ---------------------------------------------------------------------------
$script:AppVersion = '6.3.0'
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
    // 이 창이 놓인 화면의 배율을 알아냅니다.
    // 모니터마다 배율이 다를 수 있어, 창 기준으로 물어야 정확합니다.
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr hWnd);
    public static int WindowDpi(IntPtr hWnd) {
        try { uint d = GetDpiForWindow(hWnd); if (d >= 72 && d <= 480) { return (int)d; } } catch { }
        return 96;
    }
    // 창이 응답하지 않는 상태인지 봅니다. 카카오톡이 잠깐 먹통일 때 바로 실패로 몰지 않기 위해서입니다.
    [DllImport("user32.dll")] static extern bool IsHungAppWindow(IntPtr hWnd);
    public static bool IsWindowHung(IntPtr hWnd) { try { return IsHungAppWindow(hWnd); } catch { return false; } }
    // 작업 표시줄이 이 프로그램을 별개의 프로그램으로 보게 합니다.
    // 이것을 안 하면 스크립트로 실행할 때 파워셸 아이콘으로 묶여 버립니다.
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern int SetCurrentProcessExplicitAppUserModelID(string appID);
    public static void SetAppId(string appID) { try { SetCurrentProcessExplicitAppUserModelID(appID); } catch { } }
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

    [StructLayout(LayoutKind.Sequential)]
    public struct GUIINFO {
        public int cbSize; public int flags;
        public IntPtr hwndActive, hwndFocus, hwndCapture, hwndMenuOwner, hwndMoveSize, hwndCaret;
        public RECT rcCaret;
    }
    [DllImport("user32.dll")] static extern bool GetGUIThreadInfo(uint idThread, ref GUIINFO info);

    // 지금 키보드 입력을 받고 있는 칸이 무엇인지 알아냅니다.
    // 채팅창이 이미 열려 있던 경우 포커스가 다른 곳에 가 있을 수 있고,
    // 그대로 Enter 를 눌러 봐야 아무 일도 일어나지 않습니다.
    public static IntPtr GetFocusedControl(IntPtr windowOfThread) {
        uint tid = GetWindowThreadId(windowOfThread, IntPtr.Zero);
        if (tid == 0) { return IntPtr.Zero; }
        GUIINFO info = new GUIINFO();
        info.cbSize = Marshal.SizeOf(typeof(GUIINFO));
        if (!GetGUIThreadInfo(tid, ref info)) { return IntPtr.Zero; }
        return info.hwndFocus;
    }

    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int value);
    [DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hWnd);
    [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr hdc, int index);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hWnd, IntPtr hdc);

    // 화면 배율을 그대로 인식하도록 선언합니다.
    // 이걸 하지 않으면 윈도우가 화면을 대신 늘려 줍니다.
    // 그러면 우리가 뜨는 카카오톡 그림도 줄어들어 글자 인식이 나빠집니다.
    // 창을 하나라도 만들기 전에 불러야 합니다.
    public static string MakeDpiAware() {
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-4))) { return "모니터별(V2)"; } } catch { }
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-3))) { return "모니터별"; } } catch { }
        try { if (SetProcessDpiAwareness(2) == 0) { return "모니터별(shcore)"; } } catch { }
        try { if (SetProcessDPIAware()) { return "시스템"; } } catch { }
        return "";
    }

    // 지금 화면의 DPI 입니다. 96 이 100% 입니다.
    public static int GetSystemDpi() {
        IntPtr dc = GetDC(IntPtr.Zero);
        if (dc == IntPtr.Zero) { return 96; }
        int dpi = GetDeviceCaps(dc, 88);
        ReleaseDC(IntPtr.Zero, dc);
        if (dpi <= 0) { return 96; }
        return dpi;
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
# 화면 배율 (DPI)
# ---------------------------------------------------------------------------
# 윈도우 배율이 125% 나 150% 인 컴퓨터가 많습니다.
# 배율을 그대로 인식하지 않으면 윈도우가 창을 대신 늘려 줍니다.
# 보기에는 비슷하지만, 우리가 뜨는 카카오톡 그림이 줄어들어
# 채팅방 이름을 읽는 정확도가 떨어집니다.
#
# 그래서 배율을 그대로 받아들이고, 화면 요소 크기는 우리가 직접 곱합니다.
# 아래 S / New-UiPoint / New-UiSize 를 거치면 어느 배율에서도 같은 모양이 됩니다.
$script:DpiMode = ''
try { $script:DpiMode = [NativeKakao]::MakeDpiAware() } catch { }
$script:SystemDpi = 96
try { $script:SystemDpi = [int][NativeKakao]::GetSystemDpi() } catch { }
if ($script:SystemDpi -le 0) { $script:SystemDpi = 96 }
$script:UiScale = [Math]::Round(($script:SystemDpi / 96.0), 3)
if ($script:UiScale -lt 1.0) { $script:UiScale = 1.0 }
if ($script:UiScale -gt 3.0) { $script:UiScale = 3.0 }
# 시험용으로 배율을 지정했으면 그 값을 씁니다.
if ($UiScaleTest -gt 0) { $script:UiScale = [Math]::Round($UiScaleTest, 3) }
$script:UiScalePercent = [int][Math]::Round($script:UiScale * 100)

# 크기 하나를 배율에 맞춰 늘립니다.
function S([double]$Value) { return [int][Math]::Round($Value * $script:UiScale) }

# 화면 요소의 위치와 크기는 반드시 이 두 가지를 거칩니다.
function New-UiPoint([double]$X, [double]$Y) {
    return New-Object System.Drawing.Point((S $X), (S $Y))
}
function New-UiSize([double]$W, [double]$H) {
    return New-Object System.Drawing.Size((S $W), (S $H))
}
# 그림을 그릴 때 쓰는 네모입니다.
function New-UiRect([double]$X, [double]$Y, [double]$W, [double]$H) {
    return New-Object System.Drawing.Rectangle((S $X), (S $Y), (S $W), (S $H))
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

# 처음 쓰는 컴퓨터에서는 아무것도 없는 상태로 시작해야 합니다.
# 설정 파일이 없다는 것은 이 컴퓨터에서 한 번도 안 썼다는 뜻입니다.
# 그런데 프로그램을 덮어 설치했거나 옮겨 온 폴더라면 예전 기록이 남아 있을 수 있습니다.
# 남의 기록이 남아 있으면 처음 켰는데 남이 보낸 내역이 보입니다. 그래서 지웁니다.
$script:isFirstRun = (-not (Test-Path -LiteralPath $ConfigPath))
if ($script:isFirstRun) {
    foreach ($stale in @($LogDir, $BackupDir)) {
        if (Test-Path -LiteralPath $stale) {
            try { Remove-Item -LiteralPath $stale -Recurse -Force -ErrorAction Stop } catch { }
        }
    }
}
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
        DryRun = $false
        ScanPages = 30
        TestRoom = '나와의 채팅'
        AttachmentWaitMs = 1500
        OpenTimeoutMs = 8000
        SettleMs = 4000
        PreloadRooms = $true
        PreloadDone = $false
        TruncatedRooms = @()
        # ----- 채팅방 목록 (카카오톡에서 읽어 저장해 둔 것) -----
        # 예전에는 방 이름을 쳐 넣고 검색해서 찾았습니다.
        # 검색 결과를 글자로 읽다 보니 '뽀식'을 '포식'으로 읽는 일이 있었습니다.
        # 이제는 카카오톡에 실제로 보이는 목록을 통째로 읽어 여기에 담아 둡니다.
        #   { Name = '뽀식'; ListText = '뽀식'; Kind = 'group'; Order = 3;
        #     Verified = $true; LastSeen = '2026-09-02 14:00:00' }
        # Verified 는 방을 실제로 열어 창 제목으로 이름을 확인했다는 뜻입니다.
        # 창 제목은 화면 글자 인식이 아니라 윈도우가 알려 주는 진짜 글자라 정확합니다.
        Roster = @()
        RosterScannedAt = ''
        # 목록을 읽을 때 방을 하나씩 열어 창 제목으로 이름을 확정할지 정합니다.
        # 느리지만 이름이 정확해집니다. 이름을 틀리게 읽는 문제가 여기서 사라집니다.
        ScanExactNames = $true
        # 자주 보내는 문구를 담아 둡니다.  { Name = '기본 안내문'; Text = '...' }
        Templates = @()
        # 한 방이 실패했을 때 몇 번까지 다시 해 볼지 정합니다.
        RetryCount = 3
        # 한 방을 끝내면 그 채팅창을 닫고 다음 방으로 갑니다.
        CloseAfterSend = $true
        # 사진을 묶어서 한 번에 보낼지 정합니다.
        # 한 장씩 보내면 미리보기 창이 뜨고 닫히기를 되풀이해서 중간에 잘 막힙니다.
        # 묶어 보내면 미리보기가 한 번만 뜨고 한 번에 나갑니다.
        GroupPhotos = $true
        PhotoBatchSize = 10
        # 공휴일마다 어떻게 할지 하나씩 정합니다.
        #   { Date = '2026-09-24'; Name = '추석'; Action = 'move'; MoveTo = '2026-09-25' }
        #   Action: normal(그대로 보냄) / skip(그날은 안 보냄) / move(다른 날로 옮김)
        HolidayRules = @()
        # 옮긴 날에 두 번 보내지 않도록, 보낸 날을 적어 둡니다.
        SentDays = @()
        # 방이 1:1 인지 단체인지 오픈채팅인지 적어 둡니다.
        #   direct(1:1) / group(단체) / open(오픈채팅) / unknown(모름)
        RoomKinds = [pscustomobject]@{}
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

# 화면 글자 인식이 한 글자쯤 틀리면 같은 방이 둘로 남습니다.
#   [5K X 아우여 (따몽이)]  /  [5K X 아우여 (따봉이)]
# 길이가 같고 한 글자만 다르면 같은 방으로 보고 합칩니다.
# 짧은 이름은 진짜 다른 방일 수 있으므로 여덟 자 이상일 때만 합칩니다.
function Test-NearSameRoomName([string]$A, [string]$B) {
    $keyA = ConvertTo-CompareKey $A
    $keyB = ConvertTo-CompareKey $B
    if (-not $keyA -or -not $keyB) { return $false }
    if ($keyA -eq $keyB) { return $true }
    if ($keyA.Length -ne $keyB.Length) { return $false }
    if ($keyA.Length -lt 8) { return $false }
    $diff = 0
    for ($i = 0; $i -lt $keyA.Length; $i++) {
        if ($keyA[$i] -ne $keyB[$i]) { $diff++ }
        if ($diff -gt 1) { return $false }
    }
    return ($diff -eq 1)
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
        # 한 글자만 다른 이름이 이미 있으면 같은 방으로 봅니다.
        $near = ''
        foreach ($seen in $order) {
            if (Test-NearSameRoomName $name $byKey[$seen]) { $near = $seen; break }
        }
        if ($near) { $merged++; continue }
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
    if ($null -eq $Config.RoomKinds) { $Config.RoomKinds = [pscustomobject]@{} }
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

# ---------------------------------------------------------------------------
# 방 종류 (1:1 / 단체 / 오픈채팅)
# ---------------------------------------------------------------------------
# 이름만 보고 짐작하지 않습니다. 창 제목에 실제로 적힌 것을 씁니다.
# 카카오톡은 단체 채팅방 제목 뒤에 인원수를 붙입니다.  예: 우리반 공지방 (24)
# 1:1 은 인원수가 붙지 않습니다.
# 오픈채팅은 목록 탭에서 이미 알 수 있습니다.
# 확실하지 않으면 unknown 으로 두고 일반채팅으로 다룹니다. 잘못 나누는 것보다 낫습니다.
function Get-RoomKindFromTitle([string]$Title, [string]$RoomType) {
    if ($RoomType -eq $script:RoomTypeOpen) { return 'open' }
    $title = ([string]$Title).Trim()
    if (-not $title) { return 'unknown' }
    if ($title -match '\((\d{1,5})\)\s*$') {
        $count = [int]$Matches[1]
        if ($count -ge 3) { return 'group' }
        if ($count -eq 2) { return 'direct' }
    }
    return 'unknown'
}

function Get-RoomKind([string]$Name) {
    try {
        $prop = $script:config.RoomKinds.PSObject.Properties[$Name]
        if ($null -ne $prop -and [string]$prop.Value) { return [string]$prop.Value }
    } catch { }
    return 'unknown'
}

function Set-RoomKind([string]$Name, [string]$Kind) {
    if (-not $Name -or -not $Kind -or $Kind -eq 'unknown') { return }
    try {
        if ($null -eq $script:config.RoomKinds) { $script:config.RoomKinds = [pscustomobject]@{} }
        $prop = $script:config.RoomKinds.PSObject.Properties[$Name]
        if ($null -eq $prop) { Add-Member -InputObject $script:config.RoomKinds -NotePropertyName $Name -NotePropertyValue $Kind }
        else { $script:config.RoomKinds.$Name = $Kind }
    } catch { }
}

# 화면에 보여 줄 때 쓰는 말입니다.
function Get-RoomKindText([string]$Name) {
    switch (Get-RoomKind $Name) {
        'direct' { return '1:1' }
        'group'  { return '단체' }
        'open'   { return '오픈채팅' }
        default    { return '일반채팅' }
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

# ---------------------------------------------------------------------------
# 공휴일 규칙
# ---------------------------------------------------------------------------
# 공휴일마다 그대로 보낼지, 건너뛸지, 다른 날로 옮길지 하나씩 정합니다.
# 예전에는 공휴일 전체를 한꺼번에 처리해서 날짜마다 다르게 할 수 없었습니다.
# 설정 파일에서 읽어 온 항목은 형식이 굳어 있어
# 다른 형식을 그냥 넣으면 "형식이 맞지 않는다" 는 오류가 납니다.
# 그래서 항목을 지우고 새로 만듭니다. 이러면 형식 문제가 생기지 않습니다.
function Set-ConfigValue([string]$Name, [object]$Value) {
    try { $script:config.PSObject.Properties.Remove($Name) } catch { }
    try {
        Add-Member -InputObject $script:config -NotePropertyName $Name -NotePropertyValue $Value -Force
    } catch {
        Write-RunLog "설정 저장 실패 ($Name): $($_.Exception.Message)"
    }
}

function Get-HolidayRule([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    foreach ($rule in @($script:config.HolidayRules)) {
        try { if ([string]$rule.Date -eq $key) { return $rule } } catch { }
    }
    return $null
}

function Set-HolidayRule([string]$Date, [string]$Name, [string]$Action, [string]$MoveTo) {
    # 이 날짜의 예전 규칙은 빼고 나머지를 남깁니다.
    $kept = @()
    foreach ($rule in @($script:config.HolidayRules)) {
        try { if ([string]$rule.Date -ne $Date) { $kept = @($kept) + $rule } } catch { }
    }
    # 그대로 보내는 것이 기본이라 따로 적어 두지 않습니다.
    if ($Action -ne 'normal') {
        $kept = @($kept) + ([pscustomobject]@{ Date = $Date; Name = $Name; Action = $Action; MoveTo = $MoveTo })
    }
    Set-ConfigValue 'HolidayRules' @($kept)
}

# 이 날짜가 어떤 공휴일에서 옮겨 온 날인지 봅니다.
function Get-MovedFromHoliday([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    foreach ($rule in @($script:config.HolidayRules)) {
        try {
            if ([string]$rule.Action -eq 'move' -and [string]$rule.MoveTo -eq $key) { return $rule }
        } catch { }
    }
    return $null
}

# 같은 날 두 번 보내지 않도록, 보낸 날을 적어 둡니다.
# 공휴일을 다른 날로 옮겼는데 그날 원래 일정도 있으면 두 번 갈 수 있습니다.
function Test-AlreadySentToday([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    try { return (@($script:config.SentDays) -contains $key) } catch { return $false }
}

function Add-SentDay([datetime]$Date) {
    $key = $Date.ToString('yyyy-MM-dd')
    try {
        $days = @($script:config.SentDays)
        if ($days -contains $key) { return }
        # 최근 60일치만 남깁니다. 오래된 것은 쓸 일이 없습니다.
        $days = @($days + $key | Sort-Object -Unique | Select-Object -Last 60)
        Set-ConfigValue 'SentDays' @($days)
    } catch { }
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
    if ($holiday) {
        # 그 날짜에 따로 정해 둔 규칙이 있으면 그것을 먼저 따릅니다.
        $rule = Get-HolidayRule $When
        if ($null -ne $rule) {
            $action = [string]$rule.Action
            if ($action -eq 'skip') {
                return "오늘은 $holiday 입니다. 이 날은 보내지 않도록 정해 두셨습니다."
            }
            if ($action -eq 'move') {
                $moveTo = [string]$rule.MoveTo
                return "오늘은 $holiday 입니다. $moveTo 로 옮기도록 정해 두셨습니다."
            }
            # normal 이면 막지 않습니다.
        } elseif ([string]$script:config.HolidayMode -eq '보내지 않음') {
            return "오늘은 $holiday 입니다. 공휴일에는 보내지 않도록 설정되어 있습니다."
        }
    }
    # 다른 공휴일에서 옮겨 온 날인데 이미 오늘 보냈으면 또 보내지 않습니다.
    $moved = Get-MovedFromHoliday $When
    if ($null -ne $moved -and (Test-AlreadySentToday $When)) {
        return "오늘은 이미 보냈습니다. ($([string]$moved.Name) 에서 옮겨 온 날입니다)"
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
# 클립보드에 넣은 뒤 다시 읽어서 정말 들어갔는지 확인합니다.
# 넣기가 성공한 것처럼 보여도 실제로는 반영되지 않거나
# 다른 프로그램이 곧바로 덮어쓰는 경우가 있습니다.
# 확인하지 않고 Ctrl+V 를 누르면 사용자가 복사해 두었던 엉뚱한 내용이 붙습니다.
function Test-ClipboardHasText([string]$Text) {
    try { return ([string][System.Windows.Forms.Clipboard]::GetText() -eq $Text) } catch { return $false }
}

function Set-ClipboardTextSafe([string]$Text) {
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        try {
            [System.Windows.Forms.Clipboard]::SetText($Text)
            Start-Sleep -Milliseconds 90
            if (Test-ClipboardHasText $Text) { return }
        } catch { }
        Start-Sleep -Milliseconds 180
    }
    throw '클립보드에 문구를 넣지 못했습니다. 다른 프로그램이 클립보드를 사용 중일 수 있습니다.'
}

# 여러 파일을 한꺼번에 클립보드에 담습니다.
# 사진을 묶어 보낼 때 이 방법을 씁니다. 한 장씩 보내는 것보다 잘 붙습니다.
function Set-ClipboardFilesSafe([string[]]$Paths) {
    $files = New-Object System.Collections.Specialized.StringCollection
    foreach ($path in @($Paths)) {
        [void]$files.Add((Resolve-Path -LiteralPath ([string]$path)).Path)
    }
    if ($files.Count -eq 0) { throw '클립보드에 담을 파일이 없습니다.' }
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        try { [System.Windows.Forms.Clipboard]::SetFileDropList($files); return }
        catch { Start-Sleep -Milliseconds 200 }
    }
    throw '클립보드에 첨부 파일을 넣지 못했습니다.'
}

function Set-ClipboardFileSafe([string]$Path) {
    Set-ClipboardFilesSafe @($Path)
}

# 창 제목이 목표 방과 같은지 봅니다.
# 목록에 보이는 이름은 길면 뒤가 잘립니다. 그래서 저장된 이름이 창 제목보다 짧을 수 있습니다.
# 앞부분만 같으면 맞다고 볼 수도 있지만, 그러면 이름이 비슷한 다른 방에 보낼 위험이 있습니다.
# 그래서 앞부분이 같은 방이 딱 하나일 때만 맞다고 봅니다. 둘 이상이면 보내지 않습니다.
# 목록에서 창 제목으로 이름을 확정해 둔 방을 보낼 때는 이 표시를 켭니다.
# 켜져 있으면 이름이 정확히 같을 때만 같은 방으로 봅니다.
# 투투 와 토토, 뽀식 과 포식 은 서로 다른 방입니다. 비슷하다고 보내지 않습니다.
# 마지막으로 불러온 저장 문구의 이름입니다. 발송 기록 표에 무엇을 보냈는지 적을 때 씁니다.
$script:lastTemplateName = ''
$script:strictTitleMatch = $false
function Test-RoomTitle([string]$Actual, [string]$Expected) {
    $a = ([string]$Actual).Trim()
    $e = ([string]$Expected).Trim()
    if (-not $a -or -not $e) { return $false }
    if ($a -eq $e) { return $true }
    if ($script:strictTitleMatch) {
        # 정확히 같을 때만 맞다고 봅니다. 인원수만 떼어 내고 글자는 그대로 견줍니다.
        return ((Get-RoomTitleName $a) -ceq (ConvertTo-ExactKey $e))
    }
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
    # 뱃지 뒤에 기호가 바로 오는 경우도 있습니다. '0※자유 홍보 방' 같은 것입니다.
    $name = $name -replace '^[0O](?=[^\s0-9A-Za-z가-힣])', ''
    # 이름이 길면 카카오톡이 뒤를 … 로 줄여 보여 줍니다. 그 표시를 뗍니다.
    $name = $name -replace '[…⋯]+\s*$', ''
    # 화면 글자 인식이 줄 끝에 남기는 찌꺼기입니다.
    # 줄 끝에 남는 찌꺼기입니다. '마케팅 자유 홍보.-' 의 '.-' 같은 것입니다.
    $name = $name -replace '[′`´ˊˋ˙·,\.\-]+$', ''
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
# 채팅방 한 줄의 오른쪽에는 마지막 대화 시각이 있습니다.
# 이것이 그 줄이 "방 이름 줄" 이라는 표시입니다. 미리보기 줄에는 없습니다.
#
# 예전에는 시각을 알아볼 때 가운뎃점(:)을 반드시 요구했습니다.
# 그런데 화면 글자 인식은 작은 가운뎃점을 자주 놓칩니다.
#   실제 화면  오전 10:20   ->  읽힌 것  오전 10•20 / 오전 1059
# 그래서 시각을 하나도 못 알아봤고, 그 결과 아래쪽 대비책이 발동해
# 미리보기 대화내용이 방 이름으로 들어갔습니다.
# 이제 사이 글자가 무엇이든, 아예 없어도 시각으로 봅니다.
function Test-RowAnchorText([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return $false }
    # 오전/오후 가 붙은 시각.  오전 10:20 / 오전 10•20 / 오전 1020
    if ($t -match '^(오전|오후)\s*\d{1,2}\s*[^\d가-힣A-Za-z]{0,3}\s*\d{2}$') { return $true }
    if ($t -match '^(오전|오후)\s*\d{3,4}$') { return $true }
    # 오전/오후 없이 시각만.  10:20 / 10•20
    if ($t -match '^\d{1,2}\s*[^\d가-힣A-Za-z]{1,3}\s*\d{2}$') { return $true }
    if ($t -match '^(어제|오늘|그저께)$') { return $true }
    # 날짜.  2026-05-18 / 2026•05-18 / 5.18
    if ($t -match '^\d{4}\s*[^\d가-힣A-Za-z]{1,3}\s*\d{1,2}\s*[^\d가-힣A-Za-z]{1,3}\s*\d{1,2}\s*\.?$') { return $true }
    if ($t -match '^\d{1,2}\s*[.\-/]\s*\d{1,2}\s*\.?$') { return $true }
    return $false
}


# OCR 로 읽은 줄에서 방 이름만 골라냅니다. 순수 함수라 자체 점검으로 검증합니다.
# 화면에서 읽은 시각 표기를 보기 좋게 되돌립니다.
#   오전 10•20 -> 오전 10:20
#   오전 1051  -> 오전 10:51
# 판단에는 쓰지 않고 기록에만 씁니다. 원래 글자를 억지로 바꾸지 않기 위해서입니다.
function ConvertTo-ReadableTime([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return '' }
    $m = [regex]::Match($t, '^(오전|오후)?\s*(\d{1,2})\s*[^\d가-힣A-Za-z]{0,3}\s*(\d{2})$')
    if ($m.Success) {
        $ampm = $m.Groups[1].Value
        $hh = $m.Groups[2].Value
        $mm = $m.Groups[3].Value
        if ($ampm) { return "$ampm $($hh):$mm" }
        return "$($hh):$mm"
    }
    # 오전 1051 처럼 붙어 나온 경우
    $m2 = [regex]::Match($t, '^(오전|오후)\s*(\d{3,4})$')
    if ($m2.Success) {
        $digits = $m2.Groups[2].Value
        $mm = $digits.Substring($digits.Length - 2)
        $hh = $digits.Substring(0, $digits.Length - 2)
        return "$($m2.Groups[1].Value) $($hh):$mm"
    }
    return $t
}

# 시각·날짜·안읽음 숫자처럼 제목이 아닌 것을 걸러 냅니다.
# 화면 글자 인식이 이런 것을 이름 구간 안쪽으로 잘못 잡는 경우가 있습니다.
function Test-NotTitleToken([string]$Text) {
    $t = ([string]$Text).Trim()
    if (-not $t) { return $true }
    if (Test-RowAnchorText $t) { return $true }
    # 숫자만 있는 짧은 조각은 안 읽은 개수입니다.
    if ($t -match '^[@()\[\]]?\s*\d{1,4}\s*[@()\[\]]?$') { return $true }
    return $false
}

# 채팅 목록 한 줄의 생김새입니다.
#
#   [사진]  방 이름            시각      <- 이름과 시각은 같은 높이
#           마지막 대화내용    안읽음    <- 이름보다 아래
#
# 그래서 시각이 있는 높이의 글자만 방 이름으로 봅니다.
# 그 아래 글자는 마지막 대화내용이며, 절대로 이름으로 쓰지 않습니다.
#
# 제목을 못 읽었다고 아래 대화내용을 대신 쓰지 않습니다.
# 엉뚱한 이름을 넣느니 "제목 인식 실패" 가 낫습니다.
function Get-ChatRoomRowsFromOcr([object[]]$Lines, [int]$Width) {
    $rows = @()
    $all = @($Lines)
    if ($all.Count -eq 0 -or $Width -le 0) { return @() }

    # 이름이 있는 가로 구간과, 시각이 있는 가로 구간을 나눕니다.
    # 가로 위치는 목록 폭에 견주어 정하므로 화면 배율이 달라도 같습니다.
    $nameLeft = $Width * 0.13
    # 오른쪽 끝을 46% 로 좁게 잡으면 긴 제목의 뒷부분이 잘려 나갑니다.
    # 실제 화면에서 시각은 75% 언저리, 안 읽은 개수는 85% 언저리에 있으므로
    # 72% 까지는 넓혀도 그것들이 섞이지 않습니다.
    # 혹시 섞이더라도 Test-NotTitleToken 이 한 번 더 걸러 냅니다.
    $nameRight = $Width * 0.72
    $timeLeft = $Width * 0.72

    $nameZone = @($all | Where-Object { $_.Left -ge $nameLeft -and $_.Left -le $nameRight } | Sort-Object Top)
    $anchors = @($all | Where-Object { $_.Left -ge $timeLeft -and (Test-RowAnchorText $_.Text) } | Sort-Object Top)
    if ($anchors.Count -eq 0) {
        # 시각을 하나도 못 읽었습니다.
        # 여기서 다른 글자를 제목으로 추측하면 대화내용이 이름으로 들어갑니다.
        # 예전에 그렇게 해서 문제가 생겼습니다. 이제 추측하지 않습니다.
        $script:lastAnchorMissing = $true
        if ($script:debugTitleRead) { Write-RunLog '  TITLE_ANCHOR_NOT_FOUND — 시각을 하나도 못 읽어 제목을 정하지 않았습니다.' }
        return @()
    }
    $script:lastAnchorMissing = $false

    # 같은 줄로 볼 세로 오차입니다.
    # 글자 높이를 기준으로 잡으므로 화면 배율이 100% 든 150% 든 알아서 맞습니다.
    $band = 14
    $heights = @()
    foreach ($line in $nameZone) {
        $h = 0
        try { $h = [int]$line.Height } catch { $h = 0 }
        if ($h -gt 0) { $heights += $h }
    }
    if ($heights.Count -gt 0) {
        $band = [int][Math]::Max(8, [Math]::Round((($heights | Measure-Object -Average).Average) * 1.0))
    }

    for ($i = 0; $i -lt $anchors.Count; $i++) {
        $anchor = $anchors[$i]
        $rowTop = $anchor.Top - $band
        $rowEnd = if ($i + 1 -lt $anchors.Count) { $anchors[$i + 1].Top - $band } else { [int]::MaxValue }

        # 제목은 시각과 같은 높이이거나 살짝 위에 있습니다.
        # 실제로 재 보니 제목은 시각보다 0~7px 위였고,
        # 미리보기 대화내용은 시각보다 12px 넘게 아래였습니다.
        # 그래서 위아래 방향까지 봅니다. 이러면 여유가 훨씬 넉넉해집니다.
        $titleParts = @()
        foreach ($line in $nameZone) {
            $offset = $anchor.Top - $line.Top
            if ($offset -lt -2 -or $offset -gt $band) { continue }
            # 시각·날짜·안읽음 숫자가 이름 구간에 잘못 잡히면 제목에서 뺍니다.
            if (Test-NotTitleToken $line.Text) { continue }
            $titleParts = @($titleParts) + $line
        }
        # 한 제목이 여러 조각으로 읽힐 수 있습니다.
        # 화면에 보이는 순서(왼쪽부터)로 이어 붙입니다. 인식 결과 순서는 믿지 않습니다.
        $titleRaw = ''
        if ($titleParts.Count -gt 0) {
            $sorted = @($titleParts | Sort-Object Left)
            $titleRaw = (@($sorted | ForEach-Object { ([string]$_.Text).Trim() }) -join ' ').Trim()
        }

        # 그 아래부터 다음 줄 전까지가 마지막 대화내용입니다.
        $messageParts = @()
        foreach ($line in $nameZone) {
            if (($anchor.Top - $line.Top) -ge -2) { continue }
            if ($line.Top -ge $rowEnd) { continue }
            $messageParts = @($messageParts) + [string]$line.Text
        }

        $titleText = ''
        if ($titleRaw) { $titleText = ConvertTo-RoomCandidate $titleRaw }
        # 확실한 제목인지 봅니다.
        #   시각이 있고, 그 높이에 이름 후보가 있고, 이름 구간 안이고,
        #   대화내용보다 위쪽이면 확실합니다.
        $confidence = 'low'
        if ($titleText -and $titleParts.Count -ge 1) { $confidence = 'high' }
        $rows = @($rows) + ([pscustomobject]@{
            Title = $titleText
            RawTitle = $titleRaw
            LastMessage = ($messageParts -join ' ')
            Time = [string]$anchor.Text
            TimeReadable = ConvertTo-ReadableTime $anchor.Text
            Top = $rowTop
            Confidence = $confidence
            Ok = ($confidence -eq 'high')
        })
    }
    return @($rows)
}

# 방 이름만 뽑아 돌려줍니다. 제목을 못 읽은 줄은 넣지 않습니다.
function Get-RoomNamesFromOcrLines([object[]]$Lines, [int]$Width) {
    $rows = @(Get-ChatRoomRowsFromOcr $Lines $Width)
    $result = @()
    $failed = 0
    foreach ($row in $rows) {
        if (-not $row.Ok) {
            $failed++
            # 못 읽었다고 아래 대화내용을 대신 쓰지 않습니다.
            if ($script:debugTitleRead) {
                Write-RunLog "  [줄] 시각=$($row.TimeReadable) / 제목=미확정 / 결과=TITLE_READ_FAILED"
                Write-RunLog "       그 줄의 대화내용='$($row.LastMessage)' (제목으로 쓰지 않았습니다)"
            }
            continue
        }
        if ($script:debugTitleRead) {
            Write-RunLog "  [줄] 시각=$($row.Time) -> $($row.TimeReadable)"
            Write-RunLog "       제목='$($row.Title)' (읽힌 그대로: '$($row.RawTitle)') / 확실함=$($row.Confidence)"
            Write-RunLog "       대화내용='$($row.LastMessage)'"
        }
        if (@($result) -notcontains [string]$row.Title) { $result = @($result) + [string]$row.Title }
    }
    $script:lastTitleReadFailures = $failed
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

# 화면 글자 인식은 글자가 클수록 잘 맞습니다.
# 카카오톡 목록 글자는 작아서 그대로 읽히면 자주 틀립니다.
#   확대 2배: [트4규형] [서인금융진흥원]
#   확대 4배: [택규형]  [서민금융진흥원]
# 실제로 재 보니 4배가 정확하고 속도도 2배와 거의 같았습니다.
# 다만 창이 크면 그림도 커지므로, 가로 1300픽셀 언저리가 되게 배율을 정합니다.
function Get-OcrScaleFor([object]$Window) {
    $width = 0
    try { $width = [int]$Window.Width } catch { }
    if ($width -le 0) { return 4 }
    $scale = [int][Math]::Round(1300.0 / $width)
    if ($scale -lt 2) { $scale = 2 }
    if ($scale -gt 4) { $scale = 4 }
    return $scale
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
            # 글자 높이도 함께 둡니다.
            # 같은 줄인지 판단할 때 이 높이를 쓰면 화면 배율이 달라도 알아서 맞습니다.
            $bottom = ($words | ForEach-Object { $_.BoundingRect.Y + $_.BoundingRect.Height } | Measure-Object -Maximum).Maximum
            $lines += [pscustomobject]@{
                Text = [string]$line.Text
                Left = [int]($left / $Scale)
                Top = [int]($top / $Scale)
                Height = [Math]::Max(1, [int](($bottom - $top) / $Scale))
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
    # 같은 이름이 몇 번 나왔는지 세어 둡니다.
    # 이름이 같은 방이 여럿이면 이름만으로는 서로를 가릴 수 없어 알려 드려야 합니다.
    $seenCount = @{}
    # 제목을 못 읽은 줄이 몇 개인지 모아 둡니다.
    # 못 읽은 줄은 이름 목록에 넣지 않습니다. 엉뚱한 대화내용을 넣느니 빼는 것이 낫습니다.
    $titleFailures = 0
    $useMouse = $false
    $pageLimit = [Math]::Max(1, [Math]::Min(60, $MaxPages))

    for ($page = 0; $page -lt $pageLimit; $page++) {
        $before = $names.Count
        $found = @(Get-RoomNamesFromOcrLines (Get-OcrLines $list (Get-OcrScaleFor $list)) $list.Width)
        $titleFailures += [int]$script:lastTitleReadFailures
        foreach ($name in $found) {
            $key = [string]$name
            if ($seenCount.ContainsKey($key)) { $seenCount[$key] = $seenCount[$key] + 1 }
            else { $seenCount[$key] = 1 }
            if (-not $names.Contains($key)) { $names.Add($key) }
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

    if ($titleFailures -gt 0) {
        Write-RunLog "제목을 읽지 못한 줄 $($titleFailures)개는 목록에 넣지 않았습니다. (대화내용을 이름으로 쓰지 않습니다)"
    }
    # 같은 이름이 여러 화면에서 나오는 것은 겹쳐 읽힌 것일 수 있지만,
    # 한 화면 안에서 여러 번 나오면 정말로 이름이 같은 방이 여럿인 것입니다.
    $dupNames = @()
    foreach ($entry in $seenCount.GetEnumerator()) {
        if ($entry.Value -gt $pages) { $dupNames += [string]$entry.Key }
    }
    if ($dupNames.Count -gt 0) {
        Write-RunLog "이름이 같은 방이 있습니다: $(($dupNames | Select-Object -First 5) -join ', ')"
        Write-RunLog "  이름만으로는 서로를 가릴 수 없어 하나로 다룹니다. 카카오톡에서 이름을 다르게 해 주시면 정확해집니다."
    }
    return [pscustomobject]@{
        Names = @($names | Sort-Object -Unique)
        Type = $roomType
        ViewName = $layout.ViewName
        Pages = $pages
        TitleFailures = $titleFailures
    }
}

# ---------------------------------------------------------------------------
# 검색으로 방 열기 · 발송
# ---------------------------------------------------------------------------
# 목록을 위에서부터 훑어 방을 찾아 엽니다.
# 검색보다 느리지만, 검색창이 열리지 않는 환경에서도 확실히 동작합니다.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 사용자가 열어 둔 채팅방 창 읽기
# ---------------------------------------------------------------------------
# 이것이 가장 정확한 방법입니다.
# 채팅방 창이 열려 있으면 그 창의 제목이 곧 방 이름입니다.
# 창 제목은 화면 글자 인식이 아니라 윈도우가 알려 주는 진짜 글자라 틀릴 수가 없습니다.
# 목록을 훑을 필요도, 글자를 읽을 필요도 없습니다.
#
# 채팅방 창인지 어떻게 아는가:
#   1) 카카오톡 프로세스의 창이고
#   2) 보이는 창이고
#   3) 메인 창(채팅 목록)이 아니고
#   4) 글 입력칸(RICHEDIT50W)이 있고
#   5) 대화 목록(EVA_VH_ListControl_Dblclk)이 있다
# 다섯 가지를 모두 만족해야 채팅방 창입니다.
# 미리보기 창이나 알림 창은 4)나 5)가 없어서 걸러집니다.

# 이 창이 채팅방 창인지 가리는 규칙입니다.
# 규칙만 따로 떼어 두어야 카카오톡 없이도 시험할 수 있습니다.
#
# 카카오톡 창을 실제로 들여다보면 이렇게 생겼습니다.
#   메인 창    : EVA_Window_Dblclk '카카오톡'  자식에 ChatRoomListView / ContactListView / OnlineMainView
#   채팅방 창  : EVA_Window_Dblclk '방 이름'   자식에 RICHEDIT50W + EVA_VH_ListControl_Dblclk
#   알림·툴팁  : tooltips_class32, EVA_Window  등 다른 클래스
#   빈 창      : EVA_Window_Dblclk ''          제목이 없음
# 그래서 클래스와 자식 구성을 함께 봐야 채팅방 창만 정확히 골라낼 수 있습니다.
function Test-ChatWindowShape([string]$Title, [string]$ClassName, [int]$Width, [int]$Height,
                              [bool]$Visible, [bool]$HasMainView, [bool]$HasInput, [bool]$HasList) {
    if (-not $Visible) { return $false }
    # 채팅방 창은 반드시 이 클래스입니다. 툴팁이나 알림 창은 여기서 걸러집니다.
    if (([string]$ClassName) -cne 'EVA_Window_Dblclk') { return $false }
    if ($Width -lt 200 -or $Height -lt 200) { return $false }
    $t = ([string]$Title).Trim()
    if (-not $t) { return $false }
    if ($t -eq '카카오톡' -or $t -eq 'KakaoTalk') { return $false }
    # 채팅 목록·친구 목록 화면을 품고 있으면 메인 창입니다. 채팅방이 아닙니다.
    if ($HasMainView) { return $false }
    # 글 입력칸이 없으면 보낼 수 없는 창입니다. (사진 미리보기, 알림 등)
    if (-not $HasInput) { return $false }
    # 대화 목록이 없으면 채팅방이 아닙니다. (프로필, 설정 등)
    if (-not $HasList) { return $false }
    return $true
}

# 이 창이 카카오톡 메인 창인지 자식 화면 이름으로 봅니다.
function Test-HasMainView([object]$Window) {
    try {
        foreach ($child in [NativeKakao]::GetChildWindows($Window.Handle)) {
            if ([string]$child.Title -match '^(ChatRoomListView|ContactListView|OnlineMainView|MoreView)') { return $true }
        }
    } catch { }
    return $false
}

function Get-OpenChatRooms {
    $rooms = @()
    $seen = @{}
    foreach ($process in (Get-KakaoProcesses)) {
        $windows = @()
        try { $windows = @([NativeKakao]::GetWindows($process.Id)) } catch { continue }
        foreach ($window in $windows) {
            # 자식 컨트롤을 뒤지는 것은 값이 비싸므로, 싼 조건을 먼저 봅니다.
            if (-not (Test-ChatWindowShape $window.Title $window.ClassName $window.Width $window.Height $window.Visible $false $true $true)) { continue }
            if (Test-HasMainView $window) { continue }
            $inputBox = $null
            try { $inputBox = Get-ChatInputControl $window } catch { }
            $listBox = $null
            try { $listBox = Get-ChatListControl $window } catch { }
            if (-not (Test-ChatWindowShape $window.Title $window.ClassName $window.Width $window.Height $window.Visible $false ($null -ne $inputBox) ($null -ne $listBox))) { continue }

            $name = Get-RoomTitleName $window.Title
            if (-not $name) { continue }
            if ($seen.ContainsKey($name)) { continue }
            $seen[$name] = $true
            $rooms += [pscustomobject]@{
                Name = $name
                Title = [string]$window.Title
                Handle = $window.Handle
                Kind = (Get-RoomKindFromTitle $window.Title '')
                Minimized = (Test-WindowMinimized $window)
            }
        }
    }
    return @($rooms)
}
# 이름으로 열려 있는 채팅방 창을 찾습니다. 정확히 같은 이름일 때만 찾습니다.
# 창이 아직 살아 있는지도 다시 확인합니다. 그 사이에 닫혔을 수 있기 때문입니다.
function Find-OpenChatWindow([string]$Name) {
    $want = ConvertTo-ExactKey $Name
    if (-not $want) { return $null }
    foreach ($room in (Get-OpenChatRooms)) {
        if ($room.Name -cne $want) { continue }
        $live = $null
        try { $live = [NativeKakao]::GetWindow($room.Handle) } catch { }
        if ($null -eq $live -or $live.Width -le 0 -or $live.Height -le 0) { continue }
        # 최소화되어 있으면 되살립니다. 최소화된 창에는 글자가 잘 들어가지 않습니다.
        if (Test-WindowMinimized $live) {
            try {
                [void][NativeKakao]::ShowWindow($live.Handle, 9)
                Start-Sleep -Milliseconds 250
                $live = [NativeKakao]::GetWindow($room.Handle)
            } catch { }
        }
        return $live
    }
    return $null
}

# 채팅방 목록 — 카카오톡에 보이는 그대로 읽어 저장합니다
# ---------------------------------------------------------------------------
# 예전 방식은 이랬습니다.
#   방 이름을 쳐 넣는다 -> 검색한다 -> 검색 결과를 글자로 읽는다 -> 보낸다
# 글자로 읽는 단계가 두 번 들어가서, '뽀식'을 '포식'으로 읽으면 그대로 틀렸습니다.
#
# 새 방식은 이렇습니다.
#   카카오톡 목록을 통째로 읽는다 -> 방을 하나 열어 창 제목으로 이름을 확정한다
#   -> 확정한 이름을 저장한다 -> 저장한 목록만 보고 보낸다
# 창 제목은 화면 글자 인식이 아니라 윈도우가 알려 주는 진짜 글자입니다.
# 그래서 뽀식은 언제나 뽀식입니다.

# 이름을 견줄 때 쓰는 열쇠입니다.
# 앞뒤 빈칸과 사이의 겹친 빈칸만 정리하고, 글자는 하나도 바꾸지 않습니다.
# 비슷한 정도로 견주지 않습니다. 투투 와 토토 는 다른 방입니다.
function ConvertTo-ExactKey([string]$Text) {
    $t = [string]$Text
    if (-not $t) { return '' }
    # 눈에 안 보이는 글자만 없앱니다. 이모지를 잇는 글자(ZWJ)는 건드리지 않습니다.
    $t = $t -replace '[​﻿]', ''
    $t = ($t -replace '\s+', ' ').Trim()
    return $t
}

# 카카오톡은 단체방 창 제목 뒤에 인원수를 붙입니다.  예: 우리반 공지방 (24)
# 인원수는 사람이 드나들면 바뀌므로 이름의 일부로 보지 않습니다.
function Get-RoomTitleName([string]$Title) {
    $t = ConvertTo-ExactKey $Title
    if (-not $t) { return '' }
    $t = $t -replace '\s*\(\s*\d{1,6}\s*\)\s*$', ''
    return $t.Trim()
}

# 두 이름이 같은 방인지 봅니다. 정확히 같아야 같은 방입니다.
function Test-SameRoomExact([string]$A, [string]$B) {
    $x = ConvertTo-ExactKey $A
    $y = ConvertTo-ExactKey $B
    if (-not $x -or -not $y) { return $false }
    return ($x -ceq $y)
}

# ---------------------------------------------------------------------------
# 저장 메시지 — 자주 보내는 문구를 이름을 붙여 담아 둡니다
# ---------------------------------------------------------------------------
#   { Name = '기본 안내문'; Text = '...' }
function Get-Templates {
    $rows = @()
    foreach ($item in @($script:config.Templates)) {
        if ($null -eq $item) { continue }
        $name = ([string]$item.Name).Trim()
        if (-not $name) { continue }
        $rows += [pscustomobject]@{ Name = $name; Text = [string]$item.Text }
    }
    return @($rows)
}

function Set-Templates([object[]]$Rows) {
    Set-ConfigValue 'Templates' @($Rows)
    try { Save-Config $script:config } catch { }
}

function Find-Template([string]$Name) {
    $key = ([string]$Name).Trim()
    if (-not $key) { return $null }
    foreach ($row in (Get-Templates)) { if ($row.Name -eq $key) { return $row } }
    return $null
}

function Get-Roster {
    $rows = @()
    foreach ($item in @($script:config.Roster)) {
        if ($null -eq $item) { continue }
        $name = ConvertTo-ExactKey ([string]$item.Name)
        if (-not $name) { continue }
        $rows += [pscustomobject]@{
            Name = $name
            ListText = [string]$item.ListText
            Kind = $(if ([string]$item.Kind) { [string]$item.Kind } else { 'unknown' })
            Order = [int]$item.Order
            Verified = [bool]$item.Verified
            LastSeen = [string]$item.LastSeen
        }
    }
    return @($rows)
}

function Set-Roster([object[]]$Rows) {
    Set-ConfigValue 'Roster' @($Rows)
    Set-ConfigValue 'RosterScannedAt' (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}

function Find-RosterEntry([string]$Name) {
    $key = ConvertTo-ExactKey $Name
    if (-not $key) { return $null }
    foreach ($row in (Get-Roster)) { if ($row.Name -ceq $key) { return $row } }
    return $null
}

function Get-RosterKindText([string]$Kind) {
    switch ([string]$Kind) {
        'open'   { return '오픈채팅' }
        'group'  { return '일반채팅(단체)' }
        'direct' { return '일반채팅(1:1)' }
        default  { return '일반채팅' }
    }
}

# 방을 하나 열어 창 제목으로 이름을 확정하고 다시 닫습니다.
# 목록을 글자로 읽은 이름은 틀릴 수 있지만, 창 제목은 틀리지 않습니다.
function Read-RoomTitleAtRow([object]$List, [object]$Row, [IntPtr]$MainHandle) {
    $chat = Get-SingleChatWindow (Open-RoomAtLine $List $Row $MainHandle)
    if ($null -eq $chat) {
        return [pscustomobject]@{ Ok = $false; Title = ''; Kind = 'unknown'; Reason = 'ROOM_OPEN_FAILED' }
    }
    $rawTitle = [string]$chat.Title
    $name = Get-RoomTitleName $rawTitle
    $kind = Get-RoomKindFromTitle $rawTitle ''
    try { Close-ChatWindow $chat } catch { }
    if (-not $name) {
        return [pscustomobject]@{ Ok = $false; Title = ''; Kind = 'unknown'; Reason = 'TITLE_EMPTY' }
    }
    return [pscustomobject]@{ Ok = $true; Title = $name; Kind = $kind; Reason = '' }
}

$script:rosterCancel = $false
function Stop-RosterScan { $script:rosterCancel = $true }

# 카카오톡 목록을 위에서 끝까지 훑어 방을 모읍니다.
#   Exact 가 참이면 방을 하나씩 열어 창 제목으로 이름을 확정합니다. 느리지만 정확합니다.
#   Exact 가 거짓이면 화면 글자만 읽습니다. 빠르지만 이름이 틀릴 수 있습니다.
# 같은 방은 한 번만 담습니다. 정확히 같은 이름일 때만 같은 방으로 봅니다.
function Invoke-RosterScan([bool]$Exact, [int]$MaxPages) {
    $script:rosterCancel = $false
    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { throw $ready.Reason }
    $layout = $ready.Layout
    $main = $layout.Main
    if ($null -eq $layout.List) {
        throw '채팅 목록을 찾지 못했습니다. 카카오톡 창을 조금 더 크게 하고 목록이 보이게 해 주세요.'
    }
    if (-not (Initialize-Ocr)) {
        throw "화면의 글자를 읽을 수 없습니다.`r`n$($script:ocrError)"
    }

    $viewType = Get-RoomTypeFromViewName $layout.ViewName
    $fromOpenTab = ($viewType -eq $script:RoomTypeOpen)
    $pageLimit = [Math]::Max(1, [Math]::Min(60, $MaxPages))

    # 담은 방들입니다. 열쇠는 정확한 이름입니다.
    $found = New-Object System.Collections.Specialized.OrderedDictionary
    # 이미 열어 본 줄입니다. 같은 줄을 두 번 열지 않으려고 적어 둡니다.
    $openedRows = @{}
    $openFailures = 0
    $titleFailures = 0
    $pages = 0
    $noChange = 0

    Move-ListToTop $layout.List $pageLimit
    $howText = if ($Exact) { '방을 열어 이름 확정 (정확)' } else { '화면 글자만 읽기 (빠름)' }
    Write-RunLog ("목록 읽기 시작: {0} / {1}" -f $layout.ViewName, $howText)

    for ($page = 0; $page -lt $pageLimit; $page++) {
        if ($script:rosterCancel) { Write-RunLog '목록 읽기를 멈췄습니다.'; break }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -eq $fresh.List) { break }
        $list = $fresh.List
        $before = $found.Count

        $rows = @(Get-ChatRoomRowsFromOcr (Get-OcrLines $list (Get-OcrScaleFor $list)) $list.Width)
        if ($rows.Count -eq 0) { break }
        $pages++

        foreach ($row in $rows) {
            if ($script:rosterCancel) { break }
            $ocrName = ConvertTo-ExactKey ([string]$row.Title)

            if (-not $Exact) {
                # 빠른 방식입니다. 제목을 못 읽은 줄은 담지 않습니다.
                # 대화내용을 이름 대신 쓰지 않습니다. 없는 것이 틀린 것보다 낫습니다.
                if (-not $row.Ok -or -not $ocrName) { $titleFailures++; continue }
                if (-not $found.Contains($ocrName)) {
                    $kindGuess = if ($fromOpenTab) { 'open' } else { 'unknown' }
                    $found.Add($ocrName, [pscustomobject]@{
                        Name = $ocrName; ListText = $ocrName; Kind = $kindGuess; Verified = $false
                    })
                }
                continue
            }

            # 정확한 방식입니다. 줄을 열어 창 제목을 읽습니다.
            # 제목을 못 읽은 줄도 엽니다. 위치만 알면 되기 때문입니다.
            $rowKey = if ($ocrName) { $ocrName } else { ('행' + [string]$row.Top) }
            if ($openedRows.ContainsKey($rowKey)) { continue }
            if ($ocrName -and $found.Contains($ocrName)) { continue }

            $result = Read-RoomTitleAtRow $list $row $main.Handle
            $openedRows[$rowKey] = $true
            if (-not $result.Ok) {
                $openFailures++
                if ($script:debugTitleRead) {
                    Write-RunLog ("  [줄] 화면글자='{0}' -> 열지 못했습니다 ({1})" -f $ocrName, $result.Reason)
                }
                continue
            }
            $name = $result.Title
            $kind = $result.Kind
            if ($fromOpenTab) { $kind = 'open' }
            if ($found.Contains($name)) { continue }
            $found.Add($name, [pscustomobject]@{
                Name = $name
                ListText = $(if ($ocrName) { $ocrName } else { $name })
                Kind = $kind
                Verified = $true
            })
            if ($ocrName -and $ocrName -cne $name) {
                Write-RunLog ("  이름 바로잡음: 화면에는 '{0}' 으로 읽혔지만 실제 이름은 '{1}' 입니다." -f $ocrName, $name)
            }
            Set-StatusPill ("목록 읽는 중 — $($found.Count)개") 'run'
            [System.Windows.Forms.Application]::DoEvents()
        }

        if ($found.Count -eq $before) { $noChange++ } else { $noChange = 0 }
        if ($noChange -ge 2) { break }

        $notches = [Math]::Max(3, [Math]::Min(8, $rows.Count - 1))
        Move-ListByWheel $list 'down' $notches
        Start-Sleep -Milliseconds 200
    }

    Move-ListToTop $layout.List $pages

    $out = @()
    $order = 0
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    foreach ($key in @($found.Keys)) {
        $item = $found[$key]
        $out += [pscustomobject]@{
            Name = $item.Name
            ListText = $item.ListText
            Kind = $item.Kind
            Order = $order
            Verified = $item.Verified
            LastSeen = $stamp
        }
        $order++
    }
    return [pscustomobject]@{
        Rows = @($out)
        Pages = $pages
        ViewName = $layout.ViewName
        FromOpenTab = $fromOpenTab
        OpenFailures = $openFailures
        TitleFailures = $titleFailures
        Cancelled = [bool]$script:rosterCancel
    }
}

# 새로 읽은 목록을 저장된 목록과 견주어 무엇이 달라졌는지 알려 줍니다.
# 오픈채팅 탭만 읽었다면 일반채팅 방은 지우지 않습니다. 안 본 것이지 없어진 것이 아닙니다.
function Merge-RosterScan([object]$Scan, [bool]$ReplaceAll) {
    $old = @(Get-Roster)
    $oldByName = @{}
    foreach ($row in $old) { $oldByName[$row.Name] = $row }

    $new = @($Scan.Rows)
    $newByName = @{}
    foreach ($row in $new) { $newByName[$row.Name] = $row }

    $added = @()
    foreach ($row in $new) { if (-not $oldByName.ContainsKey($row.Name)) { $added += $row.Name } }

    # 이번에 본 종류의 방 가운데 안 보인 것만 없어진 것으로 봅니다.
    $scanKinds = @{}
    foreach ($row in $new) { $scanKinds[$row.Kind] = $true }
    $sawOpen = ([bool]$Scan.FromOpenTab -or $scanKinds.ContainsKey('open'))
    $removed = @()
    foreach ($row in $old) {
        if ($newByName.ContainsKey($row.Name)) { continue }
        if ($ReplaceAll) { $removed += $row.Name; continue }
        $isOpen = ($row.Kind -eq 'open')
        if ($isOpen -eq $sawOpen) { $removed += $row.Name }
    }

    # 합칩니다. 새로 읽은 것을 앞에 두고, 이번에 안 본 방은 뒤에 그대로 둡니다.
    $merged = @()
    $order = 0
    foreach ($row in $new) {
        $row.Order = $order; $order++
        $merged += $row
    }
    if (-not $ReplaceAll) {
        foreach ($row in $old) {
            if ($newByName.ContainsKey($row.Name)) { continue }
            if (@($removed) -contains $row.Name) { continue }
            $row.Order = $order; $order++
            $merged += $row
        }
    }
    Set-Roster $merged
    return [pscustomobject]@{
        Total = @($merged).Count
        Added = @($added)
        Removed = @($removed)
        Kept = (@($merged).Count - @($added).Count)
    }
}

# ---------------------------------------------------------------------------
# 검색으로 방을 찾던 옛 방식은 없앴습니다.
# ---------------------------------------------------------------------------
# 예전에는 이렇게 했습니다.
#   방 이름을 검색창에 넣는다 -> 검색 결과를 화면 글자로 읽는다 -> 그 줄을 연다
# 글자로 읽는 단계에서 '뽀식'이 '포식'으로 읽히면 그대로 엉뚱한 방이 열렸습니다.
# 이제는 카카오톡 목록을 그대로 훑어 줄을 열고, 창 제목으로 방을 확인합니다.
#   목록 읽기  : Invoke-RosterScan
#   한 방 열기 : Open-RoomFromRoster
#   발송       : Invoke-RosterSend

# 첨부가 실제로 붙는지만 확인합니다.

# 방 하나를 목록에서 찾아 엽니다. 검색은 쓰지 않습니다.
# 열고 나서 창 제목이 정확히 같을 때만 그 창을 돌려줍니다.
# 다른 방이 열리면 닫고 계속 찾습니다. 그래서 엉뚱한 방이 돌아오지 않습니다.
function Open-RoomFromRoster([string]$Name, [int]$MaxPages = 0) {
    $want = ConvertTo-ExactKey $Name
    if (-not $want) { return $null }
    if ($MaxPages -le 0) { $MaxPages = [Math]::Max(1, [int]$script:config.ScanPages) }
    $listText = $want
    $entry = Find-RosterEntry $want
    if ($null -ne $entry -and $entry.ListText) { $listText = $entry.ListText }

    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { return $null }
    $main = $ready.Layout.Main
    Move-ListToTop $ready.Layout.List $MaxPages
    $notTarget = @{}

    for ($page = 0; $page -lt $MaxPages; $page++) {
        $donePage = @{}
        $guard = 0
        $rowsSeen = 0
        while ($guard -lt 20) {
            $guard++
            $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
            if ($null -eq $fresh.List) { return $null }
            $list = $fresh.List
            $rows = @(Get-ChatRoomRowsFromOcr (Get-OcrLines $list (Get-OcrScaleFor $list)) $list.Width)
            if ($rows.Count -eq 0) { break }
            $rowsSeen = $rows.Count
            $pick = $null
            foreach ($row in $rows) {
                $posKey = 'P:' + [string]([int]([Math]::Round(([double]$row.Top) / 6.0)))
                if ($donePage.ContainsKey($posKey)) { continue }
                if ($notTarget.ContainsKey((Get-RowKey $row))) { continue }
                if (Test-RowLooksLike $row $want $listText) { $pick = $row; break }
            }
            if ($null -eq $pick) { break }
            $donePage['P:' + [string]([int]([Math]::Round(([double]$pick.Top) / 6.0)))] = $true
            $chat = Get-SingleChatWindow (Open-RoomAtLine $list $pick $main.Handle)
            if ($null -eq $chat) { $notTarget[(Get-RowKey $pick)] = $true; continue }
            if ((Get-RoomTitleName ([string]$chat.Title)) -ceq $want) { return $chat }
            try { Close-ChatWindow $chat } catch { }
            $notTarget[(Get-RowKey $pick)] = $true
        }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -eq $fresh.List) { return $null }
        Move-ListByWheel $fresh.List 'down' ([Math]::Max(3, [Math]::Min(8, $rowsSeen - 1)))
        Start-Sleep -Milliseconds 200
    }
    return $null
}
# 붙여 본 뒤 바로 치우고 보내지 않습니다.
# 카카오톡 판이나 화면 배율이 사람마다 달라서, 실제로 보내기 전에
# 이 확인을 한 번 해 보면 첨부가 될 환경인지 미리 알 수 있습니다.
function Invoke-AttachmentCheck([string]$Room, [string]$Path) {
    $report = @()
    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { return [pscustomobject]@{ Ok = $false; Text = [string]$ready.Reason } }
    $chat = Open-RoomFromRoster $Room
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



# 도중에 잘못됐을 때 화면을 안전한 상태로 되돌립니다.
# 미리보기 창이나 팝업이 떠 있는 채로 다음 일을 하면 엉뚱한 곳에 입력됩니다.
#   1) 열려 있는 미리보기 창을 닫습니다
#   2) 열려 있는 파일 선택창을 닫습니다
#   3) 채팅창의 팝업을 걷어냅니다
#   4) 입력칸에 남은 첨부 초안을 치웁니다
# 되돌리지 못하면 거짓을 돌려줍니다. 그때는 이 방을 실패로 둡니다.
function Reset-ChatAfterFailure([object]$Chat, [object]$InputBox) {
    $ok = $true
    # 1) 미리보기 창
    try {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible) { continue }
                if (-not [string]::IsNullOrWhiteSpace($window.Title)) { continue }
                if ($window.Width -lt 220 -or $window.Height -lt 220) { continue }
                if ($window.Width -gt 1200 -or $window.Height -gt 1200) { continue }
                Write-RunLog '  복구: 남아 있던 미리보기 창을 닫습니다.'
                if (-not (Close-KakaoPreview $window)) { $ok = $false }
            }
        }
    } catch { $ok = $false }
    # 2) 파일 선택창
    try {
        foreach ($process in (Get-KakaoProcesses)) {
            foreach ($window in [NativeKakao]::GetWindows($process.Id)) {
                if (-not $window.Visible) { continue }
                if ($window.ClassName -ne '#32770') { continue }
                if ($window.Width -lt 200 -or $window.Height -lt 150) { continue }
                Write-RunLog '  복구: 남아 있던 파일 선택창을 닫습니다.'
                Close-FileDialog $window
            }
        }
    } catch { }
    # 3) 채팅창 팝업과 4) 남은 첨부 초안
    try {
        if ($null -ne $Chat -and $null -ne $InputBox) {
            Hide-ChatPopup $Chat $InputBox
            [void](Clear-ChatAttachmentDraft $Chat $InputBox)
        }
    } catch { $ok = $false }
    return $ok
}
# 클립보드에 우리가 넣은 파일이 정말 들어갔는지 확인합니다.
# 다른 프로그램이 그 사이에 클립보드를 바꿔치기하면 엉뚱한 것이 붙습니다.
# 앞 채팅방에 쓰던 사진이 다음 방에 붙는 일도 이 확인으로 막습니다.
function Test-ClipboardHasFiles([string[]]$Paths) {
    try {
        $want = @()
        foreach ($path in @($Paths)) {
            try { $want += (Resolve-Path -LiteralPath ([string]$path)).Path } catch { $want += [string]$path }
        }
        $have = @([System.Windows.Forms.Clipboard]::GetFileDropList())
        if ($have.Count -ne $want.Count) { return $false }
        for ($i = 0; $i -lt $want.Count; $i++) {
            if ([string]$have[$i] -ne [string]$want[$i]) { return $false }
        }
        return $true
    } catch { return $false }
}

# 카카오톡이 잠깐 먹통일 수 있습니다. 바로 실패로 몰지 않고 돌아오기를 기다립니다.
# 끝까지 안 돌아오면 그때 알려 줍니다.
function Wait-KakaoResponsive([object]$Window, [int]$TimeoutMs = 20000) {
    if ($null -eq $Window) { return $true }
    $handle = $Window.Handle
    if (-not [NativeKakao]::IsWindowHung($handle)) { return $true }
    Write-RunLog '카카오톡이 잠깐 응답하지 않습니다. 돌아오기를 기다립니다.'
    $deadline = (Get-Date).AddMilliseconds([Math]::Max(2000, $TimeoutMs))
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 300
        if (-not [NativeKakao]::IsWindowHung($handle)) {
            Write-RunLog '카카오톡이 다시 응답합니다. 이어서 진행합니다.'
            return $true
        }
        if (Test-RunInterrupted) { return $false }
    }
    Write-RunLog 'KAKAO_NOT_RESPONDING — 카카오톡이 계속 응답하지 않습니다.'
    return $false
}

# 첨부를 보낸 뒤 대화창에 정말 올라왔는지 봅니다.
# 미리보기 창이 닫힌 것만으로는 보냈다고 할 수 없습니다.
# 취소를 눌러도 창은 닫히기 때문입니다.
function Test-AttachmentLanded([object]$Chat, [string]$Before, [int]$TimeoutMs) {
    if ([string]::IsNullOrEmpty($Before)) { return $true }
    $list = Get-ChatListControl $Chat
    if ($null -eq $list) { return $true }
    return (Test-ChatMessageLanded $list $Before $TimeoutMs)
}

# 첨부할 파일이 실제로 쓸 수 있는 상태인지 미리 봅니다.
# 없는 파일, 열리지 않는 파일, 빈 파일을 발송 도중에 만나면 거기서 막힙니다.
function Test-AttachmentFile([string]$Path) {
    $path = [string]$Path
    if (-not $path) { return [pscustomobject]@{ Ok = $false; Reason = '경로가 비어 있습니다' } }
    $name = $path
    try { $name = [System.IO.Path]::GetFileName($path) } catch { }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [pscustomobject]@{ Ok = $false; Reason = "$name - 파일을 찾을 수 없습니다" }
    }
    $info = $null
    try { $info = Get-Item -LiteralPath $path -ErrorAction Stop } catch {
        return [pscustomobject]@{ Ok = $false; Reason = "$name - 파일 정보를 읽지 못했습니다" }
    }
    if ($info.Length -le 0) {
        return [pscustomobject]@{ Ok = $false; Reason = "$name - 파일이 비어 있습니다 (0 바이트)" }
    }
    # 300MB 가 넘으면 카카오톡이 받지 않습니다.
    if ($info.Length -gt 314572800) {
        return [pscustomobject]@{ Ok = $false; Reason = "$name - 파일이 너무 큽니다 ($([Math]::Round($info.Length/1MB))MB)" }
    }
    # 실제로 열리는지 봅니다. 다른 프로그램이 붙잡고 있으면 여기서 걸립니다.
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($info.FullName, 'Open', 'Read', 'ReadWrite')
        $head = New-Object byte[] 8
        [void]$stream.Read($head, 0, 8)
    } catch {
        return [pscustomobject]@{ Ok = $false; Reason = "$name - 다른 프로그램이 쓰고 있어 열 수 없습니다" }
    } finally {
        if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
    }
    return [pscustomobject]@{ Ok = $true; Reason = '' }
}

# 첨부 목록 전체를 미리 훑어 봅니다. 문제가 있으면 파일마다 까닭을 알려 줍니다.
function Test-AttachmentList([string[]]$Paths) {
    $good = @()
    $bad = @()
    foreach ($path in @($Paths)) {
        $check = Test-AttachmentFile ([string]$path)
        if ($check.Ok) { $good += [string]$path } else { $bad += $check.Reason }
    }
    return [pscustomobject]@{ Good = @($good); Bad = @($bad) }
}
# 방 하나가 어디까지 갔는지 적어 둡니다.
# 첨부가 실패해서 다시 할 때, 이미 보낸 문구를 또 보내면 안 되기 때문입니다.
#   { MessageSent = $false; SentFiles = @{} }
$script:deliveryState = @{}
$script:trackDelivery = $false

function Reset-DeliveryState { $script:deliveryState = @{} }

function Get-DeliveryState([string]$Room) {
    if (-not $script:trackDelivery) {
        return [pscustomobject]@{ MessageSent = $false; SentFiles = @{} }
    }
    if (-not $script:deliveryState.ContainsKey($Room)) {
        $script:deliveryState[$Room] = [pscustomobject]@{ MessageSent = $false; SentFiles = @{} }
    }
    return $script:deliveryState[$Room]
}

# 이미 열린 채팅창에 보냅니다. 제목이 목표 방과 맞을 때만 전송합니다.
# 차례는 이렇습니다.
#   채팅방 확인 -> 파일 첨부 -> 첨부 확인 -> 첨부 전송 -> 메시지 입력 -> 메시지 전송 -> 전송 확인 -> 닫기
# 한 단계라도 확인이 안 되면 그 방은 실패입니다. 보내지 못한 것을 완료라고 하지 않습니다.
#
# CloseWhenDone 이 거짓이면 창을 닫지 않습니다.
# 사용자가 직접 열어 둔 창은 사용자 것입니다. 우리가 마음대로 닫지 않습니다.
function Send-ToChatWindow([object]$Chat, [string]$Room, [object]$Content, [bool]$CloseWhenDone = $true) {
    # 대화가 많이 쌓인 방은 창이 뜬 뒤에도 한참 뒤에야 내용이 채워집니다.
    # 그 사이에 판단하면 제목이 아직 이전 방이거나 입력칸이 준비되지 않은 상태라
    # 엉뚱한 방에 보내거나, 보내지도 않고 보낸 것으로 착각합니다.
    # 그래서 방이 완전히 열릴 때까지 기다린 뒤에만 손을 댑니다.
    Set-SendProgress $Room '채팅방 확인' ''
    Write-StepLog $Room '채팅방 확인 시작'
    if (-not (Wait-KakaoResponsive $Chat 20000)) {
        $script:lastSendProblem = 'KAKAO_NOT_RESPONDING — 카카오톡이 응답하지 않습니다.'
        Write-StepLog $Room $script:lastSendProblem
        if ($CloseWhenDone) { Close-ChatWindow $Chat }
        return $false
    }
    $ready = Wait-ChatWindowReady $Chat $Room ([int]$Content.OpenTimeoutMs)
    if ($null -eq $ready) {
        $script:lastSendProblem = 'ROOM_OPEN_FAILED — 방이 다 열리지 않았거나 창 제목이 이 방과 달랐습니다.'
        Write-StepLog $Room ('채팅방 확인 실패 — ' + $script:lastSendProblem)
        if ($CloseWhenDone) { Close-ChatWindow $Chat }
        return $false
    }
    $chat = $ready.Window
    Write-StepLog $Room '채팅방 확인 성공'

    if ([bool]$Content.DryRun) {
        Write-StepLog $Room '확인만 함 — 아무것도 보내지 않았습니다'
        if ($CloseWhenDone) { Close-ChatWindow $chat }
        return $true
    }

    $inputBox = $ready.InputBox
    $state = Get-DeliveryState $Room
    $problems = @()

    # ----- 1) 첨부 파일 -----
    # 사진은 묶어서 한 번에 보냅니다. 한 장씩 보내는 것보다 훨씬 잘 갑니다.
    $waitMs = [Math]::Max(500, [int]$Content.AttachmentWaitMs)
    $files = @($Content.Attachments)
    if ($files.Count -gt 0) {
        Set-SendProgress $Room '파일 첨부 중' ''
        # 이미 보낸 파일은 빼고 묶습니다. 다시 할 때 같은 사진을 또 보내면 안 됩니다.
        $left = @()
        foreach ($path in $files) {
            $p = [string]$path
            if ($state.SentFiles.ContainsKey($p)) { continue }
            $check = Test-AttachmentFile $p
            if (-not $check.Ok) {
                $problems += ('ATTACH_FILE_BAD ' + $check.Reason)
                Write-StepLog $Room ('첨부 실패 — ' + $check.Reason)
                continue
            }
            $left += $p
        }
        $batches = @(Group-AttachmentBatches $left ([bool]$Content.GroupPhotos) ([int]$Content.PhotoBatchSize))
        $batchNo = 0
        foreach ($batch in $batches) {
            $batchNo++
            $names = @(@($batch) | ForEach-Object {
                $n = $_
                try { $n = [System.IO.Path]::GetFileName([string]$_) } catch { }
                [string]$n
            })
            $count = @($batch).Count
            $label = if ($count -gt 1) { "$($count)장 묶음" } else { $names[0] }
            $mark = "$($batchNo)/$($batches.Count)"
            Set-SendProgress $Room '파일 첨부 중' "묶음 $mark — $label"
            Write-StepLog $Room "첨부 묶음 $mark 붙여넣기 ($label)"
            $outcome = $null
            try { $outcome = Send-ChatAttachments $chat $inputBox $batch $waitMs $true } catch { $outcome = $null }
            if ($null -eq $outcome) {
                $problems += "ATTACH_FAILED 묶음 $mark '$label' 을(를) 보내지 못했습니다."
                Write-StepLog $Room "첨부 묶음 $mark 실패 — 알 수 없는 문제"
            } elseif ($outcome.Sent) {
                foreach ($path in @($batch)) { $state.SentFiles[[string]$path] = $true }
                $images = 0
                foreach ($path in @($batch)) { if (Test-IsImageFile ([string]$path)) { $images++ } }
                $script:runStats.Photos += $images
                $script:runStats.Files += ($count - $images)
                Write-StepLog $Room "첨부 묶음 $mark 전송 성공 — $($names -join ', ')  [$($outcome.Method) / $($outcome.SendWay)]"
                # 묶음 하나가 나갈 때마다 적어 둡니다. 중간에 꺼져도 여기까지는 남습니다.
                Save-RunProgress $Content
            } else {
                $problems += "ATTACH_FAILED 묶음 $mark '$label' — $($outcome.Reason)"
                Write-StepLog $Room "첨부 묶음 $mark 실패 — $($outcome.Reason)"
            }
        }
    }

    # ----- 2) 문구 -----
    $message = [string]$Content.Message
    if ((-not [string]::IsNullOrWhiteSpace($message)) -and (-not $state.MessageSent)) {
        Set-SendProgress $Room '메시지 전송 중' ''
        Write-StepLog $Room '메시지 입력'
        $how = Send-ChatText $chat $inputBox $message ([int]$Content.SettleMs)
        if (-not $how) {
            $why = $script:lastSendProblem
            if (-not $why) { $why = 'SEND_FAILED 까닭을 알 수 없습니다.' }
            Write-StepLog $Room ('메시지 전송 실패 — ' + $why)
            Clear-ChatInput $inputBox
            [void](Reset-ChatAfterFailure $chat $inputBox)
            if ($CloseWhenDone) { Close-ChatWindow $chat }
            $script:lastSendProblem = $why
            return $false
        }
        $state.MessageSent = $true
        $script:runStats.Messages++
        Write-StepLog $Room "메시지 전송 성공 ($how)"
        if ($script:sendMethodLogged -ne $how) {
            $script:sendMethodLogged = $how
            Write-RunLog "전송 방식: $how"
        }
    }

    if ($CloseWhenDone) { Close-ChatWindow $chat }
    if ($problems.Count -gt 0) {
        # 문구는 갔는데 파일만 못 갔다면 그렇게 적어 둡니다.
        # 아무것도 못 간 것과 구별돼야 어디를 다시 해야 할지 압니다.
        $head = if ($state.MessageSent -and @($state.SentFiles.Keys).Count -gt 0) { '일부 파일 전송 실패' }
                elseif ($state.MessageSent) { '파일 전송 실패 (문구는 보냄)' }
                else { '전송 실패' }
        $script:lastSendProblem = $head + ' — ' + ($problems -join ' / ')
        Write-StepLog $Room $script:lastSendProblem
        return $false
    }
    Write-StepLog $Room '발송 완료'
    return $true
}
# 채팅창을 앞으로 가져오고 입력칸에 포커스를 줍니다.

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
# 입력칸이 실제로 키보드 입력을 받는 상태인지 봅니다.
function Test-ChatInputFocused([object]$InputBox) {
    if ($null -eq $InputBox) { return $false }
    try { return ([NativeKakao]::GetFocusedControl($InputBox.Handle) -eq $InputBox.Handle) } catch { return $false }
}

# 입력칸에 포커스를 줍니다.
# 우리가 방금 연 방은 대개 입력칸이 활성화되어 있지만,
# 사용자가 미리 열어 둔 방은 포커스가 대화 목록 쪽에 가 있는 경우가 있습니다.
# 그 상태로 Enter 를 누르면 전송되지 않습니다. 그래서 눌러 주기 전에 확실히 맞춰 둡니다.
function Enter-ChatInputFocus([object]$Chat, [object]$InputBox) {
    if ($null -eq $InputBox) { return $false }
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        if (Test-ChatInputFocused $InputBox) { return $true }
        [void](Set-ChatInputFocus $Chat)
        if (Test-ChatInputFocused $InputBox) { return $true }
        try {
            [NativeKakao]::ClickControl($InputBox.Handle,
                ($InputBox.Rect.Left + [int]($InputBox.Width / 2)),
                ($InputBox.Rect.Top + [int]($InputBox.Height / 2)), $false)
        } catch { }
        Start-Sleep -Milliseconds 220
    }
    return (Test-ChatInputFocused $InputBox)
}

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
    # 입력칸이 키보드 입력을 받는 상태여야 글이 들어가고 Enter 도 먹습니다.
    [void](Enter-ChatInputFocus $Chat $InputBox)
    Reset-ChatInput $InputBox
    switch ($Way) {
        '실제 붙여넣기' {
            if (-not (Enter-ChatForeground $Chat $InputBox)) { return $false }
            try { Set-ClipboardTextSafe $Message } catch { return $false }
            # 누르기 바로 직전에 한 번 더 봅니다. 그 사이 다른 프로그램이 바꿨을 수 있습니다.
            if (-not (Test-ClipboardHasText $Message)) { return $false }
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
            if (-not (Test-ClipboardHasText $Message)) { return $false }
            [NativeKakao]::PasteInto($InputBox.Handle)
            Start-Sleep -Milliseconds 340
        }
        '창 메시지' {
            [NativeKakao]::ReplaceSelection($InputBox.Handle, $Message)
            Start-Sleep -Milliseconds 280
        }
        default { return $false }
    }
    if ((Get-ChatInputState $InputBox $Message) -ne '그대로') { return $false }

    # 글자는 들어갔는데 전송 버튼이 안 켜지는 경우가 있습니다.
    # 카카오톡이 붙여넣은 글을 사람이 친 것으로 인정하지 않은 것입니다.
    # 그대로 Enter 를 눌러 봐야 먹통이라, 눌러 보기 전에 여기서 걸러 냅니다.
    $ready = Test-ChatSendReady $Chat $InputBox
    if ($ready -ne 'no') { return $true }

    # 바로 포기하지 않고 한 번 깨워 봅니다.
    # 공백을 하나 넣었다 지우면 진짜 입력이 있었던 것이 되어 버튼이 켜집니다.
    # 이러면 빠른 붙여넣기를 그대로 쓸 수 있습니다.
    try {
        [NativeKakao]::SendChar($InputBox.Handle, 32)
        Start-Sleep -Milliseconds 140
        [NativeKakao]::PressKey($InputBox.Handle, 0x08)
        Start-Sleep -Milliseconds 240
    } catch { }
    if ((Get-ChatInputState $InputBox $Message) -ne '그대로') { return $false }
    if ((Test-ChatSendReady $Chat $InputBox) -ne 'no') {
        Write-RunLog "'$Way' 로 넣은 뒤 전송 버튼이 꺼져 있어 한 번 깨웠습니다."
        return $true
    }
    # 깨워도 안 켜집니다. 카카오톡이 이 방법으로 넣은 글은 받지 않습니다.
    # Enter 를 눌러 봐야 먹통이므로 여기서 접고 다른 방법으로 넘어갑니다.
    Write-RunLog "'$Way' 로 넣었지만 전송 버튼이 켜지지 않아 다른 방법으로 넘어갑니다."
    return $false
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
    # 이 컴퓨터에서 한 번 통한 방법을 기억해 두었다가 다음 방부터 먼저 씁니다.
    # 안 되는 방법을 방마다 다시 시도하면 방 300개에서 몇 분을 그냥 버립니다.
    if ($script:preferredSendWay -and ($ways -contains $script:preferredSendWay)) {
        $ways = @($script:preferredSendWay) + @($ways | Where-Object { $_ -ne $script:preferredSendWay })
    }
    foreach ($way in $ways) {
        # 보내기 전 대화창 모습을 기억해 둡니다.
        # 보낸 뒤 이것과 견주어 글이 실제로 올라왔는지 확인합니다.
        # 어떤 방법으로 넣었든 확인합니다. 키를 눌렀다는 것과
        # 메시지가 갔다는 것은 다른 상태이기 때문입니다.
        $before = ''
        if ($null -ne $list) { $before = Get-ChatTailSignature $list }

        $ready = $false
        try { $ready = Add-ChatMessageText $Chat $InputBox $Message $way }
        catch { $script:lastSendProblem = "글을 넣는 중 문제가 생겼습니다: $($_.Exception.Message)"; continue }
        if (-not $ready) {
            $script:lastSendProblem = "INPUT_FAILED — '$way' 로는 입력칸에 글을 넣지 못했습니다."
            continue
        }

        $presses = @('입력칸에 Enter', '창을 앞으로 가져와 Enter')
        foreach ($press in $presses) {
            if ((Get-ChatInputState $InputBox $Message) -ne '그대로') { break }
            if ($press -eq '입력칸에 Enter') {
                [void](Enter-ChatInputFocus $Chat $InputBox)
                [NativeKakao]::PressKey($InputBox.Handle, 0x0D)
            } else {
                if (-not (Enter-ChatForeground $Chat $InputBox)) { continue }
                [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
            }
            if (-not (Wait-ChatInputCleared $InputBox 2200)) {
                $script:lastSendProblem = "SEND_ACTION_FAILED — '$way' 로 넣고 Enter 를 눌렀지만 입력칸이 그대로입니다."
                continue
            }
            # 입력칸이 비워진 것만으로는 보냈다고 할 수 없습니다.
            # 카카오톡이 글을 그냥 지워 버리는 경우가 있고, 그때도 입력칸은 빕니다.
            # 그래서 대화창에 글이 올라온 것까지 확인해야 성공으로 봅니다.
            if (Test-ChatMessageLanded $list $before 3500) {
                $script:preferredSendWay = $way
                return "$way + $press"
            }

            # 여기서 다른 방법으로 다시 써 넣으면 안 됩니다.
            # 실제로는 갔는데 확인만 못 한 경우라면 같은 글이 두 번 가 버립니다.
            # 확인되지 않았다고 알리고 끝냅니다.
            $script:lastSendProblem = 'SEND_VERIFY_FAILED — 보낸 뒤 대화창에 글이 올라온 것을 확인하지 못했습니다.'
            return ''
        }
    }
    if (-not $script:lastSendProblem) { $script:lastSendProblem = 'SEND_ACTION_FAILED — 전송되지 않았습니다.' }
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
# 미리보기 창의 [전송] 을 누릅니다.
# 전송 단추는 창 아래쪽에 있는데, 그 자리는 화면 배율에 따라 달라집니다.
# 100% 에서 아래로 24픽셀인 자리가 150% 에서는 36픽셀입니다.
# 그래서 이 창이 놓인 화면의 배율을 물어 그만큼 늘려 잡고, 몇 군데를 차례로 눌러 봅니다.
# 좌표를 못 맞혀도 Enter 가 남아 있습니다.
function Submit-KakaoPreview([object]$Preview, [int]$TimeoutMs) {
    $window = [NativeKakao]::GetWindow($Preview.Handle)
    if ($null -eq $window -or $window.Width -le 0) { return '미리보기 창이 사라짐' }
    $scale = 1.0
    try { $scale = [double]([NativeKakao]::WindowDpi($window.Handle)) / 96.0 } catch { $scale = 1.0 }
    if ($scale -lt 0.5 -or $scale -gt 5.0) { $scale = 1.0 }
    $midX = $window.Rect.Left + [int]($window.Width / 2)
    $rightX = $window.Rect.Right - [int](60 * $scale)
    # 아래에서 얼마나 떨어진 자리를 누를지, 배율만큼 늘려 잡습니다.
    $spots = @()
    foreach ($up in @(24, 34, 18, 46)) {
        $spots += ,@($midX, ($window.Rect.Bottom - [int]($up * $scale)))
    }
    $spots += ,@($rightX, ($window.Rect.Bottom - [int](24 * $scale)))
    $each = [Math]::Max(1200, [int]($TimeoutMs / ($spots.Count + 2)))
    $lastReason = '전송을 눌렀지만 미리보기 창이 닫히지 않음'

    $ways = @()
    foreach ($spot in $spots) {
        $sx = $spot[0]; $sy = $spot[1]
        $ways += [pscustomobject]@{ Name = "창 메시지 클릭 ($sx,$sy)"; Act = ([scriptblock]::Create(
            "[NativeKakao]::ClickControl([IntPtr]$($window.Handle), $sx, $sy, `$false)")) }
    }
    $ways += [pscustomobject]@{ Name = 'Enter'; Act = {
        [NativeKakao]::PressKey($window.Handle, 0x0D) } }
    $ways += [pscustomobject]@{ Name = '실제 마우스 클릭'; Act = {
        if ([NativeKakao]::ForceForeground($window.Handle)) {
            Start-Sleep -Milliseconds 250
            if ([NativeKakao]::GetForegroundWindow() -eq $window.Handle) {
                Invoke-PointClick ($window.Rect.Left + [int]($window.Width / 2)) ($window.Rect.Bottom - [int](24 * $scale)) $false
            }
        } } }

    foreach ($way in $ways) {
        try { & $way.Act } catch { $lastReason = $way.Name + ' 도중 문제: ' + $_.Exception.Message; continue }
        # 눌렀으면 창이 닫히기를 기다립니다. 시간만 재고 넘어가지 않습니다.
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
# 파일 선택창의 이름 칸에 경로를 넣고 [열기] 를 누릅니다.
# 여러 개를 한 번에 고를 때는 탐색기와 같은 방식으로 따옴표로 묶어 나열합니다.
#   "C:\사진\1.jpg" "C:\사진\2.jpg" "C:\사진\3.jpg"
function Submit-FileDialog([object]$Dialog, [string[]]$Paths, [int]$TimeoutMs) {
    $list = @(@($Paths) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    if ($list.Count -eq 0) { return '넣을 파일이 없습니다' }
    $typed = if ($list.Count -eq 1) { $list[0] } else { ($list | ForEach-Object { '"' + $_ + '"' }) -join ' ' }
    $edit = $null
    foreach ($child in [NativeKakao]::GetChildWindows($Dialog.Handle)) {
        if ($child.ClassName -eq 'Edit' -and $child.Visible -and $child.Width -gt 40) { $edit = $child; break }
    }
    if ($null -eq $edit) { return '파일 이름 칸을 찾지 못함' }
    [NativeKakao]::SetControlText($edit.Handle, $typed)
    Start-Sleep -Milliseconds 150
    if ([NativeKakao]::GetControlText($edit.Handle) -ne $typed) { return '파일 이름 칸에 경로가 들어가지 않음' }
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
function Add-AttachmentByClipboard([object]$Chat, [object]$InputBox, [string[]]$Paths, [int]$WaitMs) {
    $list = @(@($Paths) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    if ($list.Count -eq 0) { return (New-AttachStage '붙일 파일이 없음' $null) }
    # 한 장일 때는 그림으로도, 파일로도 붙여 봅니다.
    # 여러 장일 때는 파일 목록으로만 붙습니다. 그림은 한 번에 하나밖에 못 담습니다.
    $methods = if ($list.Count -gt 1) { @('file') }
               elseif (Test-IsImageFile $list[0]) { @('image', 'file') }
               else { @('file', 'image') }
    $lastReason = '클립보드로 붙지 않음'
    foreach ($method in $methods) {
        $ready = $false
        try {
            if ($method -eq 'image') {
                $ready = Set-ClipboardImageSafe $list[0]
                if (-not $ready) { $lastReason = '클립보드에 그림을 넣지 못함' }
            } else {
                # 넣은 뒤 그 파일이 그대로 있는지 다시 봅니다.
                # 다른 프로그램이 클립보드를 바꿔치기하면 엉뚱한 것이 붙습니다.
                # 앞 채팅방에 쓰던 사진이 다음 방에 붙는 일도 이 확인으로 막습니다.
                for ($check = 0; $check -lt 5; $check++) {
                    Set-ClipboardFilesSafe $list
                    Start-Sleep -Milliseconds 120
                    if (Test-ClipboardHasFiles $list) { $ready = $true; break }
                }
                if (-not $ready) { $lastReason = '클립보드에 넣은 파일이 그대로 있지 않음' }
            }
        } catch { $ready = $false; $lastReason = '클립보드에 넣지 못함' }
        if (-not $ready) { continue }

        $before = Get-VisibleWindowHandles
        if (-not (Enter-ChatForeground $Chat $InputBox)) { return (New-AttachStage '채팅창을 앞으로 가져오지 못함' $null) }
        # 붙여넣기 직전에 카카오톡이 살아 있는지 봅니다. 먹통이면 돌아오기를 기다립니다.
        if (-not (Wait-KakaoResponsive $Chat 20000)) { return (New-AttachStage '카카오톡이 응답하지 않음' $null) }
        [NativeKakao]::PressCtrlKey(0x56)
        # 사진은 미리보기 창이 뜹니다. 파일은 채팅창에 바로 붙기도 합니다.
        # 여러 장이면 미리보기가 뜨기까지 조금 더 걸립니다.
        $extra = [Math]::Min(6000, 400 * $list.Count)
        $preview = Wait-KakaoPreviewWindow $before ([Math]::Max(2500, $WaitMs + 1200 + $extra))
        if ($null -ne $preview) { return (New-AttachStage '' $preview) }
        if ((Test-ChatSendReady $Chat $InputBox) -eq 'yes') { return (New-AttachStage '' $null) }
        $lastReason = '붙여넣었지만 미리보기도 전송 버튼도 확인되지 않음'
    }
    return (New-AttachStage $lastReason $null)
}
function Add-AttachmentByDialog([object]$Chat, [object]$InputBox, [string[]]$Paths, [int]$WaitMs) {
    $list = @(@($Paths) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    if ($list.Count -eq 0) { return (New-AttachStage '붙일 파일이 없음' $null) }
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
            $problem = Submit-FileDialog $dialog $list 8000
            if ($problem) {
                $lastReason = $problem
                Close-FileDialog $dialog
                continue
            }
            $extra = [Math]::Min(6000, 400 * $list.Count)
            $preview = Wait-KakaoPreviewWindow $seen ([Math]::Max(2500, $WaitMs + 1200 + $extra))
            return (New-AttachStage '' $preview)
        }
    }
    return (New-AttachStage $lastReason $null)
}
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
# 첨부를 어떻게 묶어 보낼지 정합니다.
# 사진은 여러 장을 한 번에 보내는 편이 훨씬 잘 갑니다.
# 한 장씩 보내면 그때마다 미리보기 창이 뜨고 닫히기를 되풀이해서 중간에 잘 막힙니다.
# 문서나 그 밖의 파일은 카카오톡이 하나씩만 보내므로 따로 보냅니다.
#
# 순서는 사용자가 정한 그대로 지킵니다. 사진 사이에 문서가 끼어 있으면
# 그 앞뒤로 묶음이 나뉩니다. 순서를 바꾸면서까지 묶지는 않습니다.
function Group-AttachmentBatches([string[]]$Paths, [bool]$GroupPhotos, [int]$BatchSize) {
    $list = @(@($Paths) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $batches = @()
    if ($list.Count -eq 0) { return @($batches) }
    $limit = [Math]::Max(1, [Math]::Min(30, $BatchSize))
    if (-not $GroupPhotos) {
        foreach ($path in $list) { $batches += ,@($path) }
        return @($batches)
    }
    $current = @()
    foreach ($path in $list) {
        if (-not (Test-IsImageFile $path)) {
            if ($current.Count -gt 0) { $batches += ,@($current); $current = @() }
            $batches += ,@($path)
            continue
        }
        $current += $path
        if ($current.Count -ge $limit) { $batches += ,@($current); $current = @() }
    }
    if ($current.Count -gt 0) { $batches += ,@($current) }
    return @($batches)
}

# 묶음 하나를 붙여서 보냅니다. 한 장이든 열 장이든 같은 길을 씁니다.
# 성공이라고 말하기 전에 대화창에 정말 올라왔는지 확인합니다.
# 미리보기 창이 닫힌 것만으로는 보냈다고 할 수 없습니다. 취소를 눌러도 창은 닫힙니다.
function Send-ChatAttachments([object]$Chat, [object]$InputBox, [string[]]$Paths, [int]$WaitMs, [bool]$SendIt = $true) {
    $list = @(@($Paths) | ForEach-Object { [string]$_ } | Where-Object { $_ })
    $result = [pscustomobject]@{ Ok = $false; Sent = $false; Method = ''; SendWay = ''; Reason = ''; Count = $list.Count }
    if ($list.Count -eq 0) { $result.Reason = '보낼 파일이 없습니다'; return $result }

    # 붙이기 전에 파일이 쓸 수 있는 상태인지 다시 봅니다.
    # 목록에 넣은 뒤 지워졌거나 다른 프로그램이 붙잡고 있을 수 있습니다.
    $check = Test-AttachmentList $list
    if (@($check.Bad).Count -gt 0) {
        $result.Reason = 'ATTACH_FILE_BAD ' + (@($check.Bad) -join ' / ')
        return $result
    }

    $reasons = @()
    # 사진은 클립보드가 확실하고, 문서는 파일 선택창이 확실합니다.
    $allImages = $true
    foreach ($path in $list) { if (-not (Test-IsImageFile $path)) { $allImages = $false; break } }
    $ways = @()
    if ($allImages) {
        $ways += [pscustomobject]@{ Name = '붙여넣기'; Act = { Add-AttachmentByClipboard $Chat $InputBox $list $WaitMs } }
        $ways += [pscustomobject]@{ Name = '파일 선택창'; Act = { Add-AttachmentByDialog $Chat $InputBox $list $WaitMs } }
    } else {
        $ways += [pscustomobject]@{ Name = '파일 선택창'; Act = { Add-AttachmentByDialog $Chat $InputBox $list $WaitMs } }
        $ways += [pscustomobject]@{ Name = '붙여넣기'; Act = { Add-AttachmentByClipboard $Chat $InputBox $list $WaitMs } }
    }

    # 보내기 전 대화창 모습을 적어 둡니다. 보낸 뒤 이 모습이 바뀌어야 진짜로 간 것입니다.
    $before = ''
    try { $before = Get-ChatTailSignature (Get-ChatListControl $Chat) } catch { $before = '' }

    $preview = $null
    foreach ($way in $ways) {
        $stage = $null
        try { $stage = & $way.Act } catch { $stage = New-AttachStage $_.Exception.Message $null }
        if ($null -eq $stage) { $reasons += ($way.Name + ': 알 수 없는 문제'); continue }
        if ($stage.Problem) {
            $reasons += ($way.Name + ': ' + $stage.Problem)
            # 다음 방법을 해 보기 전에 화면을 원래대로 되돌립니다.
            [void](Reset-ChatAfterFailure $Chat $InputBox)
            continue
        }
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

    # 여러 장이면 미리보기에서 보내는 데 시간이 더 걸립니다.
    $extra = [Math]::Min(8000, 600 * $list.Count)
    $landWait = [Math]::Max(4000, $WaitMs + 2000 + $extra)
    if ($null -ne $preview) {
        $problem = Submit-KakaoPreview $preview ([Math]::Max(4000, $WaitMs + 2500 + $extra))
        if ($problem) {
            $result.Reason = $problem
            [void](Close-KakaoPreview $preview)
            [void](Reset-ChatAfterFailure $Chat $InputBox)
            return $result
        }
        # 미리보기는 닫혔습니다. 이제 대화창에 정말 올라왔는지 봅니다.
        if (-not (Test-AttachmentLanded $Chat $before $landWait)) {
            $result.Reason = 'ATTACH_NOT_LANDED — 미리보기는 닫혔지만 대화창에 올라온 것을 확인하지 못했습니다'
            [void](Reset-ChatAfterFailure $Chat $InputBox)
            return $result
        }
        $result.Sent = $true
        $result.SendWay = '미리보기 창의 전송 누름'
        return $result
    }

    $how = Invoke-ChatSendAttachment $Chat $InputBox ($WaitMs + $extra)
    if (-not $how) {
        $result.Reason = '붙이기는 됐지만 전송이 확인되지 않아 치웠습니다'
        [void](Clear-ChatAttachmentDraft $Chat $InputBox)
        [void](Reset-ChatAfterFailure $Chat $InputBox)
        return $result
    }
    if (-not (Test-AttachmentLanded $Chat $before $landWait)) {
        $result.Reason = 'ATTACH_NOT_LANDED — 전송은 눌렀지만 대화창에 올라온 것을 확인하지 못했습니다'
        [void](Reset-ChatAfterFailure $Chat $InputBox)
        return $result
    }
    $result.Sent = $true
    $result.SendWay = $how
    return $result
}
# 한 개만 보낼 때 쓰는 짧은 이름입니다. (첨부 시험 등)
function Send-ChatAttachment([object]$Chat, [object]$InputBox, [string]$Path, [int]$WaitMs, [bool]$SendIt = $true) {
    return (Send-ChatAttachments $Chat $InputBox @($Path) $WaitMs $SendIt)
}
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
# 제목을 어떻게 골랐는지 기록에 남길지 정합니다. 문제 분석용입니다.
$script:debugTitleRead = $false
$script:lastTitleReadFailures = 0
$script:lastAnchorMissing = $false
$script:lstProgress = $null
$script:lblProgressCount = $null
$script:barProgress = $null
$script:preferredSendWay = ''
$script:savedClipboard = $null
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
    $lines = @(Get-OcrLines $List (Get-OcrScaleFor $List))
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

# ---------------------------------------------------------------------------
# 발송 — 저장된 목록을 기준으로 한 방씩 끝까지 처리합니다
# ---------------------------------------------------------------------------
# 한 방의 차례:  열기 -> 확인 -> 첨부 -> 첨부 전송 -> 문구 -> 문구 전송 -> 확인 -> 닫기
# 한 방을 완전히 끝낸 뒤에 다음 방으로 갑니다. 창을 여러 개 열어 두지 않습니다.
#
# 지켜야 할 것이 하나 있습니다.
#   고른 방은 반드시 '발송 완료' 아니면 '실패' 로 끝납니다.
#   아무 상태 없이 목록에서 사라지는 방은 없습니다.
#   그래서 고른 수 = 완료 + 실패 가 언제나 맞아떨어집니다.

# 줄 하나를 가리키는 열쇠입니다. 같은 줄을 두 번 열지 않으려고 씁니다.
function Get-RowKey([object]$Row) {
    $name = ConvertTo-ExactKey ([string]$Row.Title)
    if ($name) { return 'N:' + $name }
    return 'Y:' + [string]([int]([Math]::Round(([double]$Row.Top) / 6.0)))
}

# 이 줄이 찾는 방일 것 같은지 봅니다.
# 여기는 관대해도 됩니다. 어느 줄을 열어 볼지 고르는 것뿐입니다.
# 실제로 보낼지는 방을 연 뒤 창 제목이 정확히 같은지로 정합니다.
function Test-RowLooksLike([object]$Row, [string]$Name, [string]$ListText) {
    $rowText = ConvertTo-CompareKey ([string]$Row.Title)
    if (-not $rowText) { return $false }
    foreach ($candidate in @($Name, $ListText)) {
        $key = ConvertTo-CompareKey $candidate
        if (-not $key) { continue }
        if ($rowText -eq $key) { return $true }
        if ($key.Length -ge 3 -and $rowText.StartsWith($key)) { return $true }
        if ($rowText.Length -ge 3 -and $key.StartsWith($rowText)) { return $true }
        if ((Get-NameSimilarity $rowText $key) -ge 0.7) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 발송 진행 상태를 파일에 적어 둡니다
# ---------------------------------------------------------------------------
# 발송 도중 프로그램이 꺼지거나 PC 가 재부팅될 수 있습니다.
# 그때 어디까지 갔는지 모르면 처음부터 다시 보내게 되고, 받은 사람은 두 번 받습니다.
# 그래서 한 방이 끝날 때마다, 그리고 사진 묶음 하나가 나갈 때마다 적어 둡니다.
#
# 적어 두는 것:
#   방마다  상태 · 까닭 · 문구를 보냈는지 · 어느 파일까지 보냈는지
# 다시 켰을 때 이 파일을 보고 [이어서 발송] 을 드립니다.
$script:ProgressPath = Join-Path $AppDir 'progress.json'
$script:runStats = @{ Photos = 0; Files = 0; Messages = 0 }
$script:lastRunResult = $null

function Get-MessageFingerprint([string]$Text) {
    # 문구가 바뀌었는데 이어서 보내면 앞뒤가 다른 글이 나갑니다. 그래서 표시를 남깁니다.
    $body = [string]$Text
    if (-not $body) { return '' }
    try {
        $sha = [System.Security.Cryptography.SHA1]::Create()
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
        $hash = $sha.ComputeHash($bytes)
        $sha.Dispose()
        return ([BitConverter]::ToString($hash) -replace '-', '').Substring(0, 16)
    } catch { return ([string]$body.Length) }
}

function Save-RunProgress([object]$Content) {
    try {
        $rooms = @()
        foreach ($name in $script:progressOrder) {
            $row = $script:progressRows[$name]
            $state = $null
            if ($script:deliveryState.ContainsKey($name)) { $state = $script:deliveryState[$name] }
            $sentFiles = @()
            if ($null -ne $state) { $sentFiles = @($state.SentFiles.Keys) }
            $rooms += [pscustomobject]@{
                Name = $name
                Status = [string]$row.Status
                Note = [string]$row.Note
                MessageSent = $(if ($null -ne $state) { [bool]$state.MessageSent } else { $false })
                SentFiles = @($sentFiles)
            }
        }
        $data = [pscustomobject]@{
            Version = 1
            StartedAt = [string]$script:runStartedAt
            UpdatedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            DryRun = [bool]$Content.DryRun
            MessageMark = (Get-MessageFingerprint ([string]$Content.Message))
            Attachments = @($Content.Attachments)
            Stats = [pscustomobject]@{
                Photos = [int]$script:runStats.Photos
                Files = [int]$script:runStats.Files
                Messages = [int]$script:runStats.Messages
            }
            Total = $script:progressOrder.Count
            Rooms = @($rooms)
        }
        $json = $data | ConvertTo-Json -Depth 6
        $temp = "$($script:ProgressPath).tmp"
        Set-Content -LiteralPath $temp -Value $json -Encoding UTF8 -ErrorAction Stop
        Move-Item -LiteralPath $temp -Destination $script:ProgressPath -Force -ErrorAction Stop
    } catch { }
}

function Import-RunProgress {
    if (-not (Test-Path -LiteralPath $script:ProgressPath)) { return $null }
    try { return (Get-Content -LiteralPath $script:ProgressPath -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { return $null }
}

function Clear-RunProgress {
    try { if (Test-Path -LiteralPath $script:ProgressPath) { Remove-Item -LiteralPath $script:ProgressPath -Force } } catch { }
}

# 이어서 할 것이 남아 있는지 봅니다.
# 아직 완료도 실패도 아닌 방이 있거나, 실패한 방이 있으면 이어서 할 수 있습니다.
function Get-ResumableRooms([object]$Saved) {
    if ($null -eq $Saved) { return @() }
    $left = @()
    foreach ($room in @($Saved.Rooms)) {
        if ($null -eq $room) { continue }
        if ([string]$room.Status -eq '발송 완료') { continue }
        $name = ConvertTo-ExactKey ([string]$room.Name)
        if ($name) { $left += $name }
    }
    return @($left)
}

# 저장해 둔 상태를 지금 실행에 다시 얹습니다.
# 이미 보낸 문구와 파일은 다시 보내지 않도록 그대로 살립니다.
function Restore-RunProgress([object]$Saved) {
    if ($null -eq $Saved) { return }
    Reset-DeliveryState
    $script:progressRows = @{}
    $script:progressOrder = New-Object System.Collections.Generic.List[string]
    foreach ($room in @($Saved.Rooms)) {
        if ($null -eq $room) { continue }
        $name = ConvertTo-ExactKey ([string]$room.Name)
        if (-not $name) { continue }
        if (-not $script:progressRows.ContainsKey($name)) {
            $script:progressRows[$name] = [pscustomobject]@{ Status = [string]$room.Status; Note = [string]$room.Note }
            [void]$script:progressOrder.Add($name)
        }
        $state = [pscustomobject]@{ MessageSent = [bool]$room.MessageSent; SentFiles = @{} }
        foreach ($file in @($room.SentFiles)) { $state.SentFiles[[string]$file] = $true }
        $script:deliveryState[$name] = $state
    }
    try {
        $script:runStats.Photos = [int]$Saved.Stats.Photos
        $script:runStats.Files = [int]$Saved.Stats.Files
        $script:runStats.Messages = [int]$Saved.Stats.Messages
    } catch { }
    Update-ProgressView
}

# 방 이름 앞에 붙여 기록을 남깁니다. 나중에 어디서 막혔는지 이 줄만 보고 알 수 있어야 합니다.
function Write-StepLog([string]$Room, [string]$Text) {
    Write-RunLog ("[{0}] {1}" -f $Room, $Text)
}
# 발송 결과를 표로 남깁니다. 시간 / 채팅방 / 문구 / 첨부 / 결과 / 사유
function Add-SendLogRow([string]$Room, [object]$Content, [bool]$Ok, [string]$Reason) {
    try {
        $path = Join-Path $LogDir ('발송기록-' + (Get-Date -Format 'yyyy-MM') + '.csv')
        if (-not (Test-Path -LiteralPath $path)) {
            Set-Content -LiteralPath $path -Value '시간,채팅방,메시지,첨부,결과,사유' -Encoding UTF8
        }
        $files = @()
        foreach ($item in @($Content.Attachments)) {
            try { $files += [System.IO.Path]::GetFileName([string]$item) } catch { $files += [string]$item }
        }
        $title = [string]$Content.TemplateName
        if (-not $title) {
            $body = ([string]$Content.Message) -replace '\s+', ' '
            if ($body.Length -gt 20) { $body = $body.Substring(0, 20) + '…' }
            $title = $body
        }
        $cells = @(
            (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),
            $Room,
            $title,
            ($files -join ' '),
            $(if ($Ok) { '성공' } else { '실패' }),
            ([string]$Reason)
        )
        $line = ($cells | ForEach-Object { '"' + (([string]$_) -replace '"', '""') + '"' }) -join ','
        Add-Content -LiteralPath $path -Value $line -Encoding UTF8
    } catch { }
}

# 목록을 한 번 훑으면서 처리할 수 있는 방을 모두 처리합니다.
#   Exhaustive 가 참이면 아직 정체를 모르는 줄을 모두 열어 봅니다.
#   이름으로 못 찾은 방을 끝까지 찾아내기 위한 방식입니다. 느리지만 빠뜨리지 않습니다.
# 보낸 방만 Pending 에서 뺍니다. 실패한 방은 남겨 두어 다음 회차에 다시 해 봅니다.
function Invoke-ListPass([object]$Pending, [object]$Content, [int]$MaxPages,
                         [int]$IntervalSeconds, [int]$BatchSize, [int]$BatchRestMinutes,
                         [hashtable]$NotTarget, [hashtable]$Reasons, [bool]$Exhaustive,
                         [int]$Total, [object]$Counter) {
    $sent = 0
    $tried = 0
    $interrupted = $false

    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { throw $ready.Reason }
    $main = $ready.Layout.Main
    Move-ListToTop $ready.Layout.List $MaxPages

    for ($page = 0; $page -lt $MaxPages; $page++) {
        if ($Pending.Count -eq 0) { break }
        if (Test-RunInterrupted) { $interrupted = $true; break }

        # 이 화면에서 이미 열어 본 줄입니다. 화면을 내리기 전까지만 씁니다.
        $donePage = @{}
        $guard = 0
        $rowsSeen = 0

        while ($guard -lt 40) {
            $guard++
            if ($Pending.Count -eq 0) { break }
            if (Test-RunInterrupted) { $interrupted = $true; break }

            $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
            if ($null -eq $fresh.List) { break }
            $list = $fresh.List
            $rows = @(Get-ChatRoomRowsFromOcr (Get-OcrLines $list (Get-OcrScaleFor $list)) $list.Width)
            if ($rows.Count -eq 0) { break }
            $rowsSeen = $rows.Count

            # 열어 볼 줄을 하나 고릅니다.
            # 여기는 관대해도 됩니다. 어느 줄을 열지 고르는 것뿐입니다.
            $pick = $null
            foreach ($row in $rows) {
                $posKey = 'P:' + [string]([int]([Math]::Round(([double]$row.Top) / 6.0)))
                if ($donePage.ContainsKey($posKey)) { continue }
                if ($NotTarget.ContainsKey((Get-RowKey $row))) { continue }
                if ($Exhaustive) { $pick = $row; break }
                foreach ($key in @($Pending.Keys)) {
                    $listText = [string]$key
                    $entry = Find-RosterEntry ([string]$key)
                    if ($null -ne $entry -and $entry.ListText) { $listText = $entry.ListText }
                    if (Test-RowLooksLike $row ([string]$key) $listText) { $pick = $row; break }
                }
                if ($null -ne $pick) { break }
            }
            if ($null -eq $pick) { break }
            $donePage['P:' + [string]([int]([Math]::Round(([double]$pick.Top) / 6.0)))] = $true

            # 줄을 엽니다. 여기서 처음으로 정확한 이름을 알게 됩니다.
            $chat = Get-SingleChatWindow (Open-RoomAtLine $list $pick $main.Handle)
            if ($null -eq $chat) {
                $NotTarget[(Get-RowKey $pick)] = $true
                continue
            }
            $openedName = Get-RoomTitleName ([string]$chat.Title)
            $openedKey = ConvertTo-ExactKey $openedName

            # 보낼 목록에 정확히 같은 이름이 있어야 보냅니다.
            # 비슷하다고 보내지 않습니다. 투투 를 찾다가 토토 가 열리면 그냥 닫습니다.
            if (-not $openedKey -or -not $Pending.Contains($openedKey)) {
                if ($openedKey) {
                    Write-RunLog "지나감: 열린 방 '$openedName' 은(는) 보낼 목록에 없습니다."
                    Set-StatusPill ("남은 방 찾는 중 — 방금 '$openedName' 확인") 'run'
                } else {
                    Write-RunLog '지나감: 열린 창의 제목을 읽지 못했습니다.'
                }
                try { Close-ChatWindow $chat } catch { }
                $NotTarget[(Get-RowKey $pick)] = $true
                if ($openedKey) { $NotTarget['N:' + $openedKey] = $true }
                continue
            }

            # 여기서부터 이 방을 끝까지 처리합니다. 끝나기 전에는 다음 방으로 가지 않습니다.
            $tried++
            $Counter.Value = $Total - $Pending.Count + 1
            Set-StatusPill ("발송 중 $($Counter.Value)/$Total — $openedName") 'run'
            Set-SendProgress $openedName '채팅방 여는 중' ''
            Set-RoomKind $openedName (Get-RoomKindFromTitle ([string]$chat.Title) (Get-RoomType $openedName))

            $script:strictTitleMatch = $true
            $ok = $false
            try { $ok = [bool](Send-ToChatWindow $chat $openedName $Content) }
            catch {
                $ok = $false
                $script:lastSendProblem = 'SEND_ERROR — ' + $_.Exception.Message
            }
            finally { $script:strictTitleMatch = $false }

            if ($ok) {
                $Pending.Remove($openedKey)
                $NotTarget['N:' + $openedKey] = $true
                $NotTarget[(Get-RowKey $pick)] = $true
                $sent++
                Set-SendProgress $openedName '발송 완료' ''
                if ($Reasons.ContainsKey($openedKey)) { $Reasons.Remove($openedKey) }
            } else {
                # 실패한 방은 목록에 남겨 둡니다. 다음 회차에 다시 해 봅니다.
                $why = $script:lastSendProblem
                if (-not $why) { $why = 'SEND_FAILED 까닭을 알 수 없습니다.' }
                $Reasons[$openedKey] = $why
                Set-SendProgress $openedName '재시도' $why
            }
            # 한 방이 끝날 때마다 적어 둡니다. 중간에 꺼져도 여기까지는 남습니다.
            Save-RunProgress $Content
            # 방 사이 간격
            if ($Pending.Count -gt 0) {
                if ($BatchSize -gt 0 -and $BatchRestMinutes -gt 0 -and $sent -gt 0 -and ($sent % $BatchSize) -eq 0) {
                    Write-RunLog "묶음 $($BatchSize)개를 처리했습니다. $($BatchRestMinutes)분 쉽니다."
                    Set-StatusPill "$($BatchRestMinutes)분 쉬는 중 — $($Counter.Value)/$Total" 'wait'
                    if (Wait-Interruptible ($BatchRestMinutes * 60)) { $interrupted = $true; break }
                } elseif ($IntervalSeconds -gt 0) {
                    if (Wait-Interruptible $IntervalSeconds) { $interrupted = $true; break }
                } elseif (Test-RunInterrupted) { $interrupted = $true; break }
            }
        }

        if ($interrupted -or $Pending.Count -eq 0) { break }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -eq $fresh.List) { break }
        $notches = [Math]::Max(3, [Math]::Min(8, $rowsSeen - 1))
        Move-ListByWheel $fresh.List 'down' $notches
        Start-Sleep -Milliseconds 200
    }

    return [pscustomobject]@{
        Sent = $sent
        Tried = $tried
        Interrupted = $interrupted
    }
}

# 열려 있는 채팅방 창으로 먼저 보냅니다.
# 사용자가 직접 열어 둔 창이라 제목이 곧 정확한 이름입니다.
# 목록을 훑을 일도, 화면 글자를 읽을 일도 없습니다. 가장 빠르고 가장 정확합니다.
# 사용자가 열어 둔 창은 보내고 나서도 닫지 않습니다.
function Invoke-OpenWindowPass([object]$Pending, [object]$Content, [int]$IntervalSeconds,
                               [int]$BatchSize, [int]$BatchRestMinutes,
                               [hashtable]$Reasons, [int]$Total, [object]$Counter) {
    $sent = 0
    $tried = 0
    $interrupted = $false
    $open = @{}
    foreach ($room in (Get-OpenChatRooms)) { $open[$room.Name] = $room }
    if ($open.Count -eq 0) {
        return [pscustomobject]@{ Sent = 0; Tried = 0; Interrupted = $false; OpenCount = 0 }
    }
    Write-RunLog ("열려 있는 채팅방 창 {0}개를 찾았습니다." -f $open.Count)

    foreach ($key in @($Pending.Keys)) {
        if (Test-RunInterrupted) { $interrupted = $true; break }
        $name = [string]$key
        if (-not $open.ContainsKey($name)) { continue }
        $window = Find-OpenChatWindow $name
        if ($null -eq $window) { continue }

        $tried++
        $Counter.Value = $Total - $Pending.Count + 1
        Set-StatusPill ("발송 중 $($Counter.Value)/$Total — $name") 'run'
        Set-SendProgress $name '채팅방 여는 중' '열려 있는 창을 씁니다'
        Set-RoomKind $name (Get-RoomKindFromTitle ([string]$window.Title) (Get-RoomType $name))

        $script:strictTitleMatch = $true
        $ok = $false
        try { $ok = [bool](Send-ToChatWindow $window $name $Content $false) }
        catch {
            $ok = $false
            $script:lastSendProblem = 'SEND_ERROR — ' + $_.Exception.Message
        }
        finally { $script:strictTitleMatch = $false }

        if ($ok) {
            $Pending.Remove($name)
            $sent++
            Set-SendProgress $name '발송 완료' ''
            if ($Reasons.ContainsKey($name)) { $Reasons.Remove($name) }
        } else {
            # 실패한 방은 목록에 남겨 둡니다. 다음 회차에 다시 해 봅니다.
            $why = $script:lastSendProblem
            if (-not $why) { $why = 'SEND_FAILED 까닭을 알 수 없습니다.' }
            $Reasons[$name] = $why
            Set-SendProgress $name '재시도' $why
        }
        # 한 방이 끝날 때마다 적어 둡니다. 중간에 꺼져도 여기까지는 남습니다.
        Save-RunProgress $Content
        if ($Pending.Count -gt 0) {
            if ($BatchSize -gt 0 -and $BatchRestMinutes -gt 0 -and $sent -gt 0 -and ($sent % $BatchSize) -eq 0) {
                Write-RunLog "묶음 $($BatchSize)개를 처리했습니다. $($BatchRestMinutes)분 쉽니다."
                Set-StatusPill "$($BatchRestMinutes)분 쉬는 중 — $($Counter.Value)/$Total" 'wait'
                if (Wait-Interruptible ($BatchRestMinutes * 60)) { $interrupted = $true; break }
            } elseif ($IntervalSeconds -gt 0) {
                if (Wait-Interruptible $IntervalSeconds) { $interrupted = $true; break }
            } elseif (Test-RunInterrupted) { $interrupted = $true; break }
        }
    }
    return [pscustomobject]@{
        Sent = $sent
        Tried = $tried
        Interrupted = $interrupted
        OpenCount = $open.Count
    }
}
# 고른 방을 모두 처리합니다. 순서는 이렇습니다.
#   ① 열려 있는 채팅방 창으로 보냅니다. 사용자가 열어 둔 창이 여기 해당합니다.
#      제목이 곧 정확한 이름이라 화면 글자를 읽을 일이 없습니다. 가장 정확합니다.
#   ② 그러고도 남은 방은 카카오톡 목록에서 이름으로 찾아 엽니다.
#   ③ 그래도 남으면 목록의 모든 줄을 하나씩 열어 확인합니다. 느리지만 빠뜨리지 않습니다.
#   ④ 끝까지 못 보낸 방은 실패로 마무리합니다. 조용히 사라지는 방은 없습니다.
# 그래서 언제나  고른 수 = 성공 + 실패  입니다.
function Invoke-RosterSend([string[]]$Targets, [object]$Content, [int]$MaxPages,
                           [int]$IntervalSeconds, [int]$BatchSize, [int]$BatchRestMinutes,
                           [int]$RetryCount) {
    $pending = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($name in $Targets) {
        $key = ConvertTo-ExactKey ([string]$name)
        if (-not $key) { continue }
        if (-not $pending.Contains($key)) { $pending.Add($key, $true) }
    }
    $total = $pending.Count
    if ($total -eq 0) { throw '보낼 채팅방을 한 개 이상 골라 주세요.' }

    $sent = 0
    $reasons = @{}
    $notTarget = @{}
    $counter = [ref]0
    $rounds = [Math]::Max(1, [Math]::Min(6, $RetryCount + 1))
    $interrupted = $false

    for ($round = 1; $round -le $rounds; $round++) {
        if ($pending.Count -eq 0) { break }
        if (Test-RunInterrupted) { $interrupted = $true; break }

        # ① 열려 있는 창부터
        $openPass = Invoke-OpenWindowPass $pending $Content $IntervalSeconds $BatchSize $BatchRestMinutes $reasons $total $counter
        $sent += $openPass.Sent
        if ($openPass.Tried -gt 0) {
            Write-RunLog ("{0}회차 · 열린 창: 보냄 {1} / 남음 {2}" -f $round, $openPass.Sent, $pending.Count)
        }
        if ($openPass.Interrupted) { $interrupted = $true; break }
        if ($pending.Count -eq 0) { break }

        # ② · ③ 남은 방은 목록에서 찾습니다.
        $exhaustive = ($round -gt 1)
        $howText = if ($exhaustive) { '아직 못 찾은 방을 위해 목록의 모든 줄을 하나씩 열어 확인합니다 (오래 걸립니다)' } else { '이름으로 찾아 열기' }
        Write-RunLog ("{0}회차 · 목록: 남은 방 {1}개 / {2}" -f $round, $pending.Count, $howText)

        $before = $pending.Count
        $pass = Invoke-ListPass $pending $Content $MaxPages $IntervalSeconds $BatchSize $BatchRestMinutes $notTarget $reasons $exhaustive $total $counter
        $sent += $pass.Sent
        Write-RunLog ("{0}회차 결과: 보냄 {1} / 남음 {2}" -f $round, ($openPass.Sent + $pass.Sent), $pending.Count)

        if ($pass.Interrupted) { $interrupted = $true; break }
        if ($pending.Count -eq 0) { break }
        # 훑었는데 하나도 줄지 않고 열어 본 방도 없으면 더 해도 같습니다.
        if ($exhaustive -and $pending.Count -eq $before -and $pass.Tried -eq 0 -and $openPass.Tried -eq 0) { break }
        if ($round -lt $rounds) {
            foreach ($key in @($pending.Keys)) { Set-SendProgress ([string]$key) '재시도' ("$($round + 1)회차를 기다리는 중") }
            Start-Sleep -Milliseconds 800
        }
    }
    # 남은 방을 실패로 마무리합니다. 이 줄이 있어야 숫자가 맞아떨어집니다.
    $failed = 0
    foreach ($key in @($pending.Keys)) {
        $name = [string]$key
        $why = 'ROOM_NOT_FOUND — 카카오톡 채팅 목록에서 이 방을 찾지 못했습니다.'
        if ($interrupted) { $why = 'STOPPED — 사용자가 멈춰서 이 방은 처리하지 못했습니다.' }
        if ($reasons.ContainsKey($key)) { $why = [string]$reasons[$key] }
        $failed++
        Set-SendProgress $name '실패' $why
        Write-RunLog "실패: '$name' — $why"
        Add-SendLogRow $name $Content $false $why
    }
    # 성공한 방을 기록에 남깁니다.
    foreach ($name in $Targets) {
        $key = ConvertTo-ExactKey ([string]$name)
        if (-not $key -or $pending.Contains($key)) { continue }
        Add-SendLogRow $key $Content $true ''
    }

    # 숫자가 맞는지 스스로 확인합니다. 안 맞으면 그대로 알려 드립니다.
    $handled = $sent + $failed
    if ($handled -ne $total) {
        Write-RunLog "COUNT_MISMATCH — 고른 방 $total 개인데 처리한 방은 $handled 개입니다. 기록을 확인해 주세요."
    }
    return [pscustomobject]@{
        Total = $total
        Sent = $sent
        Failed = $failed
        Interrupted = $interrupted
    }
}
# 이 컴퓨터가 어떤 환경인지 기록에 남깁니다.
# PC 마다 되고 안 되고가 갈릴 때, 이 기록이 있어야 원인을 짚을 수 있습니다.
# 대화 내용은 남기지 않습니다. 화면과 창 정보만 남깁니다.
function Write-EnvironmentLog([object]$MainWindow) {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $osText = if ($null -ne $os) { "$($os.Caption) 빌드 $($os.BuildNumber)" } else { '알 수 없음' }
        Write-RunLog "환경: $osText / 파워셸 $($PSVersionTable.PSVersion)"
    } catch { }
    try {
        $screens = @([System.Windows.Forms.Screen]::AllScreens)
        $primary = [System.Windows.Forms.Screen]::PrimaryScreen
        # 화면 배율은 그리기 해상도로 알아냅니다. 96 이 100% 입니다.
        $scale = 100
        try {
            $g = [System.Drawing.Graphics]::FromHwnd([IntPtr]::Zero)
            $scale = [int][Math]::Round($g.DpiX / 96 * 100)
            $g.Dispose()
        } catch { }
        Write-RunLog ("환경: 모니터 {0}개 / 주 모니터 {1}x{2} / 화면 배율 {3}%" -f `
            $screens.Count, $primary.Bounds.Width, $primary.Bounds.Height, $scale)
        if ($scale -ne 100) {
            Write-RunLog '  (배율이 100%가 아니면 화면 글자 인식이 어려워질 수 있습니다)'
        }
    } catch { }
    try {
        if ($null -ne $MainWindow) {
            $min = [NativeKakao]::IsWindowMinimized($MainWindow.Handle)
            Write-RunLog ("환경: 카카오톡 창 {0}x{1} @{2},{3} / 최소화={4}" -f `
                $MainWindow.Width, $MainWindow.Height, $MainWindow.Rect.Left, $MainWindow.Rect.Top, $min)
            if ($MainWindow.Width -lt 340 -or $MainWindow.Height -lt 480) {
                Write-RunLog '  (카카오톡 창이 작습니다. 창을 키우면 목록을 더 정확히 읽습니다)'
            }
        }
    } catch { }
}

# 보낼 방들이 어느 종류인지 보고, 지금 카카오톡이 그 탭을 보고 있는지 확인합니다.
# 오픈채팅방으로 보내려는데 [채팅] 탭이 열려 있으면 방을 찾지 못합니다.
# 그대로 진행하면 전부 실패하므로, 시작 전에 알려 드리고 멈춥니다.
function Test-SendTabReady([string[]]$Rooms, [object]$Layout) {
    $wantOpen = $false
    $wantNormal = $false
    foreach ($room in $Rooms) {
        $type = Get-RoomType ([string]$room)
        if ($type -eq $script:RoomTypeOpen) { $wantOpen = $true }
        elseif ($type -eq $script:RoomTypeNormal) { $wantNormal = $true }
    }
    # 두 종류를 함께 보내는 경우에는 막지 않습니다.
    # 한 바퀴 돈 뒤 다른 탭으로 바꿔 달라고 그때 여쭙습니다.
    if ($wantOpen -and $wantNormal) { return '' }
    if (-not $wantOpen -and -not $wantNormal) { return '' }

    $now = $script:RoomTypeUnknown
    try { $now = Get-ActiveKakaoTab $Layout } catch { }
    if ($now -eq $script:RoomTypeUnknown) { return '' }

    if ($wantOpen -and $now -ne $script:RoomTypeOpen) {
        return "[오픈채팅 탭 확인 필요]" + "`r`n`r`n" +
               "지금 오픈채팅방 발송이 선택되어 있습니다." + "`r`n`r`n" +
               "카카오톡 PC 에서 [오픈채팅] 탭을 열어 둔 뒤 다시 시도해 주세요." + "`r`n`r`n" +
               "(지금 카카오톡은 $now 을(를) 보고 있습니다)"
    }
    if ($wantNormal -and $now -ne $script:RoomTypeNormal) {
        return "[일반채팅 탭 확인 필요]" + "`r`n`r`n" +
               "지금 일반 채팅방 발송이 선택되어 있습니다." + "`r`n`r`n" +
               "카카오톡 PC 에서 [채팅] 탭을 열어 둔 뒤 다시 시도해 주세요." + "`r`n`r`n" +
               "(지금 카카오톡은 $now 을(를) 보고 있습니다)"
    }
    return ''
}

# ---------------------------------------------------------------------------
# 방별 발송 진행 상태
# ---------------------------------------------------------------------------
# 기록에 줄만 쌓이면 지금 어디까지 갔는지 알기 어렵습니다.
# 방마다 상태를 표로 보여 줍니다. 실패한 방은 까닭도 함께 적습니다.
$script:progressRows = @{}
$script:progressOrder = New-Object System.Collections.Generic.List[string]

function Reset-SendProgress([string[]]$Rooms) {
    $script:progressRows = @{}
    $script:progressOrder = New-Object System.Collections.Generic.List[string]
    foreach ($room in $Rooms) {
        $name = [string]$room
        if (-not $name -or $script:progressRows.ContainsKey($name)) { continue }
        $script:progressRows[$name] = [pscustomobject]@{ Status = '대기'; Note = '' }
        [void]$script:progressOrder.Add($name)
    }
    Update-ProgressView
}

function Set-SendProgress([string]$Room, [string]$Status, [string]$Note) {
    $name = [string]$Room
    if (-not $name) { return }
    if (-not $script:progressRows.ContainsKey($name)) {
        $script:progressRows[$name] = [pscustomobject]@{ Status = '대기'; Note = '' }
        [void]$script:progressOrder.Add($name)
    }
    $script:progressRows[$name].Status = $Status
    $script:progressRows[$name].Note = [string]$Note
    Update-ProgressView
}

function Update-ProgressView {
    if ($null -eq $script:lstProgress) { return }
    $total = $script:progressOrder.Count
    $done = 0; $failed = 0; $running = 0; $waiting = 0
    try {
        $script:lstProgress.BeginUpdate()
        $script:lstProgress.Items.Clear()
        foreach ($name in $script:progressOrder) {
            $row = $script:progressRows[$name]
            $status = [string]$row.Status
            # 상태는 여덟 가지입니다.
            #   대기 / 채팅방 여는 중 / 채팅방 확인 / 파일 첨부 중 /
            #   메시지 전송 중 / 발송 완료 / 재시도 / 실패
            switch ($status) {
                '발송 완료' { $done++ }
                '실패'      { $failed++ }
                '대기'      { $waiting++ }
                default     { $running++ }
            }
            $item = New-Object System.Windows.Forms.ListViewItem($name)
            $kindText = '일반채팅'
            $entry = Find-RosterEntry $name
            if ($null -ne $entry) { $kindText = Get-RosterKindText $entry.Kind }
            else { $kindText = Get-RoomKindText $name }
            [void]$item.SubItems.Add($kindText)
            [void]$item.SubItems.Add($status)
            [void]$item.SubItems.Add([string]$row.Note)
            if ($status -eq '발송 완료') { $item.ForeColor = $Theme.Success }
            elseif ($status -eq '실패') { $item.ForeColor = $Theme.Danger }
            elseif ($status -eq '재시도') { $item.ForeColor = $Theme.Warning }
            elseif ($status -eq '대기') { $item.ForeColor = $Theme.Muted }
            else { $item.ForeColor = $Theme.Info }
            [void]$script:lstProgress.Items.Add($item)
        }
    } finally { $script:lstProgress.EndUpdate() }
    if ($null -ne $script:lblProgressCount) {
        $script:lblProgressCount.Text = "전체 $total    발송 완료 $done    진행중 $running    대기 $waiting    실패 $failed"
    }
    if ($null -ne $script:barProgress) {
        $script:barProgress.Maximum = [Math]::Max(1, $total)
        $script:barProgress.Value = [Math]::Min($script:barProgress.Maximum, ($done + $failed))
    }
    try { [System.Windows.Forms.Application]::DoEvents() } catch { }
}


# 체크한 방의 이름이 맞는지 하나씩 열어 확인하고, 틀렸으면 바로잡습니다.
# 검색은 쓰지 않습니다. 목록을 훑어 줄을 열고 창 제목을 읽습니다.
# 창 제목은 화면 글자 인식이 아니라 윈도우가 알려 주는 진짜 글자라 틀리지 않습니다.
function Invoke-RoomNameVerify([string[]]$Names, [int]$MaxPages) {
    $pending = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($name in $Names) {
        $key = ConvertTo-ExactKey ([string]$name)
        if ($key -and -not $pending.Contains($key)) { $pending.Add($key, $true) }
    }
    $confirmed = @()
    $renamed = @()
    $notTarget = @{}

    $ready = Test-KakaoReady $true $false
    if (-not $ready.Ok) { throw $ready.Reason }
    $main = $ready.Layout.Main
    Move-ListToTop $ready.Layout.List $MaxPages

    for ($page = 0; $page -lt $MaxPages; $page++) {
        if ($pending.Count -eq 0) { break }
        $donePage = @{}
        $guard = 0
        $rowsSeen = 0
        while ($guard -lt 40 -and $pending.Count -gt 0) {
            $guard++
            $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
            if ($null -eq $fresh.List) { break }
            $list = $fresh.List
            $rows = @(Get-ChatRoomRowsFromOcr (Get-OcrLines $list (Get-OcrScaleFor $list)) $list.Width)
            if ($rows.Count -eq 0) { break }
            $rowsSeen = $rows.Count

            $pick = $null
            $pickedFor = ''
            foreach ($row in $rows) {
                $posKey = 'P:' + [string]([int]([Math]::Round(([double]$row.Top) / 6.0)))
                if ($donePage.ContainsKey($posKey)) { continue }
                if ($notTarget.ContainsKey((Get-RowKey $row))) { continue }
                foreach ($key in @($pending.Keys)) {
                    $listText = [string]$key
                    $entry = Find-RosterEntry ([string]$key)
                    if ($null -ne $entry -and $entry.ListText) { $listText = $entry.ListText }
                    if (Test-RowLooksLike $row ([string]$key) $listText) { $pick = $row; $pickedFor = [string]$key; break }
                }
                if ($null -ne $pick) { break }
            }
            if ($null -eq $pick) { break }
            $donePage['P:' + [string]([int]([Math]::Round(([double]$pick.Top) / 6.0)))] = $true

            $chat = Get-SingleChatWindow (Open-RoomAtLine $list $pick $main.Handle)
            if ($null -eq $chat) { $notTarget[(Get-RowKey $pick)] = $true; continue }
            $rawTitle = [string]$chat.Title
            $title = Get-RoomTitleName $rawTitle
            $kind = Get-RoomKindFromTitle $rawTitle ''
            try { Close-ChatWindow $chat } catch { }
            $notTarget[(Get-RowKey $pick)] = $true
            if (-not $title) { continue }

            if ($pending.Contains($title)) {
                # 이름이 이미 맞습니다.
                $pending.Remove($title)
                $confirmed += $title
                Set-RosterVerified $title $kind $title
                Write-RunLog "이름 확인: '$title' 맞습니다."
                continue
            }
            # 이름이 다릅니다. 우리가 찾던 그 방이 맞는지 조심스럽게 봅니다.
            #   비슷하고, 다른 대상과 헷갈리지 않을 때만 바로잡습니다.
            $looksLikeTarget = ((Get-NameSimilarity $title $pickedFor) -ge 0.6)
            $clashes = 0
            foreach ($key in @($pending.Keys)) {
                if ((Get-NameSimilarity $title ([string]$key)) -ge 0.6) { $clashes++ }
            }
            if ($looksLikeTarget -and $clashes -eq 1) {
                $pending.Remove($pickedFor)
                $renamed += ("$pickedFor -> $title")
                Set-RosterVerified $title $kind $pickedFor
                Write-RunLog "이름 바로잡음: '$pickedFor' → '$title'"
            } else {
                Write-RunLog "지나감: 열린 방 '$title' 은(는) 확인하려던 방이 아닙니다."
                $notTarget['N:' + $title] = $true
            }
        }
        if ($pending.Count -eq 0) { break }
        $fresh = Get-KakaoLayout (Get-MainKakaoWindow)
        if ($null -eq $fresh.List) { break }
        Move-ListByWheel $fresh.List 'down' ([Math]::Max(3, [Math]::Min(8, $rowsSeen - 1)))
        Start-Sleep -Milliseconds 200
    }

    return [pscustomobject]@{
        Confirmed = @($confirmed)
        Renamed = @($renamed)
        NotFound = @($pending.Keys)
    }
}

# 확인한 이름을 저장된 목록에 적어 둡니다. 예전 이름이 있으면 바꿔치웁니다.
function Set-RosterVerified([string]$Name, [string]$Kind, [string]$OldName) {
    $name = ConvertTo-ExactKey $Name
    if (-not $name) { return }
    $old = ConvertTo-ExactKey $OldName
    $rows = @()
    $found = $false
    foreach ($row in (Get-Roster)) {
        if ($row.Name -ceq $name -or ($old -and $row.Name -ceq $old)) {
            if ($found) { continue }
            $found = $true
            $rows += [pscustomobject]@{
                Name = $name
                ListText = $(if ($old -and $old -cne $name) { $old } else { $row.ListText })
                Kind = $(if ($Kind -and $Kind -ne 'unknown') { $Kind } else { $row.Kind })
                Order = $row.Order
                Verified = $true
                LastSeen = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            }
            continue
        }
        $rows += $row
    }
    if (-not $found) {
        $rows += [pscustomobject]@{
            Name = $name; ListText = $(if ($old) { $old } else { $name })
            Kind = $(if ($Kind) { $Kind } else { 'unknown' })
            Order = @($rows).Count; Verified = $true
            LastSeen = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        }
    }
    Set-Roster $rows
    if ($old -and $old -cne $name) { Rename-RoomInGroups $old $name }
}
# 대상 방을 한 번씩 열어만 봅니다. 아무것도 보내지 않습니다.
# 카카오톡은 방을 처음 열 때 대화를 통째로 불러옵니다. 방에 따라 12초까지 걸립니다.
# 다 불러오기 전에는 Enter 를 눌러도 전송이 되지 않습니다.
# 한 번 열어 둔 방은 카카오톡이 기억해서 다음부터 금방 열립니다.
# [채팅방 목록 새로고침]을 정확 방식으로 하면 이 일이 이미 되어 있습니다.
function Invoke-RoomPreload([string[]]$Rooms) {
    $targets = @($Rooms | ForEach-Object { ConvertTo-ExactKey ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
    if ($targets.Count -eq 0) { return $false }
    Write-RunLog "방 미리 열기: $($targets.Count)개를 한 번씩 열어 대화가 다 불러와지는지 봅니다."
    Write-RunLog '보내지 않습니다. 처음 한 번만 하면 되고, 이후 발송이 훨씬 안정적입니다.'
    $content = New-SendContent $true
    # 미리 열 때는 넉넉히 기다립니다. 여기서 오래 걸려도 실제 발송이 빨라집니다.
    $content.OpenTimeoutMs = [Math]::Max(12000, [int]$content.OpenTimeoutMs)
    $content.SettleMs = [Math]::Max(8000, [int]$content.SettleMs)
    Reset-SendProgress $targets
    Reset-DeliveryState
    $outcome = $null
    try {
        $outcome = Invoke-RosterSend $targets $content ([int]$script:config.ScanPages) 0 0 0 1
    } catch {
        Write-RunLog "방 미리 열기 중단: $($_.Exception.Message)"
        return $false
    }
    if ($null -eq $outcome) { return $false }
    Write-RunLog "방 미리 열기 끝: 열림 $($outcome.Sent)개 / 열지 못함 $($outcome.Failed)개 (전체 $($outcome.Total)개)"
    return $true
}

function New-SendContent([bool]$DryRun) {
    return [pscustomobject]@{
        Message = [string]$script:config.Message
        TemplateName = [string]$script:lastTemplateName
        Attachments = @($script:config.Attachments)
        AttachmentWaitMs = [int]$script:config.AttachmentWaitMs
        GroupPhotos = [bool]$script:config.GroupPhotos
        PhotoBatchSize = [int]$script:config.PhotoBatchSize
        OpenTimeoutMs = [Math]::Max(3000, [int]$script:config.OpenTimeoutMs)
        SettleMs = [Math]::Max(0, [Math]::Min(30000, [int]$script:config.SettleMs))
        DryRun = $DryRun
    }
}

function Get-TabLabelForType([string]$Type) {
    if ($Type -eq $script:RoomTypeOpen) { return '오픈채팅' }
    return '채팅'
}

# 고른 방에 모두 보냅니다.
# PC 카카오톡의 [채팅] 목록에는 일반 채팅방과 오픈채팅방이 함께 들어 있습니다.
# 그래서 종류로 나누지 않고 한 목록을 훑습니다. 보낼 때도 종류를 가리지 않습니다.
# 시작한 뒤에는 사용자가 다시 누를 것이 없습니다. 끝까지 알아서 갑니다.
#
# Targets 를 주면 그 방들만 보냅니다. (실패한 방만 다시 보내기 · 이어서 발송)
# Resume 이 참이면 저장해 둔 진행 상태를 그대로 이어받습니다.
function Invoke-Broadcast([string[]]$Targets = $null, [bool]$Resume = $false) {
    $rooms = @()
    if ($null -ne $Targets -and @($Targets).Count -gt 0) {
        $rooms = @(@($Targets) | ForEach-Object { ConvertTo-ExactKey ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
    } else {
        $rooms = @($script:config.Rooms | ForEach-Object { ConvertTo-ExactKey ([string]$_) } | Where-Object { $_ } | Select-Object -Unique)
    }
    if ($rooms.Count -eq 0) { throw '보낼 채팅방을 한 개 이상 골라 주세요.' }
    if ($rooms.Count -gt 500) { throw '안전을 위해 한 번에 최대 500개 방까지만 처리합니다.' }
    $dryRun = [bool]$script:config.DryRun

    $content = New-SendContent $dryRun
    # 첨부 파일을 미리 훑어 봅니다. 발송 도중에 없는 파일을 만나면 거기서 막힙니다.
    if (-not $dryRun) {
        $check = Test-AttachmentList @($content.Attachments)
        if (@($check.Bad).Count -gt 0) {
            foreach ($why in @($check.Bad)) { Write-RunLog "첨부 확인: $why" }
            $ask = "첨부 파일 $(@($check.Bad).Count)개에 문제가 있습니다." + "`r`n`r`n" +
                   ((@($check.Bad) | Select-Object -First 8) -join "`r`n")
            if (@($check.Bad).Count -gt 8) { $ask += "`r`n… 외 $((@($check.Bad).Count) - 8)개" }
            if (@($check.Good).Count -eq 0 -and [string]::IsNullOrWhiteSpace([string]$content.Message)) {
                throw ($ask + "`r`n`r`n보낼 것이 하나도 남지 않아 시작하지 않았습니다.")
            }
            $ask += "`r`n`r`n[예] 문제 있는 파일만 빼고 보냅니다." + "`r`n" + "[아니오] 시작하지 않습니다."
            if ([System.Windows.Forms.MessageBox]::Show($ask, '첨부 파일 확인', 'YesNo', 'Warning') -ne 'Yes') {
                throw '첨부 파일에 문제가 있어 시작하지 않았습니다.'
            }
            $content.Attachments = @($check.Good)
            Write-RunLog "문제 있는 첨부 $(@($check.Bad).Count)개를 빼고 $(@($check.Good).Count)개만 보냅니다."
        }
    }

    $mode = if ($dryRun) { '확인 전용' } else { '실제 발송' }
    $interval = Get-EffectiveInterval (Get-Date)
    $retry = [Math]::Max(0, [Math]::Min(5, [int]$script:config.RetryCount))
    $holiday = Get-HolidayName (Get-Date)
    if ($holiday) { Write-RunLog "오늘은 $holiday 입니다. 방 간격 $($interval)초로 진행합니다." }
    $batchSize = [int]$script:config.BatchSize
    $batchRest = [int]$script:config.BatchRestMinutes
    if ($batchSize -gt 0 -and $batchRest -gt 0) {
        Write-RunLog "묶음 발송: $($batchSize)개마다 $($batchRest)분 쉽니다."
    }
    Write-RunLog '─────────────────────────────'
    Write-RunLog ("작업 시작: 방 {0}개 / 모드={1} / 간격 {2}초 / 재시도 {3}회" -f $rooms.Count, $mode, $interval, $retry)
    if (-not $dryRun) {
        $groupText = if ([bool]$content.GroupPhotos) { "$([int]$content.PhotoBatchSize)장씩" } else { '쓰지 않음' }
        Write-RunLog ("보낼 문구 {0}자 / 첨부 {1}개 / 사진 묶음 {2}" -f ([string]$content.Message).Length, @($content.Attachments).Count, $groupText)
    }

    # 고른 방이 모두 창으로 열려 있는지 봅니다.
    # 모두 열려 있으면 카카오톡 목록이 필요 없습니다. 그 창들로 바로 보내면 됩니다.
    $openNames = @{}
    try { foreach ($room in (Get-OpenChatRooms)) { $openNames[$room.Name] = $true } } catch { }
    $notOpen = @()
    foreach ($room in $rooms) { if (-not $openNames.ContainsKey($room)) { $notOpen += $room } }
    if ($notOpen.Count -eq 0) {
        Write-RunLog "고른 방 $($rooms.Count)개가 모두 창으로 열려 있습니다. 목록을 훑지 않고 그 창으로 바로 보냅니다."
    } else {
        Write-RunLog "창으로 열려 있는 방 $($rooms.Count - $notOpen.Count)개 / 목록에서 찾아야 할 방 $($notOpen.Count)개"
    }

    # 목록에서 찾아야 할 방이 있을 때만 카카오톡 메인 창이 필요합니다.
    $mainWindow = $null
    $ready = $null
    try { $ready = Test-KakaoReady $true $false } catch { $ready = $null }
    if ($null -ne $ready -and $ready.Ok) {
        $mainWindow = $ready.Layout.Main
    } elseif ($notOpen.Count -gt 0) {
        $why = if ($null -ne $ready) { [string]$ready.Reason } else { '카카오톡을 찾지 못했습니다.' }
        throw $why
    }

    # 방마다 어디까지 갔는지 보여 줄 표를 채웁니다. 고른 방이 모두 여기 들어갑니다.
    if ($Resume) {
        Write-RunLog '이어서 발송입니다. 이미 보낸 방과 파일은 건너뜁니다.'
    } else {
        Reset-SendProgress $rooms
        Reset-DeliveryState
        $script:runStats = @{ Photos = 0; Files = 0; Messages = 0 }
        $script:runStartedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $script:trackDelivery = $true
    Save-RunProgress $content

    # 어떤 환경인지 남겨 둡니다. PC 마다 결과가 다를 때 짚어 보기 위해서입니다.
    Write-EnvironmentLog $mainWindow

    # 글과 사진을 붙여넣으려면 클립보드를 써야 합니다.
    # 사용자가 복사해 두었던 것이 날아가지 않도록 챙겨 두었다가 끝나면 되돌립니다.
    $script:savedClipboard = $null
    $script:savedClipboardFiles = $null
    try { $script:savedClipboard = [string][System.Windows.Forms.Clipboard]::GetText() } catch { }
    try { $script:savedClipboardFiles = @([System.Windows.Forms.Clipboard]::GetFileDropList()) } catch { }

    $result = $null
    try {
        $result = Invoke-RosterSend $rooms $content ([int]$script:config.ScanPages) $interval $batchSize $batchRest $retry
    } finally {
        $script:trackDelivery = $false
        Restore-SavedClipboard
    }

    if ($null -eq $result) { return 0 }
    Save-RunProgress $content

    # 실패한 방을 따로 모아 둡니다. [실패한 방만 다시 보내기] 에 씁니다.
    $failedRooms = @()
    foreach ($name in $script:progressOrder) {
        if ([string]$script:progressRows[$name].Status -eq '실패') { $failedRooms += [string]$name }
    }
    $handled = $result.Sent + $result.Failed
    $script:lastRunResult = [pscustomobject]@{
        Total = $result.Total
        Sent = $result.Sent
        Failed = $result.Failed
        Missing = ($result.Total - $handled)
        Photos = [int]$script:runStats.Photos
        Files = [int]$script:runStats.Files
        Messages = [int]$script:runStats.Messages
        FailedRooms = @($failedRooms)
        DryRun = $dryRun
        FinishedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }

    Write-RunLog '─────────────────────────────'
    Write-RunLog ("전체 대상: {0}개" -f $result.Total)
    Write-RunLog ("성공:      {0}개" -f $result.Sent)
    Write-RunLog ("실패:      {0}개" -f $result.Failed)
    Write-RunLog ("누락:      {0}개" -f $script:lastRunResult.Missing)
    Write-RunLog ("발송 사진: {0}장 / 파일 {1}개 / 메시지 {2}건" -f $script:runStats.Photos, $script:runStats.Files, $script:runStats.Messages)
    if ($script:lastRunResult.Missing -eq 0) {
        Write-RunLog '숫자가 맞습니다. 빠진 방은 없습니다.'
    } else {
        Write-RunLog "숫자가 맞지 않습니다. 고른 $($result.Total)개 중 $handled 개만 처리했습니다."
    }
    if ($failedRooms.Count -gt 0) {
        Write-RunLog "실패한 방: $((@($failedRooms) | Select-Object -First 10) -join ', ')"
    }
    Write-RunLog '자세한 결과는 logs 폴더의 발송기록 파일에 표로 남았습니다.'

    if ($dryRun) {
        # 확인 전용은 아무것도 보내지 않습니다. 완료라고 하면 보낸 줄 알게 됩니다.
        Write-RunLog ("확인 전용으로 끝났습니다: 방 {0}개를 열어 보았고, 실제로 보낸 메시지는 없습니다." -f $result.Sent)
        Write-RunLog '실제로 보내시려면 [3. 보내기] 화면에서 [실제 발송] 을 고르세요.'
    } elseif ($result.Sent -gt 0) {
        # 오늘 보냈다고 적어 둡니다. 공휴일에서 옮겨 온 날에 두 번 가지 않게 합니다.
        Add-SentDay (Get-Date)
        try { Save-Config $script:config } catch { }
    }
    # 남김없이 끝났으면 이어서 할 것이 없습니다.
    if ($result.Failed -eq 0 -and $script:lastRunResult.Missing -eq 0) { Clear-RunProgress }
    return $result.Sent
}

# 챙겨 두었던 클립보드를 되돌립니다. 글이든 파일이든 원래대로 돌려놓습니다.
function Restore-SavedClipboard {
    try {
        if ($null -ne $script:savedClipboardFiles -and @($script:savedClipboardFiles).Count -gt 0) {
            $files = New-Object System.Collections.Specialized.StringCollection
            foreach ($path in @($script:savedClipboardFiles)) { [void]$files.Add([string]$path) }
            [System.Windows.Forms.Clipboard]::SetFileDropList($files)
            return
        }
    } catch { }
    try {
        if ($null -ne $script:savedClipboard -and $script:savedClipboard -ne '') {
            if (-not (Test-ClipboardHasText $script:savedClipboard)) {
                [System.Windows.Forms.Clipboard]::SetText($script:savedClipboard)
            }
            return
        }
    } catch { }
    # 원래 비어 있었다면, 우리가 넣어 둔 파일 목록을 그대로 두면 안 됩니다.
    try { [System.Windows.Forms.Clipboard]::Clear() } catch { }
}

function Invoke-TestSend([bool]$DryRun) {
    $room = ConvertTo-ExactKey ([string]$script:config.TestRoom)
    if (-not $room) { throw '테스트 채팅방 이름을 입력해 주세요.' }
    if (-not $DryRun) {
        foreach ($attachment in @($script:config.Attachments)) {
            if (-not (Test-Path -LiteralPath ([string]$attachment) -PathType Leaf)) { throw "첨부 파일을 찾을 수 없습니다: $attachment" }
        }
    }
    $label = if ($DryRun) { '테스트(확인만)' } else { '테스트 발송' }
    Write-RunLog "$label 시작: '$room'"
    Reset-SendProgress @($room)
    Reset-DeliveryState
    $script:trackDelivery = $true
    $result = $null
    try {
        $result = Invoke-RosterSend @($room) (New-SendContent $DryRun) ([int]$script:config.ScanPages) 0 0 0 1
    } finally { $script:trackDelivery = $false }
    $ok = ($null -ne $result -and $result.Sent -gt 0)
    if (-not $ok) {
        Write-RunLog "'$room' 에 보내지 못했습니다. 카카오톡에 보이는 이름과 정확히 같은지 확인해 주세요."
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
        Body  = "카카오톡에서 보낼 채팅방을 두 번 눌러 창으로 열어 두세요.`r`n`r`n그 상태로 [열어 둔 채팅방 읽기]를 누르면 열려 있는 방을 그대로 가져옵니다.`r`n창 제목이 곧 방 이름이라 틀릴 일이 없습니다. 가져온 방은 바로 발송 대상으로 체크됩니다.`r`n`r`n방이 많아 일일이 열기 어려우면 [전체 목록 읽기]로 카카오톡 목록을 훑을 수도 있습니다.`r`n`r`n읽는 동안에는 마우스와 키보드를 사용하지 마세요."
    },
    @{
        Page = 'rooms'
        Title = '그룹으로 묶어 쓰기'
        Body  = "자주 보내는 방들을 그룹으로 묶어 두면 다음부터 한 번에 고를 수 있습니다.`r`n`r`n① 보낼 방들을 체크합니다.`r`n② [새 그룹 만들기]를 누르고 이름을 정합니다. (예: 학부모, 홍보방)`r`n`r`n다음에는 그룹을 고르고 [이 그룹 체크]만 누르면 그 방들이 한 번에 체크됩니다.`r`n`r`n이미 있는 그룹에 더 넣으려면 방을 체크한 뒤 [체크한 방 넣기]를 누르세요."
    },
    @{
        Page = 'rooms'
        Title = '2단계 · 이름 정확하게 맞추기'
        Body  = "이름 옆에 [확인됨] 이라고 적힌 방은 창 제목으로 이름을 확정한 방입니다. 틀릴 일이 없습니다.`r`n`r`n[화면 글자] 라고 적힌 방은 화면을 읽은 것이라 틀릴 수 있습니다. 그 방들을 체크하고 [이름 확인·보정]을 누르면 하나씩 열어 바로잡습니다.`r`n`r`n창으로 열어 두고 [열어 둔 채팅방 읽기]로 가져온 방은 언제나 [확인됨] 입니다."
    },
    @{
        Page = 'compose'
        Title = '3단계 · 문구와 사진 준비'
        Body  = "[1. 보낼 내용] 화면에 보낼 문구를 적고, 사진이나 파일을 추가합니다.`r`n`r`n첨부가 먼저 목록 순서대로 하나씩 전송되고, 그다음 문구가 한 개의 메시지로 전송됩니다. 순서는 [위로] [아래로] 버튼으로 바꿀 수 있습니다.`r`n`r`n자주 쓰는 문구는 [저장 메시지]에 이름을 붙여 담아 두고 골라 쓸 수 있습니다."
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
    $required = @('Rooms', 'KnownRooms', 'RoomTypes', 'RoomListNames', 'Groups', 'QuietEnabled', 'QuietStart', 'QuietEnd', 'HolidayMode', 'HolidayIntervalMultiplier', 'SkipWeekend', 'ExtraHolidays', 'AutoDownloadUpdate', 'SkipSendConfirm', 'RepeatEnabled', 'RepeatMinutes', 'RepeatCount', 'BatchSize', 'BatchRestMinutes', 'Message', 'Attachments', 'ScheduledAt', 'IntervalSeconds', 'DryRun', 'ScanPages', 'TestRoom', 'AttachmentWaitMs', 'OpenTimeoutMs', 'SettleMs', 'PreloadRooms', 'PreloadDone', 'TruncatedRooms', 'HolidayRules', 'SentDays', 'RoomKinds', 'Roster', 'RosterScannedAt', 'ScanExactNames', 'Templates', 'RetryCount', 'CloseAfterSend', 'GroupPhotos', 'PhotoBatchSize', 'AutoCheckUpdate', 'TourDone', 'Calibration')
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
    if ((Remove-RoomNameNoise '0※자유 홍보 방 ※') -ne '※자유 홍보 방 ※') { throw '이름 다듬기 실패 (기호 앞 뱃지)' }
    if ((Remove-RoomNameNoise '마케팅 자유 홍보.-') -ne '마케팅 자유 홍보') { throw '이름 다듬기 실패 (끝 찌꺼기)' }
    # 한 글자 오인식으로 같은 방이 둘로 남는 것을 합칩니다.
    if (-not (Test-NearSameRoomName '5K X 아우여 (따몽이)' '5K X 아우여 (따봉이)')) { throw '비슷한 이름을 합치지 못합니다' }
    # 짧은 이름은 진짜 다른 방일 수 있으므로 합치면 안 됩니다.
    if (Test-NearSameRoomName '토스' '토트') { throw '짧은 이름까지 합칩니다' }
    if (Test-NearSameRoomName '네이버쇼핑입니다' '카카오쇼핑입니다') { throw '두 글자 이상 달라도 합칩니다' }
    # 화면 글자 인식 배율은 창 폭에 맞춰 2~4배 사이여야 합니다.
    $probeWin = [pscustomobject]@{ Width = 325 }
    if ((Get-OcrScaleFor $probeWin) -ne 4) { throw '좁은 목록에서 확대 배율이 4배가 아닙니다' }
    $probeWide = [pscustomobject]@{ Width = 900 }
    if ((Get-OcrScaleFor $probeWide) -lt 2) { throw '넓은 목록에서 확대 배율이 너무 작습니다' }

    # ----- 채팅방 제목 읽기 -----
    # 목록 한 줄은 이렇게 생겼습니다.
    #   투투              11:32     <- 이름과 시각은 같은 높이
    #   오늘 확인했습니다            <- 마지막 대화내용
    # 시각이 있는 높이의 글자만 이름으로 봅니다.
    $probeLines = @(
        [pscustomobject]@{ Text = '투투';               Left = 60; Top = 20;  Height = 14 },
        [pscustomobject]@{ Text = '11:32';              Left = 250; Top = 20;  Height = 12 },
        [pscustomobject]@{ Text = '오늘 확인했습니다';   Left = 60; Top = 40;  Height = 13 },
        [pscustomobject]@{ Text = '뽀식';               Left = 60; Top = 90;  Height = 14 },
        [pscustomobject]@{ Text = '오전 11•20';         Left = 250; Top = 90;  Height = 12 },
        [pscustomobject]@{ Text = '대표님 연락드렸습니다'; Left = 60; Top = 110; Height = 13 },
        [pscustomobject]@{ Text = '네이버쇼핑';          Left = 60; Top = 160; Height = 14 },
        [pscustomobject]@{ Text = '오전 1051';          Left = 250; Top = 160; Height = 12 },
        [pscustomobject]@{ Text = '감사합니다.';         Left = 60; Top = 180; Height = 13 }
    )
    $probeNames = @(Get-RoomNamesFromOcrLines $probeLines 325)
    $probeWant = @('투투', '뽀식', '네이버쇼핑')
    if ($probeNames.Count -ne 3) { throw "제목을 3개 읽어야 하는데 $($probeNames.Count)개입니다: $($probeNames -join ', ')" }
    for ($i = 0; $i -lt 3; $i++) {
        if ($probeNames[$i] -ne $probeWant[$i]) { throw "제목이 다릅니다: $($probeNames[$i]) (기대 $($probeWant[$i]))" }
    }
    # 마지막 대화내용이 이름으로 들어가면 안 됩니다.
    foreach ($bad in @('오늘 확인했습니다', '대표님 연락드렸습니다', '감사합니다.')) {
        if ($probeNames -contains $bad) { throw "마지막 대화내용을 제목으로 읽었습니다: $bad" }
    }
    # 제목과 마지막 대화내용이 따로 담기는지 봅니다.
    $probeRows = @(Get-ChatRoomRowsFromOcr $probeLines 325)
    if ($probeRows.Count -ne 3) { throw "줄을 3개로 나눠야 하는데 $($probeRows.Count)개입니다" }
    if ($probeRows[0].Title -ne '투투') { throw '첫 줄 제목이 틀립니다' }
    if ($probeRows[0].LastMessage -ne '오늘 확인했습니다') { throw '첫 줄 대화내용이 틀립니다' }
    # 제목을 못 읽으면 아래 대화내용을 대신 쓰지 않고 실패로 둡니다.
    $probeNoTitle = @(
        [pscustomobject]@{ Text = '오전 11:32';        Left = 250; Top = 20; Height = 12 },
        [pscustomobject]@{ Text = '대표님 확인했습니다'; Left = 60; Top = 40; Height = 13 }
    )
    $probeRows2 = @(Get-ChatRoomRowsFromOcr $probeNoTitle 325)
    if ($probeRows2.Count -ne 1) { throw '제목 없는 줄을 못 세었습니다' }
    if ($probeRows2[0].Ok) { throw '제목이 없는데 정상이라고 합니다' }
    if ($probeRows2[0].Title -eq '대표님 확인했습니다') { throw '제목 대신 대화내용을 넣었습니다' }
    if (@(Get-RoomNamesFromOcrLines $probeNoTitle 325).Count -ne 0) { throw '제목을 못 읽었는데 이름 목록에 넣었습니다' }
    # 시각을 하나도 못 읽으면 아무 제목도 정하지 않습니다.
    $probeNoAnchor = @(
        [pscustomobject]@{ Text = '투투';             Left = 60; Top = 20; Height = 14 },
        [pscustomobject]@{ Text = '오늘 확인했습니다'; Left = 60; Top = 40; Height = 13 }
    )
    if (@(Get-RoomNamesFromOcrLines $probeNoAnchor 325).Count -ne 0) { throw '시각이 없는데 제목을 추측했습니다' }
    if (-not $script:lastAnchorMissing) { throw '시각을 못 찾은 것을 기록하지 않았습니다' }
    # 제목이 여러 조각으로 읽혀도 화면 순서대로 이어 붙여야 합니다.
    $probeSplit = @(
        [pscustomobject]@{ Text = '쇼핑';       Left = 110; Top = 20; Height = 14 },
        [pscustomobject]@{ Text = '네이버';     Left = 60;  Top = 20; Height = 14 },
        [pscustomobject]@{ Text = '광고방';     Left = 150; Top = 21; Height = 14 },
        [pscustomobject]@{ Text = '오전 11:32'; Left = 250; Top = 20; Height = 12 },
        [pscustomobject]@{ Text = '감사합니다'; Left = 60;  Top = 40; Height = 13 }
    )
    $probeMerged = @(Get-RoomNamesFromOcrLines $probeSplit 325)
    if ($probeMerged.Count -ne 1 -or $probeMerged[0] -ne '네이버 쇼핑 광고방') {
        throw "조각난 제목을 화면 순서대로 못 붙입니다: $($probeMerged -join ', ')"
    }
    # 안 읽은 개수나 시각이 제목에 섞이면 안 됩니다.
    $probeBadge = @(
        [pscustomobject]@{ Text = '투투';       Left = 60;  Top = 20; Height = 14 },
        [pscustomobject]@{ Text = '3';          Left = 140; Top = 21; Height = 10 },
        [pscustomobject]@{ Text = '오전 11:32'; Left = 250; Top = 20; Height = 12 }
    )
    $probeBadgeNames = @(Get-RoomNamesFromOcrLines $probeBadge 325)
    if ($probeBadgeNames.Count -ne 1 -or $probeBadgeNames[0] -ne '투투') {
        throw "안 읽은 개수가 제목에 섞였습니다: $($probeBadgeNames -join ', ')"
    }
    # 시각 표기를 보기 좋게 되돌리는지 봅니다.
    if ((ConvertTo-ReadableTime '오전 10•20') -ne '오전 10:20') { throw '시각 되돌리기 실패 (가운뎃점)' }
    if ((ConvertTo-ReadableTime '오전 1051') -ne '오전 10:51') { throw '시각 되돌리기 실패 (붙은 숫자)' }
    if ((ConvertTo-ReadableTime '오후 148') -ne '오후 1:48') { throw '시각 되돌리기 실패 (세 자리)' }
    # 긴 제목도 그대로 읽어야 합니다.
    foreach ($probeLong in @('네이버 쇼핑 광고 운영방', '5K 마케팅 운영팀', '광고문의_1', '서든어택 Andrew 운영진')) {
        $probeRow = @(
            [pscustomobject]@{ Text = $probeLong; Left = 60; Top = 20; Height = 14 },
            [pscustomobject]@{ Text = '오전 11:32'; Left = 250; Top = 20; Height = 12 }
        )
        $probeGot = @(Get-RoomNamesFromOcrLines $probeRow 325)
        if ($probeGot.Count -ne 1 -or $probeGot[0] -ne $probeLong) {
            throw "긴 제목을 그대로 못 읽습니다: $probeLong -> $($probeGot -join ', ')"
        }
    }
    # 화면 글자 인식이 놓친 시각 표기도 알아봐야 합니다.
    foreach ($probeTime in @('오전 10•20', '오전 1148', '11:32', '2026•05-18', '어제')) {
        if (-not (Test-RowAnchorText $probeTime)) { throw "시각을 못 알아봅니다: $probeTime" }
    }
    # 방 이름을 시각으로 잘못 보면 안 됩니다.
    foreach ($probeName in @('투투', '뽀식', '네이버쇼핑', '5K마케팅', '광고 문의방', '테스트123')) {
        if (Test-RowAnchorText $probeName) { throw "방 이름을 시각으로 봤습니다: $probeName" }
    }
    if ((Get-OcrScaleFor $probeWide) -lt 2) { throw '넓은 목록에서 확대 배율이 너무 작습니다' }
    # 화면 배율 도우미가 제대로 곱하는지 봅니다.
    $savedScale = $script:UiScale
    try {
        $script:UiScale = 1.5
        if ((S 100) -ne 150) { throw '배율 계산이 틀립니다' }
        $pt = New-UiPoint 24 40
        if ($pt.X -ne 36 -or $pt.Y -ne 60) { throw '배율에 맞춘 위치 계산이 틀립니다' }
    } finally { $script:UiScale = $savedScale }
    # 방 종류는 창 제목에 적힌 것으로만 정합니다. 이름으로 짐작하지 않습니다.
    if ((Get-RoomKindFromTitle '우리반 공지방 (24)' $script:RoomTypeNormal) -ne 'group') { throw '단체방을 못 알아봅니다' }
    if ((Get-RoomKindFromTitle '택규형' $script:RoomTypeNormal) -ne 'unknown') { throw '알 수 없는 방을 억지로 나눕니다' }
    if ((Get-RoomKindFromTitle '자유 홍보방' $script:RoomTypeOpen) -ne 'open') { throw '오픈채팅을 못 알아봅니다' }
    # 공휴일 규칙이 저장되고 다시 읽히는지 봅니다.
    $savedRules = @($script:config.HolidayRules)
    $savedDays = @($script:config.SentDays)
    try {
        Set-ConfigValue 'HolidayRules' @()
        Set-ConfigValue 'SentDays' @()
        Set-HolidayRule '2026-09-24' '추석' 'move' '2026-09-25'
        $probeRule = Get-HolidayRule ([datetime]'2026-09-24')
        if ($null -eq $probeRule -or [string]$probeRule.MoveTo -ne '2026-09-25') { throw '공휴일 규칙이 저장되지 않습니다' }
        if ($null -eq (Get-MovedFromHoliday ([datetime]'2026-09-25'))) { throw '옮겨 온 날을 못 알아봅니다' }
        if ($null -ne (Get-SendBlockReason ([datetime]'2026-09-25 10:00'))) { throw '옮긴 날인데 막습니다' }
        Add-SentDay ([datetime]'2026-09-25')
        if ($null -eq (Get-SendBlockReason ([datetime]'2026-09-25 10:00'))) { throw '이미 보낸 날인데 또 보냅니다' }
        Set-HolidayRule '2026-09-24' '추석' 'normal' ''
        if (@($script:config.HolidayRules).Count -ne 0) { throw '그대로 보냄인데 규칙이 남습니다' }
    } finally {
        Set-ConfigValue 'HolidayRules' @($savedRules)
        Set-ConfigValue 'SentDays' @($savedDays)
    }
    if ((Get-OcrScaleFor $probeWide) -lt 2) { throw '넓은 목록에서 확대 배율이 너무 작습니다' }
    # ----- 이름을 정확히 견주는지 -----
    # 여기가 이번 고침의 핵심입니다. 비슷한 이름을 같은 방으로 보면 안 됩니다.
    if (-not (Test-SameRoomExact '뽀식' '뽀식')) { throw '같은 이름을 다르다고 합니다' }
    if (Test-SameRoomExact '뽀식' '포식') { throw '뽀식 과 포식 을 같은 방이라고 합니다' }
    if (Test-SameRoomExact '투투' '토토') { throw '투투 와 토토 를 같은 방이라고 합니다' }
    if (Test-SameRoomExact '우리반 공지방' '우리반 공지방 2기') { throw '앞부분만 같은 방을 같다고 합니다' }
    if (-not (Test-SameRoomExact ' 뽀식  방 ' '뽀식 방')) { throw '빈칸 차이를 다른 방으로 봅니다' }
    if ((Get-RoomTitleName '우리반 공지방 (24)') -ne '우리반 공지방') { throw '인원수를 떼어 내지 못합니다' }
    if ((Get-RoomTitleName '뽀식') -ne '뽀식') { throw '인원수가 없는 제목을 바꿔 버립니다' }
    if ((Get-RoomTitleName '(24)명 모임') -ne '(24)명 모임') { throw '이름 앞의 괄호를 잘못 떼어 냅니다' }

    # 엄격 비교를 켰을 때 창 제목이 정확히 같아야만 통과해야 합니다.
    $script:strictTitleMatch = $true
    try {
        if (-not (Test-RoomTitle '우리반 공지방 (24)' '우리반 공지방')) { throw '인원수가 붙은 제목을 못 알아봅니다' }
        if (Test-RoomTitle '우리반 공지방 2기' '우리반 공지방') { throw '엄격 비교인데 다른 방을 같다고 합니다' }
        if (Test-RoomTitle '포식' '뽀식') { throw '엄격 비교인데 글자가 다른 방을 같다고 합니다' }
    } finally { $script:strictTitleMatch = $false }



    # 이모지가 든 방 이름이 상하면 안 됩니다. 실제로 그런 방이 있습니다.
    $probeEmoji = '나만의 대표님' + [char]::ConvertFromUtf32(0x1F618)
    if ((ConvertTo-ExactKey $probeEmoji) -cne $probeEmoji) { throw '이모지가 든 이름이 바뀝니다' }
    if ((Get-RoomTitleName $probeEmoji) -cne $probeEmoji) { throw '이모지가 든 제목이 바뀝니다' }
    if (-not (Test-SameRoomExact $probeEmoji $probeEmoji)) { throw '이모지가 든 같은 방을 다르다고 합니다' }
    # 가족 이모지처럼 여러 글자를 이어 붙인 것도 그대로 두어야 합니다.
    $probeZwj = '가족' + [char]::ConvertFromUtf32(0x1F468) + [char]0x200D + [char]::ConvertFromUtf32(0x1F467) + '방'
    if ((ConvertTo-ExactKey $probeZwj) -cne $probeZwj) { throw '이어 붙인 이모지가 끊어집니다' }
    # ----- 채팅방 창 가려내기 -----
    # 사용자가 열어 둔 채팅방 창만 골라내야 합니다.
    # 미리보기 창이나 메인 창이 섞여 들어오면 엉뚱한 곳에 보내게 됩니다.
    $okShape = 'EVA_Window_Dblclk'
    if (-not (Test-ChatWindowShape '뽀식' $okShape 400 500 $true $false $true $true)) { throw '멀쩡한 채팅방 창을 걸러 냅니다' }
    if (Test-ChatWindowShape '뽀식' $okShape 400 500 $false $false $true $true) { throw '안 보이는 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '카카오톡' $okShape 400 500 $true $false $true $true) { throw '카카오톡 본 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape 'KakaoTalk' $okShape 400 500 $true $false $true $true) { throw 'KakaoTalk 본 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '' $okShape 400 500 $true $false $true $true) { throw '제목 없는 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '뽀식' $okShape 100 500 $true $false $true $true) { throw '너무 좁은 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '뽀식' $okShape 400 100 $true $false $true $true) { throw '너무 낮은 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '사진 보내기' $okShape 400 500 $true $false $false $false) { throw '입력칸 없는 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '프로필' $okShape 400 500 $true $false $true $false) { throw '대화 목록 없는 창을 채팅방이라고 합니다' }
    # 클래스가 다르면 채팅방이 아닙니다. 툴팁과 알림 창이 여기서 걸러집니다.
    if (Test-ChatWindowShape '뽀식' 'tooltips_class32' 400 500 $true $false $true $true) { throw '툴팁 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '뽀식' 'EVA_Window' 400 500 $true $false $true $true) { throw '다른 클래스 창을 채팅방이라고 합니다' }
    if (Test-ChatWindowShape '뽀식' 'Chrome_WidgetWin_1' 400 500 $true $false $true $true) { throw '카카오톡이 아닌 창을 채팅방이라고 합니다' }
    # 채팅 목록 화면을 품고 있으면 메인 창입니다. 제목이 방 이름처럼 보여도 아닙니다.
    if (Test-ChatWindowShape '뽀식' $okShape 400 500 $true $true $true $true) { throw '메인 창을 채팅방이라고 합니다' }
    # ----- 저장된 목록 -----
    $savedRoster = @($script:config.Roster)
    try {
        Set-Roster @(
            [pscustomobject]@{ Name = '뽀식'; ListText = '포식'; Kind = 'group'; Order = 0; Verified = $true; LastSeen = '' },
            [pscustomobject]@{ Name = '토토'; ListText = '토토'; Kind = 'open';  Order = 1; Verified = $true; LastSeen = '' }
        )
        if (@(Get-Roster).Count -ne 2) { throw '목록을 저장하고 다시 읽지 못합니다' }
        if ($null -eq (Find-RosterEntry '뽀식')) { throw '저장한 방을 찾지 못합니다' }
        if ($null -ne (Find-RosterEntry '포식')) { throw '없는 방을 찾았다고 합니다' }
        if ((Find-RosterEntry '뽀식').ListText -ne '포식') { throw '목록에 보이던 글자를 잃어버렸습니다' }
        # 새로 읽었더니 토토 가 사라지고 투투 가 생긴 상황입니다.
        $fakeScan = [pscustomobject]@{
            Rows = @(
                [pscustomobject]@{ Name = '뽀식'; ListText = '포식'; Kind = 'group'; Order = 0; Verified = $true; LastSeen = '' },
                [pscustomobject]@{ Name = '투투'; ListText = '투투'; Kind = 'open';  Order = 1; Verified = $true; LastSeen = '' }
            )
            FromOpenTab = $false
        }
        $diff = Merge-RosterScan $fakeScan $true
        if (@($diff.Added) -notcontains '투투') { throw '새로 생긴 방을 못 알아봅니다' }
        if (@($diff.Removed) -notcontains '토토') { throw '없어진 방을 못 알아봅니다' }
        if ($diff.Total -ne 2) { throw '새로고침 뒤 방 수가 맞지 않습니다' }
    } finally {
        Set-ConfigValue 'Roster' @($savedRoster)
    }





    # ----- 화면 배율 -----
    # 모니터마다 배율이 다를 수 있습니다. 창 기준으로 물어야 정확합니다.
    # 값을 못 얻으면 96(100%) 으로 돌려주어야 합니다. 0 이 나오면 좌표 계산이 다 틀어집니다.
    $probeDpi = [NativeKakao]::WindowDpi([IntPtr]::Zero)
    if ($probeDpi -lt 72 -or $probeDpi -gt 480) { throw "화면 배율 값이 이상합니다: $probeDpi" }
    $probeDeskDpi = [NativeKakao]::WindowDpi([NativeKakao]::GetForegroundWindow())
    if ($probeDeskDpi -lt 72 -or $probeDeskDpi -gt 480) { throw "창 배율 값이 이상합니다: $probeDeskDpi" }
    # 미리보기 전송 자리 계산이 배율만큼 늘어나는지 봅니다.
    foreach ($probePair in @(@(96, 24), @(120, 30), @(144, 36))) {
        $probeScale = [double]$probePair[0] / 96.0
        $probeUp = [int](24 * $probeScale)
        if ($probeUp -ne $probePair[1]) { throw "배율 $($probePair[0]) 에서 누를 자리가 $probeUp 입니다 ($($probePair[1]) 이어야 합니다)" }
    }
    # ----- 첨부 파일 미리 검사 -----
    # 없는 파일이나 빈 파일을 발송 도중에 만나면 거기서 막힙니다. 미리 걸러야 합니다.
    $probeDir = Join-Path ([System.IO.Path]::GetTempPath()) ('kakao-check-' + [System.Diagnostics.Process]::GetCurrentProcess().Id)
    New-Item -ItemType Directory -Path $probeDir -Force | Out-Null
    try {
        $probeGood = Join-Path $probeDir '사진.jpg'
        [System.IO.File]::WriteAllBytes($probeGood, [byte[]](0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4))
        $probeEmpty = Join-Path $probeDir '빈파일.jpg'
        [System.IO.File]::WriteAllBytes($probeEmpty, (New-Object byte[] 0))
        $probeGone = Join-Path $probeDir '없는파일.jpg'

        if (-not (Test-AttachmentFile $probeGood).Ok) { throw '멀쩡한 파일을 문제 있다고 합니다' }
        $probeMissing = Test-AttachmentFile $probeGone
        if ($probeMissing.Ok) { throw '없는 파일을 괜찮다고 합니다' }
        if ($probeMissing.Reason -notmatch '찾을 수 없습니다') { throw "없는 파일 까닭이 이상합니다: $($probeMissing.Reason)" }
        if ($probeMissing.Reason -notmatch '없는파일\.jpg') { throw '까닭에 파일 이름이 없습니다' }
        $probeZero = Test-AttachmentFile $probeEmpty
        if ($probeZero.Ok) { throw '빈 파일을 괜찮다고 합니다' }
        if ($probeZero.Reason -notmatch '비어 있습니다') { throw "빈 파일 까닭이 이상합니다: $($probeZero.Reason)" }
        if ((Test-AttachmentFile '').Ok) { throw '빈 경로를 괜찮다고 합니다' }

        # 목록으로 보면 좋은 것과 나쁜 것이 갈라져야 합니다.
        $probeSplit = Test-AttachmentList @($probeGood, $probeGone, $probeEmpty)
        if (@($probeSplit.Good).Count -ne 1) { throw "쓸 수 있는 파일이 1개가 아닙니다: $(@($probeSplit.Good).Count)" }
        if (@($probeSplit.Bad).Count -ne 2) { throw "문제 있는 파일이 2개가 아닙니다: $(@($probeSplit.Bad).Count)" }

        # 다른 프로그램이 붙잡고 있으면 못 연다고 해야 합니다.
        $probeLocked = Join-Path $probeDir '잠긴파일.jpg'
        [System.IO.File]::WriteAllBytes($probeLocked, [byte[]](1, 2, 3, 4))
        $probeHold = [System.IO.File]::Open($probeLocked, 'Open', 'Read', 'None')
        try {
            $probeBusy = Test-AttachmentFile $probeLocked
            if ($probeBusy.Ok) { throw '다른 프로그램이 잡고 있는 파일을 괜찮다고 합니다' }
        } finally { $probeHold.Dispose() }
        if (-not (Test-AttachmentFile $probeLocked).Ok) { throw '놓아 준 파일을 여전히 문제라고 합니다' }
    } finally {
        try { Remove-Item -LiteralPath $probeDir -Recurse -Force } catch { }
    }
    # ----- 사진 묶어 보내기 -----
    # 사진은 여러 장을 한 번에 보내야 잘 갑니다.
    # 문서는 카카오톡이 하나씩만 보내므로 따로 나가야 합니다.
    # 사용자가 정한 순서는 어떤 경우에도 지켜야 합니다.
    $probeShots = @('a.jpg', 'b.png', 'c.jpeg', 'd.gif')
    $probeMix = @('a.jpg', 'b.png', '안내.pdf', 'c.jpg', 'd.jpg')

    # 묶기를 끄면 하나씩 나갑니다.
    $probeOne = @(Group-AttachmentBatches $probeShots $false 10)
    if ($probeOne.Count -ne 4) { throw "묶기를 껐는데 4묶음이 아닙니다: $($probeOne.Count)" }
    foreach ($probeBatch in $probeOne) { if (@($probeBatch).Count -ne 1) { throw '묶기를 껐는데 여러 장이 한 묶음이 됐습니다' } }

    # 사진만 있으면 한 묶음입니다.
    $probeAll = @(Group-AttachmentBatches $probeShots $true 10)
    if ($probeAll.Count -ne 1) { throw "사진 4장이 한 묶음이 아닙니다: $($probeAll.Count)" }
    if (@($probeAll[0]).Count -ne 4) { throw '사진 4장이 다 담기지 않았습니다' }
    if ((@($probeAll[0]) -join ',') -ne ($probeShots -join ',')) { throw '사진 순서가 바뀌었습니다' }

    # 한 묶음 크기를 넘으면 나뉩니다.
    $probeSplit = @(Group-AttachmentBatches $probeShots $true 2)
    if ($probeSplit.Count -ne 2) { throw "2장씩 묶으면 2묶음이어야 합니다: $($probeSplit.Count)" }
    if (@($probeSplit[0]).Count -ne 2 -or @($probeSplit[1]).Count -ne 2) { throw '2장씩 나뉘지 않았습니다' }

    # 문서가 끼면 그 앞뒤로 나뉘고, 문서는 혼자 갑니다.
    $probeMixed = @(Group-AttachmentBatches $probeMix $true 10)
    if ($probeMixed.Count -ne 3) { throw "사진·문서·사진은 3묶음이어야 합니다: $($probeMixed.Count)" }
    if (@($probeMixed[0]).Count -ne 2) { throw '앞의 사진 2장이 묶이지 않았습니다' }
    if (@($probeMixed[1]).Count -ne 1 -or $probeMixed[1][0] -ne '안내.pdf') { throw '문서가 혼자 가지 않습니다' }
    if (@($probeMixed[2]).Count -ne 2) { throw '뒤의 사진 2장이 묶이지 않았습니다' }
    # 순서가 그대로여야 합니다.
    $probeFlat = @()
    foreach ($probeBatch in $probeMixed) { $probeFlat += @($probeBatch) }
    if (($probeFlat -join ',') -ne ($probeMix -join ',')) { throw "묶으면서 순서가 바뀌었습니다: $($probeFlat -join ',')" }

    # 빈 목록과 이상한 크기도 버텨야 합니다.
    if (@(Group-AttachmentBatches @() $true 10).Count -ne 0) { throw '빈 목록에서 묶음이 생깁니다' }
    if (@(Group-AttachmentBatches $probeShots $true 0).Count -ne 4) { throw '묶음 크기 0을 1로 보지 않습니다' }
    if (@(Group-AttachmentBatches $probeShots $true 999).Count -ne 1) { throw '묶음 크기가 너무 커도 한 묶음이어야 합니다' }
    # ----- 저장 메시지 -----
    $savedTemplates = @($script:config.Templates)
    try {
        Set-Templates @()
        if (@(Get-Templates).Count -ne 0) { throw '저장 문구를 비우지 못합니다' }
        Set-Templates @(
            [pscustomobject]@{ Name = '기본 안내문'; Text = "안녕하세요.`r`n오늘도 좋은 하루 되세요." },
            [pscustomobject]@{ Name = '점검 안내';   Text = '오늘 밤 점검이 있습니다.' }
        )
        if (@(Get-Templates).Count -ne 2) { throw '저장 문구를 담지 못합니다' }
        if ((Find-Template '기본 안내문').Text -notmatch '좋은 하루') { throw '저장 문구를 다시 읽지 못합니다' }
        if ($null -ne (Find-Template '없는 문구')) { throw '없는 문구를 찾았다고 합니다' }
        # 줄바꿈이 그대로 남아야 합니다.
        if ((Find-Template '기본 안내문').Text -notmatch "`r`n") { throw '줄바꿈이 사라졌습니다' }
        # 덮어쓰기
        $edited = @()
        foreach ($row in (Get-Templates)) {
            if ($row.Name -eq '점검 안내') { $edited += [pscustomobject]@{ Name = '점검 안내'; Text = '바뀐 내용' } }
            else { $edited += $row }
        }
        Set-Templates $edited
        if ((Find-Template '점검 안내').Text -ne '바뀐 내용') { throw '저장 문구를 덮어쓰지 못합니다' }
        # 삭제
        Set-Templates @(Get-Templates | Where-Object { $_.Name -ne '점검 안내' })
        if ($null -ne (Find-Template '점검 안내')) { throw '저장 문구를 지우지 못합니다' }
        if (@(Get-Templates).Count -ne 1) { throw '지운 뒤 개수가 맞지 않습니다' }
    } finally {
        Set-ConfigValue 'Templates' @($savedTemplates)
    }

    # ----- 이어서 발송 · 같은 사진을 두 번 보내지 않기 -----
    # 사진 4장을 2장씩 묶어 보내다가 두 번째 묶음에서 실패하는 상황을 만듭니다.
    # 그다음 이어서 발송을 하면 실패한 묶음만 나가야 합니다.
    # 이미 나간 첫 번째 묶음이 또 나가면 받는 사람이 같은 사진을 두 번 받습니다.
    & {
    $script:pileAttempts = @()
    $script:pileRoom = ''
    $script:pileFail = @{ '나방|2' = 1 }

    function Wait-ChatWindowReady([object]$Chat, [string]$Room, [int]$TimeoutMs = 8000) {
        return [pscustomobject]@{ Window = $Chat; InputBox = ([pscustomobject]@{ Handle = [IntPtr]7 }) }
    }
    function Wait-KakaoResponsive([object]$Window, [int]$TimeoutMs = 20000) { return $true }
    function Test-AttachmentFile([string]$Path) { return [pscustomobject]@{ Ok = $true; Reason = '' } }
    function Close-ChatWindow([object]$Window) { }
    function Clear-ChatInput([object]$InputBox) { }
    function Reset-ChatAfterFailure([object]$Chat, [object]$InputBox) { return $true }
    function Write-RunLog([string]$Text) { }
    function Send-ChatText([object]$Chat, [object]$InputBox, [string]$Message, [int]$SettleMs = 4000) { return '모의' }
    function Send-ChatAttachments([object]$Chat, [object]$InputBox, [string[]]$Paths, [int]$WaitMs, [bool]$SendIt = $true) {
        $list = @(@($Paths) | ForEach-Object { [string]$_ })
        $script:pileAttempts = @($script:pileAttempts) + ,@($list)
        $script:pileBatchNo[$script:pileRoom] = [int]$script:pileBatchNo[$script:pileRoom] + 1
        $key = $script:pileRoom + '|' + [string]$script:pileBatchNo[$script:pileRoom]
        if ($script:pileFail.ContainsKey($key) -and $script:pileFail[$key] -gt 0) {
            $script:pileFail[$key] = $script:pileFail[$key] - 1
            return [pscustomobject]@{ Ok = $true; Sent = $false; Method = '모의'; SendWay = ''; Reason = 'ATTACH_NOT_LANDED — 모의 실패'; Count = $list.Count }
        }
        return [pscustomobject]@{ Ok = $true; Sent = $true; Method = '모의'; SendWay = '모의'; Reason = ''; Count = $list.Count }
    }

    $pileContent = [pscustomobject]@{
        Message = '문구'; TemplateName = ''
        Attachments = @('p1.jpg', 'p2.jpg', 'p3.jpg', 'p4.jpg')
        GroupPhotos = $true; PhotoBatchSize = 2
        AttachmentWaitMs = 100; OpenTimeoutMs = 100; SettleMs = 0; DryRun = $false
    }
    $pileChat = [pscustomobject]@{ Handle = [IntPtr]77; Title = '모의'; Visible = $true }
    $pileSavedProgress = $null
    if (Test-Path -LiteralPath $script:ProgressPath) { $pileSavedProgress = Get-Content -LiteralPath $script:ProgressPath -Raw -Encoding UTF8 }
    try {
        Clear-RunProgress
        Reset-SendProgress @('가방', '나방')
        Reset-DeliveryState
        $script:trackDelivery = $true
        $script:runStats = @{ Photos = 0; Files = 0; Messages = 0 }
        $script:runStartedAt = '2026-01-01 00:00:00'
        $script:pileBatchNo = @{ '가방' = 0; '나방' = 0 }

        $script:pileRoom = '가방'
        $pileOk1 = Send-ToChatWindow $pileChat '가방' $pileContent $true
        Set-SendProgress '가방' $(if ($pileOk1) { '발송 완료' } else { '실패' }) ''
        $script:pileRoom = '나방'
        $pileOk2 = Send-ToChatWindow $pileChat '나방' $pileContent $true
        Set-SendProgress '나방' $(if ($pileOk2) { '발송 완료' } else { '실패' }) '모의 실패'
        Save-RunProgress $pileContent

        if (-not $pileOk1) { throw '다 성공해야 하는 방이 실패했습니다' }
        if ($pileOk2) { throw '묶음이 실패했는데 그 방을 완료라고 합니다' }
        if (@($script:pileAttempts).Count -ne 4) { throw "붙인 묶음이 4번이 아닙니다: $(@($script:pileAttempts).Count)" }
        if ($script:runStats.Photos -ne 6) { throw "보낸 사진이 6장이 아닙니다: $($script:runStats.Photos)" }
        $pileState = $script:deliveryState['나방']
        if (@($pileState.SentFiles.Keys).Count -ne 2) { throw "실패한 방에 보낸 파일이 2개가 아닙니다: $(@($pileState.SentFiles.Keys).Count)" }
        if (-not $pileState.SentFiles.ContainsKey('p1.jpg')) { throw '첫 묶음이 보낸 것으로 남지 않았습니다' }
        if ($pileState.SentFiles.ContainsKey('p3.jpg')) { throw '실패한 묶음이 보낸 것으로 남았습니다' }

        # 프로그램이 꺼졌다가 다시 켜진 상황입니다. 파일에서 상태를 되살립니다.
        Reset-DeliveryState
        $script:progressRows = @{}
        $script:progressOrder = New-Object System.Collections.Generic.List[string]
        $pileSaved = Import-RunProgress
        if ($null -eq $pileSaved) { throw '진행 상태 파일을 읽지 못했습니다' }
        $pileLeft = @(Get-ResumableRooms $pileSaved)
        if ($pileLeft.Count -ne 1 -or $pileLeft[0] -ne '나방') { throw "이어서 할 방이 나방 하나가 아닙니다: $($pileLeft -join ',')" }
        Restore-RunProgress $pileSaved
        if (@($script:deliveryState['나방'].SentFiles.Keys).Count -ne 2) { throw '되살린 뒤 보낸 파일 기록이 사라졌습니다' }
        if (-not [bool]$script:deliveryState['나방'].MessageSent) { throw '되살린 뒤 문구를 보낸 기록이 사라졌습니다' }

        # 이어서 보냅니다. 실패했던 묶음만 나가야 합니다.
        $script:pileAttempts = @()
        $script:pileBatchNo = @{ '나방' = 1 }
        $script:pileRoom = '나방'
        $pileOk3 = Send-ToChatWindow $pileChat '나방' $pileContent $true
        if (-not $pileOk3) { throw '이어서 보냈는데도 실패했습니다' }
        if (@($script:pileAttempts).Count -ne 1) { throw "이어서 보낼 때 묶음이 1번이 아닙니다: $(@($script:pileAttempts).Count)" }
        $pileAgain = @($script:pileAttempts[0])
        if ($pileAgain.Count -ne 2 -or $pileAgain[0] -ne 'p3.jpg' -or $pileAgain[1] -ne 'p4.jpg') {
            throw "이어서 보낸 파일이 p3·p4 가 아닙니다: $($pileAgain -join ',')"
        }
        if ($script:runStats.Photos -ne 8) { throw "이어서 보낸 뒤 사진이 8장이 아닙니다: $($script:runStats.Photos)" }
        if ($script:runStats.Messages -ne 2) { throw "문구가 두 번만 나가야 합니다: $($script:runStats.Messages)" }
    } finally {
        $script:trackDelivery = $false
        Clear-RunProgress
        if ($null -ne $pileSavedProgress) { Set-Content -LiteralPath $script:ProgressPath -Value $pileSavedProgress -Encoding UTF8 }
        Reset-SendProgress @()
        Reset-DeliveryState
        $script:runStats = @{ Photos = 0; Files = 0; Messages = 0 }
    }
    }
    # ----- 발송 전체 흐름 모의 시험 -----
    # 카카오톡 없이 가짜 채팅 목록을 만들어 발송 흐름을 그대로 돌려 봅니다.
    # 확인하려는 것은 두 가지입니다.
    #   1) 고른 방 수 = 발송 완료 + 실패   (조용히 빠지는 방이 없어야 합니다)
    #   2) 이름이 비슷한 다른 방에는 절대 보내지 않는다
    # 가짜 목록에는 일부러 어려운 경우를 넣었습니다.
    #   뽀식  -> 화면에는 '포식' 으로 잘못 읽힙니다
    #   업체B -> 화면 글자를 아예 못 읽습니다
    #   우리반 공지방 2기 -> '우리반 공지방' 을 찾을 때 먼저 걸립니다
    #   토토  -> 첫 번째 전송은 실패하고 다시 하면 성공합니다
    #   없는방 -> 목록에 아예 없습니다
    $script:fakeRooms = @(
        @{ Title = '뽀식';                            Ocr = '포식' },
        @{ Title = '투투';                            Ocr = '투투' },
        @{ Title = '토토';                            Ocr = '토토' },
        @{ Title = '업체A';                           Ocr = '업체A' },
        @{ Title = '업체B';                           Ocr = '' },
        @{ Title = '우리반 공지방 2기 (7)';            Ocr = '우리반 공지방 2기' },
        @{ Title = '우리반 공지방 (24)';               Ocr = '우리반 공지방' },
        @{ Title = '스마트스토어 블로그 홍보방 (91)';  Ocr = '스마트스토어 불로그 홍보방' }
    )
    $script:fakeTop = 0
    $script:fakePageSize = 4
    $script:fakeSendLog = @()
    $script:fakeFail = @{ '토토' = 1 }
    # 투투 와 업체B 는 사용자가 이미 창으로 열어 두었다고 칩니다.
    # 이 둘은 목록을 훑지 않고 열린 창으로 바로 가야 하고, 보낸 뒤에도 닫으면 안 됩니다.
    $script:fakeOpen = @('투투', '업체B')
    $script:fakeOpenSent = @()

    # 가짜 기능은 이 묶음 안에서만 살아 있습니다.
    # 밖으로 새어 나가면 뒤에 오는 검사들이 가짜를 쓰게 됩니다.
    & {
    function Test-KakaoReady([bool]$Restore = $false, [bool]$NeedSearch = $false) {
        return [pscustomobject]@{ Ok = $true; Reason = ''; Layout = (Get-KakaoLayout $null) }
    }
    function Get-MainKakaoWindow([bool]$Restore = $false) {
        return [pscustomobject]@{ Handle = [IntPtr]1; Title = 'KakaoTalk' }
    }
    function Get-KakaoLayout([object]$MainWindow) {
        return [pscustomobject]@{
            Main = [pscustomobject]@{ Handle = [IntPtr]1 }
            List = [pscustomobject]@{ Width = 320; Height = 400; Rect = [pscustomobject]@{ Left = 0; Top = 0 } }
            ViewName = 'ChatRoomListView'
        }
    }
    function Move-ListToTop([object]$List, [int]$Pages) { $script:fakeTop = 0 }
    function Move-ListByWheel([object]$L, [string]$D, [int]$N = 4) {
        if ($D -eq 'down') {
            $script:fakeTop = [Math]::Min($script:fakeRooms.Count, $script:fakeTop + $script:fakePageSize - 1)
        } else { $script:fakeTop = 0 }
    }
    function Get-OcrLines([object]$W, [int]$S = 2) { return @() }
    function Get-OcrScaleFor([object]$W) { return 2 }
    function Get-ChatRoomRowsFromOcr([object[]]$Lines, [int]$Width) {
        $out = @()
        for ($i = 0; $i -lt $script:fakePageSize; $i++) {
            $index = $script:fakeTop + $i
            if ($index -ge $script:fakeRooms.Count) { break }
            $room = $script:fakeRooms[$index]
            $out += [pscustomobject]@{
                Title = [string]$room.Ocr
                RawTitle = [string]$room.Ocr
                LastMessage = ''
                Time = '오전 11:00'
                TimeReadable = '오전 11:00'
                Top = ($i * 60)
                Confidence = $(if ($room.Ocr) { 'high' } else { 'low' })
                Ok = [bool]$room.Ocr
                FakeIndex = $index
            }
        }
        return @($out)
    }
    function Open-RoomAtLine([object]$List, [object]$Row, [IntPtr]$MainHandle, [int]$TimeoutMs = 0) {
        $index = [int]$Row.FakeIndex
        if ($index -lt 0 -or $index -ge $script:fakeRooms.Count) { return $null }
        return [pscustomobject]@{
            Handle = [IntPtr](100 + $index)
            Title = [string]$script:fakeRooms[$index].Title
            Visible = $true
        }
    }
    function Get-SingleChatWindow([object]$Value) { return $Value }
    function Get-OpenChatRooms {
        $out = @()
        foreach ($openName in $script:fakeOpen) {
            foreach ($fake in $script:fakeRooms) {
                if ((Get-RoomTitleName ([string]$fake.Title)) -cne $openName) { continue }
                $out += [pscustomobject]@{
                    Name = $openName; Title = [string]$fake.Title
                    Handle = [IntPtr]900; Kind = 'group'; Minimized = $false
                }
            }
        }
        return @($out)
    }
    function Find-OpenChatWindow([string]$Name) {
        $want = ConvertTo-ExactKey $Name
        foreach ($room in (Get-OpenChatRooms)) {
            if ($room.Name -cne $want) { continue }
            return [pscustomobject]@{ Handle = $room.Handle; Title = $room.Title; Visible = $true }
        }
        return $null
    }
    function Close-ChatWindow([object]$Window) { }
    function Send-ToChatWindow([object]$Chat, [string]$Room, [object]$Content, [bool]$CloseWhenDone = $true) {
        # 사용자가 열어 둔 창을 닫으려 하면 잘못입니다.
        if ((@($script:fakeOpen) -contains $Room) -and $CloseWhenDone) {
            throw "'$Room' 은(는) 사용자가 열어 둔 창인데 닫으려 했습니다"
        }
        # 우리가 목록에서 연 창은 닫아야 합니다.
        if ((@($script:fakeOpen) -notcontains $Room) -and (-not $CloseWhenDone)) {
            throw "'$Room' 은(는) 우리가 연 창인데 닫지 않았습니다"
        }
        if ($script:fakeFail.ContainsKey($Room) -and $script:fakeFail[$Room] -gt 0) {
            $script:fakeFail[$Room] = $script:fakeFail[$Room] - 1
            $script:lastSendProblem = 'SEND_VERIFY_FAILED — 모의 실패'
            return $false
        }
        if (-not $CloseWhenDone) { $script:fakeOpenSent = @($script:fakeOpenSent) + $Room }
        $script:fakeSendLog = @($script:fakeSendLog) + $Room
        return $true
    }
    function Test-RunInterrupted { return $false }
    function Wait-Interruptible([int]$Seconds) { return $false }
    function Add-SendLogRow([string]$Room, [object]$Content, [bool]$Ok, [string]$Reason) { }
    function Set-StatusPill([string]$Text, [string]$Kind) { }
    function Write-RunLog([string]$Text) { }

    $simRoster = @()
    $simOrder = 0
    foreach ($fake in $script:fakeRooms) {
        $simName = Get-RoomTitleName ([string]$fake.Title)
        $simRoster += [pscustomobject]@{
            Name = $simName
            ListText = [string]$fake.Ocr
            Kind = 'group'
            Order = $simOrder
            Verified = $true
            LastSeen = ''
        }
        $simOrder++
    }
    $simSavedRoster = @($script:config.Roster)
    $simSavedKinds = $script:config.RoomKinds
    try {
        Set-Roster $simRoster
        $simTargets = @('뽀식', '투투', '토토', '업체B', '우리반 공지방', '스마트스토어 블로그 홍보방', '없는방')
        Reset-SendProgress $simTargets
        Reset-DeliveryState
        $simContent = [pscustomobject]@{
            Message = '모의 시험'
            TemplateName = ''
            Attachments = @()
            AttachmentWaitMs = 500
            OpenTimeoutMs = 1000
            SettleMs = 0
            DryRun = $false
        }
        $simResult = Invoke-RosterSend $simTargets $simContent 12 0 0 0 2

        if ($simResult.Total -ne 7) { throw "고른 방 수가 7이 아닙니다: $($simResult.Total)" }
        if (($simResult.Sent + $simResult.Failed) -ne $simResult.Total) {
            throw "숫자가 맞지 않습니다: 고른 $($simResult.Total) / 완료 $($simResult.Sent) / 실패 $($simResult.Failed)"
        }
        if ($simResult.Sent -ne 6) { throw "보낸 방이 6개가 아닙니다: $($simResult.Sent)" }
        if ($simResult.Failed -ne 1) { throw "실패한 방이 1개가 아닙니다: $($simResult.Failed)" }
        # 보낸 곳을 하나하나 확인합니다.
        foreach ($mustSend in @('뽀식', '투투', '토토', '업체B', '우리반 공지방', '스마트스토어 블로그 홍보방')) {
            if (@($script:fakeSendLog) -notcontains $mustSend) { throw "'$mustSend' 에 보내지 못했습니다" }
        }
        foreach ($mustNot in @('우리반 공지방 2기', '업체A', '포식', '없는방')) {
            if (@($script:fakeSendLog) -contains $mustNot) { throw "'$mustNot' 에는 보내면 안 되는데 보냈습니다" }
        }
        if (@($script:fakeSendLog).Count -ne 6) { throw "보낸 횟수가 6번이 아닙니다: $(@($script:fakeSendLog).Count)" }
        # 사용자가 열어 둔 창은 목록을 훑지 않고 그 창으로 바로 갔어야 합니다.
        foreach ($openName in @('투투', '업체B')) {
            if (@($script:fakeOpenSent) -notcontains $openName) {
                throw "'$openName' 은(는) 열어 둔 창으로 보냈어야 하는데 그러지 않았습니다"
            }
        }
        if (@($script:fakeOpenSent).Count -ne 2) { throw "열린 창으로 보낸 수가 2가 아닙니다: $(@($script:fakeOpenSent).Count)" }
        # 방마다 상태가 하나씩 남아 있어야 합니다.
        $simDone = 0; $simFail = 0
        foreach ($simName in $script:progressOrder) {
            $simStatus = [string]$script:progressRows[$simName].Status
            if ($simStatus -eq '발송 완료') { $simDone++ }
            elseif ($simStatus -eq '실패') { $simFail++ }
            else { throw "'$simName' 이(가) '$simStatus' 상태로 끝났습니다. 완료나 실패여야 합니다." }
        }
        if (($simDone + $simFail) -ne 7) { throw "상태표의 방 수가 7이 아닙니다: $($simDone + $simFail)" }
        if ($simDone -ne 6 -or $simFail -ne 1) { throw "상태표가 결과와 다릅니다: 완료 $simDone / 실패 $simFail" }
        if ([string]$script:progressRows['없는방'].Note -notmatch 'ROOM_NOT_FOUND') { throw '못 찾은 방에 까닭이 적히지 않았습니다' }
    } finally {
        Set-ConfigValue 'RoomKinds' $simSavedKinds
        Reset-SendProgress @()
    }
    }

    # ----- 열어 둔 창만으로 보내는 경우 -----
    # 사용자가 보낼 방을 모두 창으로 열어 두었다면 카카오톡 목록은 필요 없습니다.
    # 목록을 아예 못 읽는 상황을 만들어 두고, 그래도 다 보내지는지 봅니다.
    & {
    $script:onlyOpenSent = @()
    $script:listPassCalled = $false
    $script:onlyOpenRooms = @('뽀식', '투투', '토토')

    function Get-OpenChatRooms {
        $out = @()
        foreach ($name in $script:onlyOpenRooms) {
            $out += [pscustomobject]@{ Name = $name; Title = $name; Handle = [IntPtr]800; Kind = 'direct'; Minimized = $false }
        }
        return @($out)
    }
    function Find-OpenChatWindow([string]$Name) {
        $want = ConvertTo-ExactKey $Name
        foreach ($room in (Get-OpenChatRooms)) {
            if ($room.Name -cne $want) { continue }
            return [pscustomobject]@{ Handle = $room.Handle; Title = $room.Title; Visible = $true }
        }
        return $null
    }
    # 목록은 아예 못 읽는 상황입니다.
    function Test-KakaoReady([bool]$Restore = $false, [bool]$NeedSearch = $false) {
        return [pscustomobject]@{ Ok = $false; Reason = '모의: 카카오톡 목록을 찾지 못했습니다'; Layout = $null }
    }
    function Invoke-ListPass {
        $script:listPassCalled = $true
        throw '열린 창만으로 끝나야 하는데 목록까지 훑었습니다'
    }
    function Send-ToChatWindow([object]$Chat, [string]$Room, [object]$Content, [bool]$CloseWhenDone = $true) {
        if ($CloseWhenDone) { throw "'$Room' 은(는) 사용자가 열어 둔 창인데 닫으려 했습니다" }
        $script:onlyOpenSent = @($script:onlyOpenSent) + $Room
        return $true
    }
    function Test-RunInterrupted { return $false }
    function Wait-Interruptible([int]$Seconds) { return $false }
    function Add-SendLogRow([string]$Room, [object]$Content, [bool]$Ok, [string]$Reason) { }
    function Set-StatusPill([string]$Text, [string]$Kind) { }
    function Write-RunLog([string]$Text) { }

    $onlySavedRoster = @($script:config.Roster)
    try {
        Set-Roster @()
        $onlyContent = [pscustomobject]@{
            Message = '모의 시험'; TemplateName = ''; Attachments = @()
            AttachmentWaitMs = 500; OpenTimeoutMs = 1000; SettleMs = 0; DryRun = $false
        }
        Reset-SendProgress $script:onlyOpenRooms
        Reset-DeliveryState
        $onlyResult = Invoke-RosterSend $script:onlyOpenRooms $onlyContent 12 0 0 0 1
        if ($script:listPassCalled) { throw '열린 창만으로 끝나야 하는데 목록까지 훑었습니다' }
        if ($onlyResult.Total -ne 3) { throw "고른 방 수가 3이 아닙니다: $($onlyResult.Total)" }
        if ($onlyResult.Sent -ne 3) { throw "보낸 방이 3개가 아닙니다: $($onlyResult.Sent)" }
        if ($onlyResult.Failed -ne 0) { throw "실패한 방이 있습니다: $($onlyResult.Failed)" }
        if (($onlyResult.Sent + $onlyResult.Failed) -ne $onlyResult.Total) { throw '숫자가 맞지 않습니다' }
        foreach ($name in $script:onlyOpenRooms) {
            if (@($script:onlyOpenSent) -notcontains $name) { throw "'$name' 에 보내지 못했습니다" }
        }
    } finally {
        Set-ConfigValue 'Roster' @($onlySavedRoster)
        Reset-SendProgress @()
    }
    }
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

# 열어 둔 채팅방 창을 눈으로 확인하는 진단 모드입니다.
# 아무것도 보내지 않고, 창을 열거나 닫지도 않습니다. 그냥 보기만 합니다.
if ($OpenTest) {
    $rooms = @(Get-OpenChatRooms)
    Write-Output ("열려 있는 채팅방 창: {0}개" -f $rooms.Count)
    foreach ($room in $rooms) {
        $name = [string]$room.Name
        $state = if ($room.Minimized) { '최소화됨' } else { '보임' }
        if ($MaskNames -and $name.Length -gt 2) {
            Write-Output ("  - {0}{1} [{2}자] ({3}/{4})" -f $name.Substring(0, 2), ('*' * [Math]::Min(10, $name.Length - 2)), $name.Length, (Get-RosterKindText $room.Kind), $state)
        } else {
            Write-Output ("  - {0}  ({1}/{2})  제목='{3}'" -f $name, (Get-RosterKindText $room.Kind), $state, $room.Title)
        }
    }
    if ($rooms.Count -eq 0) {
        Write-Output '카카오톡에서 보낼 채팅방을 두 번 눌러 창으로 열어 두신 뒤 다시 해 보세요.'
    }
    Write-Output 'OPENTEST_OK'
    exit 0
}

# 목록 읽기를 눈으로 확인하는 진단 모드입니다.
# 아무것도 보내지 않고, 저장도 하지 않습니다.
#   -ScanTest             화면 글자만 읽습니다. 방을 열지 않습니다.
#   -ScanTest -ScanExact  방을 하나씩 열어 창 제목으로 이름을 확정합니다.
if ($ScanTest) {
    Write-Output ("문자 인식 사용 가능: {0}" -f (Initialize-Ocr))
    if ($script:ocrError) { Write-Output ("메모: {0}" -f $script:ocrError) }
    $ready = Test-KakaoReady
    Write-Output ("카카오톡 준비 상태: {0} {1}" -f $ready.Ok, $ready.Reason)
    if ($ready.Ok) {
        Write-Output ("현재 화면: {0} / 목록 {1}x{2}" -f $ready.Layout.ViewName, $ready.Layout.List.Width, $ready.Layout.List.Height)
    }
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $scan = Invoke-RosterScan ([bool]$ScanExact) ([int]$script:config.ScanPages)
    $watch.Stop()
    Write-Output ("방식: {0} / 화면 {1}개 / 읽은 방 {2}개 / {3:N1}초" -f `
        $(if ($ScanExact) { '방을 열어 이름 확정' } else { '화면 글자만' }), `
        $scan.Pages, @($scan.Rows).Count, ($watch.ElapsedMilliseconds / 1000))
    if ([int]$scan.OpenFailures -gt 0) { Write-Output ("  열지 못한 줄: {0}개" -f $scan.OpenFailures) }
    if ([int]$scan.TitleFailures -gt 0) { Write-Output ("  제목을 못 읽은 줄: {0}개" -f $scan.TitleFailures) }
    foreach ($row in $scan.Rows) {
        $name = [string]$row.Name
        $mark = if ($row.Verified) { '확인됨' } else { '화면글자' }
        if ($MaskNames -and $name.Length -gt 2) {
            Write-Output ("  - {0}{1} [{2}자] ({3}/{4})" -f $name.Substring(0, 2), ('*' * [Math]::Min(10, $name.Length - 2)), $name.Length, (Get-RosterKindText $row.Kind), $mark)
        } else {
            Write-Output ("  - {0}  ({1}/{2})" -f $name, (Get-RosterKindText $row.Kind), $mark)
        }
    }
    Write-Output '저장하지 않았습니다. 저장하려면 프로그램에서 [채팅방 목록 새로고침]을 눌러 주세요.'
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
        $chat = Open-RoomFromRoster $room
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
    Warning    = (New-Rgb 176 106 12)
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
    $panel.Location = (New-UiPoint $X $Y)
    $panel.Size = (New-UiSize $W $H)
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
        $label.Location = (New-UiPoint 24 18)
        $label.Size = (New-UiSize ($W - 48) 26)
        $panel.Controls.Add($label)
    }
    if ($Subtitle) {
        $sub = New-Object System.Windows.Forms.Label
        $sub.Text = $Subtitle
        $sub.Font = $FontSmall
        $sub.ForeColor = $Theme.Muted
        $sub.BackColor = $Theme.Card
        $sub.Location = (New-UiPoint 24 46)
        $sub.Size = (New-UiSize ($W - 48) 22)
        $panel.Controls.Add($sub)
    }
    return $panel
}

function New-CardLabel([object]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H = 24, [object]$Font = $null, [object]$Color = $null) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.Location = (New-UiPoint $X $Y)
    $label.Size = (New-UiSize $W $H)
    $label.BackColor = $Theme.Card
    $label.Font = if ($Font) { $Font } else { $FontBase }
    $label.ForeColor = if ($Color) { $Color } else { $Theme.Ink }
    $Parent.Controls.Add($label)
    return $label
}

function New-FieldFrame([object]$Parent, [int]$X, [int]$Y, [int]$W, [int]$H) {
    $frame = New-Object System.Windows.Forms.Panel
    $frame.Location = (New-UiPoint $X $Y)
    $frame.Size = (New-UiSize $W $H)
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
        $box.Location = (New-UiPoint 14 12)
        $box.Size = New-UiSize ($W - 30) ($H - 24)
    } else {
        $box.Location = (New-UiPoint 14 0)
        $box.Width = $W - 28
        $box.Top = [int](($H - $box.Height) / 2)
    }
    $frame.Controls.Add($box)
    return $box
}

function New-AppButton([object]$Parent, [string]$Text, [int]$X, [int]$Y, [int]$W, [int]$H, [string]$Kind = 'default') {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Location = (New-UiPoint $X $Y)
    $button.Size = (New-UiSize $W $H)
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
# 배율이 높으면 창이 화면보다 커질 수 있습니다.
# 150% 에서는 1590x1110 이 되는데 세로 1032 짜리 화면에는 안 들어갑니다.
# 그래서 화면 작업 영역을 넘지 않게 줄이고, 모자란 만큼은 스크롤로 봅니다.
$script:UiFullWidth = S 1060
$script:UiFullHeight = S 740
$script:UiWorkArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$script:UiFormWidth = [Math]::Min($script:UiFullWidth, ($script:UiWorkArea.Width - (S 16)))
$script:UiFormHeight = [Math]::Min($script:UiFullHeight, ($script:UiWorkArea.Height - (S 16)))
$script:form.ClientSize = New-Object System.Drawing.Size($script:UiFormWidth, $script:UiFormHeight)
$script:form.StartPosition = 'CenterScreen'
# 배율이 높은 컴퓨터에서는 창을 늘려 볼 수 있어야 합니다.
$script:form.FormBorderStyle = 'Sizable'
$script:form.MinimumSize = New-Object System.Drawing.Size((S 720), (S 520))
$script:form.MaximizeBox = $true
$script:form.AutoScaleMode = 'None'
$script:form.BackColor = $Theme.Bg
# ----- 프로그램 아이콘 -----
# 창 왼쪽 위, 작업 표시줄, Alt+Tab 이 모두 이 아이콘을 씁니다.
# 크기가 여럿 든 아이콘이라야 배율이 높은 화면에서도 흐려지지 않습니다.
# 여기에는 16 · 24 · 32 · 48 · 64 크기가 담겨 있습니다.
# 옆에 app.ico 가 있으면 그것을 먼저 씁니다. 256 까지 들어 있어 더 선명합니다.
$script:AppIconBase64 = @'
AAABAAUAEBAAAAEAIABoBAAAVgAAABgYAAABACAAiAkAAL4EAAAgIAAAAQAgAKgQAABGDgAAMDAA
AAEAIACoJQAA7h4AAEBAAAABACAAKEIAAJZEAAAoAAAAEAAAACAAAAABACAAAAAAAEAEAAAAAAAA
AAAAAAAAAAAAAAAAAAQF2wKBmuwCy/HsAtH+7ALP/uwCzfzsAs387ALO/OwCzfzsAs797ALN/OwC
zf3sAs/97ALM8uwAgZzsAAQF2wJ7l/ID6///A9f//wPI+f8B1f//Atv//wPX//8C2///Adv//wPY
//8D1v//Ad///wLf//8D1///A+r//wB7l/ICzPnsA9f//wHa//8Ki6v/E0JR/wSw2/8Cw/T/BanU
/wWq1f8DxPX/AtH9/w55kf8NfZf/A834/wPY//8Cy/nsAtH+7ATV//8C1f//A8Hw/xoYG/8YIif/
Fi84/xobH/8aFhn/GCQr/xBec/8UT1//FkJO/wev1P8C2///AtH+7ALQ/ewE1f//ANf//weVvP8a
HiP/HBYX/xoeIf8cDg3/Fiow/xNEUP8aHiH/FUxZ/xFnfP8Cz/3/A9f//wLQ/ewC0P3sAtz//wSw
3P8bICX/Hhka/x0WF/8RX3L/DHCI/warzf8Fwev/HBYX/xsgI/8ZKzP/BqjS/wLd//8C0f3sAtH9
7ADf//8RYXn/IBAP/x4cH/8dFRf/GDM8/wuRsf8A6///Adj//xdFUv8fFBX/IA8O/xNWaf8B3v//
AtH97ALS/uwC1P//GTtH/yEUFf8aLjX/CpCq/wW51/8VSlf/DI6q/wDs//8OhqH/IRER/yAbHf8a
Mjv/A879/wLV/uwC0/7sAtL//xs4Qv8iERL/GEhV/we11P8A3f//AOL//wyIov8IqMj/BMTv/x4m
K/8hGBr/HC83/wPM/P8C1f7sAtD97AHg//8WVWf/IhQV/yEbHv8hFxr/GztE/xF3jP8HuNj/Bbnd
/wDj//8UZXn/JAcF/xhJV/8B3f//AtL+7ALQ/ewB4f//CqLG/yMVF/8iHyP/ISIm/yIaHf8jEhT/
IRwg/xtFUP8Qg5b/EnaN/yQIBv8Mlrb/AeL//wLQ/ewC0P3sA9b//wHd//8Rfpb/JBQV/yQZG/8i
Iib/IiMo/yIhJv8kGRz/JgoL/yUNDf8Sc4j/Adv//wPX//8C0f3sAtH+7APW//8D0///Ad3//w2b
t/8dQUv/IyAj/yUYGv8lGBr/JB8i/x49Rv8Ok63/Adz//wPT//8D1v//AtL+7ALN+ewD2f//A9H+
/wPR//8B3f//AtX//wmy1v8Nmrn/DZm4/wmv0/8C0v3/Ad7//wPS//8D0f7/A9n//wLN+ewAfJfy
A+z//wPZ//8D1v//A9b//wPY//8B3///AeP//wHj//8C4P//A9n//wPW//8D1v//A9n//wPt//8C
fJfyAAQF2wCBmuwCzfHsAtL97ALQ/ewC0P3sAtH97ALR/ewC0f3sAtH97ALQ/ewC0f3sAtL97ALN
8uwCgZrsAAQF2wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAoAAAAGAAAADAAAAABACAAAAAAAGAJAAAAAAAAAAAAAAAAAAAAAAAA
AAAA2wAGCOwAdozsAr7h7ALO+uwCzv3sAs387ALN/OwCzfzsAs397ALN/OwCzfzsAs387ALN/ewC
zf3sAs387ALN/OwCzfzsAs797ALO+uwCvuPsAHeO7AAGCOwAAADbAAgK8gKhw/8D5v//A9j//wPU
//8C1v//A9T//wPT//8C0///A9P//wPU//8D1P//AtP//wPU//8D1P//A9P//wPT//8D0///A9T/
/wPU//8D2f//A+f//wKhw/8ACAryAnSM7APn//8Dz/7/A8/+/wPN/f8DwfH/AM///wHT//8Dzv7/
A8/+/wPP/v8Cz///As///wPP/v8D0P7/A879/wPQ//8B2v//Adv//wPR//8Dzv3/A8/+/wPn//8A
c4zsAr7o7APZ//8Dz/3/A9D+/wHX//8QXnL/EkZY/wWn0/8A1f//AdT//wDR//8Azf//Ac7//wHU
//8B1///AtT//wPQ/v8Ng53/C4yq/wPM+v8C0/7/A8/9/wPZ//8CvujsAs/87ATW//8D0P3/A8/9
/wHa//8Jlbf/HAQB/xgcH/8KfJz/CIqv/w5ddf8RTF7/EU1g/w9gef8Jiaz/Ar7u/xBof/8XNT3/
GC82/w9yif8C0/7/A9D+/wPV//8CzvzsAs/+7ATW//8Dz/3/A8/9/wHR//8Bxvj/Fy01/xsTFP8b
FBT/GxMU/xwQD/8cEhL/GxIT/x0IB/8cCQf/E0JP/xVEUv8PcIj/El5x/xVPXf8C2f7/A9D+/wPU
//8C0P7sAs/97ATW//8Dz/3/A87+/wDS//8Fos7/GSQq/xsaHP8bHiH/Gxga/xwTFf8bHyP/GxET
/xQvOf8XKS//Gh0g/xJdbv8YQUv/F0RQ/wmewP8B2f//A8/+/wPW//8C0P3sAtD97ATW//8D0P7/
AdP//wSr2P8ZJy3/HRcY/xweIv8dGBr/FT5J/xFRYf8dBAL/FC41/wLO7P8Nf5j/HQsK/xofIv8U
T1z/FEpX/wajzP8B1f//BND+/wPW//8C0P3sAtD97APW//8D0f//AMn6/xVDUv8fERD/HB8j/x0f
I/8dFRf/FUdS/wWx2f8Kcoz/Bbbc/wDm//8Gtt3/Gx0g/xwcHv8dGBr/Hg4O/xc0Pv8Bw/L/AtL/
/wPW//8C0P3sAtD97APW//8B1///CJO5/x8TE/8dHyL/HiAj/x0gJP8dFBb/GDI7/xZMWv8A4///
Adz//wLQ//8B2f//FkdT/x8UFv8dICP/HR8j/x8PDv8LgaL/ANn//wPW//8C0f3sAtD97APW//8A
1///El1z/yASEv8eISX/Hh8j/x4PD/8XKTD/DICT/xwaHf8UVWX/ANz//wLV//8A3///DYei/x8Q
EP8eICT/HiAk/yAUFf8VTF3/ANP//wPX//8C0f3sAtD97APX//8Bz///GERR/yAXGP8fHyL/HSEl
/xBkd/8Dw+j/AOP//wW21/8YMzr/FFRk/wHZ//8B2///BcHr/x0mKv8fHSD/HyEl/x8ZG/8ZND7/
Asj5/wPZ//8C0f3sAtD97APX//8Bzv//Gj9L/yAYGv8gGhz/GjhB/wTB5/8A4f//AN7//wDh//8B
1/7/EWh5/xJidf8C0vb/AOL//xVaa/8hExT/HyEl/yAaHf8bMTn/A8f2/wLZ//8C0P3sAtD97APX
//8A1///F1Bg/yIWF/8gIib/IB0g/x8gJP8XTFn/DYuk/wXA5f8A4P//AO///wmkwv8MiaX/Adr3
/wqev/8hFBX/HyAl/yAYGf8ZQEz/AtH+/wPY//8C0P3sAtD97APW//8A3f//D36a/yIREf8gIif/
ICIm/yAfIv8hFRf/IhIT/x8nK/8XVmT/DJKt/wPO9v8C0fv/AdD9/wHW//8bNT7/IRse/yIREf8S
aoH/AN3//wPW//8C0f3sAtD97APW//8C1v//BMHr/x8oLv8iHB//ISMn/yEiJ/8gIib/ICIm/yEe
Iv8jFRf/IxQV/x8qMP8XXGz/DJSw/wLS8P8RdYz/IxAQ/yAcH/8Hstn/Adj//wPX//8C0f3sAtD9
7APW//8D0P7/AN3//w6Mqv8kEhL/IiAk/yEjKP8hIyf/ISMo/yEiJ/8hIif/ISIn/yIeIv8jFhj/
IxUW/x4wN/8dOUP/JAwL/xF5kf8A3v//A9H+/wPW//8C0P3sAtD97APW//8D0f3/A9L+/wDd//8R
fJP/JBUX/yMaHf8iJCn/IiQp/yIjKP8iJCj/IiMo/yIjKP8iJCj/IiQp/yQXGf8lDAz/E2t//wHa
//8C0/7/A9H9/wPX//8C0f3sAtD+7APW//8D0f3/A9H+/wPT//8A3v//DZu3/x43P/8lFBb/JRcZ
/yQcIP8jHyP/JB8j/yQdIP8lGBr/JRQV/yAwNv8Ojqj/Ad3//wLU//8D0f7/A9H+/wPX//8C0f7s
As/87APW//8D0f7/A9H+/wPR/v8D0f//Ad7//wPP9/8Okq3/GVxr/x4+R/8gMTn/IDE5/x48Rf8Z
V2b/D4ul/wTJ8P8A3///A9L//wPR/v8D0f7/A9H+/wPX//8C0PzsAr/o7APb//8D0f7/A9H+/wPR
/v8D0f7/A9H+/wLV//8B3v//Ad3//wPR/f8Fx/H/Bcfx/wPQ/P8B3P//AN///wLV//8D0P7/A9H+
/wPR/v8D0f7/A9H+/wPb//8Cv+jsAHSM7APp//8D0f7/A9D9/wPR/v8D0f7/A9H+/wPR/f8D0f7/
A9L+/wPT//8C1f//AtX//wPT//8D0v//A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPp//8C
dIzsAAgK8gKhw/8D6P//A9r//wPX//8D1v//A9f//wPW//8D1v//A9f//wPX//8D1v//A9f//wPX
//8D1///A9f//wPW//8D1///A9f//wPX//8D2///A+n//wKhw/8ACAryAAAA2wAFCOwAd4zsAr/j
7ALP+uwC0f3sAtD97ALQ/ewC0f3sAtD97ALR/ewC0f3sAtH97ALR/ewC0f3sAtD97ALQ/ewC0f3s
AtH97ALQ+uwCv+PsAniO7AAGCOwAAADbAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAKAAAACAAAABAAAAAAQAgAAAAAACAEAAAAAAAAAAAAAAAAAAAAAAAAAAAANsAAADsAAQG
7ABneuwCr9DsAsjz7ALO/OwCzv3sAs387ALN/OwCzfzsAs387ALN/ewCzf3sAs387ALN/ewCzfzs
As387ALN/ewCzf3sAs797ALN/OwCzf3sAs387ALN/OwCz/zsAsnz7AKw0ewAaHrsAAUI7AAAAOwA
AADbAAAA8gAYHf8Crc3/A+T//wPb//8C1f//AtT//wLU//8C0///A9P//wPT//8C0///A9P//wPU
//8D1P//A9T//wLT//8D1P//A9T//wPU//8D0///A9P//wPU//8C0///A9T//wPV//8D1v//A9v/
/wPk//8Crc3/ABgd/wAAAPIABgjsA6zQ/wPi//8Dzv7/A879/wPO/f8Dzv7/As///wLO/v8Dzv3/
As39/wLO/f8Dzv3/A879/wPO/f8Czv3/As79/wLO/f8Dz/3/A8/9/wPO/f8Dzv3/A879/wLO/f8D
zv3/A8/9/wPP/f8Dz/7/A87+/wPi//8Cq9D/AAYI7ABkeewD5f//A87+/wPP/f8Dz/3/A8/+/wLK
+v8CwfP/AM3//wHP//8Czf3/A87+/wPP/f8Dzv7/A87+/wLP/v8Cz/7/As7+/wPP/v8Dz/3/As79
/wPN/f8C0///Adn//wLV//8C1P//A879/wPP/v8Dz/7/A8/+/wPl//8AYnjsAq/W7APc//8Dz/7/
A8/9/wPP/f8C0v//A8Px/xQ7R/8QVmv/BKTR/wDQ//8Czf//Asz9/wLO//8Bz///AdD//wHR//8C
0P//A8///wPP//8Dzv3/Adj//wTF7/8Km7v/Brjf/wa44f8C1P//A8/9/wPP/f8Dz/3/A9z//wKv
1uwCyfXsA9b//wPQ/v8D0P7/A8/9/wPP/v8A2f//EF5y/x0AAP8ZGx3/DHCM/wDF+v8Axvz/A6/e
/waaxP8Hj7X/B5C3/wadx/8DtOP/Acr+/wDX//8EvuH/EGt//xwMC/8cERD/D3GH/wHb/P8D0P7/
A8/9/wPP/v8D1v//Asj17ALP/ewD1f//BND+/wPP/f8Dz/3/A879/wHX//8GqdH/Ghga/xoWGP8b
Dw//EUha/xFMX/8XJiz/GRkb/xoVFv8aFRb/Ghod/xcoL/8SSVn/CIut/wqEpv8dEBD/C4Wi/w50
jP8dEhP/DYWe/wHb//8Dz/3/A8/9/wPV//8C0P3sAs/97APW//8E0P7/A8/9/wPP/f8Czv3/Ac//
/wHE9/8WMTv/GxYY/xodIP8bExP/GxIS/xsZG/8bHB//Ghwf/xocH/8aGx7/GxMV/xwQEP8aEhL/
DXCI/xsdIP8Kjq7/DnmU/xweIP8Fvub/AtT//wPP/f8Dz/3/A9X//wLQ/ewCz/3sA9b//wTQ/v8D
z/3/A879/wLM/f8Azf//Aq/f/xgrM/8bGBr/Gh0h/xsdIf8bHSD/Gxkc/xsdIf8bHSH/Gx4h/xkS
FP8VIin/GRse/xoZG/8SW2v/EmZ3/x0cHv8aMDf/FVFf/wW+6f8C1f//A8/9/wPP/f8D1v//AtD9
7ALP/ewD1v//BNH+/wPP/v8Czf7/Ac7//wKw4P8WNUD/HRYX/xseIv8bHiL/HB4i/xogJP8XIyj/
GxIT/xseIv8aCgr/EEdV/wPI5f8VPEb/HBMU/xsdH/8UTFj/EXGE/xFrf/8GpMz/ANP//wPN/f8E
0P7/A9H+/wPW//8C0P3sAtD97APW//8D0f7/A9D+/wLO/v8BwPP/FEBO/x4QD/8cHiL/HB4i/xse
Iv8dGRv/GDA3/wSw1f8RTVz/GwEA/xFDT/8C0fb/AOv//w18lf8dDg7/Gx0g/xsYGv8YMTj/Gx0f
/xgsNP8Duef/AdD//wPP/v8D0f7/A9b//wLR/ewC0P3sA9b//wPR/v8Dz/7/ANH//wxykP8fDg3/
HR8j/xwfIv8dHyP/HR8j/x0XGf8WN0D/D3+X/wHG+P8KdJD/A8fx/wLZ//8C2P//Bbri/xseIf8c
HB//HB8i/x0bHf8cHCD/Hg4N/xFacP8A0f//A87+/wPQ/v8D1v//AtD97ALQ/ewD1v//A9D+/wHQ
//8Cuur/Gisz/x4ZG/8dHyP/HiAj/x4gI/8dHyP/HhYY/xRHVP8aMzr/Cpe4/wDr//8C1P//As/+
/wLR//8B2v//FUlW/x4TFf8dICP/HR8j/xwfI/8dHB//HBwf/wWq1f8B0///A9D+/wPW//8C0f3s
AtD97APW//8D0P7/ANX//wqJq/8fEhL/HiAj/x4gI/8eICT/HSAj/x0cH/8dCAf/ElBe/xsiJv8b
Jyz/Bb3h/wDd//8D0P7/A9H+/wDf//8MiKT/HxAQ/x0gJP8eICT/HiAk/x4gJP8fEA//D3KN/wDX
//8D0P7/A9f//wLR/ewC0P3sA9b//wPQ/v8A1v//EmF3/yATE/8eICT/HiAk/x4hJP8eFBX/GxQW
/w9kdv8Dx+X/DIOb/x0NDf8cJCn/BMDk/wDd//8D0P3/Atf//wTC6/8cJiv/Hhwf/x4gJP8eICT/
HiAk/x8VFf8WS1r/AND//wPQ//8D1v//AtD97ALQ/ewD1v//A9D//wDR//8WTFz/IBYX/x4gJP8f
ICT/Hhwe/xVDT/8GqMf/AOD//wHX//8A4P//BrHQ/xgvNv8cICX/BL/i/wDd//8D0P7/AN7//xRb
bP8gEhP/HyIm/x8hJf8fICT/Hxga/xk3Qf8CyPr/AtH//wPW//8C0P3sAtD97APW//8D0P//AND/
/xhIVv8gFhj/HiAk/x8dIf8eJSn/Bbri/wDs//8A3P//AtP//wPQ/v8B3P//AtX7/xFjc/8aKjH/
Bbnb/wDd//8B3P//Cp6//yAUFf8fISX/HyEl/x8hJf8fGhz/GjQ9/wLH9/8C0v//A9b//wLQ/ewC
0P3sA9b//wPQ/v8A1v//FlNk/yEVFv8gISX/HyEl/x8eIv8cLDL/FF9w/wqfvP8Czfb/AOD//wDa
//8B1///AOL//wqatP8VTFn/BrTU/wDd//8Cz/n/GzU9/yAZHP8fISX/HyEl/yAYGv8ZPkn/As7+
/wPR//8D1///AtD97ALQ/ewD1v//A9D+/wDb//8Rcov/IhIS/yAiJv8gIib/HyEm/yAcIP8hEhP/
IRUX/xw1PP8TbH7/CajH/wLR+/8A4P//AOn//wTE6f8Ng5z/BLzg/wDk//8ScYf/IhER/x8hJf8g
ISX/IRMT/xVabP8A2v//A9D+/wPW//8C0f3sAtD97ALW//8D0P7/Adj//wimzf8hGRv/HyAk/yAi
Jv8gIib/ICIm/yAhJf8gICX/IBod/yISE/8iGRv/HDtE/xJzh/8IrM3/Adn//wDi//8DyPL/ANz/
/wix1v8gGx7/ICAk/yAhJv8iEhL/DI6u/wDc//8D0f3/A9b//wLR/ewC0P3sAtb//wPR/v8D0f7/
AdX+/xlHVf8iFRf/ISMn/yEjJ/8hIif/ICIm/yAiJv8gIib/ICIm/yEhJv8iGh3/IxIT/yEbHv8c
P0j/EnaK/wiv0f8C0/3/AOf//xdQXv8iFxn/IRkc/xwxOP8DyfT/AtP//wPR/v8D1///AtH97ALQ
/ewD1v//A9H+/wPQ/v8B2v//CajN/yIZG/8iHyP/ISMo/yEiJ/8hIif/ISMn/yEjJ/8hIif/ISIn
/yEiJ/8hIif/ISEl/yIaHf8jExT/IRse/xw9Rv8RfY7/GFNi/yIYGv8jERH/DY+u/wHe//8D0P7/
AtH9/wPW//8C0P3sAtD97APW//8D0f7/A9H+/wPQ/v8A3v//EICb/yQSEv8iICX/ISMo/yIjKP8i
Iyj/IiMo/yIjKP8hIif/IiMn/yEjJ/8iIyf/IiMo/yEjKP8iIib/Ihse/yMTFv8iHB//IxAQ/xRn
e/8B3P//AtH+/wPR/v8D0f7/A9f//wLR/ewCz/3sA9b//wPR/v8D0f3/A9D9/wPS//8A3f//EXyT
/yUWGP8kGx7/IiQp/yMkKf8jJCn/IiMo/yIkKf8iJCj/IiMo/yIjKP8iJCj/IiMo/yIjKP8iJCn/
Ix0h/yQSE/8UZnn/Adn//wLV//8D0P3/A9H9/wPR/f8D1///AtH97ALQ/ewC1v//A9D9/wPR/v8D
0f7/A9H+/wPT//8A3///DZ24/x8zOv8lEhT/JBsf/yMjJ/8iJCn/IiQp/yIkKP8jJCj/IyQp/yMk
Kf8jIyj/JB0h/yUTFP8hKS7/D4uj/wHd//8C1f//A9D+/wPR/v8D0f7/A9H+/wPW//8C0f3sAtD9
7ALW//8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR//8B3///BMzy/xGAlv8ePUX/JB4h/yUWF/8lFhf/
JRcZ/yUXGf8lFhj/JRUX/yQbHv8fNj3/E3SH/wXD5/8A4P//A9L//wPR/v8D0f7/A9H+/wPR/v8D
0v7/A9b//wLQ/ewCyfXsA9f//wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPQ/v8C1f//AOD//wPS
/P8Krc//EIii/xVug/8XYXL/F2By/xZsgP8RhJ3/CqjI/wPN9v8A4P//Adf//wPQ/v8D0f7/A9H+
/wPR/v8D0f7/A9H+/wPR/v8D2P//Asr17AKw1ewD3f//A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/
A9H+/wPR/v8D0f7/AtP//wHa//8A3///AN///wHd//8B3f//AN///wDf//8B2///AtT//wPR/v8D
0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPe//8CsNbsAGR57APn//8D0P7/A9H9/wPR
/f8D0f3/A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPS/v8D0f7/A9H+
/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0P7/A+f//wBkeewABgjs
AqzQ/wPk//8D0P7/A9D9/wPR/f8D0f7/A9H+/wPR/v8D0f3/A9H9/wPR/v8D0v7/A9H+/wPR/v8D
0f3/A9H+/wPR/v8D0v7/A9L+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR/f8D0f7/A9D+/wPk
//8Cq9D/AAYI7AAAAPIAFxz/AqzM/wPm//8D3f//A9j//wPW//8D1v//A9f//wPW//8D1///A9b/
/wPX//8D1v//A9f//wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///
A9j//wPd//8D5v//A63N/wAXHf8AAADyAAAA2wAAAOwABAbsAGd67AKw0OwCyfPsAtD87ALQ/ewC
0P3sAtD97ALR/ewC0f3sAtD97ALR/ewC0f3sAtH97ALR/ewC0f3sAtH97ALR/ewC0P3sAtD97ALQ
/ewC0f3sAtH97ALQ/OwCyfPsArDR7AJoe+wABAbsAAAA7AAAANsAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgAAAAw
AAAAYAAAAAEAIAAAAAAAgCUAAAAAAAAAAAAAAAAAAAAAAAAAAADbAAAA7AAAAOwAAADsAAAA7ABE
UOwCjKbsArTZ7ALH8uwCzfzsAs797ALO/ewCzfzsAs387ALM/OwCzfzsAs387ALN/OwCzfzsAs39
7ALN/ewCzfzsAs387ALN/ewCzP3sAs387ADN/ewCzfzsAs397ALN/ewCzf3sAs397ALN/OwCzf3s
As397ALN/OwCzf3sAs787ALO/OwCx/PsArXa7ACOp+wARVHsAAAA7AAAAOwAAADsAAAA7AAAANsA
AADyAAAA/wAAAP8BJS7/AqTC/wPf//8D4P//Atn//wLW//8C1P//AtP//wLT//8D0///AtP//wLS
//8C0///A9P//wLT//8D0///A9P//wPU//8D0///A9P//wPT//8C0///AtL//wPU//8D1P//AtP/
/wPT//8C0///AtP//wLT//8C0///AtP//wLT//8C0///A9T//wPU//8D1v//A9r//wPg//8C3///
AqXD/wAlLv8AAAD/AAAA/wAAAPIAAADsAAAA/wE4Rf8Dz/P/A9///wPP//8Dzv3/A879/wLO/f8C
zv3/As7+/wLO/f8Czf3/A839/wPN/f8Dzv3/As79/wLN/f8Dzv3/A879/wPP/v8Dz/3/A8/9/wPP
/v8Czv3/As39/wPO/f8Dzv7/BM/9/wPO/f8Dzv3/As39/wPO/f8Dzv3/A879/wLN/f8Dzv3/A8/9
/wPP/f8Dz/3/A8/9/wPP/f8Dzv//A9///wPO8/8BOET/AAAA/wAAAOwAAADsASIq/wPP9f8D2f//
A879/wPO/f8Dzv3/A879/wPO/f8Dzv3/A87+/wLO/f8Czf3/A879/wPO/f8Czf3/As39/wLN/f8C
zv3/As79/wPO/f8Dzv3/A879/wLO/f8Czv3/As79/wPO/f8Dzv3/A8/9/wPO/f8Dzv3/A879/wPO
/f8Dzv3/A879/wLO/f8Dzv3/A8/9/wPP/f8Dz/3/A8/9/wPQ/v8Dz/7/A879/wPZ//8DzvX/ASIq
/wAAAOwAAADsAqPH/wPf//8Dzv3/A8/9/wPP/f8Dz/3/A8/9/wPO/f8Dzf3/Asz9/wLL/f8Cyvz/
Asv9/wLN/f8Czf3/As79/wPO/f8Dz/7/A879/wPO/f8Dzv3/As79/wPO/f8Czv3/As79/wLO/f8D
z/3/A8/9/wPP/f8Dzv3/As79/wPO/f8Dzv3/As79/wPO/f8Czv3/As79/wPO/f8Dzv3/A8/+/wPP
/v8Dz/7/A8/+/wPO/v8D3///AqLH/wAAAOwAQE7sA9///wPP/v8Dz/3/A8/9/wPP/f8Dz/3/A8/+
/wPO/v8CzP3/Asb4/wHC9v8Ayv//Acj8/wLJ+v8DzP3/As79/wPO/f8Dzv3/A879/wLO/f8Dzf3/
As79/wPO/f8Czv3/As7+/wLO/f8Dz/3/A8/+/wPP/f8Czv3/A879/wPO/f8Dzv3/AtX//wLT//8C
zv3/A9L//wPO/f8Dzv3/A8/9/wPP/f8Ez/3/A9D+/wPP/v8Dz/7/A9///wA/TewAi6nsA+H//wPP
/v8Dz/7/A9D+/wPP/f8Dz/3/A8/+/wPP/v8B2f//DHqW/xUvOP8MbYj/A6nX/wDJ//8CyPv/A8r7
/wLN/f8Dzf3/As39/wLM/f8Cy/z/Asr7/wLL/P8Cy/z/A8z8/wLM/f8Dzf3/A87+/wPP/v8Dzv3/
A879/wPP/f8D0f3/Brvi/wTF7/8B3f//A836/wLT//8Dzv3/A8/+/wPP/f8Dz/3/A8/9/wPP/f8D
z/7/A+H//wCLqewCtNzsA9r//wPP/v8D0P7/A9D+/wPP/f8Dz/3/A8/9/wPP/v8B2P//CJi9/xsK
CP8bDAv/GCAk/w1mgP8BuOv/Acr//wLG+P8Cx/n/AsX4/wLF+f8Bx/z/AMn+/wDI/v8Ayf7/Acn/
/wHJ/f8CyPv/A8n7/wPL/P8Czf3/As39/wHZ//8A3///FzY9/xRIVP8MiKL/GDE4/wav1P8C2f//
A8/+/wPP/v8Dz/7/A8/9/wPP/v8Dz/7/A9n//wK03OwCx/PsA9f//wPQ/v8D0P7/A9D+/wPP/v8D
z/3/A879/wPO/f8Cz/7/ANb//xNJWP8bERL/Ghga/xsMC/8VND7/BZzH/wDH//8AxPv/Abru/wOm
1f8Gkrr/CYSm/wp7nP8JfJ3/CIaq/wWWvv8DrNv/Ab/0/wDK//8Byv7/AdD//wmbvf8Odo3/GSYs
/x0DAf8eAgD/HBAP/wijxf8B2v//A9D+/wPP/f8Dzv3/A9D+/wPP/f8Dz/3/A9b//wLH8+wCzvzs
A9X//wPQ/v8E0P7/BND9/wPP/f8Dz/7/A8/9/wPO/f8Czf3/ANr//wqNrf8bDw7/GRwf/xkcIP8a
ERH/GB8j/wp2lf8Ma4f/FDxJ/xciKP8ZFxj/GhIS/xsREf8bERH/GxMT/xoYGv8XJiv/E0BO/wxr
h/8En8r/AND//xFfdP8fAQD/Gh8i/wyAmf8PcIb/Gxka/xshJP8TWGb/Atf//wPP/v8Dz/3/A8/9
/wPP/f8Dz/3/BNT//wLP/ewCz/3sA9X//wPQ/v8Ez/3/A8/9/wPP/f8Dz/3/A8/9/wLO/f8Czf3/
AdH//wO24/8YIif/Ghgb/xocIP8ZHSH/Ghkb/xsSEf8bEBD/GxMU/xoZG/8aHB//Ghwg/xocIP8Z
HB//GRwf/xocH/8bGRz/GxQU/xwPDv8ZGh3/Ektc/wSiy/8ZJy3/FUhV/wDv//8A4P//GTE5/xwW
F/8PeI//AtT//wPQ/v8Dz/3/A8/9/wPP/f8Dz/7/A9b//wLQ/ewCz/3sA9X//wPQ/v8E0P7/A9D+
/wPP/f8Dz/3/As79/wLN/f8CzP3/Acr9/wDD9/8VOkb/GxQV/xocIP8aHSH/Gh0g/xocIP8aHCD/
Gh0g/xsdIf8bHSH/Gh0g/xocIP8aHSD/Ghwg/xocIP8aHB//GRwf/xodIP8aEhP/FTlC/w17lf8e
EBH/GyAk/wqRsf8MgZ7/HhIS/xZHUv8A3v//A9H//wPP/f8Dz/3/A8/9/wPQ/f8D0P7/A9b//wLQ
/ewCz/3sA9b//wPR/v8E0f7/A8/9/wPP/f8Dzv3/As79/wLN/f8CyPr/AcP4/wDB9v8VPEn/HBUW
/xodIP8aHSH/Ghwg/xsdIf8bHiH/Gx4h/xsdIf8bHSH/Gx0h/xodIf8bHiH/Gh0h/xgaHf8YDA3/
GRIT/xoeIf8aGBr/FjM7/w6AmP8VUlz/GjE4/x8QEP8fERD/HiAi/x4WF/8IrdH/Adj//wPQ/f8D
z/3/A8/9/wPQ/f8D0P7/A9b//wLR/ewCz/3sA9X//wPR/v8E0f7/A9D9/wPP/f8Dzv3/As39/wLK
+/8BxPj/AL3y/w9edf8cGBr/Gx0g/xsdIf8bHSH/Gx4h/xseIv8bHiL/Ghgb/xoZG/8bHiL/Gx4h
/xsdIf8aHSH/GRga/xcNDv8LdYn/EVVl/xsSE/8aHiL/GxQV/xROXP8PeYn/DY2n/x8REv8UWWj/
Bq/S/wqZuv8Cy/r/As/+/wPQ/v8E0P7/A9D9/wPQ/v8D0f7/A9f//wLQ/ewC0P3sA9b//wPR/v8D
0f7/A9D9/wPP/v8Czv3/Acv8/wHF+f8AwPb/EFht/x4ODf8cHSD/Gx4h/xweIv8bHiL/HB4i/xwe
Iv8bGx7/Fikv/xYfI/8bExT/Gx4i/xseIv8ZGBv/FwkI/wt7kv8A7v//BrTa/xoVFv8aHB//Gx8j
/xsVFv8eBwb/EG2B/w6ImP8Nhp//FEhX/wDC9P8Azf//Asv8/wPO/f8E0P3/A9D+/wPR/v8D0P3/
A9b//wLQ/ewC0P3sA9b//wPR/f8E0f7/A9D9/wPP/v8Czf7/Asf5/wDG/v8Na4b/HQ4N/xwdIf8c
HiL/HB4h/xweIv8bHiL/Gx4h/xweIv8dDw//C4Od/wO82/8VKjP/Gw4N/xkZG/8XCgn/C3uS/wHj
//8C1P//Adj//xRDTv8cExT/Gx8i/xseIf8bHSD/Gxsd/xc3Pf8ZJy3/HQoI/xNIWP8Axfj/Asr7
/wLM/f8Dz/7/A9D+/wPR/v8D0P7/A9b//wLR/ewC0P3sAtb//wPR/v8D0f7/A9D+/wPP/v8Cy/z/
AMn//weTu/8cFhf/HBse/xwfIv8cHiL/HB4i/xweIv8cHiL/Gx4h/xweIf8cFxn/Dm+D/wW73/8C
zO//EURR/xgDAf8LepH/AeH//wPT//8D0P7/AeH//wyFoP8cDg7/Gx4i/xseIv8bHiL/Gx0h/xwa
Hf8cGx7/Gx4h/x4ODf8Nc4//AM///wLJ+/8Dzv3/BND9/wPQ/v8D0f7/A9b//wLQ/ewC0P3sA9b/
/wPQ/v8D0f7/A9D+/wPN/f8ByPv/AL7y/xY8SP8eFBT/HSAj/x0fI/8dHyP/HR8j/x0fI/8dHyP/
HR8j/xwdIf8ZHyP/EGx//xdNWv8A2P//Abfq/weUtP8B2v//AtL//wLQ/v8D0f7/Atf//wS+6P8a
ISX/HBse/x0fI/8cHyL/HR8j/xwfIv8cHiL/Gx4i/xwZHP8aICT/BK3a/wHN/v8Czf3/A8/9/wPR
/v8D0f7/A9b//wLQ/ewC0P3sA9b//wPR/v8D0P3/A8/+/wLM/f8Azv//CYir/x8TE/8dHyP/HR8i
/x0fI/8dHyP/HiAk/x4gJP8dICP/HR8j/x0cH/8YKjD/D3SK/yAQD/8Jm77/ANP//wHc//8C0f//
AtD+/wLQ/v8C0P7/AtH+/wHc//8UTlz/HRIT/x0fI/8dICP/HSAk/xwfIv8cHiL/HB8i/xwfI/8e
EA//EGN6/wDQ//8CzPz/A8/+/wPQ/v8D0f7/A9f//wLR/ewC0P3sA9b//wPQ/v8D0P7/As7+/wLL
/f8AyPv/FUdX/x8UFP8dHyP/HR8j/x4fI/8eICT/HiAj/x0fIv8dHiL/HB4i/xwaHP8WNDz/EG2B
/yALCv8YP0n/AdL4/wHY//8Cz/3/AtD9/wPR/v8C0P7/AtD9/wDf//8MjKj/Hg8P/x0fI/8dHyP/
HSAj/x0gI/8eICT/HR8j/x0fI/8dGhz/Giox/wK56P8Bzf//A87+/wPQ/f8D0f7/A9f//wLR/ewC
0P3sA9b//wPR/v8D0P3/As7+/wHO//8Eq9n/HCIm/x4cH/8eICP/HiAj/x4gJP8eICT/HiAj/x0f
Iv8dHyL/Gx0h/xwJCP8TP0r/EWBy/x8KCf8eERL/FkpZ/wHS+f8B1///As/9/wPR/f8D0f7/AtD9
/wLW//8ExO3/Gycs/x4bHf8dICP/HiAj/x4gJP8eICT/HiAk/x4gJP8dHyP/HxQU/wqQsv8A0///
As79/wPQ/f8D0f7/A9f//wLR/ewC0P3sA9b//wPR/v8D0P7/As7+/wDS//8Liqz/IBUV/x4gJP8e
ICT/HiAk/x4gJP8eICP/HiAj/x0fI/8cFhj/GwwN/xJIVP8Futr/BrbW/xY4Qf8dDQz/HwwL/xZP
Xv8B1fv/Adf//wPP/f8D0P3/A9H+/wPR/v8A3///E15v/yAREv8eIST/HiAj/x4gJP8eICT/HiAk
/x4gJP8dHyP/IBIR/xFpgP8A1P//As39/wPQ/f8D0f7/A9b//wLR/ewC0P3sA9b//wPR/v8D0P7/
As7+/wDV//8Qb4n/IBIS/x4gJP8eICT/HyAk/x8hJf8eICT/HR0g/x0NDf8XKjD/CY+o/wHb//8B
2f//Adv//wLS+P8Panz/HBIU/yAGA/8VU2L/Adb8/wHX//8Cz/3/AtD9/wPR/f8B3f//CaDB/x8U
Ff8eHyP/HiAk/x8hJf8fISX/HyEk/x8hJP8eICP/HxUW/xZMW/8Az///As3+/wPQ/v8D0f7/A9f/
/wLQ/ewC0P3sA9b//wPR/v8D0P3/As39/wDT//8TX3P/IRQU/x4gJf8eICT/HiAk/x8hJf8eHiH/
HB0f/w9leP8Dye3/AOD//wLR//8C0P7/A9D+/wLV//8A4v//CKG9/xguNf8hAAD/FVNj/wHX/v8B
1v//AtD9/wPR/v8C0///A9D6/xk3P/8fGBr/HyEl/x8iJv8fISX/HiAk/x8gJP8eICP/HhcY/xg+
Sf8Byvz/As///wPQ/v8D0f3/A9b//wLR/ewC0P3sAtb//wPR/v8D0P3/As39/wDU//8WWWz/IRQV
/x4gJP8fICT/HiAl/x8hJf8hEhP/EHiO/wD2//8A2///As/+/wLQ/f8C0P3/A9H+/wPR/f8C0f7/
AN///wPL7/8RXm7/IAAA/xVQX/8B2f//Adb//wLQ/v8D0f7/AOH//xB0i/8gEBD/HyEl/x8hJf8f
ISX/HyAk/x8hJf8fICT/Hxga/xo6RP8Byfr/As///wPQ/f8D0P3/A9b//wLQ/ewC0P3sAtb//wPR
/f8D0P3/As3+/wDW//8VYHT/IhQV/x4gJP8eICX/HyEl/x8gJf8gGx7/GzpD/w2Kof8Ev+X/AN3/
/wDd//8B1P//AtD+/wLQ/f8C0P3/As/9/wLX//8B4P//Cpaw/xwXGf8WSlf/Adj//wHW//8C0P3/
Adn//wez2v8eHB//Hh4i/x8hJf8fISX/HyEk/x8hJf8eICT/IBcZ/xlASv8Bzf7/AtD//wPQ/f8D
0P3/A9b//wLQ/ewC0P3sAtb//wLQ/v8D0f7/A879/wDY//8Rcov/IhIT/yAhJv8gIib/ICIm/yAh
Jf8fIib/Hxod/yEREv8eJir/Flhm/wuWsv8DyPD/AN///wDd//8C1P//AtD+/wLQ/f8D0v//AeH/
/wTG6P8VRlD/FE1b/wHU+f8B1v//AtH+/wHZ//8XSFT/IBUX/x8hJf8fICT/HyEl/x8hJf8fICT/
IBUW/xdQX/8A1P//A8/+/wPQ/f8D0f7/A9b//wLQ/ewC0P3sA9b//wPQ/v8D0f7/A8/+/wDY//8L
kbL/IRQV/yAhJv8gISb/ICIm/yAiJv8fISX/HyEl/x8gJf8fHB//IRIU/yETFP8dLzX/FGRz/wqg
vf8Czfb/AN///wDb//8C0///A9D9/wLZ//8A3v//DoCU/xFnev8CzO//AtT//wDf//8NiqX/IRES
/x8hJf8fISX/HyEl/x8hJf8eICT/IRES/xJuhf8A2v//A8/9/wPQ/f8D0f7/Atf//wLQ/ewCz/3s
A9b//wPQ/f8D0P7/A9D+/wHT//8FueT/HyQp/yAeIv8fISX/HyEm/yEiJ/8gISb/ICEm/yAhJv8f
ISX/HyAl/x8hJf8gHB//IRIT/yEWF/8cNTz/E2x9/wmnxv8C0fv/AOD//wHa//8C1P//AeH//wex
0/8Jl7X/As71/wHY//8Fw+z/HScs/yAcIP8fISX/ICEm/yAhJf8fICT/IRUV/wqZu/8B2v//A9D9
/wPQ/f8D0f7/A9f//wLR/ewC0P3sA9b//wLQ/f8C0P7/A9D+/wLO/v8A1///F1Fg/yIVFv8fISX/
ICIm/yAiJv8gISb/ICEm/yAiJv8gISX/ICEl/yAhJf8fISX/HyEl/yAhJf8hGx7/IxIT/yEZGv8b
OkL/EnGE/wiqyv8C0vz/AN///wDh//8C0f3/A8r2/wLR/v8A3///FV1t/yETFP8gIib/ICIm/yAh
Jf8gGx3/HDA2/wPH9P8C0v//A9D9/wPR/v8D0f7/A9f//wLR/ewC0P3sAtb//wLQ/v8D0f7/A9H+
/wPP/f8A2v//C5q8/yMVFf8gISb/ISIn/yEiJ/8hIyf/ISIn/yAiJv8gISb/HyEl/yAiJv8gIib/
ICEm/yAiJv8hIif/ISMn/yEhJf8hGhz/IxIT/yEaHf8cPUb/EnSH/wmry/8C0/3/AOD//wDa//8A
3///Cp2+/yAVF/8gISX/ISIm/x8hJv8iEBD/EXCI/wDd//8Dz/3/A9H+/wPR/v8D0f7/A9f//wLR
/ewC0P3sAtb//wPR/v8D0f3/A9D9/wPQ/f8C0P7/ANT//xpJVv8iFRf/ICMo/yEiJ/8hIif/ISMn
/yEiJ/8hIif/ISIn/yEiJ/8hIif/ISIn/yAiJv8hIif/ISIn/yEiJ/8hIib/ISIn/yEhJf8iGh3/
JBMU/yEbHf8cPET/E3GE/wmoyP8C0vr/ANv//xw5Qf8hGh3/ICIm/yEbHv8eKC7/BMHq/wLV//8D
0P3/AtD9/wPR/v8D0f3/A9b//wLR/ewC0P3sAtb//wPR/v8D0f7/AtD+/wPQ/v8Dz/3/Adj//wew
1f8iHiH/IR0h/yEjKP8hIyj/ISIn/yEiJ/8hIif/ISIn/yEjJ/8hIyj/ISIn/yEiJv8hIif/ISIn
/yEiJ/8hIif/ISIn/yEiJ/8hIif/ISMn/yEhJf8iGh3/IxMU/yIaHP8cO0T/FGd3/x4wN/8hHiL/
ISEl/yMREv8Ni6n/AN///wPQ/v8D0f3/AtH+/wLR/f8D0f3/A9b//wLQ/ewC0P3sA9b//wPR/f8D
0f7/A9H+/wPR/v8D0f3/A9D+/wDe//8OiaX/JBMT/yIhJf8iJCn/ISIn/yEiJ/8hIyf/ISMo/yEj
KP8hIyj/IiMo/yEiJ/8hIif/ISMn/yIjJ/8hIyf/ISIn/yEjJ/8iIyj/ISMn/yEjJ/8hIyf/ISMo
/yEhJv8hGh3/IxQW/yEgJP8hIyf/Iw8P/xRidP8B3P//A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/
A9f//wLR/ewC0P3sA9b//wPR/v8D0f7/A9H9/wPQ/f8D0P7/A9H9/wPS/v8A3v//EneO/yQSE/8i
ICT/ISQp/yIjKP8iIyj/IiMo/yMkKf8iIyn/IiMo/yIjKP8iIyj/IiMo/yIjKP8hIyj/IiMo/yIj
KP8iJCj/IiQo/yIjKP8iIyj/IiMo/yEjJ/8hIif/ISMn/yEiJ/8jEBD/F1Ri/wHW/P8C1f//A9D9
/wLQ/f8D0f3/A9H9/wPR/v8D0f7/A9f//wLR/ewCz/3sAtb//wPR/v8D0f7/A9H9/wPR/f8D0P3/
A9H+/wPR/v8D0///AN7//xCAl/8lGRv/JBse/yIkKf8iIyj/IiMo/yMkKf8jJSn/IiQp/yIjKP8i
JCn/IyQp/yIjKP8iIyf/IiMo/yIjKP8iJCj/IiQp/yIjKP8iIyj/IiMo/yIjKP8iJCn/Ix4i/yQR
Ev8VYHH/Adb8/wLX//8D0P3/A9H9/wPQ/f8D0f3/A9H+/wPR/f8D0f7/A9f//wLR/ewCz/3sAtb/
/wLR/v8C0P7/A9D+/wPR/v8D0f3/A9H+/wPR/v8D0P7/A9L//wDg//8MoLz/IDE4/yUSFP8iHyT/
IiQp/yIkKf8iJCn/IiMo/yIjKP8iJCn/IyQp/yMkKP8jJCj/IyQp/yMkKf8jJCn/IyQp/yMkKf8j
JCn/IyQp/yIiJv8lFRb/IiIm/xCGnf8B3f//Atb//wPQ/v8D0f7/A9H+/wPR/f8D0f3/A9H+/wPR
/v8D0f7/A9f//wLR/ewC0P3sAtb//wLQ/v8D0P3/A9H9/wPR/v8D0f7/A9H+/wPS/v8D0f7/A9H+
/wPR/v8B3///BMru/xRugP8iJCj/JRMV/yQcIP8iIyf/IyQp/yMkKf8jJCn/IiQo/yIjKP8jJCn/
IiQp/yMkKf8jJCn/IyQp/yMkKf8jHyP/JRUW/yMbHv8YWWb/B7na/wDg//8D0///A9H+/wPR/v8D
0f7/A9H+/wPR/v8D0f7/A9L+/wPR/v8D0f7/A9f//wLR/ewCz/zsAtb//wLQ/v8D0f7/A9H+/wPR
/v8D0f7/A9H+/wPS/v8D0f7/A9H+/wPR/v8D0P7/Atb//wDg//8HvN//E3WJ/x86Qf8kHR//JRUX
/yUXGf8kGx7/Ix4h/yMfI/8kHyP/JB4i/yQcH/8lGRv/JRUW/yQZG/8gMDb/FmV1/wmuzf8A3f//
Adr//wPQ/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f7/A9H+/wPS/v8D0f7/A9b//wLQ/ewC
x/LsAtj//wLQ/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR
/v8C2P//AOD//wPP+f8Lqsr/En+W/xhdbP8dRlD/IDhB/yAyOf8fMjj/Hzc//x1DTf8YWGb/EneM
/wuhvv8EyPD/AN///wHb//8C0f//AtH+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9j//wLI8+wCtNvsAtv//wPQ/v8D0f7/A9L+/wPR/v8D0f7/A9H9/wPR/f8D
0v7/A9H+/wPR/f8D0f7/A9H+/wPR/v8D0f7/A9H+/wLT//8B2///AOD//wHd//8C1f//BM33/wXH
8P8Fx/D/BMz2/wLU//8B3P//AOD//wHd//8C1f//A9H+/wPR/v8C0f3/A9H9/wPR/v8D0f7/A9H+
/wPR/v8D0f7/A9H+/wPR/f8D0f7/A9L+/wPR/v8D0f7/A9z//wK13OwCjKjsA+L//wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/f8D0f7/A9H+/wPR/v8D0f7/A9L+/wPR/v8D
0f7/A9H+/wPR/v8D0///A9X//wLV//8C1f//AtT//wPT//8D0f//A9H+/wPR/v8D0f7/A9H+/wPR
/v8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9L+/wPR/v8D0f7/A+L/
/wKMq+wAQE3sA+D//wPR/v8D0f7/A9H9/wPR/f8D0f3/A9H9/wPR/f8D0f3/A9H+/wPS/v8D0f7/
A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0v7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D
0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR
/v8D0f7/A9H9/wPR/v8D0v7/A+H//wBATewAAADsAqPH/wPh//8D0P7/A9H9/wPQ/f8D0f3/A9D9
/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wLR/f8D0P3/A9H+/wPR/v8D0f7/A9H+/wPS/v8D0v7/
A9H+/wPR/v8D0v7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H9/wPR/v8D0f7/A9H+/wPR/v8D
0f7/A9H+/wPR/f8D0f3/A9H+/wPS/v8D0f7/A9H+/wPQ/v8D4f//AqPH/wAAAOwAAADsASMq/wPP
9P8D2///A9D+/wPR/f8C0P3/A9D9/wPR/f8D0f7/A9H+/wPQ/f8D0f7/A9H9/wPR/v8D0f3/A9D9
/wPR/v8D0v7/A9L+/wPR/v8D0f7/A9H9/wPR/v8D0v7/A9H+/wPR/v8D0v7/A9L+/wPS/v8D0f7/
A9H9/wPR/v8D0f7/A9H+/wPS/v8D0f7/A9H+/wPR/f8D0f3/A9H+/wPR/v8D0f7/A9D9/wPb//8D
z/X/ACIq/wAAAOwAAADsAAAA/wA2RP8CzvL/AuH//wPR//8D0f3/A9H+/wPR/v8D0f7/A9H9/wPQ
/f8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR/v8D0f7/A9H+
/wPR/v8D0v7/A9L+/wPR/v8D0f7/A9H+/wPR/f8D0f3/A9H+/wPR/v8D0f7/A9H+/wPR/f8D0f7/
A9H+/wPR/v8D0f//A+D//wPP8/8BN0T/AAAA/wAAAOwAAADyAAAA/wAAAP8AJC3/AqXC/wPg//8D
4v//Atv//wLY//8C1v//Atb//wPW//8D1///A9b//wPX//8D1///A9b//wPX//8D1v//A9b//wPX
//8D1///A9f//wPX//8D1v//A9f//wPX//8D1///A9f//wPX//8D1v//A9f//wPX//8D1///A9f/
/wPX//8D1///A9b//wPX//8D1///A9v//wPh//8D4P//A6bD/wElLf8AAAD/AAAA/wAAAPIAAADb
AAAA7AAAAOwAAADsAAAA7ABEUOwCjqfsArXa7ALH8uwCz/zsAtH97ALQ/ewC0f3sAtD97ALQ/ewC
0f3sAtH97ALR/ewC0P3sAtH97ALR/ewC0f3sAtH97ALR/ewC0f3sAtH97ALR/ewC0f3sAtH97ALQ
/ewC0f3sAtD97ALQ/ewC0P3sAtD97ALR/ewC0f3sAtH97ALQ/OwCyPLsArXa7AKPqOwAR1LsAAAA
7AAAAOwAAADsAAAA7AAAANsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAoAAAAQAAAAIAAAAABACAAAAAAAABCAAAAAAAAAAAAAAAAAAAAAAAAAAAA2wAAAOwAAADsAAAA
7AAAAOwAAADsAAAA7AAkK+wCZ3nsApe17AC03OwCw+/sAsz77ADO/ewCzf3sAs787ALN/ewCzfzs
As387ALN/OwCzfzsAMz87ALN/OwCzf3sAs387ALN/ewCzf3sAs397ALN/OwCzfzsAs387ADN/ewC
zP3sAM397ALN/OwAzfzsAs387ALN/OwCzf3sAs797ALN/ewCzv3sAs397ALM/OwCzfzsAs397ADN
/ewCzfzsAs387ALN/OwCzvzsAs377ALE8ewCtdzsApm37ABoeuwAJSzsAAAA7AAAAOwAAADsAAAA
7AAAAOwAAADsAAAA2wAAAPIAAAD/AAAA/wAAAP8AAAD/AR8m/wKPqP8D0vv/AuH//wLe//8C2f//
Atb//wLU//8C0///AtT//wLT//8D0///AtP//wLT//8C0v//AtP//wLS//8C0v//AtP//wPT//8D
0///AtP//wLT//8C0///AtL//wLT//8C0///AtL//wLS//8C0///AtP//wLT//8C0///AtP//wLT
//8C0///AtT//wLT//8C0///AtP//wLT//8C0v//AtP//wLT//8D1P//A9T//wLV//8D1v//A9n/
/wLe//8C4f//AtL7/wKQqf8BICj/AAAA/wAAAP8AAAD/AAAA/wAAAPIAAADsAAAA/wAAAP8AAAD/
AVBg/wLO8/8C4f//A9L//wPO/v8Dz/7/A8/+/wLO/v8Czv3/As79/wLO/v8Czv3/A879/wLO/f8C
zf3/As39/wPO/f8Dzv3/As39/wLO/v8Dzf3/As39/wLO/f8Dz/7/A879/wPO/f8Dzv3/A879/wLO
/f8Czf3/A839/wPO/f8Dz/7/A87+/wPO/f8Dz/3/A879/wLN/f8Czf3/A839/wLO/f8Czv3/As79
/wLN/f8Czv3/A879/wPP/f8Dz/3/A8/+/wPP/v8Dz/7/A8/+/wLR//8C4f//As/0/wFPYP8AAAD/
AAAA/wAAAP8AAADsAAAA7AAAAP8AAAD/AWF2/wPh//8D1v//A87+/wPP/v8Dzv3/A879/wLO/f8D
zv3/As79/wLO/f8Dzv3/As79/wLN/f8Czf3/A839/wPN/f8Dzf3/A879/wLN/f8Czf3/A879/wPN
/f8Dzv7/As/9/wPP/v8Dz/3/A8/+/wPO/f8Czv3/As39/wLO/f8Dzv3/A8/9/wTP/f8Ez/3/A8/9
/wPO/f8Dzf3/A879/wPO/f8Dzv3/A8/+/wLO/f8Czf3/A879/wPP/f8Dz/3/A8/9/wPP/f8Dz/3/
A8/9/wPP/f8Dzv3/A87+/wLW//8D4P//AmF2/wAAAP8AAAD/AAAA7AAAAOwAAAD/Akxd/wPh//8D
0///A879/wPO/f8Dzv3/A8/+/wPO/f8Dzv3/A879/wPP/v8Dzv3/As7+/wLO/f8Czf3/A839/wPO
/f8Dzv3/As39/wLN/f8Czv3/As39/wLO/f8Czv3/As79/wPO/f8Dzv3/A879/wLO/f8Czv7/As79
/wPO/f8Czf3/A879/wPO/f8Dzv3/A8/9/wPO/f8Czv3/A879/wPO/f8Dzv3/A879/wPO/f8Czv3/
As79/wPO/f8Dz/3/A8/9/wPP/f8Dzv3/A8/9/wPP/f8D0P7/A8/+/wPP/v8Dz/3/A9P//wPg//8B
S13/AAAA/wAAAOwAAADsABwi/wPO9f8D1v//A879/wPO/f8Dz/3/A8/+/wPO/f8Dzv3/A8/9/wPO
/f8Dzv7/A839/wLM/f8CzP3/Asz9/wPM/f8Czf3/As39/wLN/f8Czf3/As39/wPO/f8Dz/7/A879
/wPO/f8Dzv3/A879/wPO/f8Czf3/As79/wPO/v8Dz/7/As7+/wLO/f8Dz/3/A8/9/wTP/f8Dzv3/
A879/wPO/f8Czv3/A879/wPO/f8Dzv3/As39/wLO/f8Dzv3/As79/wPO/f8Dz/3/A8/9/wPP/f8D
z/7/A8/+/wPP/v8Dz/3/A8/+/wPP/v8D1v//A872/wAcIv8AAADsAAAA7AKMqv8D4f//A87+/wPP
/v8Dz/3/A8/9/wPP/f8Dz/3/A8/9/wPP/f8Czv3/A839/wLK/P8CyPv/Asf5/wLG+f8CyPr/Asr8
/wLM/f8Czf3/As79/wLO/f8Dzv3/A87+/wPO/f8Dzv3/As79/wPO/f8Dzf3/A879/wPO/f8Czv3/
As79/wLO/f8Czf3/A879/wPP/f8Ez/3/A879/wLO/f8Czv3/As39/wPO/f8Dz/3/A879/wLO/f8D
zv3/A8/9/wLP/f8Dz/3/A879/wPO/f8Dz/3/A8/9/wPP/v8Dz/7/A8/+/wPP/v8Dz/3/A8/+/wLh
//8Bi6r/AAAA7AAgJuwD0v3/A9L//wPP/v8Dz/3/A8/9/wPP/v8Dz/3/A8/9/wPP/v8Dz/7/A879
/wLM/f8Cyvz/AcX4/wDE+f8Ax/3/AcP2/wLE9v8Cyfr/A8v8/wLN/f8Dzv7/A879/wPO/f8Dzv3/
A879/wLN/f8Dzf3/A839/wLN/f8Czv3/As79/wLO/f8Czv3/As79/wPO/f8Dz/3/A8/9/wPO/f8C
zv3/A879/wPO/f8Dzv3/A8/9/wPP/f8D0f//As/+/wLO/f8Dz/3/A8/9/wPO/f8Dzv3/A8/9/wPP
/f8Dz/3/BM/+/wPP/f8Dz/7/A8/+/wPP/v8D0v//AtH8/wAfJuwAZXrsAuL//wPP/v8Dz/7/A8/+
/wPQ/v8D0P7/A8/+/wPP/f8Dz/7/A8/9/wPP/f8C0f//BL/s/xNCUP8SSFj/CX+g/wKw4f8Axv3/
AcL2/wPF9v8Cyfr/Asz9/wLN/f8Dzf3/A839/wLN/f8CzP3/Asz9/wLL/P8Cy/z/Asz9/wLM/f8C
zP3/Asz9/wLN/f8Dzf3/A879/wPP/f8Dz/3/A879/wPO/f8Dz/3/As79/wPO/f8C2f//A9L//wPR
//8D0P//Atr//wHb//8Cz///A879/wPP/f8Dz/3/A8/9/wPP/f8Dz/3/A8/9/wPP/f8Dz/7/A9D+
/wPi//8AZXvsApi57APf//8Dz/7/As/+/wPQ/v8D0P7/A9D+/wPP/f8Dzv3/A8/9/wPP/v8Dzv7/
AtL//wLG8f8XKjD/GwgF/xsQD/8XKTD/DGyH/wGy5P8Axv3/AsL1/wPH+f8Cyvv/Asr7/wLJ+/8C
yPr/Asb4/wLG9/8CxPb/AsP2/wLD9v8DxPX/A8X2/wPG9/8Dx/n/A8j6/wPL/P8Dzf3/A879/wPO
/f8Czf3/A8/9/wPQ/v8B2f//DJOu/xkqL/8JmLb/AOX//w51jP8MhaD/As/4/wPR/v8D0P7/A8/+
/wPP/v8Dz/3/A8/+/wPP/f8Dz/7/A8/+/wPP/v8C3v//Api67AK13ewD2v//A8/+/wPP/v8E0P7/
A9D+/wPQ/v8Dz/3/A8/9/wPP/f8Dz/3/A879/wPO/v8A2v//Coem/xoODf8ZHB//GhYY/xsNDP8W
Ljb/CIuv/wDE+/8CwvX/AsL0/wLC9f8CwPP/Ar/y/wG/8/8Awvf/AMT6/wDF+/8Aw/n/AMT6/wDF
+/8AxPv/AcT5/wLD9v8Cw/X/A8X3/wPI+f8Cyvz/A8z8/wLN/f8B1v//AO3//w51i/8eAQD/GCgt
/xRIUv8cERD/GiAi/wPD7P8C1v//A8/+/wPP/f8Dz/7/A8/9/wPP/f8D0P7/A8/+/wPP/v8Dz/3/
A9n//wK03OwCw+/sA9f//wPQ/v8D0P7/A9D+/wPQ/v8D0P7/A8/+/wPP/v8Dz/3/A879/wPO/f8D
zv3/AdD//wHJ9/8WMDj/GhUX/xkcH/8ZHB//GhMU/xoSEv8NYHj/ALru/wG/9P8AwPX/AMD2/wG0
5/8Doc7/Boyy/wp6m/8Lbov/DWeD/wxphP8LcY//CX6f/waSuP8Dp9X/ALnt/wDE+v8Bxfr/AsP2
/wPF9/8B0f7/DnqT/xFkdP8XO0X/GxUX/x0KCf8eBgT/GxQV/xY1Pf8CzPb/AtT//wPR//8Dz/7/
A8/9/wPO/f8Dz/7/A9D+/wPP/f8Dz/3/BM/9/wPX//8Cw+/sAs377APV//8D0P3/A9D+/wTQ/v8E
0P3/A9D9/wPP/f8D0P7/A8/9/wPO/f8Dzv3/A879/wLM/f8A2v//Dm6G/xsNDP8ZHB//GRwf/xkc
H/8YGRz/Gw0L/xJFVP8Ensr/B4iu/w9Zb/8UNUD/GCAk/xoVFv8aERH/Gw8P/xsQD/8bEA//GxAP
/xwSEv8aFxj/GCMo/xQ6R/8OYHf/B46z/wG15/8Ayf//AcX1/xopLv8fBQP/HBUW/xklKf8Pc4f/
EWN2/xsaHf8bGRr/GDM7/xVLVv8EyfX/AtL//wPP/f8Dzv3/A8/9/wPP/f8Dz/3/A8/9/wPO/f8D
1f//As777ALP/ewD1f//A9D9/wPQ/v8E0P3/BND9/wTQ/f8Dz/3/A8/9/wPP/f8Dzv3/As79/wLO
/f8Czf3/ANT//waiyf8aFhj/GRse/xkcIP8ZHCD/GRwg/xkcH/8aFBT/GR0g/xoWFv8bEA//GhUV
/xoZG/8ZHB//GRwf/xocIP8ZHCD/GRwf/xkcH/8ZHSD/Gxwg/xsaHP8bFRX/Gw8P/xoUFf8VMTr/
DGuF/wSp1/8Hl73/GSQp/x0NDP8MhqL/AOn//wDl//8SYHL/HRIS/x0PD/8cGx3/Bbrg/wLV//8D
zv3/A8/9/wPP/f8Dzv3/A8/9/wPP/f8D0P3/BNX//wLR/uwCz/zsA9X//wPQ/f8D0P7/BM/9/wPP
/f8Dz/7/A8/+/wPP/f8Dz/3/A879/wLO/f8Czf3/Asz9/wHM/v8BvO7/Fy01/xoXGP8ZHCD/Ghwg
/xodIP8ZHSD/GRwg/xoaHf8ZGx7/GRwf/xkdIP8aHSD/Gh0g/xodIP8bHSD/Ghwg/xkcIP8aHCD/
Gh0g/xodIf8aHSH/Gh0g/xodIP8aHB//GhUW/xwLCf8UNT//AbTi/xg2P/8eCwn/CpGw/wDj//8A
5v//EWyB/x8IBv8XPkf/Bbze/wLR/f8D0P7/A8/9/wPP/f8Dz/3/A8/+/wPP/f8D0P7/A9D+/wPW
//8C0P3sAs/87APV//8D0P7/BND+/wTQ/f8D0P7/A9D9/wPP/f8Dz/3/A879/wLO/f8Czf3/Asz9
/wLK/P8Bxvn/AMP4/xRDUf8cExT/Ghwg/xocIP8bHSH/Gh0g/xocIP8aHSD/Gh0g/xodIP8aHSD/
Gx4h/xodIP8aHSD/Gh0g/xocIP8aHSD/Ghwg/xocIP8aHCD/Ghwf/xkcH/8ZHSD/Ghwg/xkcH/8b
Dw//C4ik/xJmev8dExT/HRQW/xkvN/8LjKn/DXyX/xshJf8eDxD/E1pq/wDh//8D0P//A9D9/wPP
/f8Dz/3/A8/+/wPP/f8D0P7/A9D+/wPQ/v8D1v//AtD97ALP/ewD1f//A9D+/wTR/v8E0f7/A9D+
/wPP/f8Ez/3/A879/wPO/f8Czv3/Asz9/wLK+/8Bxfj/Ar7x/wDG/f8STF7/HBIS/xocIP8aHSD/
Gh0h/xocIP8aHCD/Gx0h/xseIf8bHiH/Gx4h/xsdIf8aHSH/Gx0h/xodIP8aHSD/Gx4h/xsdIf8Z
HCD/GBwf/xgWGP8YExT/GRwf/xodIP8ZHCD/GxER/w5rf/8QeI7/HR8h/xktM/8fEBD/HhQV/x8Q
EP8gEBD/HhMU/x8QD/8LmLj/Adv//wPQ/f8D0P7/A8/9/wPP/f8Ez/3/A9D+/wPQ/v8D0P7/A9b/
/wLR/ewC0P3sA9X//wPQ/v8E0f7/BNH9/wTQ/v8Dz/3/A8/9/wPO/f8Czv3/As39/wHL/P8Bxvj/
Ab3w/wDC+f8HirD/GSMo/xwaHf8aHSH/Gx0h/xsdIf8aHSD/Gx0h/xseIf8bHiH/Gx4h/xodIP8a
HCD/Gh0h/xseIf8bHSH/Gx0h/xseIf8aHSD/GRwg/xcREv8UISb/FDY+/xkXGf8aHSH/Gh0g/xob
Hv8aHB7/Cpi1/wmmw/8KpsT/F0dT/x4TFP8cJSn/D3yR/xNqff8XSVT/A8Xt/wHS//8Cz/3/BND+
/wPQ/f8Dz/3/A9D+/wPQ/v8D0f7/A9H+/wPX//8C0P3sAs/97APV//8D0P3/A9H+/wTR/v8D0P7/
A9D+/wPP/f8Czv3/As39/wLL/P8Cx/n/Ab7y/wDC+P8Kfp//HBga/x0YGv8bHyL/Gx4h/xweIv8b
HiH/Gx4h/xweIv8cHiL/Gx0h/xocH/8aFBX/GRod/xoeIf8bHiH/Gx0h/xodIf8aHCD/GBwf/xcO
D/8VHyP/BbHR/wHV+/8VMTn/GhQW/xodIP8aHiL/Gxkc/xokJ/8aIib/EWFz/wyTr/8iAAD/EHOI
/waszv8BxPX/Ac7//wHN/v8By/z/As79/wPP/f8E0P3/A9D9/wTQ/v8D0P3/A9H+/wPR/v8D1v//
AtD97ALQ/ewD1v//A9D+/wPR/v8D0f7/A9D+/wPQ/f8Dz/7/As79/wHM/f8ByPr/AcHz/wDD+v8K
gaP/HBQV/xwZG/8cHyL/Gx0h/xweIf8cHiL/Gx4h/xweIv8cHiL/HB4i/xsdIf8ZGx7/Ezc//xcV
F/8aFhj/Gh4h/xseIf8aHSH/GBwg/xcPD/8UHSH/BbHR/wHg//8A4v//DnaM/xsLC/8aHSH/Gx4i
/xsfIv8bGh3/HBQV/xgvNf8Knrv/C5qy/wioyf8bJyv/Ek1f/wDG/P8Bxvn/Asn6/wLM/f8Dzv3/
BND9/wPQ/v8D0f7/A9H+/wPQ/f8D0P7/A9b//wLQ/ewC0P3sAtb//wPQ/f8E0f3/BNH+/wPQ/v8D
0P7/A8/+/wLN/v8By/z/AsP1/wDD+v8Glb3/Gxkb/xwYGv8cHyP/HB4i/xseIf8cHiL/HB4i/xse
Iv8bHiH/HB4i/xseIf8cGBv/Fysy/wHT//8Ik67/FxcZ/xoREv8aHSH/GRwg/xgPEP8UHSH/BbHQ
/wHh//8D0P7/Adn//wa12/8ZGhz/Ghse/xseIv8bHiL/Gx4h/xseIv8bGRv/Ghwf/xc1PP8ZKC7/
GhYZ/x0ODP8OaYH/AMr//wLG9/8Cyvv/A839/wPP/f8D0P7/A9H+/wPR/v8D0P7/A9H9/wPX//8C
0f3sAtD97ALW//8C0P7/A9H+/wPR/v8D0P7/A9D+/wPP/v8Czf3/Asj5/wHC9v8Cr+D/GC01/xwU
Ff8cHiL/HB4i/xweIv8cHiH/HB4h/xweIv8cHiL/Gx4h/xseIf8cHiL/HRUX/xRBTP8FsNP/ANr/
/wWszf8ULTP/GQwL/xcPEP8VHiH/BbDP/wHh//8D0P7/A9H+/wLS//8B3P//E0tZ/xwREv8bHiL/
Gx4h/xseIf8bHiH/Gx4h/xscH/8cGRz/HBoc/xodIP8bGx7/HRQU/wiOsv8AzP//Asf4/wLL/P8D
zf3/A8/9/wTQ/f8D0P7/A9H+/wPR/v8D1///AtH97ALQ/ewD1v//A9D9/wPR/v8D0f7/A9D9/wPP
/f8Dzv3/Asv8/wHD9f8Aw/r/EVpw/x4PDv8cHyP/HR8j/x0fIv8cHiL/HB4i/xweIv8dHyL/HR8j
/xweIv8cHiH/HB4i/xwSE/8QWmv/Emt8/wuRr/8A4///Ar/r/xA/TP8VGBr/Ba/O/wHh//8Cz/7/
A9H+/wPR/v8D0f7/AeD//wqMqv8cDg7/Gx4i/xweIv8cHyL/HB4i/xweIv8cHyL/HB8i/xweIv8b
HiL/Gx4i/x0WF/8ZLjb/Abfo/wHH+/8Cyvv/As39/wPP/f8E0P7/A9H+/wPR/v8D0f7/A9b//wLQ
/ewC0P3sA9b//wPQ/f8D0P7/A9H+/wPQ/v8Dz/7/Asz9/wHH+f8Axvv/BZrD/xwZGv8cHB//HR8i
/x0fI/8dHyP/HR8j/x0fI/8dHyP/HR8j/x0gI/8dHyP/HR8j/xweIv8cDw//DWt//xVba/8ZP0b/
ANH+/wDE+f8Cs+P/BLfc/wHd//8C0P7/AtD+/wLQ/v8D0f7/A9H9/wLX//8Ew+3/GSUq/xwaHf8c
HyL/HR8j/x0fI/8cHyL/HB8j/xweIv8cHiL/Gx4h/xweIv8bHiL/Hg4N/w5rhP8Azv//Asf5/wLM
/f8Dzv3/A9D9/wPR/v8C0f7/A9H+/wPW//8C0P3sAtD97APW//8D0f7/A9H+/wPQ/f8Dz/3/As7+
/wLM/P8Cxff/AMb7/xNRYv8fEhL/HR8j/x0fIv8dHyP/HR8j/x0fI/8eICP/HSAj/x4gJP8eICT/
HR8j/x0fI/8cHyL/HA8P/wx5kP8WVmX/IAsJ/wqfwP8AxPb/Asv5/wHZ//8Cz/3/AtD+/wLQ/v8C
0P7/A9D+/wPQ/v8C0f7/At7//xRUYv8dERH/HB8i/x0fI/8dHyP/HiAk/x0fI/8cHiL/HB4i/xwe
Iv8cHyL/HB4i/xwZHP8aJiv/A7Ph/wHJ/P8Cy/z/A87+/wPQ/f8D0f7/AtH+/wPR/v8D1///AtD9
7ALQ/ewD1v//A9H+/wPR/v8D0P7/A8/9/wLN/v8Cy/z/Acn9/wWjz/8cHiH/HR0g/x0fI/8dHyP/
HR8j/x4gI/8dICP/HiAk/x4fI/8dHyP/HR8i/x0fIv8cHiL/HB4i/xwREv8MhZ7/F0VQ/yANDP8X
SFL/ANr//wLW//8Cz/3/AtD9/wLQ/v8C0P7/A9D+/wLQ/v8C0P7/AtH+/wHf//8Lka7/HQ8P/xwe
Iv8dHyP/HSAj/x4gI/8dHyP/HR8j/x0gI/8dHyP/HR8j/xweIv8cHyP/HhAP/wx3lP8Az///Asr7
/wPO/f8Dz/3/A9D9/wPR/v8D0f7/A9f//wLR/ewC0P3sAtb//wPQ/f8D0P7/A9D9/wLO/v8Czf3/
Asn6/wDM//8ObYj/HxAQ/x0fI/8eHyP/HR8j/x0fI/8eICT/HiAk/x4gI/8dHyP/HR4i/x0eIv8d
HiL/HB4i/xsdIf8aFRb/C4mk/xk1PP8dGx3/HhIT/xBsgf8A3f//AdL//wLP/f8C0P3/A9D+/wPR
/v8D0f7/AtH+/wLQ/f8B1f//BMbw/xopLv8dGhz/HR8j/xwfI/8dICP/HiAj/x4gJP8eICT/HiAj
/x0fI/8dICP/HR8i/x4VFv8XP0v/Acb4/wLJ+/8Czf3/A879/wPQ/f8D0f7/A9H+/wPX//8C0P3s
AtD97ALW//8D0P3/A9H+/wPQ/f8Dzv7/As39/wLI+v8Bwvb/Fz9M/x8WF/8eICP/HiAk/x4fI/8e
ICT/HiAk/x4gJP8eICT/HR8j/x0eIv8dHyL/HB4h/xodIf8aERL/GBYZ/wmRrP8bGx3/HRod/x0e
If8fDg7/EHCG/wDe//8C0///AtD9/wLQ/v8D0f7/A9H+/wLR/v8D0f3/AtD+/wDf//8SYHL/HhAQ
/x0fI/8dICT/HSAj/x4gI/8eICT/HiAk/x4gJP8eICT/HiAk/x4gI/8eHSD/HR8i/wWq1P8Bzf//
Asz9/wPP/f8D0P3/A9H+/wPR/v8D1///AtH97ALQ/ewD1v//A9H9/wPR/v8D0P7/A8/+/wLM/f8B
y/7/Ba3Z/x0kKf8fHSD/HiAk/x4gJP8eICT/HiAk/x4gJP8eICT/HiAk/x4fI/8dHyL/Gx8i/xsZ
G/8aCgr/FDE4/wieuf8C1fX/Dmt9/xsREf8cFRf/HB4h/x8QD/8QdYv/AN///wLT//8D0P3/A9D9
/wPQ/f8D0f7/A9H+/wPQ/v8A3f//CaPE/x4UFf8eHyP/HiEk/x0gI/8eICP/HiAk/x4gJP8eICT/
HiAk/x4gI/8dHyP/HR8j/yAUE/8Lh6f/ANH//wLL/P8Dzv3/A9D9/wPR/v8D0f7/A9b//wLR/ewC
0P3sA9f//wPR/v8D0f7/A9D+/wPP/v8CzP3/AND//wmVuv8fFxj/HiAj/x4gJP8eICT/HiAk/x8g
JP8fIST/HiAj/x4gI/8dHyP/HB0h/xwOD/8YGh3/DXSI/wLQ9v8A3v//AtT//wDh//8Inrn/Fyow
/x0NDf8cHB//HxEQ/w94j/8A3///AtL//wLQ/f8C0P7/A9H9/wPR/f8D0f3/A9P//wLS+/8ZOEH/
Hxga/x4gJP8eICP/HiAk/x8hJP8fISX/HyEk/x8hJP8eICT/Hh8j/x0gJP8gEhL/EWd9/wDS//8C
y/z/A87+/wPQ/f8D0f7/AtH+/wPW//8C0P3sAtD97APW//8D0f7/A9H+/wPQ/f8Czv7/Asz8/wDT
//8NgJ7/IBMT/x4gJP8eICT/HiAk/x4gJP8fISX/HyEl/x4gJP8dICP/HRYY/xsODv8STVn/BbfX
/wDh//8C1P//As/9/wLQ/f8C0P//AN///wPJ7P8RWGb/HA8P/x0WGP8fERH/DnqS/wDg//8B0v//
AtD9/wLQ/f8C0f3/A9H+/wPQ/f8A4f//EHaN/yAPD/8eICT/HiAk/x8hJf8fIib/HyEl/x4gJP8f
ISX/HyEl/x4gI/8dHyP/HxQV/xVRYf8Az///Asv9/wPO/f8D0P3/A9H+/wPR/v8D1///AtD97ALQ
/ewD1v//A9H+/wPR/v8D0P3/As79/wLL/P8A0///EHGK/yETE/8eICX/HiAl/x4gJP8eICT/HiEk
/x8gJP8eICT/HRga/xgtM/8Jkav/ANv//wHa//8Cz/3/AtD9/wLQ/f8C0f7/A9D+/wPQ/v8C2P//
Ad///wqQqP8ZIyj/Hg0N/x8REP8Ofpb/AOD//wHS//8C0P3/AtD9/wPR/v8C0P7/Adn//we13P8d
HR//Hh4h/x4gJP8fIib/HyIm/x8hJf8eICT/HiAk/x8gJP8fICT/HR8i/x4WF/8XRVL/AMz//wLN
/v8Czv7/A9D9/wPQ/f8D0f3/A9f//wLR/ewC0P3sAtX//wLQ/f8D0f7/A9D9/wLO/f8CzPz/ANX/
/xJsg/8hExT/HiAk/x8hJP8fICT/HiAk/x8hJf8fISX/Hxwf/x0sMf8Dx/D/AOT//wHQ//8C0P3/
AtD9/wLQ/f8C0P3/A9H+/wPR/f8D0f7/A9D9/wLS//8A4f//BMDh/xNOWv8eCwr/HwwL/w6Cmv8A
4f//AtL//wLQ/f8C0f7/A9H+/wPS/v8B2v//F0xZ/x8UFf8fISX/HyEl/x8hJf8fISX/HyEk/x4g
JP8fISX/HyAk/x0fI/8fFxn/GUFM/wHM/v8Czf//A879/wPQ/f8D0P3/AtD9/wPW//8C0f3sAtD9
7ALW//8C0P3/A9H9/wPQ/f8Czv3/Acz9/wDW//8Tb4b/IhMU/x4gI/8eICT/HiAk/x8hJf8fICX/
HyEk/x8dIP8eJyv/CqPE/wDY//8A3v//Adf//wLR//8C0P3/AtD9/wLQ/f8C0P3/AtD9/wLQ/f8C
0P7/A9D+/wLa//8B3P//DIWb/xsaHf8gBAH/DoSc/wDh//8B0f//AtD+/wLR/f8D0P7/Ad///w2N
qf8gERH/HiAk/x4hJf8fISX/HyEl/x8gJP8fISX/HyEl/x4gJP8eICT/HxcY/xlET/8Bzv//As7/
/wPP/f8D0P3/A9D9/wLQ/f8C1v//AtD97ALQ/ewC1v//A9D9/wPQ/f8D0P3/A8/9/wLM/f8A1///
D3yX/yITFP8fISX/HyAl/x8hJf8fISX/HyEl/x8hJf8fISX/Hx0g/x8aG/8ZQkz/D4CW/wW63v8A
2v//AN7//wHV//8C0P7/AtD+/wPR/v8C0P3/AtD9/wLQ/f8D0P7/A9P//wHj//8FuNj/FkNM/yAA
AP8NgZr/AOL//wLR/v8C0P3/AtD+/wHW//8Exe//HCku/x8bHv8eICT/HyAl/x8hJf8fICT/ICEl
/x8hJf8fIST/HiAk/yAVF/8XTlz/ANP//wLO/v8Dz/3/A9D9/wPR/f8D0P3/A9b//wLQ/ewC0P3s
Atb//wLR/v8C0P7/A9H+/wPQ/f8Czf3/ANb//wuSs/8hFRb/HyAl/yAiJv8gIib/ICIm/yAiJv8g
ISX/HyEl/x8hJf8fHiP/IBYZ/yEREf8fIiX/F1Bc/w2Op/8Dw+n/AN3//wDd//8B1P//AtH+/wLR
/v8C0P3/AtH9/wPR/v8D0P7/Atz//wLb//8Oeo7/HQ4N/w5+lP8A4v//AtH//wLQ/v8C0f7/AN//
/xRfcP8gEhL/HyEl/x8gJf8fISX/HyAl/x8hJf8fISX/HyEl/x4fI/8gEhP/FGN2/wDY//8Czf3/
A8/9/wPQ/f8D0f7/A9H+/wPW//8C0P3sAtD97APW//8D0P7/A9D+/wPR/v8D0P7/As39/wDT//8G
rdb/IB8i/x8fI/8gISb/ICEm/yAiJv8gIib/ICIm/x8hJf8fICX/HyEl/x4gJP8eICT/Hx0g/yAU
Fv8hEhP/Hiou/xZcaf8LmLP/A8nw/wDe//8A3P//AtT//wLQ/v8C0P3/A9H9/wPQ/v8D1P//AOL/
/wavzf8YNz3/DnyS/wDe//8C0v//AtD9/wDd//8KocL/IBUW/x8gJP8fISX/HyEl/x8gJP8fISX/
HyEk/x8gJP8eICP/IhMT/w+Cnf8A2f//A879/wPQ/f8D0P3/A9H+/wPR/v8C1v//AtH97ALP/ewD
1f//A9D9/wPQ/f8D0P3/A9D9/wLO/f8Bz///Acn3/xw2P/8hGh3/ICEm/yAhJf8fISX/ICIm/yEi
J/8gISb/ICEl/x8hJf8fISX/HyAl/x8gJP8fICX/HyEl/yAdIP8iExX/IRQV/x0vNP8UZHP/Cp+9
/wLN9f8A3///ANv//wLT//8D0P3/A9D9/wPQ/v8B3f//A9T4/xBvgP8LiaL/AdX7/wLR/v8C0///
AtH6/xs3P/8gGRv/HyEl/x8hJf8fISX/ICEm/yAhJf8fICX/Hh8j/yAaHP8HqM7/Adb//wPP/f8D
0P3/A9D9/wPQ/v8C0f7/Atf//wLR/ewC0P3sAtb//wPQ/f8C0P3/AtD9/wPQ/v8Dz/3/As39/wDa
//8TZXr/IhIT/x8hJv8fISX/HyAl/yAiJv8gIib/ICIm/yAhJv8gIib/ICIm/yAhJf8gISX/HyEl
/yAhJf8gISX/HyEl/x8hJf8gGx//IhMU/yIWF/8dNTv/E2t8/wmmxP8C0fr/AN///wDa//8D0///
A9D9/wLU//8A3f//CKjJ/wa01/8C1P7/AtH+/wDh//8Rdov/IRAR/x8gJf8gISb/ICIm/yAhJf8g
ISX/HyEl/yAaHP8bNz//Asv4/wLQ//8D0P3/A9D9/wPR/f8D0f7/A9H+/wPX//8C0f3sAtD97ALW
//8D0P3/AtD+/wLQ/v8D0f7/A9D9/wLO/f8A1///CaPI/yIYGf8fICT/HyEl/x8hJv8hIif/ICEm
/yAhJv8gISb/ICIm/yAiJv8gISX/HyEl/yAhJf8gISX/ICEl/x8hJf8fISX/ICIm/yEiJv8gISX/
IRse/yISE/8hGBn/HDpB/xJvgf8Iqcj/AtH7/wDf//8A2v//AtP//wHX//8Dz/v/AtD9/wLQ/f8B
2f//CLPZ/x8dH/8gHyP/ICIm/yAiJv8gISX/ICEl/x8hJf8iERH/EXCF/wDc//8Dzv3/A9D9/wPR
/f8D0f7/A9H+/wPR/v8D1///AtD97ALQ/ewC1v//AtD9/wLQ/v8D0f7/A9H+/wPR/f8Dz/3/As/+
/wDT/v8aRE//IhcZ/yAiJv8gIif/ISIn/yEiJ/8hIyf/ISMo/yEiJv8gIib/ICEm/x8hJf8fISX/
ICIm/yAiJv8gIib/ICEm/yAiJv8hIif/ISIn/yEiJv8gIib/ICAk/yEaHP8jEhP/IRoc/xw8RP8T
cYT/CarK/wLR+/8A3///ANr//wLT//8C0P3/AdH//wHZ//8YSFT/IRUX/yAhJf8hIib/ICEl/x8h
Jf8gHiL/IB4h/wWz3P8B1v//A8/9/wPQ/f8D0f7/A9H+/wPR/v8D0f7/A9f//wLR/ewC0P3sAtb/
/wPR/v8D0f7/A9H+/wPR/f8D0f3/A9D9/wPO/f8A2v//DJe5/yMUFf8fISb/ICIn/yEiJ/8hIib/
ISMn/yEjJ/8gIif/ISIn/yEiJ/8hIib/ICEm/yEiJv8gIib/ISIn/yAiJv8gIib/ISIn/yEiJ/8h
Iif/ISIn/yAiJv8hIif/ICIn/yEhJf8iGx7/JBMU/yIbHf8cO0P/E3CD/wmnx/8Cz/j/AN7//wDb
//8A4v//DYyn/yEUFP8gISX/ICIm/yAiJv8fISb/IhES/xRgcv8A2///A8/+/wPQ/f8C0P3/AtH+
/wPR/v8D0f7/A9H+/wPX//8C0f3sAtD97ALW//8D0f7/A9H+/wPR/v8D0f3/AtD+/wPQ/f8Dz/3/
Ac7+/wDX//8ZT13/IxQV/yAjKP8gIif/ISIn/yAiJ/8iIyf/ISIn/yEjJ/8hIif/ISIn/yEiJ/8h
Iif/ISMn/yEiJ/8hIif/ICIm/yEiJ/8hIib/ISIn/yEiJ/8hIib/ISIn/yEiJv8gIib/ISIm/yEi
J/8hISX/IRkc/yMSE/8iGhz/HTlA/xRsfv8KosH/AdX5/wa84v8hIST/IB8j/yAhJv8gIib/IRwf
/x8kKP8FvOP/Adf//wPQ/f8D0P7/AtD9/wLR/v8C0f3/A9H9/wPR/v8D1v//AtH97ALQ/ewC1v//
AtD9/wPR/v8D0f7/AtD+/wLQ/v8D0P7/A9D9/wPP/f8B1///Brne/yEjJ/8iHB//ISMn/yEjKP8i
Iyj/ISIn/yEiJ/8hIif/ISIn/yEiJ/8hIif/ISMn/yEjKP8hIyf/ISIn/yAiJv8hIif/ISIm/yEi
J/8hIif/ISIn/yEiJ/8hIyf/ISMn/yEiJ/8hIif/ISMn/yEiJ/8gIib/ISEm/yIbHv8jExT/Ihga
/xw7Q/8aQk3/ICAk/yAhJf8hIib/ISEl/yMREv8OiKT/AN///wPQ/f8D0P3/A9H9/wPR/v8C0f7/
AtH9/wPR/f8C0f3/A9b//wLQ/ewC0P3sAtb//wLQ/f8D0f3/A9H+/wPQ/v8D0f7/A9H9/wPR/f8D
0P3/A8/9/wDe//8Nk7D/IxUV/yIgJP8iIyj/IiQp/yEjJ/8hIif/ISIn/yEjJ/8hIyf/ISMo/yEj
J/8hIyj/IiMo/yIjKP8hIif/ISIn/yEiJ/8hIyf/IiIn/yIjKP8hIif/ISIn/yEjJ/8iIyj/ISMn
/yEjKP8hIif/ISMn/yEjJ/8hIyf/ICIn/yAhJf8hGh7/Ihod/yEjJ/8hIif/ISIm/yMPEP8UXnD/
Adz//wPR/v8D0P3/A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f7/AtH+/wPX//8C0f3sAtD97APW//8D
0f3/A9H9/wPR/f8D0P3/A9D9/wPR/f8D0f7/A9D9/wPQ/f8D0P7/AN///xF6kv8kEhL/IiEl/yEj
KP8hIyj/ISMo/yEjKP8iIyj/ISMo/yIjKP8iIyj/ISMo/yIjKP8iIyj/IiMn/yIjKP8iIyf/IiMn
/yIjKP8iIyj/ISMn/yIjKP8iIyf/IiQp/yIkKP8iJCj/ISMo/yIkKP8iIyj/ISMo/yEiJ/8hIif/
ISIn/yIjJ/8hIyf/ICMn/yMQEf8YSlb/AtT5/wLW//8D0P3/A9D9/wLR/v8D0f3/A9H9/wPR/f8D
0f7/A9H+/wPR/v8D1///AtH97ALQ/ewC1v//AtD9/wPR/v8D0f7/A9H+/wPR/f8D0f3/A9D+/wLQ
/v8D0f7/A9H+/wLT//8A3f//EnWL/yQTFP8iHyP/IiQp/yIjKP8iJCn/IiMo/yIjKP8iJCn/IyQp
/yIkKf8iIyn/IiMo/yIjKP8iIyj/IiMo/yIkKP8iIyj/ISMo/yIjKP8hIyj/IiMn/yIjKP8iJCn/
IiQo/yIjKP8iIyj/IiQp/yIjKP8iJCj/ISMo/yIjKP8iIyj/ISIn/yMQEf8ZSVX/A9D0/wLZ//8D
0P7/A9H9/wPR/f8D0P3/A9D+/wPR/f8D0f3/A9H9/wPR/v8D0f7/A9f//wLR/ewCz/3sAtb//wLQ
/f8D0f7/A9H+/wPR/f8D0f7/A9H9/wPQ/f8C0f7/A9H+/wPR/v8D0f3/A9P//wDe//8PhZz/JBsd
/yQbHv8iJCn/IiMo/yIjKP8iIyj/IiMo/yMkKf8kJSn/IyQp/yIjKP8iIyj/IyQp/yMlKv8jJCn/
IiMo/yIjJ/8iIyj/IiMo/yIjKP8iIyj/IiQp/yIkKf8hIyj/ISMo/yIjKP8iIyj/IiMo/yIjKP8i
JCn/Ix8j/yMREv8WW2r/AtP4/wHZ//8D0P3/A9H9/wPR/v8D0f3/A9D9/wLQ/f8D0f7/BNH+/wPR
/f8D0f7/AtH+/wPX//8C0f3sAs/97ALW//8C0P7/AtD+/wLQ/v8C0P3/A9H+/wPR/v8D0f7/A9H9
/wPR/v8D0f7/A9H+/wPQ/f8D0v//AOD//wulwf8gMzn/JRMV/yIhJf8iIyj/IiMo/yIjKf8jJCn/
IiQp/yIkKf8iIyj/IiMo/yIkKf8iJCn/IyQp/yMkKP8iJCj/IyQp/yIkKf8jJCn/IyQp/yMkKf8j
JCn/IyQp/yIjKP8jJCn/IiQo/yIjKP8jJCj/JBYZ/yIfIv8QgZf/Adz//wHW//8D0P7/A9H+/wPR
/v8D0f7/A9H+/wPQ/v8C0P3/A9H+/wPR/v8D0f7/A9H+/wPR/f8D1///AtH97ALQ/ewD1v//AtH+
/wLQ/v8C0P3/A9H9/wPR/f8D0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H9/wPQ/v8B3v//
BMvu/xZoeP8jHB//JBUX/yIhJv8iJCn/IiQo/yIkKP8iJCj/IiQp/yIkKf8jJCn/IiMo/yIkKP8j
JCj/IyQp/yMkKf8jJCn/IyUp/yMkKf8jJCn/IyQp/yMkKf8jJCn/IyQp/yIjKP8jGRz/JBQW/xpJ
VP8IstH/AOH//wLT//8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+
/wPR/v8D0f3/A9f//wLR/ewC0P7sA9b//wLQ/v8C0P7/A9H9/wPR/f8D0f7/A9H+/wPR/f8D0f7/
A9H+/wPS/v8D0v3/A9H+/wPR/v8D0f7/A9D+/wLX//8A4P//Ca/N/xlXZP8jHiH/JRQW/yQdIf8i
Iyj/IyQp/yMkKf8jJCn/IyQp/yMkKf8iIyj/IiMo/yMkKf8jJCn/IiQp/yIkKf8jJCn/IyQp/yIk
Kf8iJCn/IyAk/yQWGP8kFxn/HEBJ/w2Vrf8C2v//Adz//wPQ/v8D0f7/A9H+/wPS/v8D0f7/A9H+
/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9L+/wPS/v8D0f7/A9D9/wPW//8C0f7sAs767ALW//8C0f7/
AtD9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0v7/A9H+/wPR/v8D0f7/A9L+/wPR/v8D
0f7/A9H+/wHb//8B3f//CLLS/xVugP8fNz7/JRwe/yYVF/8kGRz/Ix0h/yMhJf8jIyj/IiMo/yMk
Kf8jIyj/IyQp/yMjKP8jISb/JB8j/yQbHf8lFRf/JBcZ/yEsMP8YWmn/C5+6/wLV/f8A3///AtP/
/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/
A9H+/wPQ/v8D1v//As/77ALD7uwC2P//AtD+/wLQ/v8C0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D
0f7/A9H+/wPR/v8C0f7/A9H+/wPR/v8D0f7/A9H9/wPR/f8D0f3/A9H//wHa//8A3///A832/wum
xf8TeY3/GlJf/x84P/8iKCz/JB8j/yUcHv8kGRv/JBkb/yQbHf8kHyL/IiYq/x80Ov8aSlX/FW1/
/w2ZtP8Ew+n/AN3//wDd//8C0///A9H+/wLR/v8C0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR/f8D0f7/A9j//wLF7+wCtNvsAtv//wLQ/v8D
0P7/A9H+/wPR/v8D0v3/A9H+/wPR/v8D0v7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR
/v8D0f7/A9H9/wPR/v8D0f7/A9D+/wLT//8B2///AOD//wHa//8Ezff/B7zi/wqt0P8LocH/DZq4
/w2auP8MoL//CqvM/wi53f8EyvL/Adf//wDf//8B3v//Atb//wLR//8D0f7/A9H+/wPR/f8C0f3/
A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/BNH+/wPR/v8D
0f7/A9H+/wPb//8CtdzsApi37ALg//8C0P3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR
/v8D0f7/A9L+/wPR/v8D0f3/A9H9/wPR/f8D0v7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+
/wPR/v8D0v//A9T//wLX//8B2v//Adz//wHd//8B3f//Adz//wHb//8C2P//AtX//wPT//8D0v7/
A9H+/wPR/v8D0f7/A9H+/wLR/v8C0f3/A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D
0f7/A9H+/wPR/f8D0f7/A9H+/wTS/v8D0v7/A9H+/wPR/f8D4P//Apm67ABleewD4///A9D+/wPR
/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPS/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+
/wPR/v8D0f7/A9H+/wPS/v8D0v7/AtH+/wPR/v8C0f7/A9H+/wPR/v8D0f7/A9L9/wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0v7/A9H+/wPR/v8D0f7/A9H+/wPR/f8D
0f7/A9H9/wPR/f8D0f7/A9H+/wLR/f8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR
/f8D0f7/A+P//wBne+wAICbsA9P9/wPU//8D0f7/A9H+/wPR/v8D0f3/BNH9/wPR/f8D0f3/A9H9
/wPR/f8D0f3/A9H+/wPS/v8D0v7/A9H+/wPR/f8D0f7/A9H+/wPR/v8D0f7/AtH+/wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9L+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wLR/v8D0f7/A9H+/wPR/v8D
0f7/A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/AtH+/wPR/v8D0f3/A9H+/wPR/v8D0f7/A9H9/wPR
/v8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR/v8D0f7/A9T//wPS/P8AICbsAAAA7AKMqv8D4///A9D+
/wPR/v8D0f7/A9H9/wPQ/f8D0f3/A9H9/wPQ/f8D0f7/A9H+/wPR/f8D0v7/A9L+/wPR/v8D0f3/
A9H9/wLR/v8D0f3/AtD9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9L+/wPS/v8D0f7/A9H+/wPR/v8D
0f7/A9L+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8C0f7/A9H+/wPR/v8D0v7/A9H+/wPR
/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/f8D0f3/A9L+/wPS/v8D0f7/A9H+/wPR/v8D0P7/A9D+
/wPj//8CjKr/AAAA7AAAAOwAHCL/A8/2/wPY//8C0P7/A9H+/wPR/f8D0P3/A9D9/wPQ/f8D0P3/
A9H+/wPR/v8D0f7/A9H+/wLR/v8D0f7/A9H+/wPR/f8D0f3/A9H9/wPQ/f8D0f3/A9H+/wPS/v8D
0f7/A9H+/wPS/v8D0f7/A9H+/wPR/f8D0f7/A9L+/wPR/v8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR
/v8D0f3/A9H9/wPR/f8D0f7/A9H+/wPR/v8D0f7/A9L+/wPR/v8D0f7/A9H9/wPR/f8D0P3/A9H9
/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9D+/wPY//8DzvX/ARwi/wAAAOwAAADsAAAA/wFLXP8D4f//
AtT//wPQ/f8D0f7/A9H9/wLR/f8D0P3/A9D9/wPR/f8D0f7/A9H+/wPR/v8D0f3/A9H+/wPR/f8D
0f3/A9H+/wPR/v8D0f3/AtD+/wPR/v8D0v7/A9L+/wPS/v8D0f7/A9H+/wPR/v8D0f7/A9L+/wPS
/v8D0f7/A9H+/wPS/v8D0v7/A9L+/wPS/v8D0v7/A9H+/wPR/v8D0f3/A9H+/wPR/v8D0f7/A9H+
/wPS/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR/f8D0f7/A9H+/wPR/v8D0f3/A9D9/wPV//8D4f//
AUtd/wAAAP8AAADsAAAA7AAAAP8AAAD/AV91/wLg//8C1///A9D+/wPR/v8D0f3/A9H+/wPR/v8D
0f7/A9H+/wPR/v8D0f7/A9D9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wLR/v8C0f3/A9H+/wPR
/v8D0f7/A9H9/wPR/f8D0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0v7/A9L+/wPS/v8D0v3/A9H+
/wPR/v8D0f7/A9H9/wPR/f8D0f3/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f3/
A9H+/wPR/v8D0f7/A9D9/wPX//8E4f//AmB1/wAAAP8AAAD/AAAA7AAAAOwAAAD/AAAA/wAAAP8B
Tl//As7z/wLi//8D1P//A9D+/wPR/v8C0f7/AtH+/wPR/v8C0f7/A9D9/wPR/f8D0f7/AtH+/wLQ
/f8D0f7/A9H+/wPR/f8C0f7/A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+
/wPS/f8D0f7/A9H+/wPS/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/A9H+/wPR/v8D0f7/
A9H+/wPR/v8D0f7/A9H9/wPR/v8D0f7/A9H9/wPR/v8D0P7/A9T//wPj//8Ez/P/Ak9f/wAAAP8A
AAD/AAAA/wAAAOwAAADyAAAA/wAAAP8AAAD/AAAA/wEfJ/8Cj6j/AtP7/wPj//8D3///Atr//wLX
//8C1///Atb//wPX//8C1///A9f//wPX//8D1v//A9f//wPX//8D1///A9f//wPX//8D1v//A9f/
/wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///
A9f//wPX//8D1///A9f//wPX//8D1///A9f//wPX//8D1///A9b//wPW//8D1///A9j//wLa//8D
3///A+L//wPT/P8Dkan/ASAn/wAAAP8AAAD/AAAA/wAAAP8AAADyAAAA2wAAAOwAAADsAAAA7AAA
AOwAAADsAAAA7AAkK+wAaHnsApm37AK02+wAxO7sAs767ALR/ewC0P3sAtD97ALR/ewC0f3sAtD9
7ALQ/ewC0f3sAtH97ALR/ewC0f3sAtD97ALR/ewC0f3sAtH97ALR/ewC0f3sAtH97ALR/ewC0f3s
AtH97ALR/ewC0f3sAtH97ALR/ewC0f3sAtD97ALR/ewC0f3sAtD97ALQ/ewC0f3sAtD97ALQ/ewC
0f3sAtH97ALQ/ewC0f3sAs767ALF7+wCtdzsApm57ABpe+wAJi3sAAAA7AAAAOwAAADsAAAA7AAA
AOwAAADsAAAA2wAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
AAAAAAAAAAAA
'@

function Get-AppIcon {
    # 1) 옆에 있는 app.ico (가장 선명합니다)
    try {
        $iconPath = Join-Path $AppDir 'app.ico'
        if (Test-Path -LiteralPath $iconPath) { return (New-Object System.Drawing.Icon($iconPath)) }
    } catch { }
    # 2) 프로그램 안에 담아 둔 아이콘
    try {
        $bytes = [Convert]::FromBase64String(($script:AppIconBase64 -replace '\s', ''))
        $stream = New-Object System.IO.MemoryStream(,$bytes)
        return (New-Object System.Drawing.Icon($stream))
    } catch { }
    # 3) 실행 파일에 박힌 아이콘 (크기가 하나뿐이라 조금 흐릴 수 있습니다)
    try {
        if ($script:IsExe -and $script:HostPath) { return [System.Drawing.Icon]::ExtractAssociatedIcon($script:HostPath) }
    } catch { }
    return $null
}

# 작업 표시줄이 이 프로그램을 파워셸이 아니라 별개의 프로그램으로 보게 합니다.
try { [NativeKakao]::SetAppId('KakaoSender.Broadcaster') } catch { }
try {
    $script:appIcon = Get-AppIcon
    if ($null -ne $script:appIcon) { $script:form.Icon = $script:appIcon }
} catch { }
$script:form.Font = $FontBase

# ----- 사이드바 -----
$sidebar = New-Object System.Windows.Forms.Panel
$sidebar.Location = (New-UiPoint 0 0)
$sidebar.Size = New-Object System.Drawing.Size((S 220), $script:UiFormHeight)
$sidebar.Dock = 'Left'
$sidebar.BackColor = $Theme.Sidebar
$script:form.Controls.Add($sidebar)

$logo = New-Object System.Windows.Forms.Panel
$logo.Location = (New-UiPoint 0 0)
$logo.Size = (New-UiSize 220 104)
$logo.BackColor = $Theme.Sidebar
$logo.Add_Paint({
    param($sender, $e)
    $e.Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $mark = New-UiRect 26 28 44 44
    $path = Get-RoundedPath $mark 13
    $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
    $e.Graphics.FillPath($brush, $path)
    $brush.Dispose(); $path.Dispose()
    Write-Text $e.Graphics '톡' $FontLogoMark $Theme.AccentInk $mark $TextCenter
    Write-Text $e.Graphics '카카오 발송기' $FontLogo $Theme.Ink (New-UiRect 82 32 130 22) $TextLeft
    Write-Text $e.Graphics "v$($script:AppVersion)" $FontSmall $Theme.NavIdle (New-UiRect 82 54 130 20) $TextLeft
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
$bottomY = 306
foreach ($page in $script:NavPages) {
    if ($page.Group -eq 'bottom' -and $navY -lt $bottomY) { $navY = $bottomY }
    $script:navText[$page.Key] = $page.Text
    $item = New-Object System.Windows.Forms.Panel
    $item.Location = (New-UiPoint 0 $navY)
    $item.Size = (New-UiSize 220 48)
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
            $inner = New-Object System.Drawing.Rectangle((S 14), (S 4), ($sender.Width - (S 28)), ($sender.Height - (S 8)))
            $shape = Get-RoundedPath $inner 10
            $fill = New-Object System.Drawing.SolidBrush ($Theme.SidebarHi)
            $e.Graphics.FillPath($fill, $shape)
            $fill.Dispose(); $shape.Dispose()
        }
        $color = if ($isActive) { $Theme.Ink } else { $Theme.NavIdle }
        $font = if ($isActive) { $FontStrong } else { $FontBase }
        Write-Text $e.Graphics $script:navText[$key] $font $color (New-Object System.Drawing.Rectangle((S 32), 0, (S 174), $sender.Height)) $TextLeft
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
$navDivider.Location = New-UiPoint 28 ($bottomY - 18)
$navDivider.Size = (New-UiSize 164 1)
$navDivider.BackColor = $Theme.Border
$sidebar.Controls.Add($navDivider)

$script:pnlUpdate = New-Object System.Windows.Forms.Panel
$script:pnlUpdate.Location = (New-UiPoint 18 626)
$script:pnlUpdate.Size = (New-UiSize 184 46)
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
$lblHint.Location = (New-UiPoint 26 684)
$lblHint.Size = (New-UiSize 176 40)
$lblHint.BackColor = $Theme.Sidebar
$lblHint.ForeColor = $Theme.Muted
$lblHint.Font = $FontSmall
$sidebar.Controls.Add($lblHint)


# 사이드바와 본문을 나누는 얇은 선입니다. 밝은 바탕끼리는 이 선 하나면 충분합니다.
$sideEdge = New-Object System.Windows.Forms.Panel
$sideEdge.Location = (New-UiPoint 219 0)
$sideEdge.Size = (New-UiSize 1 740)
$sideEdge.BackColor = $Theme.Border
$script:form.Controls.Add($sideEdge)
$sideEdge.BringToFront()

# ----- 헤더 -----
$header = New-Object System.Windows.Forms.Panel
$header.Location = (New-UiPoint 220 0)
$header.Size = New-Object System.Drawing.Size(($script:UiFormWidth - (S 220)), (S 96))
$header.Anchor = 'Top,Left,Right'
$header.BackColor = $Theme.Bg
$script:form.Controls.Add($header)

$script:lblPageTitle = New-Object System.Windows.Forms.Label
$script:lblPageTitle.Text = '발송 준비'
$script:lblPageTitle.Font = $FontPage
$script:lblPageTitle.ForeColor = $Theme.Ink
$script:lblPageTitle.BackColor = $Theme.Bg
$script:lblPageTitle.Location = (New-UiPoint 28 12)
$script:lblPageTitle.Size = (New-UiSize 440 32)
$header.Controls.Add($script:lblPageTitle)

$script:pillStatus = New-Object System.Windows.Forms.Panel
$script:pillStatus.Location = (New-UiPoint 28 50)
$script:pillStatus.Size = (New-UiSize 184 32)
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
    $e.Graphics.FillEllipse($dot, (S 17), ([int]($sender.Height / 2) - (S 4)), (S 9), (S 9))
    $dot.Dispose()
    Write-Text $e.Graphics $script:statusText $FontBase $ink (New-Object System.Drawing.Rectangle((S 34), 0, ($sender.Width - (S 46)), $sender.Height)) $TextLeft
})
$header.Controls.Add($script:pillStatus)

# 지금 어떤 방식으로, 언제 보내는지 상태 알약 옆에 한 줄로 보여 줍니다.
$script:lblHeaderPlan = New-Object System.Windows.Forms.Label
$script:lblHeaderPlan.Font = $FontBase
$script:lblHeaderPlan.ForeColor = $Theme.Sub
$script:lblHeaderPlan.BackColor = $Theme.Bg
$script:lblHeaderPlan.Location = (New-UiPoint 222 56)
$script:lblHeaderPlan.Size = (New-UiSize 264 22)
$script:lblHeaderPlan.Cursor = [System.Windows.Forms.Cursors]::Hand
$header.Controls.Add($script:lblHeaderPlan)
# 어느 화면에 있든 바로 누를 수 있게 위쪽에 둡니다.
$btnHeaderEdit  = New-AppButton $header '내용 수정' 498 26 104 46
$script:btnHeaderStart = New-AppButton $header '발송 시작' 610 26 132 46 'primary'
# 예약 대기 중이거나 발송 중일 때 [발송 시작] 자리에 나타납니다.
$script:btnHeaderStop = New-AppButton $header '중지' 610 26 132 46 'danger'
$script:btnHeaderStop.Visible = $false

$btnHelp = New-AppButton $header '?' 750 26 36 46 'default'
$btnHelp.Font = $FontStrong
$tipHelp = New-Object System.Windows.Forms.ToolTip
$tipHelp.SetToolTip($btnHelp, '사용 가이드 다시 보기')
$tipHelp.SetToolTip($script:btnHeaderStart, '지금 발송을 시작합니다')
$tipHelp.SetToolTip($btnHeaderEdit, '보낼 문구와 첨부를 고칩니다')

# ----- 페이지 컨테이너 -----
$pageHost = New-Object System.Windows.Forms.Panel
$pageHost.Location = (New-UiPoint 220 96)
$pageHost.Size = New-Object System.Drawing.Size(($script:UiFormWidth - (S 220)), ($script:UiFormHeight - (S 96)))
# 창을 늘리면 같이 늘어나고, 창이 작으면 스크롤로 볼 수 있습니다.
$pageHost.Anchor = 'Top,Left,Bottom,Right'
$pageHost.AutoScroll = $true
$pageHost.BackColor = $Theme.Bg
$script:form.Controls.Add($pageHost)

$script:pages = @{}
function New-Page([string]$Key) {
    $panel = New-Object System.Windows.Forms.Panel
    $panel.Location = (New-UiPoint 0 0)
    $panel.Size = (New-UiSize 840 644)
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

$cardMessage = New-Card $pageCompose 28 12 784 212 '발송 문구' '카카오톡에 붙여넣기로 전송됩니다. 줄바꿈도 그대로 유지됩니다.'
$script:txtMessage = New-AppTextBox $cardMessage 24 72 736 110 $true
$script:txtMessage.Text = [string]$script:config.Message
$script:lblMessageCount = New-CardLabel $cardMessage '' 24 186 736 18 $FontSmall $Theme.Muted

# 자주 보내는 문구를 이름을 붙여 담아 둡니다. 다시 칠 필요가 없습니다.
$cardTemplates = New-Card $pageCompose 28 232 784 112 '저장 메시지'
$script:lblTemplateState = New-CardLabel $cardTemplates '' 24 46 736 16 $FontSmall $Theme.Muted
$script:cmbTemplate = New-Object System.Windows.Forms.ComboBox
$script:cmbTemplate.DropDownStyle = 'DropDownList'
$script:cmbTemplate.Font = $FontBase
$script:cmbTemplate.Location = (New-UiPoint 24 68)
$script:cmbTemplate.Size = (New-UiSize 300 32)
$cardTemplates.Controls.Add($script:cmbTemplate)
$btnTplLoad   = New-AppButton $cardTemplates '불러오기' 334 68 100 32 'strong'
$btnTplSave   = New-AppButton $cardTemplates '새로 저장' 442 68 100 32
$btnTplUpdate = New-AppButton $cardTemplates '덮어쓰기' 550 68 96 32
$btnTplDelete = New-AppButton $cardTemplates '삭제' 654 68 106 32 'danger'

$cardFiles = New-Card $pageCompose 28 352 784 258 '첨부 사진 · 파일' '첨부를 먼저 보내고 그다음 문구를 보냅니다. [첨부 시험]은 붙는지만 확인하고 보내지 않습니다.'
$frameFiles = New-FieldFrame $cardFiles 24 72 576 150
$script:lstFiles = New-Object System.Windows.Forms.ListBox
$script:lstFiles.BorderStyle = 'None'
$script:lstFiles.Font = $FontBase
$script:lstFiles.Location = (New-UiPoint 12 12)
$script:lstFiles.Size = (New-UiSize 552 126)
$script:lstFiles.DisplayMember = 'Name'
$script:lstFiles.ItemHeight = 24
$frameFiles.Controls.Add($script:lstFiles)
foreach ($file in @($script:config.Attachments)) { [void]$script:lstFiles.Items.Add((New-AttachmentItem ([string]$file))) }

$btnAddFile    = New-AppButton $cardFiles '파일 추가' 616 72 144 36 'strong'
$btnFileUp     = New-AppButton $cardFiles '위로' 616 114 70 32
$btnFileDown   = New-AppButton $cardFiles '아래로' 690 114 70 32
$btnRemoveFile = New-AppButton $cardFiles '선택 제거' 616 152 144 32 'danger'
$btnCheckAttach = New-AppButton $cardFiles '첨부 시험' 616 190 144 32

# 사진을 묶어서 한 번에 보냅니다.
# 한 장씩 보내면 미리보기 창이 뜨고 닫히기를 되풀이해서 중간에 잘 막힙니다.
$script:chkGroupPhotos = New-Object System.Windows.Forms.CheckBox
$script:chkGroupPhotos.Text = '사진은 묶어서 한 번에 보내기'
$script:chkGroupPhotos.Checked = [bool]$script:config.GroupPhotos
$script:chkGroupPhotos.Location = (New-UiPoint 24 228)
$script:chkGroupPhotos.Size = (New-UiSize 236 26)
$script:chkGroupPhotos.BackColor = $Theme.Card
$script:chkGroupPhotos.Font = $FontBase
$cardFiles.Controls.Add($script:chkGroupPhotos)
[void](New-CardLabel $cardFiles '한 번에' 268 231 52 20 $FontSmall $Theme.Muted)
$script:numPhotoBatch = New-Object System.Windows.Forms.NumericUpDown
$script:numPhotoBatch.Minimum = 1
$script:numPhotoBatch.Maximum = 30
$script:numPhotoBatch.Value = [Math]::Max(1, [Math]::Min(30, [int]$script:config.PhotoBatchSize))
$script:numPhotoBatch.Location = (New-UiPoint 322 227)
$script:numPhotoBatch.Size = (New-UiSize 62 28)
$script:numPhotoBatch.Font = $FontBase
$script:numPhotoBatch.BorderStyle = 'FixedSingle'
$cardFiles.Controls.Add($script:numPhotoBatch)
[void](New-CardLabel $cardFiles '장씩 · 문서와 그 밖의 파일은 하나씩 보냅니다' 392 231 368 20 $FontSmall $Theme.Muted)

$lblComposeHint = New-CardLabel $pageCompose '내용은 자동 저장됩니다. 실제로 보내기 전에 [설정] 화면의 테스트 발송으로 결과를 먼저 확인해 보세요.' 28 618 784 22 $FontSmall $Theme.Muted
$lblComposeHint.BackColor = $Theme.Bg

# ===========================================================================
# 페이지 2 — 받을 채팅방
# ===========================================================================
$pageRooms = New-Page 'rooms'
$cardRooms = New-Card $pageRooms 28 12 784 620 '발송 대상 채팅방' '카카오톡에서 보낼 채팅방을 창으로 열어 두시고 [열어 둔 채팅방 읽기]를 누르세요.'

$btnReadOpen   = New-AppButton $cardRooms '열어 둔 채팅방 읽기' 24 78 176 36 'strong'
$btnScanRooms  = New-AppButton $cardRooms '전체 목록 읽기' 208 78 124 36
$btnVerifyRoom = New-AppButton $cardRooms '이름 확인·보정' 340 78 124 36
$btnAddRoom    = New-AppButton $cardRooms '직접 추가' 472 78 80 36
$btnEditRoom   = New-AppButton $cardRooms '이름 수정' 560 78 80 36
$btnClearRooms = New-AppButton $cardRooms '목록 비우기' 648 78 112 36 'ghost'

# 방이 많을 때를 위한 검색칸과 보기 필터
[void](New-CardLabel $cardRooms '검색' 24 130 34 22 $FontSmall $Theme.Muted)
$script:txtRoomSearch = New-AppTextBox $cardRooms 60 122 200 34
$btnSearchClear = New-AppButton $cardRooms '지우기' 268 122 66 34 'ghost'

[void](New-CardLabel $cardRooms '보기' 346 130 34 22 $FontSmall $Theme.Muted)
$btnFilterAll    = New-AppButton $cardRooms '전체' 384 122 56 34
$btnFilterPerson = New-AppButton $cardRooms '1:1' 444 122 56 34
$btnFilterChat   = New-AppButton $cardRooms '단체' 504 122 56 34
$btnFilterOpen   = New-AppButton $cardRooms '오픈채팅' 564 122 78 34

[void](New-CardLabel $cardRooms '탐색' 650 130 34 22 $FontSmall $Theme.Muted)
$script:numScanPages = New-Object System.Windows.Forms.NumericUpDown
$script:numScanPages.Minimum = 1
$script:numScanPages.Maximum = 60
$script:numScanPages.Value = [Math]::Max(1, [Math]::Min(60, [int]$script:config.ScanPages))
$script:numScanPages.Location = (New-UiPoint 688 123)
$script:numScanPages.Size = (New-UiSize 72 32)
$script:numScanPages.Font = $FontBase
$script:numScanPages.BorderStyle = 'FixedSingle'
$cardRooms.Controls.Add($script:numScanPages)

$script:lblRoomCount = New-CardLabel $cardRooms '선택 0 / 전체 0' 24 166 500 22 $FontStrong $Theme.Ink
$script:lblSearchState = New-CardLabel $cardRooms '' 530 166 230 22 $FontSmall $Theme.Info

$frameRooms = New-FieldFrame $cardRooms 24 194 736 300
$script:lstRooms = New-Object System.Windows.Forms.ListView
$script:lstRooms.View = 'Details'
$script:lstRooms.CheckBoxes = $true
$script:lstRooms.FullRowSelect = $true
$script:lstRooms.HideSelection = $false
$script:lstRooms.BorderStyle = 'None'
$script:lstRooms.Font = $FontBase
$script:lstRooms.Location = (New-UiPoint 12 12)
$script:lstRooms.Size = (New-UiSize 712 276)
[void]$script:lstRooms.Columns.Add('채팅방 이름', 470)
[void]$script:lstRooms.Columns.Add('종류', 130)
[void]$script:lstRooms.Columns.Add('이름 확인', 108)
$frameRooms.Controls.Add($script:lstRooms)

$btnCheckAll   = New-AppButton $cardRooms '전체 선택' 24 506 92 34
$btnCheckNone  = New-AppButton $cardRooms '전체 해제' 124 506 92 34
$btnPickNormal = New-AppButton $cardRooms '일반채팅만' 224 506 104 34
$btnPickOpen   = New-AppButton $cardRooms '오픈채팅만' 336 506 104 34
$btnDeleteRoom = New-AppButton $cardRooms '체크 삭제' 448 506 96 34 'danger'

# ----- 그룹 -----
[void](New-CardLabel $cardRooms '그룹' 24 556 40 24 $FontSmall $Theme.Muted)
$script:cmbGroup = New-Object System.Windows.Forms.ComboBox
$script:cmbGroup.DropDownStyle = 'DropDownList'
$script:cmbGroup.Font = $FontBase
$script:cmbGroup.Location = (New-UiPoint 66 552)
$script:cmbGroup.Size = (New-UiSize 160 30)
$cardRooms.Controls.Add($script:cmbGroup)
$btnGroupCheck  = New-AppButton $cardRooms '이 그룹 체크' 234 550 106 32
$btnGroupNew    = New-AppButton $cardRooms '새 그룹 만들기' 348 550 118 32
$btnGroupAdd    = New-AppButton $cardRooms '체크한 방 넣기' 474 550 118 32
$btnGroupDelete = New-AppButton $cardRooms '그룹 삭제' 600 550 96 32 'danger'

$lblRoomsHint = New-CardLabel $cardRooms '방을 연 뒤 창 제목이 정확히 같을 때만 보냅니다. 비슷한 이름이면 보내지 않고 닫습니다.' 24 590 736 22 $FontSmall $Theme.Muted
$lblRoomsHint.BackColor = $Theme.Card

# ===========================================================================
# 페이지 3 — 보내기
# ===========================================================================
$pageRun = New-Page 'run'

$cardSend = New-Card $pageRun 28 12 784 292 '보내기' '지금 바로 보내거나, 시각을 정해 예약할 수 있습니다.'
$script:rdoLive = New-Object System.Windows.Forms.RadioButton
$script:rdoLive.Text = '실제 발송 — 고른 모든 방에 문구와 첨부를 실제로 보냅니다.'
$script:rdoLive.Location = (New-UiPoint 24 76)
$script:rdoLive.Size = (New-UiSize 730 26)
$script:rdoLive.BackColor = $Theme.Card
$script:rdoLive.Font = $FontBase
$cardSend.Controls.Add($script:rdoLive)

$script:rdoDry = New-Object System.Windows.Forms.RadioButton
$script:rdoDry.Text = '확인 전용 — 방만 열어 보고 아무것도 보내지 않습니다. (연습용)'
$script:rdoDry.Location = (New-UiPoint 24 106)
$script:rdoDry.Size = (New-UiSize 730 26)
$script:rdoDry.BackColor = $Theme.Card
$script:rdoDry.Font = $FontBase
$cardSend.Controls.Add($script:rdoDry)
if ([bool]$script:config.DryRun) { $script:rdoDry.Checked = $true } else { $script:rdoLive.Checked = $true }

[void](New-CardLabel $cardSend '예약 시각' 24 144 100 22 $FontSmall $Theme.Muted)
$script:dtSchedule = New-Object System.Windows.Forms.DateTimePicker
$script:dtSchedule.Format = 'Custom'
$script:dtSchedule.CustomFormat = 'yyyy-MM-dd  HH:mm:ss'
$script:dtSchedule.ShowUpDown = $true
$script:dtSchedule.Location = (New-UiPoint 24 166)
$script:dtSchedule.Size = (New-UiSize 222 30)
$script:dtSchedule.Font = $FontBase
try { $script:dtSchedule.Value = [datetime]::ParseExact([string]$script:config.ScheduledAt, 'yyyy-MM-dd HH:mm:ss', $null) }
catch { $script:dtSchedule.Value = (Get-Date).Date.AddDays(1) }
if ($script:dtSchedule.Value -lt $script:dtSchedule.MinDate -or $script:dtSchedule.Value -le (Get-Date)) { $script:dtSchedule.Value = (Get-Date).Date.AddDays(1) }
$cardSend.Controls.Add($script:dtSchedule)
$btnPickSchedule = New-AppButton $cardSend '달력에서 고르기' 254 166 140 30

# 간격과 반복은 [설정] 화면 한 곳에서만 정합니다. 여기서는 지금 상태만 보여 줍니다.
$script:lblRunPace = New-CardLabel $cardSend '' 410 140 350 56 $FontSmall $Theme.Sub

$btnRunNow    = New-AppButton $cardSend '지금 실행' 24 206 160 42 'primary'
$btnArm       = New-AppButton $cardSend '예약 시작' 192 206 150 42
$btnCancelArm = New-AppButton $cardSend '예약 취소' 350 206 150 42
$btnSave      = New-AppButton $cardSend '설정 저장' 508 206 120 42 'ghost'
$btnGoPaceSettings = New-AppButton $cardSend '설정에서 바꾸기' 636 206 124 42
$btnCancelArm.Enabled = $false
$script:lblCountdown = New-CardLabel $cardSend '예약이 설정되지 않았습니다.' 24 256 380 24 $FontStrong $Theme.Muted

# 중간에 꺼졌거나 실패한 방이 있을 때 쓰는 단추입니다.
# 이미 보낸 방과 이미 나간 사진은 다시 보내지 않습니다.
$script:btnResumeRun = New-AppButton $cardSend '이어서 발송' 412 252 174 32
$script:btnRetryFailed = New-AppButton $cardSend '실패한 방만 다시 보내기' 594 252 166 32
$script:btnResumeRun.Enabled = $false
$script:btnRetryFailed.Enabled = $false
# ----- 발송 진행 상황 -----
# 보내는 동안 여기만 보고 있으면 됩니다. 스크롤할 필요가 없어야 합니다.
$cardProgress = New-Card $pageRun 28 316 784 322 '발송 진행 상황' '방마다 어디까지 갔는지 보여 줍니다. 실패한 방은 까닭도 적습니다.'
$script:lblProgressCount = New-CardLabel $cardProgress '전체 0    발송 완료 0    진행중 0    대기 0    실패 0' 24 74 736 24 $FontStrong $Theme.Ink
$script:barProgress = New-Object System.Windows.Forms.ProgressBar
$script:barProgress.Location = (New-UiPoint 24 104)
$script:barProgress.Size = (New-UiSize 736 12)
$script:barProgress.Minimum = 0
$script:barProgress.Maximum = 1
$script:barProgress.Value = 0
$cardProgress.Controls.Add($script:barProgress)

$script:lstProgress = New-Object System.Windows.Forms.ListView
$script:lstProgress.View = 'Details'
$script:lstProgress.FullRowSelect = $true
$script:lstProgress.HideSelection = $false
$script:lstProgress.BorderStyle = 'FixedSingle'
$script:lstProgress.Font = $FontBase
$script:lstProgress.Location = (New-UiPoint 24 128)
$script:lstProgress.Size = (New-UiSize 736 176)
[void]$script:lstProgress.Columns.Add('채팅방', (S 300))
[void]$script:lstProgress.Columns.Add('종류', (S 110))
[void]$script:lstProgress.Columns.Add('상태', (S 110))
[void]$script:lstProgress.Columns.Add('비고', (S 190))
$cardProgress.Controls.Add($script:lstProgress)



# ===========================================================================
$pageSettings = New-Page 'settings'

$cardStatus = New-Card $pageSettings 28 12 784 240 '카카오톡 연결 상태' '좌표를 맞출 필요는 없습니다. 카카오톡 화면 구조를 그때그때 읽어 자동으로 찾습니다.'
$script:lblKakaoState = New-CardLabel $cardStatus '확인 중입니다...' 24 78 736 104 $FontBase $Theme.Sub
$btnCheckKakao = New-AppButton $cardStatus '지금 확인' 24 190 150 40 'strong'
$btnOpenKakao = New-AppButton $cardStatus '카카오톡 창 앞으로 가져오기' 184 190 220 40
# 프로그램이 돌아가는 데 필요한 것들을 확인하고, 없으면 설치까지 해 줍니다.
$btnPrereq = New-AppButton $cardStatus '필수 요소 확인' 414 190 150 40

$cardUpdate = New-Card $pageSettings 28 264 784 236 '업데이트' '최신 배포를 확인합니다.'
$script:lblUpdateState = New-CardLabel $cardUpdate "현재 버전 v$($script:AppVersion)" 24 76 736 46 $FontBase $Theme.Ink
$btnCheckUpdate  = New-AppButton $cardUpdate '업데이트 확인' 24 130 160 40
$script:btnDoUpdate = New-AppButton $cardUpdate '지금 업데이트' 194 130 160 40 'strong'
$script:btnDoUpdate.Enabled = $false
$btnClearLogFiles = New-AppButton $cardUpdate '로그 파일 모두 지우기' 364 130 200 40 'danger'
$script:chkAutoUpdate = New-Object System.Windows.Forms.CheckBox
$script:chkAutoUpdate.Text = '시작할 때 자동 확인'
$script:chkAutoUpdate.Checked = [bool]$script:config.AutoCheckUpdate
$script:chkAutoUpdate.Location = (New-UiPoint 24 182)
$script:chkAutoUpdate.Size = (New-UiSize 240 28)
$script:chkAutoUpdate.BackColor = $Theme.Card
$script:chkAutoUpdate.Font = $FontBase
$cardUpdate.Controls.Add($script:chkAutoUpdate)

$script:chkAutoDownload = New-Object System.Windows.Forms.CheckBox
$script:chkAutoDownload.Text = '새 버전이 있으면 물어보고 바로 받기'
$script:chkAutoDownload.Checked = [bool]$script:config.AutoDownloadUpdate
$script:chkAutoDownload.Location = (New-UiPoint 280 182)
$script:chkAutoDownload.Size = (New-UiSize 320 28)
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
$script:numInterval.Location = (New-UiPoint 144 78)
$script:numInterval.Size = (New-UiSize 80 30)
$script:numInterval.Font = $FontBase
$script:numInterval.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numInterval)
[void](New-CardLabel $cardPace '초 — 0이면 쉬지 않고 바로 다음 방으로 갑니다' 234 82 520 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '방 열림 대기' 24 124 110 24 $FontSmall $Theme.Muted)
$script:numOpenTimeout = New-Object System.Windows.Forms.NumericUpDown
$script:numOpenTimeout.Minimum = 3
$script:numOpenTimeout.Maximum = 60
$script:numOpenTimeout.Value = [Math]::Max(3, [Math]::Min(60, [int]([Math]::Round([int]$script:config.OpenTimeoutMs / 1000))))
$script:numOpenTimeout.Location = (New-UiPoint 144 120)
$script:numOpenTimeout.Size = (New-UiSize 80 30)
$script:numOpenTimeout.Font = $FontBase
$script:numOpenTimeout.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numOpenTimeout)
[void](New-CardLabel $cardPace '초까지 방이 열리기를 기다립니다 (대화가 많은 방은 늘리세요)' 234 124 520 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '대화 로딩 대기' 24 166 110 24 $FontSmall $Theme.Muted)
$script:numSettle = New-Object System.Windows.Forms.NumericUpDown
$script:numSettle.Minimum = 0
$script:numSettle.Maximum = 30
$script:numSettle.Value = [Math]::Max(0, [Math]::Min(30, [int]([Math]::Round([int]$script:config.SettleMs / 1000))))
$script:numSettle.Location = (New-UiPoint 144 162)
$script:numSettle.Size = (New-UiSize 80 30)
$script:numSettle.Font = $FontBase
$script:numSettle.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numSettle)
[void](New-CardLabel $cardPace '초 동안 화면이 멈추기를 기다린 뒤 보냅니다 (오픈채팅은 늘리세요)' 234 166 520 24 $FontSmall $Theme.Muted)

$script:chkPreload = New-Object System.Windows.Forms.CheckBox
$script:chkPreload.Text = '보내기 전에 대상 방을 한 번씩 열어 두기'
$script:chkPreload.Checked = [bool]$script:config.PreloadRooms
$script:chkPreload.Location = (New-UiPoint 24 208)
$script:chkPreload.Size = (New-UiSize 330 28)
$script:chkPreload.BackColor = $Theme.Card
$script:chkPreload.Font = $FontBase
$cardPace.Controls.Add($script:chkPreload)

# 한 방이 실패했을 때 몇 번까지 다시 해 볼지 정합니다.
# 0 이면 한 번만 하고 실패로 둡니다. 3 이면 세 번 더 해 봅니다.
[void](New-CardLabel $cardPace '실패 시 재시도' 364 212 96 24 $FontSmall $Theme.Muted)
$script:numRetry = New-Object System.Windows.Forms.NumericUpDown
$script:numRetry.Minimum = 0
$script:numRetry.Maximum = 5
$script:numRetry.Value = [Math]::Max(0, [Math]::Min(5, [int]$script:config.RetryCount))
$script:numRetry.Location = (New-UiPoint 466 208)
$script:numRetry.Size = (New-UiSize 66 30)
$script:numRetry.Font = $FontBase
$script:numRetry.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numRetry)
[void](New-CardLabel $cardPace '회' 538 212 26 24 $FontSmall $Theme.Muted)
$btnPreloadNow = New-AppButton $cardPace '지금 미리 열기' 576 204 184 36
$script:chkRepeat = New-Object System.Windows.Forms.CheckBox
$script:chkRepeat.Text = '다 보낸 뒤 일정 시간마다 다시 보내기'
$script:chkRepeat.Checked = [bool]$script:config.RepeatEnabled
$script:chkRepeat.Location = (New-UiPoint 24 250)
$script:chkRepeat.Size = (New-UiSize 330 28)
$script:chkRepeat.BackColor = $Theme.Card
$script:chkRepeat.Font = $FontBase
$cardPace.Controls.Add($script:chkRepeat)

$script:numRepeatMinutes = New-Object System.Windows.Forms.NumericUpDown
$script:numRepeatMinutes.Minimum = 1
$script:numRepeatMinutes.Maximum = 1440
$script:numRepeatMinutes.Value = [Math]::Max(1, [Math]::Min(1440, [int]$script:config.RepeatMinutes))
$script:numRepeatMinutes.Location = (New-UiPoint 364 248)
$script:numRepeatMinutes.Size = (New-UiSize 80 30)
$script:numRepeatMinutes.Font = $FontBase
$script:numRepeatMinutes.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numRepeatMinutes)
[void](New-CardLabel $cardPace '분마다 ·  최대' 452 252 96 24 $FontSmall $Theme.Muted)

$script:numRepeatCount = New-Object System.Windows.Forms.NumericUpDown
$script:numRepeatCount.Minimum = 0
$script:numRepeatCount.Maximum = 999
$script:numRepeatCount.Value = [Math]::Max(0, [Math]::Min(999, [int]$script:config.RepeatCount))
$script:numRepeatCount.Location = (New-UiPoint 552 248)
$script:numRepeatCount.Size = (New-UiSize 74 30)
$script:numRepeatCount.Font = $FontBase
$script:numRepeatCount.BorderStyle = 'FixedSingle'
$cardPace.Controls.Add($script:numRepeatCount)
[void](New-CardLabel $cardPace '회 (0이면 멈출 때까지 계속)' 634 252 130 24 $FontSmall $Theme.Muted)

[void](New-CardLabel $cardPace '방 300개를 10분 안에 보내려면 간격을 0~1초로 두세요. 간격 8초면 300개에 약 48분 걸립니다.' 24 286 736 24 $FontSmall $Theme.Muted)

$cardLimit = New-Card $pageSettings 28 1036 784 306 '발송 제한 및 묶음 발송' '보내면 안 되는 시간과 날짜, 그리고 몇 개마다 쉴지 정할 수 있습니다.'
$script:chkQuiet = New-Object System.Windows.Forms.CheckBox
$script:chkQuiet.Text = '방해금지 시간대에는 보내지 않기'
$script:chkQuiet.Checked = [bool]$script:config.QuietEnabled
$script:chkQuiet.Location = (New-UiPoint 24 78)
$script:chkQuiet.Size = (New-UiSize 280 26)
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
$script:chkSkipWeekend.Location = (New-UiPoint 24 116)
$script:chkSkipWeekend.Size = (New-UiSize 280 26)
$script:chkSkipWeekend.BackColor = $Theme.Card
$script:chkSkipWeekend.Font = $FontBase
$cardLimit.Controls.Add($script:chkSkipWeekend)

[void](New-CardLabel $cardLimit '공휴일에는' 24 158 90 24 $FontSmall $Theme.Muted)
$script:cmbHoliday = New-Object System.Windows.Forms.ComboBox
$script:cmbHoliday.DropDownStyle = 'DropDownList'
$script:cmbHoliday.Font = $FontBase
$script:cmbHoliday.Location = (New-UiPoint 116 154)
$script:cmbHoliday.Size = (New-UiSize 190 30)
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
$script:numHolidayMultiplier.Location = (New-UiPoint 452 154)
$script:numHolidayMultiplier.Size = (New-UiSize 78 30)
$script:numHolidayMultiplier.Font = $FontBase
$script:numHolidayMultiplier.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numHolidayMultiplier)
$btnShowHolidays = New-AppButton $cardLimit '공휴일 설정' 548 152 150 34

[void](New-CardLabel $cardLimit '묶음 발송' 24 200 80 24 $FontSmall $Theme.Muted)
$script:numBatchSize = New-Object System.Windows.Forms.NumericUpDown
$script:numBatchSize.Minimum = 0
$script:numBatchSize.Maximum = 500
$script:numBatchSize.Value = [Math]::Max(0, [Math]::Min(500, [int]$script:config.BatchSize))
$script:numBatchSize.Location = (New-UiPoint 108 196)
$script:numBatchSize.Size = (New-UiSize 84 30)
$script:numBatchSize.Font = $FontBase
$script:numBatchSize.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numBatchSize)
[void](New-CardLabel $cardLimit '개 보낸 뒤' 198 200 84 24 $FontSmall $Theme.Muted)
$script:numBatchRest = New-Object System.Windows.Forms.NumericUpDown
$script:numBatchRest.Minimum = 1
$script:numBatchRest.Maximum = 240
$script:numBatchRest.Value = [Math]::Max(1, [Math]::Min(240, [int]$script:config.BatchRestMinutes))
$script:numBatchRest.Location = (New-UiPoint 286 196)
$script:numBatchRest.Size = (New-UiSize 84 30)
$script:numBatchRest.Font = $FontBase
$script:numBatchRest.BorderStyle = 'FixedSingle'
$cardLimit.Controls.Add($script:numBatchRest)
[void](New-CardLabel $cardLimit '분 쉬기  (0개면 쉬지 않고 계속)' 376 200 384 24 $FontSmall $Theme.Muted)

$script:lblLimitState = New-CardLabel $cardLimit '' 24 236 736 56 $FontSmall $Theme.Sub

# 페이지 5 — 실행 기록
# ===========================================================================

# ----- 테스트 발송 -----
# 실제로 보내기 전에 한 방에만 똑같이 보내 결과를 확인합니다.
$cardTest = New-Card $pageSettings 28 1378 784 214 '테스트 발송' '실제 발송 전에 지정한 한 방에만 똑같이 보내 결과를 확인합니다.'
[void](New-CardLabel $cardTest '테스트로 보낼 채팅방 (직접 입력하거나 목록에서 고르세요)' 24 82 460 22 $FontSmall $Theme.Muted)
$script:txtTestRoom = New-AppTextBox $cardTest 24 108 414 38
$script:txtTestRoom.Text = [string]$script:config.TestRoom
$btnPickTestRoom = New-AppButton $cardTest '목록에서 고르기' 454 108 150 38
$btnTestMyChat   = New-AppButton $cardTest '나와의 채팅' 614 108 146 38 'ghost'
$btnTestSend = New-AppButton $cardTest '테스트 발송' 24 156 200 40 'primary'
$btnTestDry  = New-AppButton $cardTest '방 확인만 (전송 안 함)' 236 156 200 40
[void](New-CardLabel $cardTest '기본값은 나와의 채팅이라 아무에게도 가지 않습니다.' 452 162 308 30 $FontSmall $Theme.Muted)
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
$script:txtLog.Location = (New-UiPoint 14 12)
$script:txtLog.Size = (New-UiSize 708 446)
$frameLog.Controls.Add($script:txtLog)
$btnOpenLogDir = New-AppButton $cardLog '로그 폴더 열기' 24 566 170 40
$btnClearLog   = New-AppButton $cardLog '화면 지우기' 204 566 140 40 'ghost'
$btnOpenSendLog = New-AppButton $cardLog '발송 기록 표 열기' 354 566 190 40 'strong'

# ===========================================================================
# 저장 메시지 고르기 상자
# ===========================================================================
function Update-TemplateCombo([string]$Select = '') {
    if ($null -eq $script:cmbTemplate) { return }
    $keep = if ($Select) { $Select } else { [string]$script:cmbTemplate.SelectedItem }
    $script:cmbTemplate.Items.Clear()
    foreach ($row in (Get-Templates)) { [void]$script:cmbTemplate.Items.Add($row.Name) }
    if ($script:cmbTemplate.Items.Count -eq 0) {
        $script:lblTemplateState.Text = '아직 저장한 문구가 없습니다. 위에 문구를 쓰고 [새로 저장]을 눌러 보세요.'
        return
    }
    $index = $script:cmbTemplate.Items.IndexOf($keep)
    $script:cmbTemplate.SelectedIndex = $(if ($index -ge 0) { $index } else { 0 })
    $script:lblTemplateState.Text = "저장된 문구 $($script:cmbTemplate.Items.Count)개"
}

# ===========================================================================
# 채팅방 목록 상태 관리
# ===========================================================================
$script:roomEntries = New-Object System.Collections.Generic.List[object]
$script:roomFilter = '전체'
$script:suppressRoomEvents = $false

function Add-RoomEntry([string]$Name, [string]$Type, [bool]$Checked) {
    $clean = ConvertTo-ExactKey $Name
    if (-not $clean) { return $false }
    foreach ($entry in $script:roomEntries) {
        if ($entry.Name -ceq $clean) {
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
    $kind = Get-RoomKind $clean
    $verified = $false
    $found = Find-RosterEntry $clean
    if ($null -ne $found) { $kind = $found.Kind; $verified = $found.Verified }
    $script:roomEntries.Add([pscustomobject]@{
        Name = $clean; Type = $Type; Checked = $Checked; Kind = $kind; Verified = $verified
    })
    return $true
}

# 저장된 채팅방 목록을 화면 목록에 그대로 옮깁니다.
# 체크해 둔 것은 그대로 두고, 목록에서 사라진 방은 화면에서도 뺍니다.
function Sync-RoomEntriesFromRoster {
    $checked = @{}
    foreach ($entry in $script:roomEntries) { if ($entry.Checked) { $checked[$entry.Name] = $true } }
    $roster = @(Get-Roster)
    $byName = @{}
    foreach ($row in $roster) { $byName[$row.Name] = $row }

    $fresh = New-Object System.Collections.Generic.List[object]
    foreach ($row in $roster) {
        $type = if ($row.Kind -eq 'open') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
        $fresh.Add([pscustomobject]@{
            Name = $row.Name
            Type = $type
            Checked = [bool]$checked[$row.Name]
            Kind = $row.Kind
            Verified = [bool]$row.Verified
        })
    }
    # 직접 넣은 방은 목록에 없어도 남겨 둡니다. 사용자가 일부러 넣은 것이기 때문입니다.
    foreach ($entry in $script:roomEntries) {
        if ($byName.ContainsKey($entry.Name)) { continue }
        $fresh.Add($entry)
    }
    $script:roomEntries = $fresh
}

function Update-RoomCountLabel {
    $checked = @($script:roomEntries | Where-Object { $_.Checked }).Count
    $total = $script:roomEntries.Count
    $shown = $script:lstRooms.Items.Count
    $text = "선택 $($checked) / 전체 $($total)"
    if ($shown -ne $total) { $text += "   ·   보이는 것 $($shown)" }
    $stamp = [string]$script:config.RosterScannedAt
    if ($stamp) { $text += "   ·   읽은 때 $stamp" }
    $script:lblRoomCount.Text = $text
}

# 검색어를 견주기 좋게 다듬습니다. 띄어쓰기와 기호는 무시합니다.
function Test-RoomMatchesSearch([string]$Name, [string]$Key) {
    if (-not $Key) { return $true }
    return ((ConvertTo-CompareKey $Name).Contains($Key))
}

function Update-FilterButtons {
    foreach ($pair in @(@($btnFilterAll, '전체'), @($btnFilterPerson, 'direct'), @($btnFilterChat, 'group'), @($btnFilterOpen, 'open'))) {
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
        $kind = [string]$entry.Kind
        if (-not $kind) { $kind = 'unknown' }
        if ($script:roomFilter -eq 'open' -and $kind -ne 'open') { continue }
        if ($script:roomFilter -eq 'direct' -and $kind -ne 'direct') { continue }
        if ($script:roomFilter -eq 'group' -and $kind -ne 'group') { continue }
        if (-not (Test-RoomMatchesSearch $entry.Name $key)) { continue }
        $item = New-Object System.Windows.Forms.ListViewItem([string]$entry.Name)
        [void]$item.SubItems.Add((Get-RosterKindText $kind))
        [void]$item.SubItems.Add($(if ($entry.Verified) { '확인됨' } else { '화면 글자' }))
        $item.Checked = [bool]$entry.Checked
        if (-not $entry.Verified) { $item.ForeColor = $Theme.Muted }
        $items.Add($item)
    }
    if ($items.Count -gt 0) { $script:lstRooms.Items.AddRange($items.ToArray()) }
    $script:lstRooms.EndUpdate()
    $script:suppressRoomEvents = $false
    Update-FilterButtons
    Update-RoomCountLabel
    if ($null -ne $script:lblSearchState) {
        if ($key) {
            $script:lblSearchState.Text = "'$query' 검색 결과 $($items.Count)개"
            $script:lblSearchState.ForeColor = if ($items.Count -gt 0) { $Theme.Info } else { $Theme.Danger }
        } else {
            $script:lblSearchState.Text = ''
        }
    }
}

function Get-RoomEntry([string]$Name) {
    foreach ($entry in $script:roomEntries) { if ($entry.Name -ceq $Name) { return $entry } }
    return $null
}

# 종류로 한 번에 고릅니다. 고른 것 말고는 모두 풉니다.
function Select-RoomsByKind([string[]]$Kinds) {
    foreach ($entry in $script:roomEntries) {
        $kind = [string]$entry.Kind
        if (-not $kind) { $kind = 'unknown' }
        $entry.Checked = (@($Kinds) -contains $kind)
    }
    Update-RoomListView
    Sync-ConfigFromForm
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
    try { if ($null -ne $script:appIcon) { $dialog.Icon = $script:appIcon } } catch { }
    $dialog.Text = $Title
    $dialog.ClientSize = (New-UiSize 520 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Theme.Card
    $dialog.Font = $FontBase

    $lblFind = New-Object System.Windows.Forms.Label
    $lblFind.Text = '찾기'
    $lblFind.Location = (New-UiPoint 20 22)
    $lblFind.Size = (New-UiSize 40 24)
    $lblFind.BackColor = $Theme.Card
    $dialog.Controls.Add($lblFind)

    $txtFind = New-AppTextBox $dialog 62 16 438 34

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.MultiSelect = $false
    $list.Font = $FontBase
    $list.Location = (New-UiPoint 20 62)
    $list.Size = (New-UiSize 480 388)
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
        "예약 $($script:dtSchedule.Value.ToString('MM-dd HH:mm')) 대기"
    } else {
        "예약 없음"
    }
    # 머리말은 짧게 둡니다. 자세한 것은 아래 요약과 [설정] 에 있습니다.
    $repeat = if ([bool]$script:chkRepeat.Checked) {
        "반복 $([int]$script:numRepeatMinutes.Value)분"
    } else {
        "간격 $([int]$script:numInterval.Value)초"
    }
    # 확인 전용인지 실제 발송인지가 가장 중요합니다. 맨 앞에 둡니다.
    $dry = $false
    try { $dry = [bool]$script:rdoDry.Checked } catch { }
    $modeText = if ($dry) { '확인 전용' } else { '실제 발송' }
    $script:lblHeaderPlan.Text = "$modeText · $when · $repeat"
    $script:lblHeaderPlan.ForeColor = if ($dry) { $Theme.Danger } elseif ($script:armed) { $Theme.Info } else { $Theme.Muted }

    # [보내기] 화면의 요약도 같이 맞춥니다.
    # 설정은 [설정] 화면 한 곳에서만 바꾸고, 여기는 그 결과를 보여 주기만 합니다.
    # 확인 전용이면 단추 이름부터 다르게 해서 헷갈리지 않게 합니다.
    try {
        if ($null -ne $script:btnHeaderStart) {
            $label = if ($dry) { '확인 시작' } else { '발송 시작' }
            if ($script:btnHeaderStart.Tag.Label -ne $label) {
                $script:btnHeaderStart.Tag.Label = $label
                $script:btnHeaderStart.AccessibleName = $label
                $script:btnHeaderStart.Invalidate()
            }
        }
    } catch { }
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
    $script:config.RetryCount = [int]$script:numRetry.Value
    $script:config.GroupPhotos = [bool]$script:chkGroupPhotos.Checked
    $script:config.PhotoBatchSize = [int]$script:numPhotoBatch.Value
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
# 저장된 채팅방 목록(Roster)이 먼저입니다. 여기에 종류와 이름 확인 여부가 들어 있습니다.
$selectedSet = @{}
foreach ($room in @($script:config.Rooms)) { $selectedSet[(ConvertTo-ExactKey ([string]$room))] = $true }
foreach ($row in (Get-Roster)) {
    $rowType = if ($row.Kind -eq 'open') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
    [void](Add-RoomEntry $row.Name $rowType ($selectedSet.ContainsKey($row.Name)))
}
# 예전 버전에서 넘어온 방도 빠뜨리지 않고 넣습니다.
foreach ($room in @(@($script:config.KnownRooms) + @($script:config.Rooms) | ForEach-Object { ConvertTo-ExactKey ([string]$_) } | Where-Object { $_ } | Sort-Object -Unique)) {
    [void](Add-RoomEntry $room (Get-RoomType $room) ($selectedSet.ContainsKey($room)))
}
Update-RoomListView
Update-GroupCombo
Update-TemplateCombo
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
$script:chkGroupPhotos.Add_CheckedChanged({ Sync-ConfigFromForm })
$script:numPhotoBatch.Add_ValueChanged({ Request-AutoSave })
# 발송 방식을 바꾸면 머리말 표시도 곧바로 바꿉니다.
# 확인 전용인지 실제 발송인지가 가장 헷갈리는 부분이라 항상 보이게 합니다.
$script:rdoDry.Add_CheckedChanged({ try { Update-HeaderSummary } catch { }; Request-AutoSave })
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

# 공휴일마다 어떻게 할지 하나씩 정하는 화면입니다.
# 예전에는 공휴일 전체를 한꺼번에 처리해서 날짜별로 다르게 할 수 없었습니다.
function Show-HolidayManager {
    $year = (Get-Date).Year
    $dialog = New-Object System.Windows.Forms.Form
    try { if ($null -ne $script:appIcon) { $dialog.Icon = $script:appIcon } } catch { }
    $dialog.Text = "$($year)년 공휴일 설정"
    $dialog.ClientSize = (New-UiSize 640 520)
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false
    $dialog.BackColor = $Theme.Bg
    $dialog.Font = $FontBase

    [void](New-CardLabel $dialog '공휴일마다 어떻게 할지 정합니다. 정하지 않은 날은 그대로 보냅니다.' 24 18 592 24 $FontBase $Theme.Sub)
    [void](New-CardLabel $dialog '날짜를 옮기면 그날 이미 보냈는지 확인해 두 번 가지 않게 합니다.' 24 42 592 22 $FontSmall $Theme.Muted)

    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.HideSelection = $false
    $list.BorderStyle = 'FixedSingle'
    $list.Font = $FontBase
    $list.Location = (New-UiPoint 24 76)
    $list.Size = (New-UiSize 592 300)
    [void]$list.Columns.Add('날짜', (S 110))
    [void]$list.Columns.Add('공휴일', (S 160))
    [void]$list.Columns.Add('처리 방식', (S 150))
    [void]$list.Columns.Add('대체 발송일', (S 150))
    $dialog.Controls.Add($list)

    $script:holidayRows = @()
    function Refresh-HolidayList {
        $list.BeginUpdate()
        $list.Items.Clear()
        $script:holidayRows = @()
        $days = @((Get-KoreanHolidays $year).GetEnumerator() | Sort-Object -Property Name)
        foreach ($entry in $days) {
            $date = [datetime]::ParseExact($entry.Key, 'yyyy-MM-dd', $null)
            $dow = ('일','월','화','수','목','금','토')[[int]$date.DayOfWeek]
            $rule = Get-HolidayRule $date
            $action = 'normal'
            $moveTo = ''
            if ($null -ne $rule) { $action = [string]$rule.Action; $moveTo = [string]$rule.MoveTo }
            $actionText = switch ($action) {
                'skip' { '보내지 않음' }
                'move' { '날짜 옮김' }
                default  { '그대로 보냄' }
            }
            $item = New-Object System.Windows.Forms.ListViewItem("$($entry.Key) ($dow)")
            [void]$item.SubItems.Add([string]$entry.Value)
            [void]$item.SubItems.Add($actionText)
            [void]$item.SubItems.Add($(if ($action -eq 'move') { $moveTo } else { '-' }))
            if ($action -eq 'skip') { $item.ForeColor = $Theme.Danger }
            elseif ($action -eq 'move') { $item.ForeColor = $Theme.Info }
            [void]$list.Items.Add($item)
            $script:holidayRows += [pscustomobject]@{ Date = [string]$entry.Key; Name = [string]$entry.Value }
        }
        $list.EndUpdate()
    }
    Refresh-HolidayList

    [void](New-CardLabel $dialog '고른 날을' 24 396 80 26 $FontBase $Theme.Ink)
    $cmbAction = New-Object System.Windows.Forms.ComboBox
    $cmbAction.DropDownStyle = 'DropDownList'
    $cmbAction.Location = (New-UiPoint 108 392)
    $cmbAction.Size = (New-UiSize 150 30)
    $cmbAction.Font = $FontBase
    [void]$cmbAction.Items.AddRange(@('그대로 보냄', '보내지 않음', '날짜 옮김'))
    $cmbAction.SelectedIndex = 0
    $dialog.Controls.Add($cmbAction)

    [void](New-CardLabel $dialog '옮길 날짜' 274 396 80 26 $FontBase $Theme.Ink)
    $dtMove = New-Object System.Windows.Forms.DateTimePicker
    $dtMove.Format = 'Custom'
    $dtMove.CustomFormat = 'yyyy-MM-dd'
    $dtMove.Location = (New-UiPoint 356 392)
    $dtMove.Size = (New-UiSize 140 30)
    $dtMove.Font = $FontBase
    $dtMove.Enabled = $false
    $dialog.Controls.Add($dtMove)
    $cmbAction.Add_SelectedIndexChanged({ $dtMove.Enabled = ($cmbAction.SelectedIndex -eq 2) })

    $btnApply = New-AppButton $dialog '이 날에 적용' 508 390 108 36 'strong'
    $btnApply.Add_Click({
        if ($list.SelectedIndices.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('위 목록에서 날짜를 먼저 골라 주세요.', '공휴일 설정') | Out-Null
            return
        }
        $index = $list.SelectedIndices[0]
        $row = $script:holidayRows[$index]
        $action = switch ($cmbAction.SelectedIndex) { 1 { 'skip' } 2 { 'move' } default { 'normal' } }
        $moveTo = ''
        if ($action -eq 'move') {
            $moveTo = $dtMove.Value.ToString('yyyy-MM-dd')
            if ($moveTo -eq $row.Date) {
                [System.Windows.Forms.MessageBox]::Show('같은 날로는 옮길 수 없습니다.', '공휴일 설정') | Out-Null
                return
            }
        }
        Set-HolidayRule $row.Date $row.Name $action $moveTo
        try { Save-Config $script:config } catch { }
        Write-RunLog "공휴일 설정: $($row.Date) $($row.Name) -> $action $moveTo"
        Refresh-HolidayList
        try { Update-LimitStateLabel } catch { }
    })

    [void](New-CardLabel $dialog '음력 명절은 Windows 음력 달력으로 계산합니다. 임시공휴일은 들어 있지 않습니다.' 24 440 500 22 $FontSmall $Theme.Muted)
    $btnClose = New-AppButton $dialog '닫기' 508 436 108 36
    $btnClose.Add_Click({ $dialog.Close() })

    [void]$dialog.ShowDialog($script:form)
    $dialog.Dispose()
}

$btnShowHolidays.Add_Click({ Show-HolidayManager })

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
$script:btnHeaderStart.Add_Click({
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


# ----- 저장 메시지 -----
$btnTplLoad.Add_Click({
    $name = [string]$script:cmbTemplate.SelectedItem
    if (-not $name) {
        [System.Windows.Forms.MessageBox]::Show('불러올 문구를 골라 주세요.', '저장 메시지') | Out-Null
        return
    }
    $row = Find-Template $name
    if ($null -eq $row) { return }
    if ($script:txtMessage.Text.Trim() -and $script:txtMessage.Text -ne $row.Text) {
        $ask = "지금 쓰던 문구를 '$name' 으로 바꿉니다.`r`n`r`n계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($ask, '저장 메시지 불러오기', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    $script:txtMessage.Text = $row.Text
    $script:lastTemplateName = $name
    $script:lblTemplateState.Text = "'$name' 을(를) 불러왔습니다."
    Sync-ConfigFromForm
})

$btnTplSave.Add_Click({
    $body = [string]$script:txtMessage.Text
    if (-not $body.Trim()) {
        [System.Windows.Forms.MessageBox]::Show('먼저 위에 보낼 문구를 써 주세요.', '저장 메시지') | Out-Null
        return
    }
    $name = ([string][Microsoft.VisualBasic.Interaction]::InputBox('이 문구에 붙일 이름을 적어 주세요. 예: 기본 안내문', '저장 메시지 — 새로 저장', '')).Trim()
    if (-not $name) { return }
    if ($null -ne (Find-Template $name)) {
        $ask = "'$name' 이(가) 이미 있습니다.`r`n`r`n덮어쓸까요?"
        if ([System.Windows.Forms.MessageBox]::Show($ask, '저장 메시지', 'YesNo', 'Question') -ne 'Yes') { return }
    }
    $rows = @(Get-Templates | Where-Object { $_.Name -ne $name })
    $rows += [pscustomobject]@{ Name = $name; Text = $body }
    Set-Templates $rows
    $script:lastTemplateName = $name
    Update-TemplateCombo $name
    $script:lblTemplateState.Text = "'$name' 으로 저장했습니다."
})

$btnTplUpdate.Add_Click({
    $name = [string]$script:cmbTemplate.SelectedItem
    if (-not $name) {
        [System.Windows.Forms.MessageBox]::Show('덮어쓸 문구를 골라 주세요.', '저장 메시지') | Out-Null
        return
    }
    $body = [string]$script:txtMessage.Text
    if (-not $body.Trim()) {
        [System.Windows.Forms.MessageBox]::Show('위에 쓴 문구가 비어 있습니다.', '저장 메시지') | Out-Null
        return
    }
    $ask = "'$name' 에 지금 쓴 문구를 덮어씁니다.`r`n`r`n계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($ask, '저장 메시지 덮어쓰기', 'YesNo', 'Warning') -ne 'Yes') { return }
    $rows = @()
    foreach ($row in (Get-Templates)) {
        if ($row.Name -eq $name) { $rows += [pscustomobject]@{ Name = $name; Text = $body } }
        else { $rows += $row }
    }
    Set-Templates $rows
    $script:lastTemplateName = $name
    Update-TemplateCombo $name
    $script:lblTemplateState.Text = "'$name' 을(를) 새 내용으로 바꿨습니다."
})

$btnTplDelete.Add_Click({
    $name = [string]$script:cmbTemplate.SelectedItem
    if (-not $name) { return }
    $ask = "'$name' 을(를) 지웁니다.`r`n`r`n지운 문구는 되돌릴 수 없습니다. 계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($ask, '저장 메시지 삭제', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Templates @(Get-Templates | Where-Object { $_.Name -ne $name })
    if ($script:lastTemplateName -eq $name) { $script:lastTemplateName = '' }
    Update-TemplateCombo
    $script:lblTemplateState.Text = "'$name' 을(를) 지웠습니다."
})
$btnFilterAll.Add_Click({ $script:roomFilter = '전체'; Update-RoomListView })
$btnFilterPerson.Add_Click({ $script:roomFilter = 'direct'; Update-RoomListView })
$btnFilterChat.Add_Click({ $script:roomFilter = 'group'; Update-RoomListView })
$btnFilterOpen.Add_Click({ $script:roomFilter = 'open'; Update-RoomListView })

# 일반채팅은 1:1 과 단체를 모두 뜻합니다. 종류를 아직 모르는 방도 일반채팅으로 봅니다.
$btnPickNormal.Add_Click({ Select-RoomsByKind @('direct', 'group', 'unknown') })
$btnPickOpen.Add_Click({ Select-RoomsByKind @('open') })
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

# 사용자가 창으로 열어 둔 채팅방을 읽습니다.
# 이것이 가장 정확합니다. 창 제목은 윈도우가 알려 주는 진짜 글자라 틀리지 않습니다.
# 화면 글자를 읽지 않으므로 뽀식 을 포식 으로 잘못 읽는 일이 아예 없습니다.
#
# 목록은 열려 있는 방으로 통째로 바꿉니다. 더하지 않습니다.
# 열어 두신 방이 곧 보낼 방이기 때문입니다.
# 예전에 읽어 둔 방이 섞여 있으면 무엇을 보내는지 알 수 없게 됩니다.
$btnReadOpen.Add_Click({
    try {
        Sync-ConfigFromForm
        $found = @(Get-OpenChatRooms)
        if ($found.Count -eq 0) {
            $help = "열려 있는 채팅방 창이 없습니다." + "`r`n`r`n" +
                    "카카오톡에서 보낼 채팅방을 두 번 눌러 창으로 열어 두신 뒤" + "`r`n" +
                    "다시 [열어 둔 채팅방 읽기]를 눌러 주세요." + "`r`n`r`n" +
                    "카카오톡이 채팅방을 한 창 안에서만 보여 주도록 설정돼 있으면" + "`r`n" +
                    "창이 따로 열리지 않습니다. 그때는 [전체 목록 읽기]를 쓰세요."
            [System.Windows.Forms.MessageBox]::Show($help, '열어 둔 채팅방 읽기') | Out-Null
            return
        }

        $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        $rows = @()
        $order = 0
        foreach ($room in $found) {
            $rows += [pscustomobject]@{
                Name = $room.Name
                ListText = $room.Name
                Kind = $room.Kind
                Order = $order
                Verified = $true
                LastSeen = $stamp
            }
            $order++
        }
        Set-Roster $rows

        # 화면 목록도 열려 있는 방만 남깁니다.
        $script:roomEntries = New-Object System.Collections.Generic.List[object]
        foreach ($room in $found) {
            $type = if ($room.Kind -eq 'open') { $script:RoomTypeOpen } else { $script:RoomTypeNormal }
            $script:roomEntries.Add([pscustomobject]@{
                Name = $room.Name; Type = $type; Checked = $true
                Kind = $room.Kind; Verified = $true
            })
        }
        $script:roomFilter = '전체'
        if ($null -ne $script:txtRoomSearch) { $script:txtRoomSearch.Text = '' }
        Update-RoomListView
        Sync-ConfigFromForm
        try { Save-Config $script:config } catch { }

        Write-RunLog "열어 둔 채팅방 $($found.Count)개를 읽었습니다. (창 제목으로 확인한 이름입니다)"
        foreach ($room in $found) { Write-RunLog "  - $($room.Name)  [$(Get-RosterKindText $room.Kind)]" }

        $text = "열려 있는 채팅방 $($found.Count)개를 읽었습니다." + "`r`n`r`n" +
                ((@($found | ForEach-Object { '· ' + $_.Name }) | Select-Object -First 12) -join "`r`n")
        if ($found.Count -gt 12) { $text += "`r`n… 외 $($found.Count - 12)개" }
        $text += "`r`n`r`n이 $($found.Count)개만 목록에 남기고 모두 체크했습니다."
        $text += "`r`n창 제목에서 가져온 이름이라 틀릴 일이 없습니다."
        $text += "`r`n`r`n보낼 방을 바꾸시려면 카카오톡에서 창을 열거나 닫은 뒤 다시 눌러 주세요."
        [System.Windows.Forms.MessageBox]::Show($text, '열어 둔 채팅방 읽기') | Out-Null
    } catch {
        Write-RunLog "열어 둔 채팅방 읽기 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '열어 둔 채팅방 읽기 실패') | Out-Null
    }
})

# 목록을 통째로 비웁니다. 예전에 잘못 읽힌 방이 잔뜩 쌓였을 때 씁니다.
$btnClearRooms.Add_Click({
    $count = $script:roomEntries.Count
    if ($count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('목록이 이미 비어 있습니다.', '목록 비우기') | Out-Null
        return
    }
    $ask = "저장된 채팅방 $($count)개를 모두 지웁니다." + "`r`n`r`n" +
           "카카오톡의 채팅방을 지우는 것이 아닙니다." + "`r`n" +
           "이 프로그램이 기억하고 있는 목록만 비웁니다." + "`r`n`r`n" +
           "계속할까요?"
    if ([System.Windows.Forms.MessageBox]::Show($ask, '목록 비우기', 'YesNo', 'Warning') -ne 'Yes') { return }
    Set-Roster @()
    Set-ConfigValue 'KnownRooms' @()
    Set-ConfigValue 'Rooms' @()
    $script:roomEntries = New-Object System.Collections.Generic.List[object]
    $script:roomFilter = '전체'
    if ($null -ne $script:txtRoomSearch) { $script:txtRoomSearch.Text = '' }
    Update-RoomListView
    Sync-ConfigFromForm
    try { Save-Config $script:config } catch { }
    Write-RunLog "저장된 채팅방 목록 $($count)개를 비웠습니다."
    [System.Windows.Forms.MessageBox]::Show("목록을 비웠습니다.`r`n`r`n카카오톡에서 보낼 방을 창으로 열어 두시고 [열어 둔 채팅방 읽기]를 눌러 주세요.", '목록 비우기') | Out-Null
})

# 카카오톡에 보이는 채팅방 목록을 통째로 읽어 저장합니다.
# 사용자가 이름을 치는 방식은 쓰지 않습니다. 카카오톡에 있는 그대로를 가져옵니다.
$btnScanRooms.Add_Click({
    try {
        Sync-ConfigFromForm
        $ready = Test-KakaoReady $true $false
        if (-not $ready.Ok) {
            [System.Windows.Forms.MessageBox]::Show("$($ready.Reason)`r`n`r`n카카오톡에서 [채팅] 탭을 눌러 목록이 보이게 한 뒤 다시 눌러 주세요.", '먼저 확인해 주세요') | Out-Null
            return
        }
        $before = @(Get-Roster).Count
        $ask = "카카오톡 채팅 목록을 위에서 끝까지 훑어 읽습니다." + "`r`n`r`n" +
               "[예]  방을 하나씩 열어 창 제목으로 이름을 확인합니다." + "`r`n" +
               "      이름이 정확해집니다. 방 하나에 2~3초 걸리고 읽음 표시가 됩니다." + "`r`n`r`n" +
               "[아니오]  화면 글자만 읽습니다." + "`r`n" +
               "          빠르지만 뽀식 을 포식 으로 읽는 것 같은 실수가 생길 수 있습니다." + "`r`n`r`n" +
               "· 카카오톡 화면: $($ready.Layout.ViewName)" + "`r`n" +
               "· 지금 저장된 방: $($before)개" + "`r`n`r`n" +
               "보낼 방을 창으로 열어 두셨다면 [취소]를 누르고" + "`r`n" +
               "[열어 둔 채팅방 읽기]를 쓰시는 편이 훨씬 빠르고 정확합니다."
        $answer = [System.Windows.Forms.MessageBox]::Show($ask, '전체 목록 읽기', 'YesNoCancel', 'Question')
        if ($answer -eq 'Cancel') { return }
        $exact = ($answer -eq 'Yes')
        Set-ConfigValue 'ScanExactNames' $exact
        $script:form.Enabled = $false
        Set-StatusPill '목록 읽는 중' 'run'
        $scan = $null
        try {
            $scan = Invoke-RosterScan $exact ([int]$script:config.ScanPages)
        } finally {
            $script:form.Enabled = $true
            $script:form.Activate()
        }
        if ($null -eq $scan) { Set-StatusPill '준비됨' 'idle'; return }

        $diff = Merge-RosterScan $scan $false
        Sync-RoomEntriesFromRoster
        Update-RoomListView
        Sync-ConfigFromForm
        try { Save-Config $script:config } catch { }
        Set-StatusPill '준비됨' 'idle'

        $readCount = @($scan.Rows).Count
        Write-RunLog "목록 새로고침 끝: 읽은 방 $($readCount)개 / 새로 생김 $(@($diff.Added).Count)개 / 없어짐 $(@($diff.Removed).Count)개 / 저장된 전체 $($diff.Total)개"

        $result = "채팅방 $($readCount)개를 읽었습니다." + "`r`n`r`n" +
                  "· 새로 생긴 방: $(@($diff.Added).Count)개" + "`r`n" +
                  "· 목록에서 없어진 방: $(@($diff.Removed).Count)개" + "`r`n" +
                  "· 저장된 전체: $($diff.Total)개"
        if (@($diff.Added).Count -gt 0) {
            $result += "`r`n`r`n[새로 생긴 방]`r`n" + ((@($diff.Added) | Select-Object -First 8) -join "`r`n")
            if (@($diff.Added).Count -gt 8) { $result += "`r`n… 외 $((@($diff.Added).Count) - 8)개" }
        }
        if (@($diff.Removed).Count -gt 0) {
            $result += "`r`n`r`n[없어진 방]`r`n" + ((@($diff.Removed) | Select-Object -First 8) -join "`r`n")
            if (@($diff.Removed).Count -gt 8) { $result += "`r`n… 외 $((@($diff.Removed).Count) - 8)개" }
        }
        if ([int]$scan.OpenFailures -gt 0) {
            $result += "`r`n`r`n$([int]$scan.OpenFailures)개 줄은 방을 열지 못해 목록에 넣지 못했습니다."
            $result += "`r`n카카오톡 창을 조금 크게 한 뒤 다시 해 보세요."
        }
        if ([int]$scan.TitleFailures -gt 0) {
            $result += "`r`n`r`n$([int]$scan.TitleFailures)개 줄은 제목을 못 읽어 넣지 않았습니다."
            $result += "`r`n대화내용을 이름으로 쓰면 엉뚱한 방에 갈 수 있어 일부러 뺐습니다."
            $result += "`r`n[방을 열어 이름 확인]을 켜고 다시 하시면 이 줄들도 읽힙니다."
        }
        if ([bool]$scan.Cancelled) { $result += "`r`n`r`n도중에 멈췄습니다. 읽은 데까지만 저장했습니다." }
        if ($readCount -eq 0) {
            $result += "`r`n`r`n한 개도 읽지 못했습니다. 카카오톡에서 목록이 실제로 보이는지 확인하고, 창을 조금 크게 한 뒤 다시 해 보세요."
        } else {
            $result += "`r`n`r`n이제 보낼 방만 체크하시면 됩니다."
        }
        [System.Windows.Forms.MessageBox]::Show($result, '채팅방 목록 새로고침') | Out-Null
    } catch {
        $script:form.Enabled = $true
        $script:form.Activate()
        Set-StatusPill '목록 읽기 실패' 'error'
        Write-RunLog "목록 읽기 실패: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '목록 읽기 실패') | Out-Null
    }
})
$btnVerifyRoom.Add_Click({
    try {
        Sync-ConfigFromForm
        $targets = @($script:roomEntries | Where-Object { $_.Checked } | ForEach-Object { [string]$_.Name })
        if ($targets.Count -eq 0) { throw '확인할 채팅방을 먼저 체크해 주세요.' }
        if ($targets.Count -gt 60) { throw '한 번에 최대 60개까지만 확인합니다.' }
        $body = "체크한 $($targets.Count)개 방을 하나씩 열어 창 제목으로 이름을 확인합니다." + "`r`n`r`n" +
                "메시지는 보내지 않습니다. 다만 방이 열리므로 읽음 표시가 됩니다." + "`r`n" +
                "진행하는 동안 마우스와 키보드를 쓰지 말아 주세요." + "`r`n`r`n" +
                "계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($body, '이름 확인·보정', 'YesNo', 'Question') -ne 'Yes') { return }

        $script:form.Enabled = $false
        Set-StatusPill '이름 확인 중' 'run'
        $result = $null
        try { $result = Invoke-RoomNameVerify $targets ([int]$script:config.ScanPages) }
        finally {
            $script:form.Enabled = $true
            $script:form.Activate()
        }
        Sync-RoomEntriesFromRoster
        Update-RoomListView
        Sync-ConfigFromForm
        Set-StatusPill '이름 확인 완료' 'done'
        if ($null -eq $result) { return }

        $text = "확인 $(@($result.Confirmed).Count)개 · 바로잡음 $(@($result.Renamed).Count)개 · 못 찾음 $(@($result.NotFound).Count)개"
        if (@($result.Renamed).Count -gt 0) {
            $text += "`r`n`r`n[바로잡은 이름]`r`n" + ((@($result.Renamed) | Select-Object -First 10) -join "`r`n")
        }
        if (@($result.NotFound).Count -gt 0) {
            $text += "`r`n`r`n[못 찾은 방]`r`n" + ((@($result.NotFound) | Select-Object -First 10) -join "`r`n")
            $text += "`r`n`r`n[채팅방 목록 새로고침]을 [방을 열어 이름 확인]을 켜고 한 번 해 보세요."
        }
        [System.Windows.Forms.MessageBox]::Show($text, '이름 확인·보정 완료') | Out-Null
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
    try { if ($null -ne $script:appIcon) { $dialog.Icon = $script:appIcon } } catch { }
    $dialog.Text = '예약 시각 고르기'
    $dialog.ClientSize = (New-UiSize 560 470)
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
    $title.Location = (New-UiPoint 26 22)
    $title.Size = (New-UiSize 508 32)
    $dialog.Controls.Add($title)

    $calendar = New-Object System.Windows.Forms.MonthCalendar
    $calendar.Location = (New-UiPoint 26 62)
    $calendar.MaxSelectionCount = 1
    $calendar.MinDate = (Get-Date).Date
    $calendar.SetDate($Current.Date)
    $dialog.Controls.Add($calendar)

    [void](New-CardLabel $dialog '시' 300 80 24 26 $FontSmall $Theme.Muted)
    $numHour = New-Object System.Windows.Forms.NumericUpDown
    $numHour.Minimum = 0; $numHour.Maximum = 23; $numHour.Value = $Current.Hour
    $numHour.Location = (New-UiPoint 326 76)
    $numHour.Size = (New-UiSize 66 30)
    $numHour.Font = $FontBase; $numHour.BorderStyle = 'FixedSingle'
    $dialog.Controls.Add($numHour)

    [void](New-CardLabel $dialog '분' 400 80 24 26 $FontSmall $Theme.Muted)
    $numMinute = New-Object System.Windows.Forms.NumericUpDown
    $numMinute.Minimum = 0; $numMinute.Maximum = 59; $numMinute.Value = $Current.Minute
    $numMinute.Location = (New-UiPoint 426 76)
    $numMinute.Size = (New-UiSize 66 30)
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
    try { if ($null -ne $script:appIcon) { $dialog.Icon = $script:appIcon } } catch { }
    $dialog.Text = $Action
    $dialog.ClientSize = (New-UiSize 600 620)
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
    $title.Location = (New-UiPoint 28 24)
    $title.Size = (New-UiSize 544 34)
    $dialog.Controls.Add($title)

    $dryRun = [bool]$script:config.DryRun
    $mode = if ($dryRun) { '확인 전용 — 방만 열어 보고 전송하지 않습니다.' } else { '실제로 메시지가 전송됩니다.' }
    $summary = New-Object System.Windows.Forms.Label
    $summary.Font = $FontBase
    $summary.ForeColor = if ($dryRun) { $Theme.Sub } else { $Theme.Danger }
    $summary.BackColor = $Theme.Card
    $summary.Location = (New-UiPoint 28 62)
    $summary.Size = (New-UiSize 544 46)
    $summary.Text = "$mode`r`n$(Get-EstimatedRunText)"
    $dialog.Controls.Add($summary)

    $lblTo = New-Object System.Windows.Forms.Label
    $lblTo.Text = "받는 채팅방 $($rooms.Count)개"
    $lblTo.Font = $FontStrong
    $lblTo.ForeColor = $Theme.Ink
    $lblTo.BackColor = $Theme.Card
    $lblTo.Location = (New-UiPoint 28 116)
    $lblTo.Size = (New-UiSize 544 24)
    $dialog.Controls.Add($lblTo)

    $listFrame = New-FieldFrame $dialog 28 144 544 224
    $list = New-Object System.Windows.Forms.ListView
    $list.View = 'Details'
    $list.FullRowSelect = $true
    $list.BorderStyle = 'None'
    $list.Font = $FontBase
    $list.Location = (New-UiPoint 12 12)
    $list.Size = (New-UiSize 520 200)
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
    $lblMsg.Location = (New-UiPoint 28 380)
    $lblMsg.Size = (New-UiSize 544 24)
    $dialog.Controls.Add($lblMsg)

    $msgFrame = New-FieldFrame $dialog 28 408 544 104
    $preview = New-Object System.Windows.Forms.TextBox
    $preview.Multiline = $true
    $preview.ReadOnly = $true
    $preview.ScrollBars = 'Vertical'
    $preview.BorderStyle = 'None'
    $preview.BackColor = [System.Drawing.Color]::White
    $preview.Font = $FontBase
    $preview.Location = (New-UiPoint 12 10)
    $preview.Size = (New-UiSize 518 82)
    $preview.Text = if ([string]::IsNullOrWhiteSpace($script:config.Message)) { '(문구 없음)' } else { [string]$script:config.Message }
    $msgFrame.Controls.Add($preview)

    $lblFiles = New-Object System.Windows.Forms.Label
    $lblFiles.Text = "첨부 $(@($script:config.Attachments).Count)개"
    $lblFiles.Font = $FontSmall
    $lblFiles.ForeColor = $Theme.Muted
    $lblFiles.BackColor = $Theme.Card
    $lblFiles.Location = (New-UiPoint 28 518)
    $lblFiles.Size = (New-UiSize 300 22)
    $dialog.Controls.Add($lblFiles)

    $chkSkip = New-Object System.Windows.Forms.CheckBox
    $chkSkip.Text = '다음부터 이 확인 창 보지 않기'
    $chkSkip.Font = $FontSmall
    $chkSkip.BackColor = $Theme.Card
    $chkSkip.Location = (New-UiPoint 28 548)
    $chkSkip.Size = (New-UiSize 280 26)
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

function Start-BroadcastAsync([string[]]$Targets = $null, [bool]$Resume = $false) {
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
        $count = Invoke-Broadcast $Targets $Resume
        Set-StatusPill "작업 완료 · 성공 $($count)개" 'done'
        Show-RunResult
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
        Update-ResumeButtons
        $script:form.Activate()
    }
}

# 끝난 뒤 결과를 한눈에 보여 줍니다. 숫자가 맞는지 여기서 바로 확인하실 수 있습니다.
function Show-RunResult {
    $r = $script:lastRunResult
    if ($null -eq $r) { return }
    $lines = @()
    $lines += "전체 대상: $($r.Total)개"
    $lines += "성공:      $($r.Sent)개"
    $lines += "실패:      $($r.Failed)개"
    $lines += "누락:      $($r.Missing)개"
    $lines += ''
    if ($r.DryRun) {
        $lines += '확인 전용이라 실제로 보낸 것은 없습니다.'
    } else {
        $lines += "발송 사진: $($r.Photos)장"
        $lines += "발송 파일: $($r.Files)개"
        $lines += "메시지:    $($r.Messages)건"
    }
    if ($r.Missing -ne 0) {
        $lines += ''
        $lines += '[주의] 누락이 0이 아닙니다. 실행 기록을 확인해 주세요.'
    }
    if (@($r.FailedRooms).Count -gt 0) {
        $lines += ''
        $lines += "[실패한 채팅방 $(@($r.FailedRooms).Count)개]"
        $lines += ((@($r.FailedRooms) | Select-Object -First 15) -join "`r`n")
        if (@($r.FailedRooms).Count -gt 15) { $lines += "… 외 $((@($r.FailedRooms).Count) - 15)개" }
        $lines += ''
        $lines += '[보내기] 화면의 [실패한 방만 다시 보내기] 로 이 방들만 다시 보낼 수 있습니다.'
    }
    $title = if ($r.Missing -eq 0) { '발송 완료 — 빠진 방 없음' } else { '발송 완료 — 확인 필요' }
    [System.Windows.Forms.MessageBox]::Show(($lines -join "`r`n"), $title) | Out-Null
}

# 이어서 발송 · 실패한 방만 다시 보내기 단추를 켜고 끕니다.
function Update-ResumeButtons {
    try {
        $failed = @()
        if ($null -ne $script:lastRunResult) { $failed = @($script:lastRunResult.FailedRooms) }
        if ($null -ne $script:btnRetryFailed) {
            $script:btnRetryFailed.Enabled = ((-not $script:running) -and $failed.Count -gt 0)
            $script:btnRetryFailed.Tag.Label = if ($failed.Count -gt 0) { "실패한 $($failed.Count)개 다시 보내기" } else { '실패한 방만 다시 보내기' }
            $script:btnRetryFailed.Invalidate()
        }
        if ($null -ne $script:btnResumeRun) {
            $left = @(Get-ResumableRooms (Import-RunProgress))
            $script:btnResumeRun.Enabled = ((-not $script:running) -and $left.Count -gt 0)
            $script:btnResumeRun.Tag.Label = if ($left.Count -gt 0) { "이어서 발송 ($($left.Count)개 남음)" } else { '이어서 발송' }
            $script:btnResumeRun.Invalidate()
        }
    } catch { }
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

# ----- 이어서 발송 · 실패한 방만 다시 보내기 -----
$script:btnResumeRun.Add_Click({
    try {
        $saved = Import-RunProgress
        $left = @(Get-ResumableRooms $saved)
        if ($left.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('이어서 보낼 방이 없습니다.', '이어서 발송') | Out-Null
            return
        }
        Sync-ConfigFromForm
        # 문구가 바뀌었으면 이어서 보내면 안 됩니다. 앞뒤가 다른 글이 나갑니다.
        $mark = Get-MessageFingerprint ([string]$script:config.Message)
        if ([string]$saved.MessageMark -and [string]$saved.MessageMark -ne $mark) {
            $ask = "저장된 발송과 지금 문구가 다릅니다." + "`r`n`r`n" +
                   "이어서 보내면 앞에 보낸 것과 다른 글이 나갑니다." + "`r`n`r`n" +
                   "그래도 이어서 보낼까요?"
            if ([System.Windows.Forms.MessageBox]::Show($ask, '이어서 발송', 'YesNo', 'Warning') -ne 'Yes') { return }
        }
        $ask2 = "저장된 발송을 이어서 진행합니다." + "`r`n`r`n" +
                "· 남은 방: $($left.Count)개" + "`r`n" +
                "· 시작한 때: $([string]$saved.StartedAt)" + "`r`n`r`n" +
                "이미 보낸 방과 이미 나간 사진은 다시 보내지 않습니다." + "`r`n`r`n" +
                "계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($ask2, '이어서 발송', 'YesNo', 'Question') -ne 'Yes') { return }
        Restore-RunProgress $saved
        Show-AppPage 'run'
        Start-BroadcastAsync $left $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '이어서 발송 실패') | Out-Null
    }
})

$script:btnRetryFailed.Add_Click({
    try {
        $failed = @()
        if ($null -ne $script:lastRunResult) { $failed = @($script:lastRunResult.FailedRooms) }
        if ($failed.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show('다시 보낼 실패한 방이 없습니다.', '실패한 방만 다시 보내기') | Out-Null
            return
        }
        Sync-ConfigFromForm
        $ask = "실패한 방 $($failed.Count)개에만 다시 보냅니다." + "`r`n`r`n" +
               ((@($failed) | Select-Object -First 10) -join "`r`n")
        if ($failed.Count -gt 10) { $ask += "`r`n… 외 $($failed.Count - 10)개" }
        $ask += "`r`n`r`n이미 나간 사진은 다시 보내지 않습니다. 계속할까요?"
        if ([System.Windows.Forms.MessageBox]::Show($ask, '실패한 방만 다시 보내기', 'YesNo', 'Question') -ne 'Yes') { return }
        Show-AppPage 'run'
        Start-BroadcastAsync $failed $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '다시 보내기 실패') | Out-Null
    }
})
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
    # 열어 둔 채팅방 창이 몇 개인지 알려 드립니다. 이 창들이 발송의 기본 대상입니다.
    $openRooms = @()
    try { $openRooms = @(Get-OpenChatRooms) } catch { }
    if ($openRooms.Count -gt 0) {
        $preview = (@($openRooms | ForEach-Object { $_.Name }) | Select-Object -First 4) -join ', '
        if ($openRooms.Count -gt 4) { $preview += " 외 $($openRooms.Count - 4)개" }
        $lines.Add("[정상] 열어 둔 채팅방 창 $($openRooms.Count)개: $preview")
    } else {
        $lines.Add('[안내] 열어 둔 채팅방 창이 없습니다. 보낼 방을 창으로 열어 두시면 그 창으로 바로 보냅니다.')
    }
    if (Initialize-Ocr) { $lines.Add('[정상] 한국어 문자 인식 사용 가능 (전체 목록 읽기에만 씁니다)') }
    else { $lines.Add("[확인 필요] 한국어 문자 인식 불가 - $($script:ocrError)") }
    $lines.Add('[안내] 열어 둔 창으로 보낼 때는 화면 글자를 읽지 않습니다. 창 제목이 곧 정확한 이름입니다.')
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
$btnPrereq.Add_Click({
    # 필수 요소 확인은 따로 떨어진 스크립트로 돌립니다.
    # 한국어 문자 인식을 설치하려면 관리자 권한이 필요한데,
    # 이 프로그램 전체를 관리자로 띄울 이유는 없기 때문입니다.
    try {
        $script = Join-Path $AppDir 'prereq.ps1'
        if (-not (Test-Path -LiteralPath $script)) {
            [System.Windows.Forms.MessageBox]::Show('prereq.ps1 을 찾지 못했습니다. 프로그램을 다시 받아 주세요.', '필수 요소 확인') | Out-Null
            return
        }
        Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-NoLaunch') -WorkingDirectory $AppDir
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '필수 요소 확인') | Out-Null
    }
})
$btnOpenLogs.Add_Click({ Start-Process 'explorer.exe' $LogDir })
$btnOpenLogDir.Add_Click({ Start-Process 'explorer.exe' $LogDir })
# 발송 결과를 표로 적어 둔 파일입니다. 시간 / 채팅방 / 문구 / 첨부 / 결과 / 사유
$btnOpenSendLog.Add_Click({
    $path = Join-Path $LogDir ('발송기록-' + (Get-Date -Format 'yyyy-MM') + '.csv')
    if (-not (Test-Path -LiteralPath $path)) {
        $found = @(Get-ChildItem -LiteralPath $LogDir -Filter '발송기록-*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($found.Count -gt 0) { $path = $found[0].FullName }
    }
    if (-not (Test-Path -LiteralPath $path)) {
        [System.Windows.Forms.MessageBox]::Show('아직 발송 기록이 없습니다. 한 번 보내고 나면 여기에 표로 쌓입니다.', '발송 기록') | Out-Null
        return
    }
    try { Start-Process -FilePath $path } catch { Start-Process 'explorer.exe' $LogDir }
})
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
    try { if ($null -ne $script:appIcon) { $tour.Icon = $script:appIcon } } catch { }
    $tour.FormBorderStyle = 'None'
    $tour.Size = (New-UiSize 600 440)
    $tour.StartPosition = 'Manual'
    $tour.BackColor = $Theme.Card
    $tour.Font = $FontBase
    $tour.ShowInTaskbar = $false
    $tour.KeyPreview = $true
    # 창 위치는 실제 좌표라 그대로 쓰고, 떨어뜨릴 거리만 배율에 맞춥니다.
    $tour.Location = New-Object System.Drawing.Point(
        ($script:form.Left + (S 320)),
        ($script:form.Top + (S 160)))
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
    $lblStep.Location = (New-UiPoint 38 34)
    $lblStep.Size = (New-UiSize 200 22)
    $lblStep.Font = $FontStrong
    $lblStep.ForeColor = $Theme.Muted
    $lblStep.BackColor = $Theme.Card
    $tour.Controls.Add($lblStep)

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Location = (New-UiPoint 36 60)
    $lblTitle.Size = (New-UiSize 528 36)
    $lblTitle.Font = $FontTourTitle
    $lblTitle.ForeColor = $Theme.Ink
    $lblTitle.BackColor = $Theme.Card
    $tour.Controls.Add($lblTitle)

    $lblBody = New-Object System.Windows.Forms.Label
    $lblBody.Location = (New-UiPoint 38 106)
    $lblBody.Size = (New-UiSize 526 246)
    $lblBody.Font = $FontTourBody
    $lblBody.ForeColor = $Theme.Sub
    $lblBody.BackColor = $Theme.Card
    $tour.Controls.Add($lblBody)

    $dots = New-Object System.Windows.Forms.Panel
    $dots.Location = (New-UiPoint 38 376)
    $dots.Size = (New-UiSize 170 26)
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
    try { if ($null -ne $script:appIcon) { $splash.Icon = $script:appIcon } } catch { }
    $splash.FormBorderStyle = 'None'
    $splash.StartPosition = 'CenterScreen'
    $splash.Size = (New-UiSize 560 420)
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
        $mark = New-UiRect 40 40 52 52
        $path = Get-RoundedPath $mark 15
        $brush = New-Object System.Drawing.SolidBrush ($Theme.Accent)
        $e.Graphics.FillPath($brush, $path)
        $brush.Dispose(); $path.Dispose()
        Write-Text $e.Graphics '톡' $FontTourTitle $Theme.AccentInk $mark $TextCenter
        Write-Text $e.Graphics '카카오 발송기' $FontTourTitle $Theme.Ink (New-UiRect 108 42 300 30) $TextLeft
        Write-Text $e.Graphics "버전 $($script:AppVersion)" $FontSmall $Theme.Muted (New-UiRect 110 70 300 22) $TextLeft
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
        $row.Location = (New-UiPoint 42 $y)
        $row.Size = (New-UiSize 478 44)
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
Update-ResumeButtons
# 처음 켠 것이라면 기록을 남기지 않습니다. 빈 화면으로 시작해야 하기 때문입니다.
if (-not $script:isFirstRun) {
    Write-RunLog "프로그램 시작 (v$($script:AppVersion)). 설정은 자동 저장됩니다."
    if ($script:roomRepairNote) { Write-RunLog $script:roomRepairNote }
}

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
    $script:form.Location = (New-UiPoint -4000 -4000)
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
