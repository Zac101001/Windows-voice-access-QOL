param(
    [switch]$AutoHide
)

# Hide/show of the Voice Access window requires Administrator (Voice Access runs with UI Access).
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-WindowStyle", "Hidden", "-File", $PSCommandPath)
    if ($AutoHide) { $argList += "-AutoHide" }
    Start-Process -FilePath "powershell" -ArgumentList $argList -Verb RunAs -WindowStyle Hidden
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Speech
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public class VEnum {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
    [DllImport("user32.dll", SetLastError=true)] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static System.Collections.Generic.List<IntPtr> Find() {
        var result = new System.Collections.Generic.List<IntPtr>();
        EnumWindows((hWnd, lParam) => {
            uint pid; GetWindowThreadProcessId(hWnd, out pid);
            System.Diagnostics.Process p = null;
            try { p = System.Diagnostics.Process.GetProcessById((int)pid); } catch { return true; }
            if (!string.Equals(p.ProcessName, "VoiceAccess", StringComparison.OrdinalIgnoreCase)) return true;
            var t = new StringBuilder(256); var c = new StringBuilder(256);
            GetWindowText(hWnd, t, 256); GetClassName(hWnd, c, 256);
            string title = t.ToString(); string cls = c.ToString();
            if (title.IndexOf("Voice access", StringComparison.OrdinalIgnoreCase) >= 0 ||
                cls.IndexOf("Voice access", StringComparison.OrdinalIgnoreCase) >= 0) {
                result.Add(hWnd);
            }
            return true;
        }, IntPtr.Zero);
        return result;
    }
}
'@

Add-Type @'
using System; using System.Runtime.InteropServices;
public class ABar {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct APPBARDATA { public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage; public uint uEdge; public RECT rc; public IntPtr lParam; }
    [DllImport("shell32.dll")] public static extern IntPtr SHAppBarMessage(uint dwMessage, ref APPBARDATA pData);
    public const uint ABM_REMOVE = 1;
    public static IntPtr Remove(IntPtr hWnd) {
        APPBARDATA data = new APPBARDATA();
        data.cbSize = (uint)Marshal.SizeOf(typeof(APPBARDATA));
        data.hWnd = hWnd;
        return SHAppBarMessage(ABM_REMOVE, ref data);
    }
}
'@

Add-Type @'
using System; using System.Runtime.InteropServices;
public class WakeKeys {
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    // Simulates Alt+Shift+B (Voice Access wake/sleep toggle)
    public static void AltShiftB() {
        keybd_event(0x12, 0, 0, UIntPtr.Zero);
        keybd_event(0x10, 0, 0, UIntPtr.Zero);
        keybd_event(0x42, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(120);
        keybd_event(0x42, 0, 2, UIntPtr.Zero);
        keybd_event(0x10, 0, 2, UIntPtr.Zero);
        keybd_event(0x12, 0, 2, UIntPtr.Zero);
    }
    public static void Esc() {
        keybd_event(0x1B, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(80);
        keybd_event(0x1B, 0, 2, UIntPtr.Zero);
    }
}
'@

# Audio device control (default endpoint + endpoint visibility) via the undocumented IPolicyConfig COM interface.
Add-Type @'
using System; using System.Runtime.InteropServices;
public class AudioPolicy {
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumeratorComObject { }
    [Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator {
        int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
        int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppEndpoint);
        int GetDevice(string pwstrId, out IMMDevice ppDevice);
        int RegisterEndpointNotificationCallback(IntPtr pClient);
        int UnregisterEndpointNotificationCallback(IntPtr pClient);
    }
    [Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceCollection { int GetCount(out int pcDevices); int Item(int nDevice, out IMMDevice ppDevice); }
    [Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice {
        int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IntPtr ppInterface);
        int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
        int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
        int GetState(out int pdwState);
    }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class CPolicyConfigClient { }
    [Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig {
        [PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string d, out IntPtr p);
        [PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string d, bool b, out IntPtr p);
        [PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string d);
        [PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string d, IntPtr a, IntPtr b);
        [PreserveSig] int GetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string d, bool b, out IntPtr a, out IntPtr c);
        [PreserveSig] int SetProcessingPeriod([MarshalAs(UnmanagedType.LPWStr)] string d, IntPtr a);
        [PreserveSig] int GetShareMode([MarshalAs(UnmanagedType.LPWStr)] string d, out IntPtr p);
        [PreserveSig] int SetShareMode([MarshalAs(UnmanagedType.LPWStr)] string d, IntPtr p);
        [PreserveSig] int GetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string d, bool b, IntPtr k, out IntPtr pv);
        [PreserveSig] int SetPropertyValue([MarshalAs(UnmanagedType.LPWStr)] string d, bool b, IntPtr k, IntPtr pv);
        [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string d, int role);
        [PreserveSig] int SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string d, bool v);
    }
    public static string GetDefaultRender() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice d; en.GetDefaultAudioEndpoint(0, 0, out d); string id; d.GetId(out id); return id;
    }
    // dataFlow: 0 = render, 1 = capture. role: 0 = console. Returns the default capture endpoint id.
    public static string GetDefaultCapture() {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDevice d; en.GetDefaultAudioEndpoint(1, 0, out d); string id; d.GetId(out id); return id;
    }
    public static string SetDefault(string id) {
        var pc = (IPolicyConfig)(new CPolicyConfigClient());
        int a = pc.SetDefaultEndpoint(id, 0);
        int b = pc.SetDefaultEndpoint(id, 1);
        int c = pc.SetDefaultEndpoint(id, 2);
        return string.Format("{0},{1},{2}", a, b, c);
    }
    public static int SetVisible(string id, bool v) {
        var pc = (IPolicyConfig)(new CPolicyConfigClient());
        return pc.SetEndpointVisibility(id, v);
    }
    // Returns "id|state" for the capture endpoint whose id contains guid, else "".
    public static string CaptureState(string guid) {
        var en = (IMMDeviceEnumerator)(new MMDeviceEnumeratorComObject());
        IMMDeviceCollection col; en.EnumAudioEndpoints(1, 0x0F, out col);
        int n; col.GetCount(out n);
        for (int i = 0; i < n; i++) {
            IMMDevice d; col.Item(i, out d); string id; d.GetId(out id); int st; d.GetState(out st);
            if (id.ToLower().Contains(guid.ToLower())) return id + "|" + st;
        }
        return "";
    }
}
'@

