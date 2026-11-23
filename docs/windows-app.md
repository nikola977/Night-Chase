# Windows-Version und GitHub

## Windows-Version bauen

- Windows-Programm „Night Chase“: bauen mit `tools\build_windows.ps1` (PowerShell) →
  `build\Night Chase.exe` (`/build/` ist in .gitignore). Export-Vorlage `export_presets.cfg`
  („Windows Desktop“): Architektur x86_64, `.pck` in die `.exe` eingebettet (eine einzige Datei),
  Symbol `assets/icon/icon.ico`, Version 1.0.0, Texturen als S3TC/BPTC. Filter: ohne Original-GLBs von
  Verkehr und Tankstelle (es reichen die vorbereiteten `prepared/model.res`), ohne `kia_stinger`,
  `screenshots/`, `docs/` (hat `.gdignore`) und `tools/`. Die Vollversion enthält die Automodelle
  (teils NC/ND): nur für den eigenen PC, nicht hochladen, kein Release.
- Voraussetzung: Godot 4.7.2 (Standard-Version) und die Exportvorlagen 4.7.2 (in Godot:
  *Editor → Exportvorlagen verwalten → Herunterladen*). Das Skript sucht Godot über `-Godot "Pfad"`,
  die Umgebungsvariable `GODOT` oder `godot` im PATH. Am besten die `_console.exe`-Datei nehmen,
  dann sieht man die Ausgabe im Terminal.
- Blockiert PowerShell das Skript: einmal `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`.
- Die `.exe` ist nicht signiert. Windows SmartScreen zeigt beim ersten Start vom Download
  „Der Computer wurde durch Windows geschützt“: *Weitere Informationen → Trotzdem ausführen*.

## Zwei Varianten

- Vollversion: `tools\build_windows.ps1 [-Install]` (Vorlage „Windows Desktop“, alle 8 Garage-Autos und alle
  Verkehrsmodelle) → `build\Night Chase.exe`; mit `-Install` zusätzlich nach
  `%LOCALAPPDATA%\Programs\Night Chase`. Nur für den eigenen PC.
- Download-Version: `tools\build_windows.ps1 -Download` (Vorlage „Windows Download“) →
  `build\download\Night Chase.exe` und `build\Car-Driving-World-1.0.0-Windows.zip`.
  Nur CC-BY-Modelle: BMW M3 E30, M3 GTS E92, M5 F90, M4 CSL, Audi S3 (Verkehr), Tankstelle. Die
  Vorlage schließt die Ordner von M2 (CC BY-NC-ND), M5 G90, SL 65, C 63, LC 500, Accord, Aztek
  (CC BY-NC-SA) und ID. Buzz (CC BY-NC) ganz aus (`res://assets/models/<ordner>/*`).
- Sicherheitsprüfung im Skript: Steht in der `.exe` der Download-Version ein Pfad
  `assets/models/<NC-Ordner>/`, bricht es ab.
- Im Spiel: Die Garage zeigt nur Autos, deren Modell da ist (`Garage._keep_available_cars`, Marke ohne Auto
  verschwindet; fehlen alle, bleiben alle ausgegraut wie bisher). Verkehr ohne Modell fährt mit den gebauten
  Ersatzformen (`Traffic._model` → null). Garage > Credits nennt nur vorhandene Modelle (Garage, Verkehr über
  `Traffic.TYPES[...]["credit"]`, Tankstelle `RoadNetwork.STATION_CREDIT`), dazu Schrift, Texturen, Engine.
- Beigelegt: `tools/download/CREDITS.txt` (Credits aller enthaltenen Modelle, Texturen, Inter, Godot-MIT-Text),
  `LICENSE.txt` und `Inter-LICENSE.txt` neben der `.exe` und im ZIP, dazu `tools/download/README.txt`
  (Installation, SmartScreen-Hinweis).
- Getestet wird mit `tools\test.ps1 --app` (Vollversion) bzw. `tools\test.ps1 "--app=build\download\Night Chase.exe"`.
- Erster Start einer neu gebauten Version: dauert etwas länger, bis die Welt da ist (Godot übersetzt alle
  Shader, der Ladebildschirm zeigt das an), danach nur noch wenige Sekunden.
- Hochskalierung: `project.godot` nutzt `rendering/scaling_3d/mode=1` (FSR 1.0, räumlich). Der Regler
  „Render-Auflösung“ im Pausemenü setzt nur den Anteil (`scaling_3d_scale`), die Zeile „Upscaling“ schaltet
  zwischen 1 (FSR 1.0: scharf, keine Geisterbilder) und 2 (FSR 2.2: zeitlich, glattere Kanten, zieht bei
  Tempo aber Scheiben und Kanten nach). 0 = bilinear.
  Grund: mit FSR 2.2 waren bei hohem Tempo Heckfenster und Karosseriekanten „zerzogen“ (Geisterbilder aus
  der Bilderhistorie). Vorher/nachher geprüft mit `--bench=9 --highway --car=f90 --benchshot=8`, Heck 4×
  vergrößert.
