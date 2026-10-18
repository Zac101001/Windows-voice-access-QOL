# Build the Voice Access Bar Control installer.
#   - compiles the uninstaller (VoiceAccessTrayUninstall.exe)
#   - compiles the setup GUI (VoiceAccessTraySetup.exe) with the app script and
#     the uninstaller embedded as resources, so the setup .exe is fully standalone.
# Run:  powershell -ExecutionPolicy Bypass -File build.ps1
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { throw "csc.exe (C# compiler) not found." }

$payloadSrc = Join-Path (Split-Path -Parent $here) "V2\VoiceAccessTray.ps1"
$payloadDir = Join-Path $here "payload"
$distDir    = Join-Path $here "dist"
$srcDir     = Join-Path $here "src"
New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
New-Item -ItemType Directory -Path $distDir    -Force | Out-Null

# 1. payload = current application script
Copy-Item -Path $payloadSrc -Destination (Join-Path $payloadDir "VoiceAccessTray.ps1") -Force

$winRefs = @("/r:System.Windows.Forms.dll", "/r:System.Drawing.dll")

# 2. uninstaller
$uninstaller = Join-Path $distDir "VoiceAccessTrayUninstall.exe"
& $csc /nologo /target:winexe /optimize+ /out:"$uninstaller" @winRefs (Join-Path $srcDir "Uninstall.cs")
if ($LASTEXITCODE -ne 0) { throw "Uninstaller compilation failed." }
Write-Host "Built $uninstaller"

# 3. setup (embeds the payload script + the uninstaller)
$setup = Join-Path $distDir "VoiceAccessTraySetup.exe"
$res1 = "/resource:" + (Join-Path $payloadDir "VoiceAccessTray.ps1") + ",VoiceAccessTray.ps1"
$res2 = "/resource:" + $uninstaller + ",VoiceAccessTrayUninstall.exe"
& $csc /nologo /target:winexe /optimize+ /out:"$setup" @winRefs "$res1" "$res2" (Join-Path $srcDir "Setup.cs")
if ($LASTEXITCODE -ne 0) { throw "Setup compilation failed." }
Write-Host "Built $setup"

Write-Host ""
Write-Host "Output:"
Get-ChildItem $distDir -File | ForEach-Object { "{0,-34} {1,8:N0} bytes" -f $_.Name, $_.Length }
