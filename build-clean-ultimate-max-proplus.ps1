#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputPath = '')
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop') {
    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -OutputPath $OutputPath
    exit $LASTEXITCODE
}
Import-Module ps2exe -MinimumVersion 1.0.12
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $PSScriptRoot 'clean-ultimate-max-proplus.exe' }
if (Test-Path -LiteralPath $OutputPath) {
    try { $handle = [System.IO.File]::Open($OutputPath, 'Open', 'ReadWrite', 'None'); $handle.Dispose() }
    catch { throw "Zamknij uruchomiony plik EXE przed kompilacją: $OutputPath" }
}
$options = @{
    inputFile = Join-Path $PSScriptRoot 'clean-ultimate-max-proplus.ps1'
    outputFile = $OutputPath
    iconFile = Join-Path $PSScriptRoot 'cleanmax-fluent.ico'
    title = 'Clean Ultimate MAX PRO++'
    description = 'Analiza i czyszczenie pamięci podręcznej — Windows 10 / Windows 11'
    company = 'Netteria.NET'
    product = 'Clean Ultimate MAX PRO++'
    version = '2.1.0.0'
    noConsole = $true
    STA = $true
    DPIAware = $true
    supportOS = $true
    noConfigFile = $true
}
# AnyCPU, Windows PowerShell 5.1, no PowerShell 7 or sidecar files needed.
$buildStarted = [DateTime]::UtcNow
Invoke-ps2exe @options
if (-not (Test-Path -LiteralPath $options.outputFile)) { throw 'Kompilacja nie utworzyła pliku EXE.' }
if ((Get-Item -LiteralPath $options.outputFile).LastWriteTimeUtc -lt $buildStarted) { throw 'Kompilacja nie zaktualizowała pliku EXE.' }
Get-FileHash -LiteralPath $options.outputFile -Algorithm SHA256