$script:VoiceAccessExe = "$env:SystemRoot\System32\VoiceAccess.exe"
$script:AutoStartRegPath = "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Accessibility"
$script:AppRegPath = "HKCU:\Software\VoiceAccessTray"
$script:MicRegPath = "HKCU:\Software\Microsoft\VoiceAccess"
$script:MMCapturePath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture"
$script:MMRenderPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
$script:PKEY_Name = "{a45c254e-df1c-4efd-8020-67d146a850e0},2"
$script:PKEY_Desc = "{b3f8fa53-0004-438e-9003-51a46e139bfc},6"
$script:LogPath = Join-Path $env:LOCALAPPDATA "VoiceAccessTray\tray.log"

# ---- Tunables (previously scattered as magic numbers) ----
$script:LogMaxBytes             = 262144   # rotate tray.log above 256 KB
$script:AudioInterfaceGuid      = "{2eef81be-33fa-4800-9670-1cd474972c3f}"
$script:StereoMixPattern        = "Stereo Mix|What U Hear|Wave Out Mix|Mixage stéréo|Mixed Output|Stereo Mixer"
$script:StereoMixRetries        = 8        # SetEndpointVisibility is flaky (ERROR_NOT_FOUND)
$script:StereoMixPollMs         = 1000
$script:CommandModeAttempts     = 4
$script:CommandModeWaitSec      = 3
$script:StartVoiceAccessTimeoutMs = 30000
$script:StartVoiceAccessPollMs  = 500
$script:WakeAttempts            = 3
$script:WakeLoadingMaxSec       = 15
$script:HideDelaySec            = 5
$script:LogonDelayMs            = 4000
$script:StereoMixDesc           = $null    # description of the Stereo Mix endpoint in use (for render matching)

$script:autoRunning = $false
$script:notifyIcon  = $null

function Write-Log([string]$msg) {
    try {
        $dir = Split-Path -Parent $script:LogPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Simple rotation: keep one previous file once the log grows past the cap.
        if ((Test-Path $script:LogPath) -and ((Get-Item $script:LogPath).Length -gt $script:LogMaxBytes)) {
            Move-Item -Path $script:LogPath -Destination "$($script:LogPath).1" -Force -ErrorAction SilentlyContinue
        }
        ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
    } catch {}
}

# Sleep that keeps the WinForms message loop pumping so the tray menu stays responsive
# during the (long) startup sequence instead of freezing for ~40-60s.
function Wait-UI([int]$milliseconds) {
    $end = (Get-Date).AddMilliseconds($milliseconds)
    while ((Get-Date) -lt $end) {
        try { [System.Windows.Forms.Application]::DoEvents() } catch {}
        Start-Sleep -Milliseconds 50
    }
}

