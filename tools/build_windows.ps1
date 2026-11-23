# Baut die Windows-Version "Night Chase" in einer von zwei Varianten:
#   Vollversion (Vorlage "Windows Desktop") -> build\Night Chase.exe, mit allen Autos (teils NC/ND-Lizenz:
#     nur fuer diesen PC, nie hochladen). Mit -Install danach nach %LOCALAPPDATA%\Programs\Night Chase kopieren.
#   Download-Version (-Download, Vorlage "Windows Download") -> build\download\Night Chase.exe, nur Modelle
#     mit CC-BY-Lizenz (E30, E92, M5 F90, M4 CSL, Audi S3, Tankstelle), dazu CREDITS.txt, LICENSE.txt und
#     Inter-LICENSE.txt neben der .exe und ein ZIP zum Weitergeben: build\Car-Driving-World-VERSION-Windows.zip
# Die .exe enthaelt das Spiel (.pck) schon eingebettet, es ist also nur eine einzige Datei.
# Voraussetzung: Godot 4.7.2 und die passenden Exportvorlagen (in Godot: Editor > Exportvorlagen verwalten).
# Aufruf (PowerShell, im Projektordner):
#   tools\build_windows.ps1 [-Download] [-Install] [-Godot "C:\Pfad\zu\Godot_console.exe"]
# Godot-Programm: -Godot, sonst Umgebungsvariable GODOT, sonst "godot" aus dem PATH.
# Falls PowerShell Skripte blockiert: einmal  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

param(
    [switch]$Download,
    [switch]$Install,
    [string]$Godot = $env:GODOT
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")
if (-not $Godot) { $Godot = "godot" }

$Name = "Night Chase"
$Version = (Select-String -Path "project.godot" -Pattern '^config/version="(.*)"$').Matches[0].Groups[1].Value
# Ordner der Modelle mit NC/ND-Lizenz: duerfen nie in der Download-Version stecken
$NcFolders = @("bmw_m2", "2025_bmw_m5_sedan", "2009_mercedes-benz_sl65_amg_black_series",
    "2013_mercedes-benz_c63_amg_coupe_black_series", "verkehr/2005_pontiac_aztek", "verkehr/2021_honda_accord",
    "verkehr/2023_volkswagen_id_buzz_gtx", "verkehr/2017_lexus_lc_500", "verkehr/kia_stinger")

if ($Download) {
    if ($Install) { Write-Host "-Install nur fuer die Vollversion (beide Programme heissen gleich)"; exit 1 }
    $Preset = "Windows Download"
    $Out = "build\download"
} else {
    $Preset = "Windows Desktop"
    $Out = "build"
}
$Exe = Join-Path $Out "$Name.exe"

if (Test-Path $Exe) { Remove-Item $Exe -Force }
New-Item -ItemType Directory -Force -Path $Out | Out-Null
& $Godot --headless --path . --export-release $Preset $Exe
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $Exe)) {
    Write-Host "FEHLER: Export fehlgeschlagen (sind die Exportvorlagen 4.7.2 installiert?)"
    exit 1
}

if ($Download) {
    # Sicherheitspruefung: In der .exe (mit eingebettetem .pck) darf kein Pfad aus einem NC/ND-Ordner stehen
    Add-Type -TypeDefinition @"
using System;
using System.IO;
public static class BytesSearch {
    public static bool Contains(string file, string needle) {
        byte[] pat = System.Text.Encoding.ASCII.GetBytes(needle);
        byte[] buf = new byte[4 * 1024 * 1024 + pat.Length];
        using (FileStream fs = File.OpenRead(file)) {
            int keep = 0;
            int read;
            while ((read = fs.Read(buf, keep, 4 * 1024 * 1024)) > 0) {
                int len = keep + read;
                for (int i = 0; i + pat.Length <= len; i++) {
                    int j = 0;
                    while (j < pat.Length && buf[i + j] == pat[j]) j++;
                    if (j == pat.Length) return true;
                }
                keep = Math.Min(pat.Length - 1, len);
                Array.Copy(buf, len - keep, buf, 0, keep);
            }
        }
        return false;
    }
}
"@
    $ExeFull = (Resolve-Path $Exe).Path
    foreach ($folder in $NcFolders) {
        if ([BytesSearch]::Contains($ExeFull, "assets/models/$folder/")) {
            Write-Host "FEHLER: $folder steckt in der Download-Version ($Exe)"
            exit 1
        }
    }
    # Credits und Lizenzen gehoeren zum Spiel
    Copy-Item "tools\download\CREDITS.txt" (Join-Path $Out "CREDITS.txt") -Force
    Copy-Item "LICENSE" (Join-Path $Out "LICENSE.txt") -Force
    Copy-Item "assets\fonts\Inter-LICENSE.txt" (Join-Path $Out "Inter-LICENSE.txt") -Force
}

$SizeMb = [math]::Round((Get-Item $Exe).Length / 1MB)
Write-Host "Fertig: $Exe ($SizeMb MB, Version $Version)"

if ($Download) {
    # ZIP zum Weitergeben: Ordner mit .exe, Lies-mich, Credits und Lizenzen
    $Stage = Join-Path $Out "$Name $Version"
    $Zip = "build\Car-Driving-World-$Version-Windows.zip"
    if (Test-Path $Stage) { Remove-Item $Stage -Recurse -Force }
    if (Test-Path $Zip) { Remove-Item $Zip -Force }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null
    Copy-Item $Exe $Stage
    Copy-Item "tools\download\README.txt", "tools\download\CREDITS.txt" $Stage
    Copy-Item "LICENSE" (Join-Path $Stage "LICENSE.txt")
    Copy-Item "assets\fonts\Inter-LICENSE.txt" (Join-Path $Stage "Inter-LICENSE.txt")
    Compress-Archive -Path $Stage -DestinationPath $Zip
    Remove-Item $Stage -Recurse -Force
    Write-Host ("ZIP: $Zip ({0} MB)" -f [math]::Round((Get-Item $Zip).Length / 1MB, 1))
}

if ($Install) {
    $Target = Join-Path $env:LOCALAPPDATA "Programs\$Name"
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    Copy-Item $Exe $Target -Force
    Write-Host "Installiert: $Target\$Name.exe"
}
