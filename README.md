# clean-ultimate-max-proplus
Clean Ultimate MAX PRO++ is an advanced Windows cleaner with Fluent UI, Acrylic Blur, Dark Mode, tabs, checkboxes and full GUI. It safely removes system junk, app caches, developer leftovers and browser data. Built by Netteria.NET to deliver fast, safe and modern system maintenance.
# Clean Ultimate MAX PRO++
Advanced Windows 10/11 cleaning tool with a modern GUI, modular cleaning system, administrator execution, and safe system maintenance.  
Created by **Netteria.NET**  
https://netteria.net

Clean Ultimate MAX PRO++ is an open‑source Windows cleaner designed for developers, administrators, and power users.  
It provides a modern interface, modular cleaning categories, safe removal of temporary files, caches, logs, and leftover data — without touching user files or critical system components.

## Features
- Modern GUI with tabbed navigation
- Modular cleaning (System, Apps, Developer, Browser)
- Safe removal of temporary files, caches, logs, and leftovers
- Administrator‑level execution for full access
- No registry modifications
- No deletion of user documents or system files
- Open‑source and fully auditable

## Download
Latest releases are available here:  
https://github.com/netteria/clean-ultimate-max-proplus/releases

## Build from Source
1. Install PS2EXE:
   Install-Module -Name ps2exe -Force
2. Compile:
   ps2exe -inputFile "src/clean-ultimate-max-proplus.ps1"
-outputFile "build/output/clean-ultimate-max.exe" -title "Clean Ultimate MAX PRO++"
-product "Clean Ultimate MAX PRO++" -company "Netteria.NET"
-description "Advanced Windows cleaner with modular GUI" -version "2.0.0.0"
-requireAdmin


## Requirements
- Windows 10 or Windows 11  
- PowerShell 5.1+ (for building)  
- Administrator privileges  

## License
MIT License — see `LICENSE` file.

## Contributing
Pull requests are welcome.  
For major changes, please open an issue first.

## Issues
If you encounter a problem, please open an issue and include:
- description  
- steps to reproduce  
- expected behavior  
- actual behavior  

## Author
**Netteria.NET**  
https://netteria.net
