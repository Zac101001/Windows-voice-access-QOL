// Voice Access Bar Control - Uninstaller
// Standalone WinForms .exe. Removes the scheduled task, installed files, shortcuts,
// the "Apps & features" entry, preferences and the log folder.
// Builds with: csc /target:winexe /r:System.Windows.Forms.dll
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Principal;
using System.Windows.Forms;
using Microsoft.Win32;

static class Program
{
    const string TaskName = "VoiceAccessTray";
    const string AppName  = "Voice Access Bar Control";

    static string InstallDir
    {
        get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "VoiceAccessTray"); }
    }

    [STAThread]
    static void Main(string[] args)
    {
        bool quiet = HasFlag(args, "-quiet");
        try
        {
            string exe = Assembly.GetExecutingAssembly().Location;
            string exeDir = Path.GetDirectoryName(exe);

            // If we run from the install dir, copy ourselves to %TEMP% and relaunch there,
            // so the install dir (this exe included) can be deleted cleanly.
            if (SameDir(exeDir, InstallDir))
            {
                string tmp = Path.Combine(Path.GetTempPath(), "VoiceAccessTrayUninstallTemp.exe");
                File.Copy(exe, tmp, true);
                ProcessStartInfo psi = new ProcessStartInfo(tmp);
                psi.UseShellExecute = true;
                psi.Arguments = "-fromtemp" + (quiet ? " -quiet" : "");
                if (!IsAdmin()) psi.Verb = "runas";
                Process.Start(psi);
                return;
            }

            if (!IsAdmin()) { RelaunchElevated(exe, args); return; }

            if (!quiet)
            {
                DialogResult r = MessageBox.Show(
                    "Remove " + AppName + " and stop its automatic startup sequence?",
                    AppName + " - Uninstall",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (r != DialogResult.Yes) return;
            }

            DoUninstall();

            // If we are the temporary copy, remove ourselves (delayed, after we exit).
            string self = Assembly.GetExecutingAssembly().Location;
            if (Path.GetFullPath(self).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    Process.Start(new ProcessStartInfo("cmd.exe",
                        "/c ping 127.0.0.1 -n 2 > nul & del /f /q \"" + self + "\"")
                        { UseShellExecute = false, CreateNoWindow = true });
                }
                catch { }
            }

            if (!quiet) MessageBox.Show(AppName + " was removed.", AppName + " - Uninstall", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
        catch (Exception ex)
        {
            if (!quiet) MessageBox.Show("Uninstall error: " + ex.Message, AppName + " - Uninstall", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    static void DoUninstall()
    {
        // Stop and remove the scheduled task.
        Run("schtasks.exe", "/End /TN \"" + TaskName + "\"", false);
        Run("schtasks.exe", "/Delete /TN \"" + TaskName + "\" /F", false);

        // Stop any running tray instance (we are elevated, so we can read command lines and kill).
        string ps = Path.Combine(Path.GetTempPath(), "vat-kill-tray.ps1");
        File.WriteAllText(ps,
            "Get-CimInstance Win32_Process -Filter \"Name='powershell.exe'\" | " +
            "Where-Object { $_.CommandLine -like '*VoiceAccessTray.ps1*' } | " +
            "ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }");
        Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -File \"" + ps + "\"", false);
        try { File.Delete(ps); } catch { }

        // Start-menu shortcuts.
        string smFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu), "Programs", AppName);
        try { if (Directory.Exists(smFolder)) Directory.Delete(smFolder, true); } catch { }
        string smLnk = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu), "Programs", AppName + ".lnk");
        try { if (File.Exists(smLnk)) File.Delete(smLnk); } catch { }

        // "Apps & features" entry.
        try { Registry.LocalMachine.DeleteSubKeyTree(@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\VoiceAccessTray", false); } catch { }

        // App preferences (keeps the user's choice out of the registry after removal).
        try { Registry.CurrentUser.DeleteSubKeyTree(@"Software\VoiceAccessTray", false); } catch { }

        // Log folder.
        string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "VoiceAccessTray");
        try { if (Directory.Exists(logDir)) Directory.Delete(logDir, true); } catch { }

        // Install dir (retry a few times: the tray process may still be shutting down).
        for (int i = 0; i < 6 && Directory.Exists(InstallDir); i++)
        {
            try { Directory.Delete(InstallDir, true); } catch { System.Threading.Thread.Sleep(500); }
        }
    }

    // ---- helpers ----
    static bool HasFlag(string[] args, string flag)
    {
        foreach (string a in args) if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    static bool SameDir(string a, string b)
    {
        if (a == null || b == null) return false;
        return string.Equals(a.TrimEnd('\\'), b.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
    }

    static bool IsAdmin()
    {
        using (WindowsIdentity id = WindowsIdentity.GetCurrent())
            return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
    }

    static void RelaunchElevated(string exe, string[] args)
    {
        ProcessStartInfo psi = new ProcessStartInfo(exe);
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
