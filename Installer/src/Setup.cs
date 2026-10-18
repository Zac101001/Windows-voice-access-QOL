// Voice Access Bar Control - Setup
// Standalone WinForms installer. Embeds VoiceAccessTray.ps1 and VoiceAccessTrayUninstall.exe.
// Builds with:
//   csc /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll
//       /resource:payload\VoiceAccessTray.ps1,VoiceAccessTray.ps1
//       /resource:dist\VoiceAccessTrayUninstall.exe,VoiceAccessTrayUninstall.exe
//       src\Setup.cs
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Text;
using System.Windows.Forms;
using Microsoft.Win32;

static class Program
{
    const string TaskName = "VoiceAccessTray";
    const string AppName  = "Voice Access Bar Control";
    const string Version  = "2.0";

    static string InstallDir
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "VoiceAccessTray"); }
    }
    static string ScriptPath { get { return Path.Combine(InstallDir, "VoiceAccessTray.ps1"); } }
    static string UninstPath { get { return Path.Combine(InstallDir, "VoiceAccessTrayUninstall.exe"); } }

    [STAThread]
    static void Main(string[] args)
    {
        bool silent    = HasFlag(args, "-silent");
        bool uninstall = HasFlag(args, "-uninstall");
        try
        {
            if (!IsAdmin()) { RelaunchElevated(args); return; }

            if (uninstall) { LaunchUninstaller(true); return; }
            if (silent)    { Install(); return; }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }
        catch (Exception ex)
        {
            MessageBox.Show("Setup error: " + ex.Message, AppName + " - Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    // ---- Install ----
    public static void Install()
    {
        Directory.CreateDirectory(InstallDir);
        ExtractResource("VoiceAccessTray.ps1", ScriptPath);
        ExtractResource("VoiceAccessTrayUninstall.exe", UninstPath);

        CreateTask();

        // Default preference: logon sequence ON (the tray creates this too, but set it explicitly).
        using (RegistryKey k = Registry.CurrentUser.CreateSubKey(@"Software\VoiceAccessTray"))
            if (k.GetValue("AutoSetup") == null) k.SetValue("AutoSetup", 1, RegistryValueKind.DWord);

        CreateShortcuts();
        WriteUninstallEntry();

        // Stop any running tray first: the single-instance mutex would otherwise block the new one.
        StopRunningTray();

        // Start it right now as well.
        Run("schtasks.exe", "/Run /TN \"" + TaskName + "\"", false);
    }

    static void StopRunningTray()
    {
        string ps = Path.Combine(Path.GetTempPath(), "vat-kill-tray-setup.ps1");
        File.WriteAllText(ps,
            "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | " +
            "Where-Object { $_.CommandLine -like '*VoiceAccessTray.ps1*' } | " +
            "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }");
        Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\"", false);
        try { File.Delete(ps); } catch { }
        System.Threading.Thread.Sleep(1500);
    }

    public static void LaunchUninstaller(bool fallbackMessage)
    {
        if (File.Exists(UninstPath))
        {
            Process.Start(new ProcessStartInfo(UninstPath) { UseShellExecute = true });
        }
        else if (fallbackMessage)
        {
            MessageBox.Show("The uninstaller was not found. " + AppName + " does not look installed to " + InstallDir + ".",
                AppName + " - Setup", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
    }

    static void CreateTask()
    {
        string user = WindowsIdentity.GetCurrent().Name;
        string xml =
            "<?xml version=\"1.0\" encoding=\"UTF-16\"?>\r\n" +
            "<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">\r\n" +
            "  <RegistrationInfo><Description>" + AppName + " - applies Command mode and hides the bar at logon.</Description></RegistrationInfo>\r\n" +
            "  <Triggers><LogonTrigger><Enabled>true</Enabled><UserId>" + Xml(user) + "</UserId></LogonTrigger></Triggers>\r\n" +
            "  <Principals><Principal id=\"Author\"><UserId>" + Xml(user) + "</UserId><LogonType>InteractiveToken</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>\r\n" +
            "  <Settings>\r\n" +
            "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\r\n" +
            "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\r\n" +
            "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\r\n" +
            "    <AllowHardTerminate>true</AllowHardTerminate>\r\n" +
            "    <StartWhenAvailable>true</StartWhenAvailable>\r\n" +
            "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\r\n" +
            "    <Enabled>true</Enabled>\r\n" +
            "  </Settings>\r\n" +
            "  <Actions Context=\"Author\"><Exec>\r\n" +
            "    <Command>powershell.exe</Command>\r\n" +
            "    <Arguments>-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + Xml(ScriptPath) + "\" -AutoHide</Arguments>\r\n" +
            "  </Exec></Actions>\r\n" +
            "</Task>\r\n";

        string tmp = Path.Combine(Path.GetTempPath(), "VoiceAccessTrayTask.xml");
        File.WriteAllText(tmp, xml, Encoding.Unicode);
        Run("schtasks.exe", "/Create /TN \"" + TaskName + "\" /XML \"" + tmp + "\" /F", true);
        try { File.Delete(tmp); } catch { }
    }

    static void CreateShortcuts()
    {
        string startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu), "Programs", AppName);
        Directory.CreateDirectory(startMenu);

        CreateShortcut(Path.Combine(startMenu, AppName + ".lnk"),
            "powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + ScriptPath + "\" -AutoHide",
            InstallDir, AppName + " - start the tray (Voice Access bar control)");

        CreateShortcut(Path.Combine(startMenu, "Uninstall " + AppName + ".lnk"),
            UninstPath, "", InstallDir, "Uninstall " + AppName);
    }

    static void CreateShortcut(string lnk, string target, string arguments, string workdir, string description)
    {
        Type t = Type.GetTypeFromProgID("WScript.Shell");
        if (t == null) return;
        object shell = Activator.CreateInstance(t);
        object sc = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { lnk });
        Type sct = sc.GetType();
        sct.InvokeMember("TargetPath",       BindingFlags.SetProperty, null, sc, new object[] { target });
        sct.InvokeMember("Arguments",        BindingFlags.SetProperty, null, sc, new object[] { arguments });
        sct.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, sc, new object[] { workdir });
        sct.InvokeMember("Description",      BindingFlags.SetProperty, null, sc, new object[] { description });
        sct.InvokeMember("Save",             BindingFlags.InvokeMethod, null, sc, null);
    }

    static void WriteUninstallEntry()
    {
        using (RegistryKey k = Registry.LocalMachine.CreateSubKey(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VoiceAccessTray"))
        {
            k.SetValue("DisplayName", AppName);
            k.SetValue("DisplayVersion", Version);
            k.SetValue("Publisher", "ZAC");
            k.SetValue("DisplayIcon", UninstPath);
            k.SetValue("InstallLocation", InstallDir);
            k.SetValue("UninstallString", "\"" + UninstPath + "\"");
            k.SetValue("NoModify", 1, RegistryValueKind.DWord);
            k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
        }
    }

    // ---- helpers ----
    static void ExtractResource(string name, string dest)
    {
        Assembly asm = Assembly.GetExecutingAssembly();
        string full = null;
        foreach (string n in asm.GetManifestResourceNames())
            if (n.EndsWith(name, StringComparison.OrdinalIgnoreCase)) { full = n; break; }
        if (full == null) throw new Exception("Embedded resource not found: " + name);
        using (Stream s = asm.GetManifestResourceStream(full))
        using (FileStream f = File.Create(dest))
            s.CopyTo(f);
    }

    static string Xml(string s)
    {
        return s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;");
    }

    static bool HasFlag(string[] args, string flag)
    {
        foreach (string a in args) if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    static bool IsAdmin()
    {
        using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
    }

    static void RelaunchElevated(string[] args)
    {
        ProcessStartInfo psi = new ProcessStartInfo(Application.ExecutablePath);
        psi.UseShellExecute = true;
        psi.Verb = "runas";
        if (args != null && args.Length > 0) psi.Arguments = string.Join(" ", args);
        Process.Start(psi);
    }

    static int Run(string file, string args, bool throwOnFail)
    {
        ProcessStartInfo psi = new ProcessStartInfo(file, args);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.RedirectStandardOutput = true;
        psi.RedirectStandardError = true;
        Process p = Process.Start(psi);
        string err = p.StandardError.ReadToEnd();
        p.WaitForExit();
        if (throwOnFail && p.ExitCode != 0) throw new Exception(file + " failed (exit " + p.ExitCode + "): " + err);
        return p.ExitCode;
    }
}

class SetupForm : Form
{
    Label  status;
    Button btnInstall, btnUninstall, btnClose;

    public SetupForm()
    {
        Text = AppName2() + " - Setup";
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        MinimizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        ClientSize = new Size(470, 230);
        Font = new Font("Segoe UI", 9f);

        Label title = new Label();
        title.Text = "Voice Access Bar Control";
        title.Font = new Font("Segoe UI", 13f, FontStyle.Bold);
        title.SetBounds(18, 15, 430, 30);
        Controls.Add(title);

        Label info = new Label();
        info.Text = "Installs the tray app, registers the logon task (wake up, Command mode, hide)\n" +
                    "and creates Start-menu shortcuts, including an uninstaller and an entry in\n" +
                    "Windows Settings > Apps.";
        info.SetBounds(20, 52, 430, 60);
        Controls.Add(info);

        btnInstall = new Button();
        btnInstall.Text = "Install";
        btnInstall.SetBounds(20, 130, 140, 36);
        btnInstall.Click += new EventHandler(OnInstall);
        Controls.Add(btnInstall);

        btnUninstall = new Button();
        btnUninstall.Text = "Uninstall";
        btnUninstall.SetBounds(170, 130, 140, 36);
        btnUninstall.Click += new EventHandler(OnUninstall);
        Controls.Add(btnUninstall);

        btnClose = new Button();
        btnClose.Text = "Close";
        btnClose.SetBounds(320, 130, 130, 36);
        btnClose.Click += new EventHandler(delegate(object s, EventArgs e) { Close(); });
        Controls.Add(btnClose);

        status = new Label();
        status.SetBounds(20, 178, 430, 40);
        status.ForeColor = Color.DimGray;
        status.Text = "Ready. Install requires Administrator (this window is already elevated).";
        Controls.Add(status);
    }

    static string AppName2() { return "Voice Access Bar Control"; }

    void OnInstall(object sender, EventArgs e)
    {
        try
        {
            status.Text = "Installing...";
            status.Refresh();
            Program.Install();
            status.Text = "Installed to " + Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles) + "\\VoiceAccessTray. The tray is running; the logon task is set.";
        }
        catch (Exception ex)
        {
            status.Text = "Install failed: " + ex.Message;
            MessageBox.Show("Install failed: " + ex.Message, "Setup", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    void OnUninstall(object sender, EventArgs e)
    {
        Program.LaunchUninstaller(true);
        Close();
    }
}
