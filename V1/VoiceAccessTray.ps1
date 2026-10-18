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

function Write-Log([string]$msg) {
    try {
        $dir = Split-Path -Parent $script:LogPath
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        ("[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg) | Out-File -FilePath $script:LogPath -Append -Encoding UTF8
    } catch {}
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
        if ($mic -eq $null -or $speech -eq $null) { return @{ Handle = $bars[0]; Readable = $false } }
        $micName = $mic.Current.Name
        $speechName = $speech.Current.Name
        $modeName = if ($mode) { $mode.Current.Name } else { "" }
        $listening = ($speechName -match "Listening") -or ($micName -match "active")
        return @{ Handle = $bars[0]; Readable = $true; Listening = [bool]$listening; Mic = $micName; Speech = $speechName; Mode = $modeName }
    } catch { return $null }
}

function Invoke-HideVoiceBar {
    $windows = [VEnum]::Find()
    if ($windows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Voice Access window not found. Is Voice Access running?", "Voice Access", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    foreach ($h in $windows) {
        if (-not [VEnum]::IsWindow($h)) { continue }
        [ABar]::Remove($h) | Out-Null
        [VEnum]::ShowWindow($h, 0) | Out-Null
    }
    $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Bar hidden. Screen space is free. Voice Access keeps listening in the background.", [System.Windows.Forms.ToolTipIcon]::Info)
    return $true
}

function Invoke-ShowVoiceBar {
    $windows = [VEnum]::Find()
    if ($windows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Voice Access window not found. Is Voice Access running?", "Voice Access", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return $false
    }
    foreach ($h in $windows) {
        if (-not [VEnum]::IsWindow($h)) { continue }
        [VEnum]::ShowWindow($h, 5) | Out-Null  # SW_SHOW
    }
    $script:notifyIcon.ShowBalloonTip(1500, "Voice Access", "Bar is visible again.", [System.Windows.Forms.ToolTipIcon]::Info)
    return $true
}

function Invoke-StartVoiceAccess {
    $proc = Get-Process VoiceAccess -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Start-Process -FilePath $script:VoiceAccessExe
        Start-Sleep -Seconds 3
    }
    # Wait for the bar (up to 30s) and make sure it is visible
    for ($i = 0; $i -lt 60; $i++) {
        $bars = [VEnum]::Find()
        if ($bars.Count -gt 0) {
            foreach ($h in $bars) { [VEnum]::ShowWindow($h, 5) | Out-Null }
            return $true
        }
        Start-Sleep -Milliseconds 500
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

function Get-StereoMixCandidates {
    # Capture endpoints named "Stereo Mix" that are present (enabled or disabled, not unplugged/absent).
    # Returns GUIDs WITHOUT braces.
    $res = @()
    Get-ChildItem -Path $script:MMCapturePath -ErrorAction SilentlyContinue | ForEach-Object {
        $props = Get-ItemProperty -Path "$($_.PSPath)\Properties" -ErrorAction SilentlyContinue
        $nm = $props.$($script:PKEY_Name)
        $st = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($nm -match "Stereo Mix" -and $st -ne $null -and (($st -band 0xF) -eq 1 -or ($st -band 0xF) -eq 2)) {
            $res += ($_.PSChildName -replace '[{}]', '')
        }
    }
    return $res
}

function Get-RealtekRenderShortId {
    # First active Realtek playback endpoint (Stereo Mix captures the Realtek output).
    foreach ($k in (Get-ChildItem -Path $script:MMRenderPath -ErrorAction SilentlyContinue)) {
        $props = Get-ItemProperty -Path "$($k.PSPath)\Properties" -ErrorAction SilentlyContinue
        $nm = $props.$($script:PKEY_Name)
        $ds = $props.$($script:PKEY_Desc)
        $st = (Get-ItemProperty -Path $k.PSPath -ErrorAction SilentlyContinue).DeviceState
        if ($nm -and $ds -like "*Realtek*" -and $st -ne $null -and ($st -band 0xF) -eq 1) {
            return "{0.0.0.00000000}." + $k.PSChildName
        }
    }
    return $null
}

function Enable-StereoMix {
    # Enables the first usable "Stereo Mix" capture endpoint. Returns @{ Guid; Short } or $null.
    # SetEndpointVisibility can fail transiently (ERROR_NOT_FOUND), so retry.
    foreach ($g in Get-StereoMixCandidates) {
        $id = "{0.0.1.00000000}.{$g}"
        for ($attempt = 0; $attempt -lt 8; $attempt++) {
            try { [AudioPolicy]::SetVisible($id, $true) | Out-Null } catch {}
            Start-Sleep -Milliseconds 1000
            $s = [AudioPolicy]::CaptureState($g)
            if ($s -and ($s.Split('|')[1] -eq "1")) { return @{ Guid = $g; Short = $id } }
        }
    }
    return $null
}

function Disable-StereoMix($guid) {
    if ($guid) { try { [AudioPolicy]::SetVisible("{0.0.1.00000000}.{$guid}", $false) | Out-Null } catch {} }
}

function Select-VoiceMic([string]$nameSub) {
    # Switches Voice Access microphone LIVE through its Settings > microphone menu (no restart).
    $bars = [VEnum]::Find()
    if ($bars.Count -eq 0) { return $false }
    try {
        $el = [System.Windows.Automation.AutomationElement]::FromHandle($bars[0])
        $root = [System.Windows.Automation.AutomationElement]::RootElement
        $sb = $el.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "SettingsButton")))
        if ($sb -eq $null) { return $false }
        $sb.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Start-Sleep -Milliseconds 1400
        $ml = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, "MicrophoneList")))
        if ($ml -eq $null) { [WakeKeys]::Esc(); return $false }
        $ml.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 1400
        $items = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem)))
        $target = $null
        foreach ($m in $items) { if ($m.Current.Name -like "*$nameSub*") { $target = $m; break } }
        if ($target -eq $null) { [WakeKeys]::Esc(); return $false }
        $target.GetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern).Toggle()
        Start-Sleep -Seconds 2
        return $true
    } catch { return $false }
}

