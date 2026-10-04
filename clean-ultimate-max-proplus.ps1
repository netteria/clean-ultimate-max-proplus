Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Enable Acrylic Blur (Windows 11 style)
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Blur {
    [DllImport("user32.dll")]
    public static extern int SetWindowCompositionAttribute(IntPtr hwnd, ref WindowCompositionAttributeData data);

    public enum AccentState {
        ACCENT_DISABLED = 0,
        ACCENT_ENABLE_GRADIENT = 1,
        ACCENT_ENABLE_TRANSPARENTGRADIENT = 2,
        ACCENT_ENABLE_BLURBEHIND = 3,
        ACCENT_ENABLE_ACRYLICBLURBEHIND = 4
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct AccentPolicy {
        public AccentState AccentState;
        public int AccentFlags;
        public int GradientColor;
        public int AnimationId;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WindowCompositionAttributeData {
        public int Attribute;
        public IntPtr Data;
        public int SizeOfData;
    }
}
"@

function Enable-AcrylicBlur($form) {
    $accent = New-Object Blur+AccentPolicy
    $accent.AccentState = [Blur+AccentState]::ACCENT_ENABLE_ACRYLICBLURBEHIND
    $accent.GradientColor = 0xCC1E1E1E  # Dark acrylic

    $accentStructSize = [System.Runtime.InteropServices.Marshal]::SizeOf($accent)
    $accentPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal($accentStructSize)
    [System.Runtime.InteropServices.Marshal]::StructureToPtr($accent, $accentPtr, $false)

    $data = New-Object Blur+WindowCompositionAttributeData
    $data.Attribute = 19
    $data.SizeOfData = $accentStructSize
    $data.Data = $accentPtr

    [Blur]::SetWindowCompositionAttribute($form.Handle, [ref]$data)
}

# Main Window
$form = New-Object System.Windows.Forms.Form
$form.Text = "Clean Ultimate MAX PRO++ - Netteria.NET"
$form.Size = New-Object System.Drawing.Size(900,600)
$form.StartPosition = "CenterScreen"
$form.Icon = New-Object System.Drawing.Icon("C:\Tools\cleanmax-fluent.ico")
$form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)
$form.ForeColor = [System.Drawing.Color]::White

$form.Add_Shown({ Enable-AcrylicBlur $form })

# Title
$title = New-Object System.Windows.Forms.Label
$title.Text = "Clean Ultimate MAX PRO++"
$title.Font = New-Object System.Drawing.Font("Segoe UI",22,[System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::White
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20,20)
$form.Controls.Add($title)

# Branding
$brand = New-Object System.Windows.Forms.Label
$brand.Text = "Powered by Netteria.NET"
$brand.Font = New-Object System.Drawing.Font("Segoe UI",12)
$brand.ForeColor = [System.Drawing.Color]::LightGray
$brand.AutoSize = $true
$brand.Location = New-Object System.Drawing.Point(22,60)
$form.Controls.Add($brand)

$link = New-Object System.Windows.Forms.LinkLabel
$link.Text = "https://netteria.net"
$link.Font = New-Object System.Drawing.Font("Segoe UI",12)
$link.LinkColor = [System.Drawing.Color]::SkyBlue
$link.ActiveLinkColor = [System.Drawing.Color]::DeepSkyBlue
$link.AutoSize = $true
$link.Location = New-Object System.Drawing.Point(22,85)
$link.add_Click({ Start-Process "https://netteria.net" })
$form.Controls.Add($link)

# Tabs
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Size = New-Object System.Drawing.Size(850,400)
$tabs.Location = New-Object System.Drawing.Point(20,130)
$form.Controls.Add($tabs)

$tabSystem = New-Object System.Windows.Forms.TabPage
$tabSystem.Text = "System"

$tabApps = New-Object System.Windows.Forms.TabPage
$tabApps.Text = "Apps"

$tabDev = New-Object System.Windows.Forms.TabPage
$tabDev.Text = "Developer"

$tabBrowser = New-Object System.Windows.Forms.TabPage
$tabBrowser.Text = "Browser"

$tabs.TabPages.AddRange(@($tabSystem,$tabApps,$tabDev,$tabBrowser))

# Checkboxes
function Add-Check($tab,$text,$y) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $text
    $cb.ForeColor = [System.Drawing.Color]::White
    $cb.Location = New-Object System.Drawing.Point(20,$y)
    $cb.Checked = $true
    $tab.Controls.Add($cb)
    return $cb
}

# System
$cbSysTemp = Add-Check $tabSystem "Windows Temp" 20
$cbSysPrefetch = Add-Check $tabSystem "Prefetch" 50
$cbSysUpdate = Add-Check $tabSystem "Windows Update Cache" 80
$cbSysCBS = Add-Check $tabSystem "CBS Logs" 110
$cbSysDISM = Add-Check $tabSystem "DISM Logs" 140
$cbSysWER = Add-Check $tabSystem "Windows Error Reporting" 170

# Apps
$cbAppsPackages = Add-Check $tabApps "UWP Packages Cache" 20
$cbAppsOpenAI = Add-Check $tabApps "OpenAI Cache" 50
$cbAppsLM = Add-Check $tabApps "LM Studio Updater" 80
$cbAppsNetBeans = Add-Check $tabApps "NetBeans Cache" 110
$cbAppsCrash = Add-Check $tabApps "CrashDumps" 140

# Developer
$cbDevNpm = Add-Check $tabDev "npm-cache" 20
$cbDevNvm = Add-Check $tabDev "nvm" 50
$cbDevNuget = Add-Check $tabDev "NuGet Cache" 80
$cbDevVS = Add-Check $tabDev "Visual Studio Cache" 110
$cbDevJet = Add-Check $tabDev "JetBrains Cache" 140

# Browser
$cbBrave = Add-Check $tabBrowser "Brave Cache" 20
$cbChrome = Add-Check $tabBrowser "Chrome Cache" 50
$cbEdge = Add-Check $tabBrowser "Edge Cache" 80
$cbChromium = Add-Check $tabBrowser "Chromium Cache" 110

# Progress
$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(20,540)
$progress.Size = New-Object System.Drawing.Size(850,25)
$form.Controls.Add($progress)

# Log
$log = New-Object System.Windows.Forms.TextBox
$log.Multiline = $true
$log.ScrollBars = "Vertical"
$log.Location = New-Object System.Drawing.Point(20,540)
$log.Size = New-Object System.Drawing.Size(850,25)

# Button
$button = New-Object System.Windows.Forms.Button
$button.Text = "Start Cleaning"
$button.Size = New-Object System.Drawing.Size(160,45)
$button.Location = New-Object System.Drawing.Point(700,30)
$button.BackColor = [System.Drawing.Color]::FromArgb(45,45,45)
$button.ForeColor = [System.Drawing.Color]::White
$form.Controls.Add($button)

# Cleanup logic
$button.Add_Click({
    $progress.Value = 0

    $paths = @()

    if ($cbSysTemp.Checked) { $paths += "C:\Windows\Temp" }
    if ($cbSysPrefetch.Checked) { $paths += "C:\Windows\Prefetch" }
    if ($cbSysUpdate.Checked) { $paths += "C:\Windows\SoftwareDistribution\Download" }
    if ($cbSysCBS.Checked) { $paths += "C:\Windows\Logs\CBS" }
    if ($cbSysDISM.Checked) { $paths += "C:\Windows\Logs\DISM" }
    if ($cbSysWER.Checked) { $paths += "C:\ProgramData\Microsoft\Windows\WER" }

    if ($cbAppsPackages.Checked) { $paths += "$env:LOCALAPPDATA\Packages" }
    if ($cbAppsOpenAI.Checked) { $paths += "$env:LOCALAPPDATA\OpenAI" }
    if ($cbAppsLM.Checked) { $paths += "$env:LOCALAPPDATA\lm-studio-updater" }
    if ($cbAppsNetBeans.Checked) { $paths += "$env:LOCALAPPDATA\NetBeans" }
    if ($cbAppsCrash.Checked) { $paths += "$env:LOCALAPPDATA\CrashDumps" }

    if ($cbDevNpm.Checked) { $paths += "$env:LOCALAPPDATA\npm-cache" }
    if ($cbDevNvm.Checked) { $paths += "$env:LOCALAPPDATA\nvm" }
    if ($cbDevNuget.Checked) { $paths += "$env:LOCALAPPDATA\NuGet\Cache" }
    if ($cbDevVS.Checked) { $paths += "$env:LOCALAPPDATA\Microsoft\VisualStudio" }
    if ($cbDevJet.Checked) { $paths += "$env:LOCALAPPDATA\JetBrains" }

    if ($cbBrave.Checked) { $paths += "$env:LOCALAPPDATA\BraveSoftware" }
    if ($cbChrome.Checked) { $paths += "$env:LOCALAPPDATA\Google" }
    if ($cbEdge.Checked) { $paths += "$env:LOCALAPPDATA\Microsoft\Edge" }
    if ($cbChromium.Checked) { $paths += "$env:LOCALAPPDATA\Chromium" }

    $total = $paths.Count
    $i = 0

    foreach ($p in $paths) {
        $i++
        $progress.Value = [int](($i / $total) * 100)

        if (Test-Path $p) {
            Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    [System.Windows.Forms.MessageBox]::Show("Cleanup finished.","Netteria.NET")
})

$form.ShowDialog()
