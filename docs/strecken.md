# Strecken-Modus (Osaka Nanko)

Eine eigene Welt neben der endlosen Landschaft: die umgewandelte Assetto-Corsa-Strecke
**„Osaka Nanko Kamome Futo“** (Team 90's Golden Drift Spot Project). Freies Fahren, kein
Verkehr, keine Tempolimits, keine Karte. Die endlose Welt bleibt vollständig erhalten.

> **Lizenz:** Die Strecke ist ein fremder Mod. In `credit.txt` steht ausdrücklich
> „Do not convert into other games without permission“. Der Ordner `assets/tracks/` ist
> deshalb in `.gitignore` und darf **nie** veröffentlicht werden – auch nicht in einem
> Release. Wer die Strecke zeigen will, braucht vorher die schriftliche Erlaubnis des Teams.

## Werkzeug: `tools/kn5_to_gltf.py`

Godot kann `.kn5` nicht lesen. Das Skript liest das Assetto-Format direkt (ohne Assetto
Corsa, ohne Blender) und schreibt **pro Bodenkachel eine `.glb`-Datei** – ein einziges OBJ
mit 1,4 GB würde Godot nicht in vertretbarer Zeit laden.

```powershell
$PY = "C:\Users\Nikola\AppData\Local\Programs\Python\Python313\python.exe"
$T  = "C:\Users\Nikola\Desktop\content\tracks\90sgdsp_osaka_nanko"

& $PY tools\kn5_to_gltf.py --in "$T\90sgdsp_osaka_nanko.kn5" --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\buildings.kn5"          --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\props.kn5"              --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\metal_pole.kn5"         --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\vehicles.kn5"           --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\bg.kn5"                 --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\lights.kn5"             --out assets\tracks\osaka --tile=250
& $PY tools\kn5_to_gltf.py --in "$T\physical_free.kn5"      --out assets\tracks\osaka --collision
```

Danach einmal importieren (dauert etwa eine Minute):

```powershell
& $G --headless --path . --import
```

## Ausprobieren

```powershell
& $G --path . res://scenes/track_world.tscn -- --shot=osaka --wait=8   # Foto nach screenshots\osaka.png
& $G --path . res://scenes/track_world.tscn -- --bench=10              # Bildrate messen
& $G --path . -- --track=osaka                                        # normaler Start in der Strecke
```

Im Spiel: **Esc → „Osaka Nanko (track)“**, zurück mit **Esc** (lädt die endlose Welt neu).

## Zahlen (gemessen am 21.11.2026, RX 7700 XT, 1280×720)

| | |
|---|---|
| Dreiecke Strecke / Gebäude / Masten | 3,9 Mio. / 1,0 Mio. / 6,0 Mio. |
| Dreiecke gesamt (Fahrbahn, Gebäude, Requisiten, Masten, Autos, Kulisse, Lichter) | ca. 12 Mio. |
| Kacheln | 124 × 250 m |
| Dateien / Größe | 148 `.glb`, 435 MB |
| Import | ~55 s |
| Ladezeit im Spiel | 1,4 s |
| Bildrate stehend, alles sichtbar | 138 FPS im Schnitt |
| Fahrbahn-Physik | 21 469 Dreiecke (aus `physical_free.kn5`) |

## Texturen

Die **Original-Texturen fehlen in dieser Download-Version**: in allen `.kn5`-Dateien stecken
nur 270 Stück 1×1-Pixel-Platzhalter (PNG, 70 Byte), und auf dem Rechner liegt keine
Assetto-Corsa-Installation, aus deren `content/texture` die Strecke etwas laden könnte.

Deshalb erzeugt `track_world.gd` die Oberflächen selbst (`add_textures`, `TEXTURE_STYLES`):
pro Materialart ein Rausch-Muster als Farbe **und** als Normalen-Karte, projiziert mit
**Triplanar-Mapping in Weltkoordinaten** – dadurch braucht die Geometrie keine UVs.
Asphalt bekommt feines Korn, Beton grobe Flecken, Rost und Ziegel kräftiges Relief, Metall
kaum. Kosten: 15 Texturen, 40 ms beim Laden, keine messbare Bildrate weniger (138 statt 141 FPS).

Feinheit je Stil über `meters` (Meter bis zur nächsten Wiederholung), Stärke des Reliefs über
`bump`. Alles im Godot-Editor im Knoten `TrackWorld` einstellbar.

**Echte Texturen nachrüsten** (nur mit eigenem Assetto Corsa + Content Manager möglich):
Strecke dort öffnen, Modell als FBX/OBJ **mit Texturen** exportieren, dann in
`tools/kn5_to_gltf.py` UVs (`TEXCOORD_0`) mitschreiben und die `.dds`-Dateien mit Pillow
nach PNG wandeln. Dafür müssen dann die erzeugten Texturen abgeschaltet werden
(`add_textures = false`).

## Was fehlt / ist anders als in Assetto Corsa

- **Keine Original-Texturen** (siehe oben) – die selbst erzeugten ersetzen nur die Körnung,
  nicht die echten Schriften, Schilder, Plakate und Fassaden.
- **Bäume, Büsche, Gras, Fensterscheiben und Skidmarks sind weggelassen** – das sind in Assetto Corsa
  flache Karten mit Alphakanal; ohne Textur würden sie als große farbige Platten wirken
  (`should_skip` im Werkzeug). Ebenso die Skidmarks.
- **Kein Verkehr, keine Tempolimits, keine Minimap, keine Entdeckerkarte, kein Rennen.**
  Die Strecke hat keine Wegsuche-Daten (`ai/fast_lane.ai` fehlt in dieser Version).
- **Kein Straßenbelag-Modell:** gefahren wird auf dem Dreiecksnetz der Physik-Datei
  (Jolt, `create_trimesh_shape`), nicht auf der prozeduralen Straße.
- Die Ausrüstung des Spiels (Wetter, Garage, Cockpit, Kamera, Rücklauf) ist im Strecken-Modus
  noch nicht angebunden – dort läuft nur Auto, Kamera und ein kleines Tempo-HUD.

## Nächste Schritte, wenn gewünscht

1. Echte Texturen besorgen (eigenes Assetto Corsa + Content Manager, Export als FBX/OBJ).
2. LOD-Stufen für `metal_pole` (6 Mio. Dreiecke) – aktuell nur Sichtweite statt LOD.
3. HUD/Speedometer, Wetter und Garage an den Strecken-Modus anbinden.
4. Startbildschirm „Endlose Welt / Osaka Nanko“ statt Umschalten im Pausemenü.
