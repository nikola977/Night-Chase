# Automatischer Testlauf: startet das Spiel mit --selftest (scripts/self_test.gd: Landstrasse und
# Autobahn mit dem Autopiloten, Regen, Schnee, Nacht, Garage, Karte, Fotomodus, Pausemenue,
# Chill-Modus) und wertet danach das Log aus. Am Ende steht "OK" oder die Liste der Fehler und
# Warnungen. Stille Abstuerze erkennt er daran, dass die Zeile "SELFTEST ENDE" fehlt.
#
# Aufruf (PowerShell, im Projektordner):
#   tools\test.ps1                         im Editor-Godot (vorher einmal --import, macht das Skript selbst)
#   tools\test.ps1 --app                   gegen die exportierte Windows-Version (build\Night Chase.exe)
#   tools\test.ps1 "--app=build\download\Night Chase.exe"   gegen eine andere .exe (z. B. Download-Version)
#   tools\test.ps1 --shots                 zusaetzlich ein Foto pro Schritt (screenshots\selftest_*.png)
#   tools\test.ps1 --godot=C:\Godot\Godot_v4.7.2-stable_win64_console.exe   Godot-Programm angeben
#   weitere Argumente gehen ans Spiel, z. B. tools\test.ps1 --car=e92
# Godot-Programm: --godot=..., sonst Umgebungsvariable GODOT, sonst "godot" aus dem PATH.
# Log: screenshots\test.log (bzw. test_app.log). Rueckgabe: 0 = OK, 1 = Fehler.
# Falls PowerShell Skripte blockiert: einmal  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

$Godot = $env:GODOT
if (-not $Godot) { $Godot = "godot" }
$App = "build\Night Chase.exe"
$Limit = 300          # Sekunden, danach gilt der Lauf als haengengeblieben
$UseApp = $false
$TestArg = "--selftest"
$Extra = @()
foreach ($arg in $args) {
    if ($arg -eq "--app") { $UseApp = $true }
    elseif ($arg -like "--app=*") { $UseApp = $true; $App = $arg.Substring(6) }
    elseif ($arg -like "--godot=*") { $Godot = $arg.Substring(8) }
    elseif ($arg -eq "--shots") { $TestArg = "--selftest=shots" }
    else { $Extra += $arg }
}

# Meldungen, die bekannt und harmlos sind (Muster als Regex), mit Begruendung:
$Known = @(
    # Nur die exportierte Version, beim Beenden (docs/windows-app.md, "Bekannt")
    "shaders of type ParticlesShaderRD were never freed",
    "MaterialStorage.*Shader.*leaked|1 RID of type ""Shader"" was leaked"
)

function Quote([string]$text) {
    if ($text -match '\s') { return '"' + $text + '"' }
    return $text
}

New-Item -ItemType Directory -Force -Path "screenshots" | Out-Null
$ProjectDir = (Get-Location).Path

if ($UseApp) {
    $Log = "screenshots\test_app.log"
    if (-not (Test-Path $App)) { Write-Host "FEHLER: Spiel nicht gefunden: $App"; exit 1 }
    $Exe = (Resolve-Path $App).Path
    $GameArgs = @("--always-on-top", "--log-file", (Quote (Join-Path $ProjectDir $Log)), "--", $TestArg) + $Extra
} else {
    $Log = "screenshots\test.log"
    # Neue class_name-Skripte sind erst nach dem Import bekannt
    $ImportLog = Join-Path $ProjectDir "screenshots\test_import.log"
    $imp = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", (Quote $ProjectDir), "--import", "--log-file", (Quote $ImportLog)) -PassThru -Wait
    $Exe = $Godot
    $GameArgs = @("--path", (Quote $ProjectDir), "--always-on-top", "--log-file", (Quote (Join-Path $ProjectDir $Log)), "--", $TestArg) + $Extra
}
if (Test-Path $Log) { Remove-Item $Log }

Write-Host "Testlauf startet: $Exe $($GameArgs -join ' ')"
$proc = Start-Process -FilePath $Exe -ArgumentList $GameArgs -PassThru
$null = $proc.Handle     # noetig, damit ExitCode nach dem Ende gelesen werden kann
if (-not $proc.WaitForExit($Limit * 1000)) {
    try { $proc.Kill() } catch { }
    Start-Sleep -Seconds 1
    Add-Content -Path $Log -Value "HAENGT: nach $Limit s abgebrochen" -Encoding UTF8
}
$proc.WaitForExit()
$Code = $proc.ExitCode

$LogLines = @()
if (Test-Path $Log) { $LogLines = @(Get-Content $Log -Encoding UTF8) }
$Pattern = "ERROR|WARNING|Parse Error|HAENGT|leaked|Leaked"

# Fehler und Warnungen einsammeln (Godot schreibt "ERROR:", "WARNING:", "SCRIPT ERROR:" ...)
$Found = @($LogLines | Where-Object { $_ -match $Pattern -and $_ -notmatch "^SELFTEST" })
if (-not $UseApp -and (Test-Path $ImportLog)) {
    $Found += @(Get-Content $ImportLog -Encoding UTF8 | Where-Object { $_ -match "ERROR|Parse Error" })
}
$Counted = @($Found | Group-Object | Sort-Object Count -Descending |
    ForEach-Object { "{0,6} {1}" -f $_.Count, $_.Name })

$KnownHits = @()
foreach ($pattern in $Known) {
    $KnownHits += @($Counted | Where-Object { $_ -match $pattern })
    $Counted = @($Counted | Where-Object { $_ -notmatch $pattern })
}
$Problems = @($Counted | Where-Object { $_.Trim() -ne "" })

$LogLines | Where-Object { $_ -match "^SELFTEST (gefahren|FPS|ENDE)|Welt geladen" } | ForEach-Object { Write-Host $_ }
$Failed = $false
if (-not ($LogLines | Where-Object { $_ -match "^SELFTEST ENDE nach" })) {
    Write-Host "FEHLER: Keine Zeile ""SELFTEST ENDE"" - das Spiel ist abgestuerzt oder haengengeblieben (Rueckgabe $Code)."
    Write-Host "Letzte Zeilen:"
    $LogLines | Select-Object -Last 8 | ForEach-Object { Write-Host "  $_" }
    $Failed = $true
} elseif ($Code -ne 0) {
    Write-Host "FEHLER: Rueckgabe $Code (erwartet 0)"
    $Failed = $true
}
if ($Problems.Count -gt 0) {
    Write-Host "FEHLER/WARNUNGEN im Log ($Log):"
    $Problems | ForEach-Object { Write-Host "  $_" }
    $Failed = $true
}
if ($KnownHits.Count -gt 0) {
    Write-Host "Bekannt und harmlos:"
    $KnownHits | ForEach-Object { Write-Host "  $_" }
}
if (-not $Failed) {
    Write-Host "OK"
    exit 0
}
exit 1
