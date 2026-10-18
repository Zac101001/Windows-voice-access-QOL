param(
    [switch]$Show,
    [switch]$List
)

# Auto-elevate (hiding the Voice Access window requires Administrator)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath) + $args
    Start-Process -FilePath "powershell" -ArgumentList $argList -Verb RunAs -WindowStyle Hidden
    exit
}

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class VoiceEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    public struct RECT { public int Left, Top, Right, Bottom; }

    public static System.Collections.Generic.List<string> Matches = new System.Collections.Generic.List<string>();

    public static System.Collections.Generic.List<IntPtr> FindWindows() {
        var result = new System.Collections.Generic.List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            System.Diagnostics.Process p = null;
            try { p = System.Diagnostics.Process.GetProcessById((int)pid); } catch { return true; }
            if (!string.Equals(p.ProcessName, "VoiceAccess", StringComparison.OrdinalIgnoreCase)) return true;

            var t = new StringBuilder(256); var c = new StringBuilder(256);
            GetWindowText(hWnd, t, 256); GetClassName(hWnd, c, 256);
            string title = t.ToString(); string cls = c.ToString();

            bool isBar = (title.IndexOf("Voice access", StringComparison.OrdinalIgnoreCase) >= 0) ||
                         (cls.IndexOf("Voice access", StringComparison.OrdinalIgnoreCase) >= 0);

            if (isBar) {
                RECT r; GetWindowRect(hWnd, out r);
                result.Add(hWnd);
                Matches.Add(string.Format("HWND={0} (0x{0:X}) title=\"{1}\" class=\"{2}\" rect=({3},{4},{5},{6})", hWnd.ToInt64(), title, cls, r.Left, r.Top, r.Right, r.Bottom));
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class AppBarFree {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct APPBARDATA {
        public uint cbSize;
        public IntPtr hWnd;
        public uint uCallbackMessage;
        public uint uEdge;
        public RECT rc;
        public IntPtr lParam;
    }

    [DllImport("shell32.dll")]
    public static extern IntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);

    public const uint ABM_REMOVE = 1;

    public static IntPtr RemoveAppBar(IntPtr hWnd) {
        APPBARDATA data = new APPBARDATA();
        data.cbSize = (uint)Marshal.SizeOf(typeof(APPBARDATA));
        data.hWnd = hWnd;
        return SHAppBarMessage(ABM_REMOVE, ref data);
    }
}
'@

[VoiceEnum]::Matches.Clear()
$windows = [VoiceEnum]::FindWindows()

if ($windows.Count -eq 0) {
    Write-Host "Voice Access window not found. Is Voice Access running?" -ForegroundColor Yellow
    exit
}

Write-Host "Voice Access windows found:"
[VoiceEnum]::Matches | ForEach-Object { Write-Host $_ }

if (-not $List) {
    $cmd = if ($Show) { 5 } else { 0 }  # 5=SW_SHOW, 0=SW_HIDE
    foreach ($h in $windows) {
        if (-not [VoiceEnum]::IsWindow($h)) { continue }
        if (-not $Show) {
            $res = [AppBarFree]::RemoveAppBar($h)
            Write-Host "AppBar space reservation removed for $h (0x$($h.ToString('X'))): result $res"
        }
        $old = [VoiceEnum]::ShowWindow($h, $cmd)
        $action = if ($Show) { "shown" } else { "hidden" }
        Write-Host "Window $h (0x$($h.ToString('X'))) $action. ShowWindow result: $old"
    }
}