function Get-VoiceAccessState {
    $bars = [VEnum]::Find()
    if ($bars.Count -eq 0) { return $null }
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($bars[0])
        if ($el -eq $null) { return $null }
        $cond = { param($aid) New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $aid) }
        $mic = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $cond "MicrophoneButtonControl"))
        $speech = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $cond "SpeechTextBlock"))
        $mode = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $cond "RecognitionModeTextBlock"))
        if ($mic -eq $null -or $speech -eq $null) {
            return @{ Handle = $bars[0]; Readable = $false; ToggleKnown = $false; ModePresent = $false }
        }
        $micName = $mic.Current.Name
        $speechName = $speech.Current.Name
        $modeName = if ($mode) { $mode.Current.Name } else { "" }

        # Listening detection: use the definite (English) text when present - this preserves
        # the previously verified behaviour - and otherwise fall back to the microphone
        # button's ToggleState so it keeps working on a localized Windows.
        $toggleKnown = $false
        $listening = $false
        if (($speechName -match "Listening") -or ($micName -match "(?i)active")) {
            $listening = $true; $toggleKnown = $true
        } elseif (($speechName -match "(?i)sleep") -or ($micName -match "(?i)sleep")) {
            $listening = $false; $toggleKnown = $true
        } else {
            try {
                $tp = $mic.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern)
                $listening = ($tp.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On)
                $toggleKnown = $true
            } catch { $listening = $false; $toggleKnown = $false }
        }

        return @{
            Handle = $bars[0]; Readable = $true; Listening = [bool]$listening; ToggleKnown = $toggleKnown
            Mic = $micName; Speech = $speechName; Mode = $modeName; ModePresent = [bool]($mode -ne $null)
        }
    } catch { return $null }
}

function Invoke-HideVoiceBar {
    $windows = [VEnum]::Find()
    if ($windows.Count -eq 0) {
        if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Voice Access window not found. Is Voice Access running?", [System.Windows.Forms.ToolTipIcon]::Warning) }
        return $false
    }
    foreach ($h in $windows) {
        if (-not [VEnum]::IsWindow($h)) { continue }
        [ABar]::Remove($h) | Out-Null
        [VEnum]::ShowWindow($h, 0) | Out-Null
    }
    if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Bar hidden. Screen space is free. Voice Access keeps listening in the background.", [System.Windows.Forms.ToolTipIcon]::Info) }
    return $true
}

function Invoke-ShowVoiceBar {
    $windows = [VEnum]::Find()
    if ($windows.Count -eq 0) {
        if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Voice Access window not found. Is Voice Access running?", [System.Windows.Forms.ToolTipIcon]::Warning) }
        return $false
    }
    foreach ($h in $windows) {
        if (-not [VEnum]::IsWindow($h)) { continue }
        [VEnum]::ShowWindow($h, 5) | Out-Null  # SW_SHOW
    }
    if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Bar is visible again.", [System.Windows.Forms.ToolTipIcon]::Info) }
    return $true
}

function Invoke-StartVoiceAccess {
    $proc = Get-Process VoiceAccess -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Start-Process -FilePath $script:VoiceAccessExe
        Wait-UI 3000
    }
    # Wait for the bar and make sure it is visible
    $waited = 0
    while ($waited -lt $script:StartVoiceAccessTimeoutMs) {
        $bars = [VEnum]::Find()
        if ($bars.Count -gt 0) {
            foreach ($h in $bars) { [VEnum]::ShowWindow($h, 5) | Out-Null }
            return $true
        }
        Wait-UI $script:StartVoiceAccessPollMs
        $waited += $script:StartVoiceAccessPollMs
    }
    return $false
}

# ---- Helpers for the "Commands mode" injection via Stereo Mix ----

function Get-GuidFromEndpointId([string]$value) {
    if ([string]::IsNullOrEmpty($value)) { return $null }
    if ($value -match '\{0\.0\.1\.00000000\}\.\{([0-9a-fA-F\-]+)\}') { return $Matches[1] }
    if ($value -match '\{([0-9a-fA-F]{8}-[0-9a-fA-F\-]+)\}') { return $Matches[1] }
    return $null
}

# Builds the full device-interface path Voice Access expects, from a short MMDevice id
# ("{0.0.1.00000000}.{guid}") -> "\\?\SWD#MMDEVAPI#...#{interface}".
function New-EndpointInterfacePath([string]$shortId) {
    return "\\?\SWD#MMDEVAPI#$shortId#$($script:AudioInterfaceGuid)"
}

# Short id of the current default capture endpoint, or $null.
function Get-CaptureShortId {
    try { $id = [AudioPolicy]::GetDefaultCapture() } catch { Write-Log "Get-CaptureShortId error: $($_.Exception.Message)"; return $null }
    if ($id -and $id -match '\{0\.0\.1\.00000000\}\.\{[0-9a-fA-F\-]+\}') { return $Matches[0] }
    return $null
}