function Invoke-CommandModeInjection {
    # Voice Access must already be running with the Stereo Mix microphone and be listening.
    # Speaks "Commands mode" via TTS and waits until the bar shows Command mode.
    $ok = $false
    $origRender = $null
    $renderChanged = $false
    try {
        $spk = Get-RealtekRenderShortId
        $origRender = [AudioPolicy]::GetDefaultRender()
        if ($spk -and $spk -ne $origRender) {
            [AudioPolicy]::SetDefault($spk) | Out-Null
            $renderChanged = $true
            Start-Sleep -Milliseconds 1200
        }
        $synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $synth.Volume = 100
        $synth.Rate = 0
        for ($i = 0; $i -lt 4 -and -not $ok; $i++) {
            $synth.Speak("Commands mode")
            Start-Sleep -Seconds 3
            $state = Get-VoiceAccessState
            if ($state -ne $null -and $state.Readable -and $state.Mode -eq "Command mode") { $ok = $true }
        }
        $synth.Dispose()
    } catch {
    } finally {
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
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        $state = Get-VoiceAccessState
        if ($state -eq $null) { return $false }
        if (-not $state.Readable) {
            [VEnum]::ShowWindow($state.Handle, 5) | Out-Null
            Start-Sleep -Milliseconds 1500
            $state = Get-VoiceAccessState
            if ($state -eq $null -or -not $state.Readable) { return $false }
        }
        $waited = 0
        while ($state.Speech -match "Loading" -and $waited -lt 15) {
            Start-Sleep -Seconds 1
            $waited++
            $state = Get-VoiceAccessState
            if ($state -eq $null -or -not $state.Readable) { return $false }
        }
        if ($state.Listening) { return $true }
        [WakeKeys]::AltShiftB()
        Start-Sleep -Seconds 3
    }
    $state = Get-VoiceAccessState
    return ($state -ne $null -and $state.Readable -and $state.Listening -and -not ($state.Speech -match "Loading"))
}

