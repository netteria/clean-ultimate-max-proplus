# Clean Ultimate MAX PRO++ — Installation and Build Guide

Clean Ultimate MAX PRO++ scans and cleans selected temporary files and application caches on Windows. The interface is available in **English and Polish**.

You can use a ready-made EXE or build it from the source code. Build tools are not required to run the finished application.

## Requirements

- Windows 10 or Windows 11.
- Windows PowerShell 5.1 and the system .NET Framework, included in standard installations of these Windows versions.
- An internet connection to download the application and install the build tool.

PowerShell 7, Python and Visual Studio are not required. The compiled EXE still uses Windows PowerShell and .NET Framework at runtime.

The application has been tested on Windows 11. A separate Windows 10 installation and ARM64 devices have not been tested.

## Option A: Download and run the EXE

1. If a compiled release is available, open the repository's **Releases** section.
2. Expand **Assets** and download `clean-ultimate-max-proplus.exe`. The **Source code** archives contain the project sources, not the ready-made application.
3. Save the EXE to a folder of your choice and double-click it.

No installer is required. You only need the EXE; the `.ps1` and `.ico` files do not need to be placed beside it. If no EXE is available in Releases, follow the build instructions below.

### Using the application

1. Select **English** or **Polski** in the top-right corner.
2. Close the applications and browsers whose caches you want to clean.
3. Select the areas to include. **Select all categories** selects every available option across all tabs, then changes to **Deselect all categories**.
4. Click **Scan**. Scanning does not delete any files.
5. Review the results, click **Clean**, and confirm the operation.

**Deleted files bypass the Recycle Bin.** Clicking **Cancel** stops further operations but does not restore files that have already been deleted.

By default, only user temporary files older than 24 hours are selected. **Recommended** restores this selection. Locked files, files changed since the scan, and filesystem links are skipped. The application does not delete entire browser profiles or application installation folders.

### Why is “Windows temporary files” disabled?

This option requires administrator access. Click **Run as administrator** and approve the standard Windows prompt to enable it. The application will reopen; cleaning does not start automatically.

Other available options can be used without running the application as administrator.

## Option B: Build the EXE yourself

Use **Windows PowerShell 5.1** for the following steps. You do not need to run PowerShell as administrator to build the application.

### 1. Download and extract the source code

On the repository page, select **Code → Download ZIP**, then extract the downloaded archive. Do not run the build directly from inside the ZIP file.

To build the application with its icon and version information, place these three files in the same folder:

```text
clean-ultimate-max-proplus.ps1
build-clean-ultimate-max-proplus.ps1
cleanmax-fluent.ico
```

### 2. Open Windows PowerShell in that folder

Open the extracted folder in File Explorer. Click the address bar, type `powershell.exe`, and press **Enter**.

Check that the required files are listed:

```powershell
Get-ChildItem
```

If the archive contains an additional parent folder, open the folder containing the files listed above and start PowerShell there.

### 3. Install PS2EXE

You only need to do this once for your Windows account:

```powershell
Install-Module -Name ps2exe -Repository PSGallery -Scope CurrentUser
```

PowerShell may ask to install the **NuGet** provider and confirm downloading the module from **PSGallery**. Accept those prompts using the choices displayed in the console to continue.

`CurrentUser` installs the module for your account without requiring administrator access.

### 4. Build the application

Close any running copy of the application before rebuilding it. Then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\build-clean-ultimate-max-proplus.ps1
```

`-ExecutionPolicy Bypass` applies only to the PowerShell process launched by this command. It does not permanently change the system's script execution policy.

After a successful build, this file will appear in the same folder:

```text
clean-ultimate-max-proplus.exe
```

The build script adds the application icon, version information, and GUI and Windows compatibility settings. It also prints the generated file's SHA-256 checksum.

### 5. Run the EXE

Double-click `clean-ultimate-max-proplus.exe` in File Explorer, or run:

```powershell
.\clean-ultimate-max-proplus.exe
```

You can move the EXE to another folder. PS2EXE is needed only to build it, not to run it.

To launch the application directly in English, use:

```powershell
.\clean-ultimate-max-proplus.exe -Language en
```

The default language is Polish. You can also change the language using the buttons in the application.

## Building from the application PS1 file only

If you only have `clean-ultimate-max-proplus.ps1`, you can still create an EXE. This file contains the complete application code and both interface languages.

Install PS2EXE as described above, open Windows PowerShell in the folder containing the PS1 file, and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Import-Module ps2exe; Invoke-ps2exe -inputFile .\clean-ultimate-max-proplus.ps1 -outputFile .\clean-ultimate-max-proplus.exe -noConsole -STA -DPIAware -supportOS -noConfigFile"
```

This produces a working EXE with the same interface and features. It does not add the project icon or version information configured by `build-clean-ultimate-max-proplus.ps1`.

## Troubleshooting

| Problem | Solution |
| --- | --- |
| The PS1 file cannot be found | Open PowerShell in the extracted folder containing the project files. |
| The `ps2exe` module cannot be found | Install the module in Windows PowerShell 5.1 using the same Windows account. |
| `cleanmax-fluent.ico` is missing | Download the icon and place it beside the scripts, or use the PS1-only build command. |
| The EXE cannot be overwritten | Close the running application and build it again. |
| The module download fails | Check your internet connection and access to PowerShell Gallery. |
| A managed computer blocks execution | Contact your administrator. The build command does not override organizational application control policies. |

Build tool documentation: [PS2EXE on GitHub](https://github.com/MScholtes/PS2EXE).