function Get-EndpointMenuName([string]$guid) {
    $p = "$script:MMCapturePath\{$guid}\Properties"
    $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if ($props -eq $null) { return $null }
    $nm = $props.$($script:PKEY_Name)
    $ds = $props.$($script:PKEY_Desc)
    if ($nm -and $ds) { return "$nm ($ds)" }
    if ($nm) { return $nm }
    return $null
}

function Get-EndpointName([string]$guid) {
    $p = "$script:MMCapturePath\{$guid}\Properties"
    $props = Get-ItemProperty -Path $p -ErrorAction SilentlyContinue
    if ($props -eq $null) { return $null }
    return $props.$($script:PKEY_Name)
}

function Get-StereoMixCandidates {
    # Capture endpoints that look like a stereo/system mixer and are present
    # (enabled or disabled, not unplugged/absent). Returns objects with Guid (no braces) + Desc + Name.
    $res = @()
    Get-ChildItem -Path $script:MMCapturePath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path "$($_.PSPath)\Properties" -ErrorAction SilentlyContinue
        $nm = $props.$($script:PKEY_Name)
        $ds = $props.$($script:PKEY_Desc)
        $st = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($nm -match $script:StereoMixPattern -and $st -ne $null -and (($st -band 0xF) -eq 1 -or ($st -band 0xF) -eq 2)) {
            $res += [pscustomobject]@{ Guid = ($_.PSChildName -replace '[{}]', ''); Desc = $ds; Name = $nm }
        }
    }
    return $res
}