function Invoke-AutoSetup {
    # Automatic startup sequence:
    #   1. (re)start Voice Access so it can temporarily use the Stereo Mix microphone
    #   2. wake it up (listening)
    #   3. enter Command mode by speaking "Commands mode" into Stereo Mix (digital, reliable)
    #   4. switch the microphone back to the real one (live, no restart) so the mode is kept
    #   5. wait ~5s   6. hide the bar
    try {
        Write-Log "AutoSetup: begin"
        $origMic = (Get-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -ErrorAction SilentlyContinue).VoiceAccessMicrophoneId
        Write-Log "AutoSetup: origMic=$origMic"

        # 1. stop Voice Access so it starts with the Stereo Mix microphone
        Get-Process VoiceAccess -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        # enable Stereo Mix and point Voice Access at it before it starts
        $stereo = Enable-StereoMix
        Write-Log "AutoSetup: stereo=$($stereo.Guid)"
        if ($stereo -ne $null -and $origMic) {
            $stereoFull = $origMic -replace '(\{0\.0\.1\.00000000\}\.)\{[0-9a-fA-F\-]+\}', "`$1{$($stereo.Guid)}"
            Set-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -Value $stereoFull -Type String -ErrorAction SilentlyContinue
            Write-Log "AutoSetup: mic set to $stereoFull"
        }

        if (-not (Invoke-StartVoiceAccess)) {
            Write-Log "AutoSetup: could not start Voice Access"
            $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Could not start Voice Access.", [System.Windows.Forms.ToolTipIcon]::Warning)
            return
        }
        Start-Sleep -Seconds 2

        # 2. wake up (listening)
        $awake = Invoke-WakeVoiceAccess
        Write-Log "AutoSetup: awake=$awake"

        # 3. Command mode (only possible while Voice Access listens to Stereo Mix)
        $modeOk = $false
        if ($stereo -ne $null) {
            $modeOk = Invoke-CommandModeInjection
            Write-Log "AutoSetup: modeOk=$modeOk"
            # 4. switch the microphone back to the real one (live, keeps Command mode)
            $origGuid = Get-GuidFromEndpointId $origMic
            $menuName = if ($origGuid) { Get-EndpointMenuName $origGuid } else { $null }
            Write-Log "AutoSetup: switch back to '$menuName'"
            $switched = $false
            if ($menuName) { $switched = Select-VoiceMic $menuName }
            if (-not $switched) { $switched = Select-VoiceMic "Microphone Array" }
            Write-Log "AutoSetup: switched=$switched"
            if ($origMic) { Set-ItemProperty -Path $script:MicRegPath -Name "VoiceAccessMicrophoneId" -Value $origMic -Type String -ErrorAction SilentlyContinue }
            Disable-StereoMix $stereo.Guid
            if (-not $switched) {
                $script:notifyIcon.ShowBalloonTip(3000, "Voice Access", "Could not switch the microphone back automatically. Please pick your microphone in Voice Access settings.", [System.Windows.Forms.ToolTipIcon]::Warning)
            }
        }

        if (-not $awake) {
            $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Could not confirm listening state. Hiding the bar in 5 seconds anyway...", [System.Windows.Forms.ToolTipIcon]::Warning)
        } elseif ($modeOk) {
            $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Command mode is active (listening with your real microphone). Hiding the bar in 5 seconds...", [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            $script:notifyIcon.ShowBalloonTip(3000, "Voice Access", "Listening in default mode (Command mode injection unavailable on this system). Hiding the bar in 5 seconds...", [System.Windows.Forms.ToolTipIcon]::Info)
        }

        # 5. wait 5 seconds, 6. hide the bar
        Start-Sleep -Seconds 5
        Write-Log "AutoSetup: hiding bar"
        Invoke-HideVoiceBar | Out-Null
        Write-Log "AutoSetup: done"
    } catch {
        Write-Log "AutoSetup ERROR: $($_.Exception.Message)"
        $script:notifyIcon.ShowBalloonTip(2000, "Voice Access", "Auto-setup error: $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error)
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
        Set-ItemProperty -Path $script:AutoStartRegPath -Name "Configuration" -Value ""
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
    [System.Windows.Forms.Application]::Exit()
})

$script:notifyIcon.ContextMenuStrip = $contextMenu
$script:notifyIcon.add_DoubleClick({ Invoke-HideVoiceBar | Out-Null })

if ($AutoHide -and (Get-AutoSetup)) {
    # Launched at logon and the automatic sequence is enabled:
    # let the desktop settle, then run it once.
    $timer = New-Object System.Windows.Forms.Timer
    $timer.Interval = 4000
    $timer.Add_Tick({
        $timer.Stop()
        $timer.Dispose()
        Invoke-AutoSetup
    })
    $timer.Start()
}

[System.Windows.Forms.Application]::Run()