- Logo (`assets/icon/`): neues Symbol seit 22.11.2026 — Sportwagen mit Lichtspur auf einer
  Bergstraße bei Nacht (Mondsichel, Sterne), vom Nutzer gezeichnet. `icon.png` (1024 × 1024,
  abgerundete Ecken transparent, Fenster-Symbol `application/config/icon`), `icon.ico`
  (16–256 px, für Export und `config/windows_native_icon`), `splash.png` (1376 × 768,
  Startbildschirm, enthält dasselbe Symbol mit Schriftzug).
  Die Vorlagen lagen als JPEG mit falschen Endungen (.ico/.svg) vor; daraus wurde mit Pillow ein
  echtes PNG (Alpha an den runden Ecken), ein echtes ICO mit sieben Größen und ein echtes PNG für
  den Splash gemacht. `icon.svg` gibt es nicht mehr, es wurde im Projekt nicht verwendet.
  Achtung: auf dem Splash steht „Night Chase“, der Fenstertitel ist weiter „Night Chase“.
- Name: Der Projektname bleibt „Endlose Welt“, denn danach heißt der Speicherordner
  (`%APPDATA%\Godot\app_userdata\Endlose Welt`): Editor und `.exe` teilen sich so
  Einstellungen, Karte, Orte, Aussichtspunkte und Fotos. Der Fenstertitel kommt aus
  `Game.APP_TITLE` („Night Chase“).
- Exportierte Projekte: `DirAccess.get_files_at("res://…")` sieht dort nur die umgewandelten
  Dateien. Deshalb sucht `CarModel.model_path` die .glb mit `ResourceLoader.list_directory`.

## Version und Changelog

- Versionsnummer an zwei Stellen gleich halten: `project.godot` → `application/config/version` (Pausemenü,
  „Was ist neu“, `WhatsNew.version()`) und `export_presets.cfg` → `application/file_version` und
  `application/product_version` (Eigenschaften der `.exe`, z. B. `1.0.0.0`). Stand: 1.0.0.
- `CHANGELOG.md` im Projektordner: neueste Version oben, Abschnitte `## 1.0.0 – Datum` mit `### Neu` /
  `### Verbessert` und Punkten (`- **Fett** Text`, Fortsetzung eingerückt). Kommt per `include_filter` mit in
  das Spiel (ist keine Godot-Ressource). Neue Version: Nummer an beiden Stellen erhöhen, Abschnitt oben
  anlegen, Git-Tag `vX.Y.Z`.

## README-Bilder

- README-Bilder (`docs/screenshots/*.jpg`, 1280 × 720, JPG 86 %): nur CC-BY-Modelle (E30, E92, F90,
  M4 CSL, Audi S3, Tankstelle), also immer `--car=e92|m4csl|f90|e30` (ohne `--car` fährt im Test der
  M2!) und `--traffic=0` bzw. `--boxcars` (Raststätte: geparkte Autos als Kästen). `docs/` hat eine
  `.gdignore` (Godot importiert die Bilder nicht). Neue Bilder: garage, dam, waterfall, bridge
  (Hängebrücke `--pos=-10183,-9442 --cam=-10183,-10100,30 --lookat=-10183,-9442,35`), bath, moon,
  dyno, rest-area, village (Buchhof nachts `--pos=-660,459 --heading=103 --time=22`), explorer-map
  (`--bench=60 --highway --map`), chill (`--bench=62 --chill --car=m4csl --pos=2400,4180`).

## Autos unsichtbar im exportierten Spiel (behoben)

- Befund: Im exportierten Spiel waren Garage-Autos unsichtbar (nur das Kennzeichen schwebte über
  der Straße), Log ohne Fehler.
- Ursache: Godots Umwandlung der Text-Ressourcen (`.tres`) in Binärdateien beim Export
  (`editor/export/convert_text_resources_to_binary`, Standard an) verliert die `PackedStringArray`-Werte
  der Autoprofile. Ohne Rad-Muster findet `CarModel._build` keine Räder, der Radstand des Modells ist 0,
  `_fit` skaliert mit unendlich → Auto unsichtbar.
- Lösung: `editor/export/convert_text_resources_to_binary=false` in project.godot (nicht ändern!).
  `CarModel` meldet außerdem eine Warnung, wenn ein Modell nicht geladen werden kann.
- Fotos aus dem exportierten Spiel landen in `user://screenshots`
  (`%APPDATA%\Godot\app_userdata\Endlose Welt\screenshots`), z. B.
  `& "build\Night Chase.exe" --always-on-top -- --shot=NAME --meshcheck --car=m2`.

## Bekanntes

- Nur das exportierte Spiel meldet beim Beenden „1 shaders of type ParticlesShaderRD were
  never freed“ und einen nicht freigegebenen Shader. Harmlos (passiert erst beim Schließen).
- Die Messwerte in `leistung.md` stammen vom früheren Entwicklungsrechner; auf Windows-PCs
  ändern sich die Zahlen mit der Grafikkarte.