function Get-InjectionRenderShortId {
    # The render endpoint Stereo Mix captures. Generic heuristic (no hardcoded brand):
    #   1) an active render endpoint whose name/description shares the Stereo Mix adapter wording,
    #   2) the current default render (if active), 3) the first active render.
    $renders = @()
    foreach ($k in (Get-ChildItem -Path $script:MMRenderPath -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -Path "$($k.PSPath)\Properties" -ErrorAction SilentlyContinue
        $nm = $props.$($script:PKEY_Name)
        $ds = $props.$($script:PKEY_Desc)
        $st = (Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue).DeviceState
        if (-not $nm -or $st -eq $null -or ($st -band 0xF) -ne 1) { continue }
        $renders += [pscustomobject]@{ Short = "{0.0.0.00000000}." + $k.PSChildName; Name = $nm; Desc = $ds }
    }
    if ($renders.Count -eq 0) { return $null }
    if ($script:StereoMixDesc) {
        $tok = ($script:StereoMixDesc -split '[^A-Za-z0-9]' | Where-Object { $_.Length -ge 4 } | Select-Object -First 1)
        if ($tok) {
            $m = $renders | Where-Object { "$($_.Desc) $($_.Name)" -like "*$tok*" } | Select-Object -First 1
            if ($m) { return $m.Short }
        }
    }
    try { $def = [AudioPolicy]::GetDefaultRender() } catch { $def = $null }
    if ($def) { $d = $renders | Where-Object { $_.Short -eq $def } | Select-Object -First 1; if ($d) { return $d.Short } }
    return $renders[0].Short
}

function Enable-StereoMix {
    # Enables the first usable Stereo-Mix capture endpoint. Returns @{ Guid; Short; Desc } or $null.
    # SetEndpointVisibility can fail transiently (ERROR_NOT_FOUND), so retry and log.
    foreach ($c in Get-StereoMixCandidates) {
        $id = "{0.0.1.00000000}.{$($c.Guid)}"
        for ($attempt = 1; $attempt -le $script:StereoMixRetries; $attempt++) {
            try { [AudioPolicy]::SetVisible($id, $true) | Out-Null }
            catch { Write-Log "Enable-StereoMix: SetVisible($($c.Guid)) error: $($_.Exception.Message)" }
            Wait-UI $script:StereoMixPollMs
            $s = [AudioPolicy]::CaptureState($c.Guid)
            if ($s -and ($s.Split('|')[1] -eq "1")) { return @{ Guid = $c.Guid; Short = $id; Desc = $c.Desc } }
        }
    }
    return $null
}

function Disable-StereoMix($guid) {
    if (-not $guid) { return }
    # Mirror Enable-StereoMix: SetEndpointVisibility can be flaky, so retry and confirm.
    $id = "{0.0.1.00000000}.{$guid}"
    for ($attempt = 1; $attempt -le $script:StereoMixRetries; $attempt++) {
        try { [AudioPolicy]::SetVisible($id, $false) | Out-Null }
        catch { Write-Log "Disable-StereoMix: SetVisible($guid) error: $($_.Exception.Message)" }
        Wait-UI $script:StereoMixPollMs
        $s = [AudioPolicy]::CaptureState($guid)
        if ($s -and (($s.Split('|')[1] -band 0xF) -eq 2)) { return }
    }
    Write-Log "Disable-StereoMix: could not confirm disabled state for $guid"
}

function Select-VoiceMic([string]$nameSub) {
    # Switches the Voice Access microphone LIVE via Settings > microphone menu (no restart).
    # That UIA popup is fragile, so the whole open/expand/match/toggle is retried a few rounds.
    # Plain Start-Sleep is used (not Wait-UI/DoEvents) so the popup is not dismissed mid-way.
    # Returns $true only if the toggle is verified to be On.
    $bars = [VEnum]::Find()
    if ($bars.Count -eq 0) { return $false }
    $aid = { param($id) New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $id) }
    $core = ("$nameSub" -split '\(')[0].Trim()
    for ($round = 1; $round -le 3; $round++) {
        try {
            $el = [System.Windows.Automation.AutomationElement]::FromHandle([VEnum]::Find()[0])
            if ($el -eq $null) { Start-Sleep -Milliseconds 800; continue }
            $root = [System.Windows.Automation.AutomationElement]::RootElement
            $sb = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $aid "SettingsButton"))
            if ($sb -eq $null) { Start-Sleep -Milliseconds 800; continue }
            $sb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            Start-Sleep -Milliseconds 1600
            $ml = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (& $aid "MicrophoneList"))
            if ($ml -eq $null) { [WakeKeys]::Esc(); Start-Sleep -Milliseconds 800; continue }
            $ml.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
            Start-Sleep -Milliseconds 1600
            # Match: exact full name, then the part before the first "(", then a contains match.
            $target = $null; $names = @()
            for ($t = 1; $t -le 6 -and $target -eq $null; $t++) {
                $items = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)))
                $names = @(); foreach ($m in $items) { $names += $m.Current.Name }
                foreach ($m in $items) { if ($m.Current.Name -ieq $nameSub) { $target = $m; break } }
                if ($target -eq $null -and $core) { foreach ($m in $items) { if ($m.Current.Name -ieq $core) { $target = $m; break } } }
                if ($target -eq $null -and $core) { foreach ($m in $items) { if ($m.Current.Name -like "*$core*") { $target = $m; break } } }
                if ($target -eq $null) { foreach ($m in $items) { if ($m.Current.Name -like "*$nameSub*") { $target = $m; break } } }
                if ($target -eq $null) { Start-Sleep -Milliseconds 500 }
            }
            if ($target -eq $null) { Write-Log "Select-VoiceMic: round $round no match for '$nameSub'. Candidates: $($names -join ' | ')"; [WakeKeys]::Esc(); Start-Sleep -Milliseconds 600; continue }
            $target.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
            Start-Sleep -Milliseconds 1800
            $on = $false
            try { $on = ($target.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) } catch {}
            if ($on) { return $true }
            Write-Log "Select-VoiceMic: round $round toggled but not confirmed On"
            [WakeKeys]::Esc(); Start-Sleep -Milliseconds 600
        } catch { Write-Log "Select-VoiceMic ERROR (round $round): $($_.Exception.Message)"; Start-Sleep -Milliseconds 600 }
    }
    return $false
}

function Invoke-CommandModeInjection {
    # Voice Access must already be running with the Stereo Mix microphone and be listening.
    # Speaks "Commands mode" via TTS and waits until the bar reports a mode element.
    $ok = $false
    $synth = $null
    $origRender = $null
    $renderChanged = $false
    try {
        $spk = Get-InjectionRenderShortId
        $origRender = [AudioPolicy]::GetDefaultRender()
        if ($spk -and $spk -ne $origRender) {
            [AudioPolicy]::SetDefault($spk) | Out-Null
            $renderChanged = $true
            Wait-UI 1200
        }
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Volume = 100
        $synth.Rate = 0
        for ($i = 0; $i -lt $script:CommandModeAttempts -and -not $ok; $i++) {
            $synth.Speak("Commands mode")
            Wait-UI ($script:CommandModeWaitSec * 1000)
            $state = Get-VoiceAccessState
            # Success = a non-default mode is active. Guard against the known English
            # misrecognition "Communication mode"; localized mode names pass on presence.
            if ($state -ne $null -and $state.Readable -and $state.ModePresent -and ($state.Mode -eq "Command mode" -or $state.Mode -notmatch '(?i)communicat')) { $ok = $true }
        }
    } catch {
        Write-Log "CommandModeInjection ERROR: $($_.Exception.Message)"
    } finally {
        if ($synth) { try { $synth.Dispose() } catch {} }
        if ($renderChanged) { try { [AudioPolicy]::SetDefault($origRender) | Out-Null } catch {} }
    }
    return $ok
}

function Invoke-WakeVoiceAccess {
    # Ensures Voice Access is listening (no need to say "wake up").
    # The bar must be VISIBLE to read its state, so show it first if needed.
    # Only sends the Alt+Shift+B toggle when confirmed asleep. Never toggles blindly.
    # A fresh start briefly shows "Loading..." - wait for it to resolve first.
    # Returns $true when listening, $false otherwise.
    for ($attempt = 1; $attempt -le $script:WakeAttempts; $attempt++) {
        $state = Get-VoiceAccessState
        if ($state -eq $null) { return $false }
        if (-not $state.Readable) {
            [VEnum]::ShowWindow($state.Handle, 5) | Out-Null
            Wait-UI 1500
            $state = Get-VoiceAccessState
            if ($state -eq $null -or -not $state.Readable) { return $false }
        }
        $waited = 0
        # Wait out the transient "Loading" state (locale-independent via ToggleKnown, English text as fallback).
        while ((-not $state.ToggleKnown -or $state.Speech -match "Loading") -and $waited -lt $script:WakeLoadingMaxSec) {
            Wait-UI 1000
            $waited++
            $state = Get-VoiceAccessState
            if ($state -eq $null -or -not $state.Readable) { return $false }
        }
        if ($state.Listening) { return $true }
        [WakeKeys]::AltShiftB()
        Wait-UI 3000
    }
    $state = Get-VoiceAccessState
    return ($state -ne $null -and $state.Readable -and $state.Listening)
}

function Invoke-AutoSetup {
    # Automatic startup sequence:
    #   1. (re)start Voice Access so it can temporarily use the Stereo Mix microphone
    #   2. wake it up (listening)
    #   3. enter Command mode by speaking "Commands mode" into Stereo Mix (digital, reliable)
    #   4. switch the microphone back to the real one (live, no restart) so the mode is kept
    #   5. wait ~5s   6. hide the bar
    # Guarded against re-entry and guaranteed to restore the audio state on ANY exit.
    if ($script:autoRunning) { Write-Log "AutoSetup: already running - ignored"; return }
    $script:autoRunning = $true
    $origMic = $null
    $origRender = $null
    $stereo = $null
    $switchFailed = $false
    try {
        Write-Log "AutoSetup: begin"
        $origMic = (Get-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -ErrorAction SilentlyContinue).VoiceAccessMicrophoneId
        if (-not $origMic) {
            $short = Get-CaptureShortId
            if ($short) { $origMic = New-EndpointInterfacePath $short; Write-Log "AutoSetup: registry mic missing; using default capture '$short'" }
        }
        Write-Log "AutoSetup: origMic=$origMic"
        if (-not $origMic) {
            Write-Log "AutoSetup: no microphone reference available - aborting"
            if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2500, "Voice Access", "Could not determine the original microphone. Startup sequence skipped.", [System.Windows.Forms.ToolTipIcon]::Warning) }
            return
        }
        $micGuid = Get-GuidFromEndpointId $origMic
        try { $origRender = [AudioPolicy]::GetDefaultRender() } catch { $origRender = $null }

        # 1. stop Voice Access so it starts with the Stereo Mix microphone
        Get-Process VoiceAccess -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Wait-UI 2000

        # enable Stereo Mix and point Voice Access at it before it starts
        $stereo = Enable-StereoMix
        $script:StereoMixDesc = if ($stereo) { $stereo.Desc } else { $null }
        Write-Log "AutoSetup: stereo=$($stereo.Guid)"
        if ($stereo -ne $null) {
            $stereoFull = New-EndpointInterfacePath ("{0.0.1.00000000}.{$($stereo.Guid)}")
            Set-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -Value $stereoFull -Type String -ErrorAction SilentlyContinue
            Write-Log "AutoSetup: mic set to $stereoFull"
        }

        if (-not (Invoke-StartVoiceAccess)) {
            Write-Log "AutoSetup: could not start Voice Access"
            if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Could not start Voice Access.", [System.Windows.Forms.ToolTipIcon]::Warning) }
            return
        }
        Wait-UI 2000

        # 2. wake up (listening)
        $awake = Invoke-WakeVoiceAccess
        Write-Log "AutoSetup: awake=$awake"

        # 3. Command mode (only possible while Voice Access listens to Stereo Mix)
        $modeOk = $false
        if ($stereo -ne $null) {
            $modeOk = Invoke-CommandModeInjection
            Write-Log "AutoSetup: modeOk=$modeOk"
            # 4. switch the microphone back to the real one (live, keeps Command mode)
            $menuName = if ($micGuid) { Get-EndpointMenuName $micGuid } else { $null }
            Write-Log "AutoSetup: switch back to '$menuName'"
            $switched = $false
            if ($menuName) { $switched = Select-VoiceMic $menuName }
            if (-not $switched) {
                $micName = if ($micGuid) { Get-EndpointName $micGuid } else { $null }
                if ($micName) { $switched = Select-VoiceMic $micName }
            }
            Write-Log "AutoSetup: switched=$switched"
            if (-not $switched) {
                $switchFailed = $true
                if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(3000, "Voice Access", "Could not switch the microphone back automatically. Please pick your microphone in Voice Access settings.", [System.Windows.Forms.ToolTipIcon]::Warning) }
            }
        }

        if (-not $awake) {
            if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Could not confirm listening state. Hiding the bar in $($script:HideDelaySec) seconds anyway...", [System.Windows.Forms.ToolTipIcon]::Warning) }
        } elseif ($modeOk) {
            if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Command mode is active (listening with your real microphone). Hiding the bar in $($script:HideDelaySec) seconds...", [System.Windows.Forms.ToolTipIcon]::Info) }
        } else {
            if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(3000, "Voice Access", "Listening in default mode (Command mode injection unavailable on this system). Hiding the bar in $($script:HideDelaySec) seconds...", [System.Windows.Forms.ToolTipIcon]::Info) }
        }

        # 5. wait, 6. hide the bar
        Wait-UI ($script:HideDelaySec * 1000)
        Write-Log "AutoSetup: hiding bar"
        Invoke-HideVoiceBar | Out-Null
        Write-Log "AutoSetup: done"
    } catch {
        Write-Log "AutoSetup ERROR: $($_.Exception.Message)"
        if ($script:notifyIcon) { $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Auto-setup error: $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error) }
    } finally {
        # Fail-safe: always restore the audio state, even on early return/exception,
        # so Voice Access is never left pointing at a disabled Stereo Mix device.
        try { if ($origMic) { Set-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -Value $origMic -Type String -ErrorAction SilentlyContinue; Write-Log "AutoSetup: restored microphone registry" } } catch {}
        try { if ($origRender) { [AudioPolicy]::SetDefault($origRender) | Out-Null; Write-Log "AutoSetup: restored default playback" } } catch {}
        try { if ($stereo) { Disable-StereoMix $stereo.Guid; Write-Log "AutoSetup: disabled Stereo Mix" } } catch {}
        # Safety net: if the live microphone switch failed, Voice Access would stay on the (now
        # disabled) Stereo Mix and be deaf. Restart it on the real microphone so it keeps working
        # (in default mode - Command mode is lost, but the microphone is usable again).
        try {
            if ($switchFailed) {
                Write-Log "AutoSetup: microphone switch failed - restarting Voice Access on the real microphone"
                Get-Process VoiceAccess -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Wait-UI 2000
                if (Invoke-StartVoiceAccess) { Wait-UI 3000; Invoke-HideVoiceBar | Out-Null }
                Write-Log "AutoSetup: fallback restart done"
            }
        } catch {}
        $script:StereoMixDesc = $null
        $script:autoRunning = $false
    }
}

function Get-WindowsAutoStart {
    try {
        $v = (Get-ItemProperty -Path $script:AutoStartRegPath -Name "Configuration" -ErrorAction Stop).Configuration
        return ($v -eq "voiceaccess")
    } catch { return $false }
}

function Set-WindowsAutoStart([bool]$enable) {
    New-Item -Path $script:AutoStartRegPath -Force | Out-Null
    if ($enable) {
        Set-ItemProperty -Path $script:AutoStartRegPath -Name "Configuration" -Value "voiceaccess"
    } else {
        Remove-ItemProperty -Path $script:AutoStartRegPath -Name "Configuration" -ErrorAction SilentlyContinue
    }
}

function Get-AutoSetup {
    # ON by default. Persisted in HKCU so the tray checkbox survives reboots.
    try {
        $v = (Get-ItemProperty -Path $script:AppRegPath -Name "AutoSetup" -ErrorAction Stop).AutoSetup
        return ($v -ne 0)
    } catch {
        New-Item -Path $script:AppRegPath -Force | Out-Null
        Set-ItemProperty -Path $script:AppRegPath -Name "AutoSetup" -Value 1
        return $true
    }
}

function Set-AutoSetup([bool]$enable) {
    New-Item -Path $script:AppRegPath -Force | Out-Null
    Set-ItemProperty -Path $script:AppRegPath -Name "AutoSetup" -Value ([int]$enable)
}

# ---- Single instance (prevents the documented "tray instances pile up" issue) ----
$script:singleInstance = New-Object System.Threading.Mutex($false, "Local\VoiceAccessTray")
$script:haveInstance = $false
try { $script:haveInstance = $script:singleInstance.WaitOne(0) }
catch [System.Threading.AbandonedMutexException] { $script:haveInstance = $true }
if (-not $script:haveInstance) {
    Write-Log "Another VoiceAccessTray instance is already running - exiting"
    exit
}

# ---- Tray icon (Voice Access icon, with fallback) ----
$script:notifyIcon = New-Object System.Windows.Forms.NotifyIcon
try {
    $script:notifyIcon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($script:VoiceAccessExe)
} catch {
    $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application
}
if ($script:notifyIcon.Icon -eq $null) { $script:notifyIcon.Icon = [System.Drawing.SystemIcons]::Application }
$script:notifyIcon.Text = "Voice Access Bar Control"
$script:notifyIcon.Visible = $true

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuHide = $contextMenu.Items.Add("Hide Voice Access bar")
$menuShow = $contextMenu.Items.Add("Show Voice Access bar")
$menuStart = $contextMenu.Items.Add("Start Voice Access")
$menuWake = $contextMenu.Items.Add("Wake up (start listening)")
$menuAutoNow = $contextMenu.Items.Add("Run startup sequence now (wake up, Command mode, hide)")
$contextMenu.Items.Add("-") | Out-Null
$menuAutoSetup = $contextMenu.Items.Add("Startup sequence at logon (wake up, Command mode, hide)")
$menuAutoSetup.CheckOnClick = $true
$menuAutoSetup.Checked = Get-AutoSetup
$menuAutoStart = $contextMenu.Items.Add("Start automatically with Windows")
$menuAutoStart.CheckOnClick = $true
$menuAutoStart.Checked = Get-WindowsAutoStart
$contextMenu.Items.Add("-") | Out-Null
# "Uninstall" entry - only shown when the uninstaller sits next to this script (i.e. installed via the setup .exe).
$script:uninstallerPath = Join-Path $PSScriptRoot "VoiceAccessTrayUninstall.exe"
if (Test-Path $script:uninstallerPath) {
    $menuUninstall = $contextMenu.Items.Add("Uninstall Voice Access Bar Control...")
    $menuUninstall.Add_Click({ Start-Process -FilePath $script:uninstallerPath })
}
$menuExit = $contextMenu.Items.Add("Exit")

$menuHide.Add_Click({ Invoke-HideVoiceBar | Out-Null })
$menuShow.Add_Click({ Invoke-ShowVoiceBar | Out-Null })
$menuStart.Add_Click({
    if (Invoke-StartVoiceAccess) {
        $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Voice Access started and visible.", [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Could not start Voice Access.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$menuWake.Add_Click({
    if (Invoke-WakeVoiceAccess) {
        $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Voice Access is listening.", [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Voice Access is still asleep. Try again or click the mic button.", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})
$menuAutoNow.Add_Click({ Invoke-AutoSetup })
$menuAutoSetup.Add_Click({
    Set-AutoSetup $menuAutoSetup.Checked
    $msg = if ($menuAutoSetup.Checked) { "Startup sequence enabled (wake up, Command mode, hide at logon)." } else { "Startup sequence disabled." }
    $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", $msg, [System.Windows.Forms.ToolTipIcon]::Info)
})
$menuAutoStart.Add_Click({
    Set-WindowsAutoStart $menuAutoStart.Checked
    $msg = if ($menuAutoStart.Checked) { "Voice Access will start automatically after sign-in." } else { "Automatic start disabled." }
    $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", $msg, [System.Windows.Forms.ToolTipIcon]::Info)
})
$menuExit.Add_Click({
    $script:notifyIcon.Visible = $false
    $script:notifyIcon.Dispose()
    try { $script:singleInstance.ReleaseMutex() } catch {}
    [System.Windows.Forms.Application]::Exit()
})

$script:notifyIcon.ContextMenuStrip = $contextMenu
$script:notifyIcon.add_DoubleClick({ Invoke-HideVoiceBar | Out-Null })

Write-Log "VoiceAccessTray started (AutoHide=$AutoHide)"

if ($AutoHide -and (Get-AutoSetup)) {
    # Launched at logon and the automatic sequence is enabled:
    # let the desktop settle, then run it once.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = $script:LogonDelayMs
    $timer.Add_Tick({
        $timer.Stop()
        $timer.Dispose()
        Invoke-AutoSetup
    })
    $timer.Start()
}

[System.Windows.Forms.Application]::Run()
