# Fortschritt im Detail

Die Kurzfassung steht in der CLAUDE.md. Hier die ursprüngliche Meilenstein-Liste und alle
erledigten Aufgaben in der Reihenfolge, in der sie gebaut wurden.

## Meilensteine (ursprünglicher Plan)

1. Auto mit guter Fahrphysik auf flacher Ebene, Kamera folgt
2. Endloses Terrain aus Noise in Chunks, mit Kollision
3. Himmel, Sonne, Tag-Nacht-Wechsel, Schatten, Nebel
4. Prozedurales Straßennetz, das sich ans Gelände anpasst
5. Wasser: Seen, Flüsse, Brücken
6. Vegetation: Bäume, Gras, Felsen (MultiMesh, LOD)
7. Echtes Automodell, Scheinwerfer, Rücklichter, Motorsound
8. Grafik-Politur und Qualitätsstufen, FPS-Anzeige, Einstellungsmenü
9. Verkehr (KI-Autos auf den Straßen) und kleine Orte

## Erledigt

- [x] Meilenstein 0: Setup geprüft
- [x] Meilenstein 1 (Feinabstimmung der Fahrwerte nach Nicks Probefahrt möglich)
- [x] Meilenstein 2 (Terrain, Horizont-Ring, FPS-Anzeige, Screenshot-Werkzeug)
- [x] Meilenstein 3 (Himmel-Shader, Tag-Nacht, Nebel, Schatten, Render-Skalierung)
- [x] Meilenstein 4 (Straßennetz mit Serpentinen, Geländeanpassung, Start auf Straße)
- [x] Meilenstein 5 (Flüsse, Seen, Wasser-Shader, Brücken, Auto im Wasser)
- [x] Meilenstein 6 (Bäume, Büsche, Felsen, Gras mit Wind, Stamm-Kollision)
- [x] Meilenstein 7 (BMW M2 Competition: Modell, Antrieb, Licht, Spuren, Rauch, Sound)
- [x] Extra: Autoauswahl mit Garage (5 BMW, Profile, Showroom, Sound pro Motor)
- [x] Extra: Minimap mit Navi (Kartenkacheln, Route über Orts-Graphen, Abbiege-Hinweise)
- [x] Extra: Wetter und Jahreszeiten (6 Wetterlagen, Regen mit SSR, Talnebel, Schnee, 4 Jahreszeiten)
- [x] Extra: Tunnel (statt verworfener Abschnitte, Röhre mit Lampen, Portale, Hall, Augen-Anpassung)
- [x] Extra: HUD im Glas-Stil, Garage in der Welt
- [x] Extra: Autobahn ohne Tempolimit (Anschlussstellen, Schilderbrücken, Leitpfosten, Navi)
- [x] Extra: Aussichtspunkte (Parkbucht, Schild, Entdecken, Karte, Sammlung) und Fotomodus
- [x] Extra: Pops & Bangs mit Flammen, Turbo-Pfeifen mit Ladedruck, Abblasventil
- [x] Extra: Regenbogen, Wolkenschatten, Polarlicht
- [x] Extra: Tunnel-Bug behoben, mehr Grip (Grip-Stufen), Blinker/Warnblinker/Hupe
- [x] Extra: Anschlussstellen an jedem Stützpunkt, Raststätten mit Tankstelle und Rasthof
- [x] Extra: Drei neue Garage-Autos (M4 CSL, SL 65, C 63) mit Marken-Reitern
- [x] Extra: Verkehr mit echten Modellen, Verzögerungs- und Beschleunigungsstreifen
- [x] Extra: Raststätten neu (Tankstellen-Modell, Pkw-/Lkw-Plätze, Inseln, geparkte Fahrzeuge)
- [x] Extra: Wände in langen Tunneln behoben (Horizont-Ring, Schürzen, Vegetation), Prüfwerkzeug erweitert
- [x] Extra: Tempolimits mit Verkehrszeichen und Schilder-Erkennung im HUD, KI und Navi halten sich daran
- [x] Extra: Tempomat mit Abstandsregelung (ACC, 4 Stufen, Warnung, Limits übernehmen)
- [x] Extra: Lichthupe und spontane Rennen gegen KI-Autos, Vorbeifahrt-Geräusche
- [x] Extra: Fenster runter, Wunschkennzeichen, Pfützen mit Fontäne, Herbstlaub
- [x] Extra: Werkstatt mit Leistungsprüfstand (Messlauf, PS-/Nm-Diagramm, Vergleich von 3 Autos)
- [x] Extra: Talsperren mit Staumauer und Stausee, Wasserfälle mit Becken, Gischt und Rauschen
- [x] Extra: Bogen- und Hängebrücken als Landmarke, Badestellen, Campingplätze und Boote an Seen
- [x] Extra: Mondphasen, Sternschnuppen, Lichtverschmutzung (dunkle Nächte fern von Orten)
- [x] Extra: Entdecker-Karte mit Nebel (Sichtlinien von Aussichtspunkten), Orte-Sammlung in der Garage
- [x] Extra: Chill-Modus (Autopilot auf schönen Strecken, Kamera mit Schnitten wie im Film)
- [x] Extra: Mac-App „Night Chase“ (Logo, Startbild, Build-Skript, gleiche Spielstände)
- [x] Extra: README auf Englisch mit allen neuen Funktionen und Bildern, GitHub aktualisiert
- [x] Meilenstein 8 (Pausemenü, Einstellungen mit 5 Reitern, Qualitätsstufen, Tastenbelegung, Audio-Busse)
- [x] Meilenstein 9 (Dörfer mit Häusern, Ortsschildern, Laternen; Verkehr mit KI-Autos)
- [x] Aufräumen: CLAUDE.md nach docs/ aufgeteilt (13.11.)
- [x] Testlauf tools/test.ps1 (Selbsttest mit allen Modi) und Welt-Prüfer tools/world_check.gd (13.11.)
- [x] Teil 3–7 (13.11.): Straßen-Bugs und breitere Rampen, Tunnel-Deckel, Reset, Kennzeichen, Autos in der App
- [x] Teil 1 (16.11.): Cockpit- und Ego-Sicht (Tab) mit drehendem Lenkrad, eigenem Kombiinstrument,
  Rückspiegeln mit Kamera, Kopfbewegung, Innenraum, Regentropfen auf den Scheiben
- [x] Teil 2 (16.11.): Verfolger-Kamera mit Feder und Blick in die Kurve, Sichtfeld 65–75°, Karosserie
  nickt und wankt, Kollisionen mit Funken, Schleifen, Schlag und Kamera-Ruck
- [x] Teil 3 (16.11.): Blinker im Glas der Modelle (Spiegelblinker bei F90 und M4 CSL), Begrüßungslicht
  mit Motorstart in der Garage, Scheinwerfer mit Projektor-Bild (Abblend- und Fernlicht)
- [x] Teil 4 (16.11.): 2WD-Modus für beide M5 (Taste U, Drift 4° → 30°), Zurückspulen bis 10 s mit Verkehr
- [x] Teil 5 (17.11.): Regentropfen auf Lack und Scheiben, Schnee auf dem Auto, vereiste Scheiben am kalten
  Morgen, weicher Kontaktschatten unter eigenem Auto und Verkehr
- [x] Teil 6 (17.11.): Motorsound 48 kHz, Limiter, Signalton mit Ducking bei Ansagen, Hall der Umgebung,
  Pegel per Messung angeglichen
- [x] Teil 1 (17.11.): Vorfahrt an Kreuzungen (Raute, Vorfahrt gewähren, Stopp, Haltelinien, KI wartet),
  Verkehr nach Uhrzeit mit Berufsverkehr und Stau vor Anschlussstellen
- [x] Teil 2 (17.11.): Tunnel-Ausstattung (Notrufnischen, Fluchtweg-Schilder, Ventilatoren, Pannenbuchten,
  Tunnelname am Portal)
- [x] Teil 3 (17.11.): Bäume in drei Stufen (detailliert, mittel, Impostor), weiche Übergänge zwischen den
  Detailstufen, Baumgruppen, Lichtungen, Waldränder, Schilf und Steine am Ufer
- [x] Teil 4 (17.11.): Fels ohne sichtbare Wiederholung, Grasrand am Bankett, Reifenspuren, Flickstellen,
  Kuppen und Senken ausgerundet (bei 250 km/h kein Abheben mehr)
- [x] Teil 5 (17.11., teilweise): Ruckler-Suche pro Bild, Gras und Bäume ruckeln weniger beim Nachladen,
  Shader vorher übersetzen, dünne Teile in der Ferne ausgeblendet. Occlusion Culling noch nicht.
- [x] Teil 1 (17.11.): Ladebildschirm mit wechselnden Bildern, echtem Ladestand und Tipps, weiche
  Animationen in Menüs und HUD, Meldungen ohne Überlappung, Tastenhilfe (abschaltbar)
- [x] Teil 2 (17.11.): Version 1.0.0 (Pausemenü, App-Info), CHANGELOG.md aus der Git-Geschichte, Fenster
  „Was ist neu“ einmal pro Version, Git-Tag v1.0.0
- [x] Teil 3 (17.11.): Mac-App in zwei Varianten: Vollversion in /Applications, Download-Version nur mit
  CC-BY-Modellen (ZIP mit Credits und Lizenzen), Garage zeigt nur vorhandene Autos, Credits nur vorhandene Modelle
- [x] Teil 4 (17.11.): README mit Download-Abschnitt und Version 1.0, Push, Release v1.0.0 auf GitHub mit der
  Download-Version (https://github.com/nicks2d/Car-Driving-World/releases/tag/v1.0.0)
- [x] 22.11.: Neues Symbol (Sportwagen auf Bergstraße bei Nacht), App heißt jetzt „Night Chase“
  (Speicherordner bleibt „Endlose Welt“), zweite Karte heißt „City Block“
- [x] 22.11.: City Block im Haupt-Szenenaufbau (Auto, Garage, HUD, Wetter, Pausemenü mitgenutzt),
  Bordsteine überfahrbar, echtes Auto in beiden Welten
- [x] 22.11.: Flimmern behoben (Straßenbelag lag exakt auf einer Ebene), Kantenglättung (TAA) in der Stadt,
  Schilder und Fenster leuchten nachts, Ladebildschirm wartet auf das Automodell (keine rote Kiste mehr)
- [x] 22.11.: Drei Parkplätze mit Markierungen auf dem freien Feld (West, Ost, leerer Block in der Mitte),
  8 cm Platte mit Rampe; Karte (M) zeigt im City Block ein Bild von oben statt Straßen; Garage mit
  engerem Schattenbereich und TAA gegen Flimmern
- [x] 22.11.: City Block – 18 Straßenlaternen und Ampelpfosten fallen um, wenn man sie anfährt
  (Kollision aus, Neigung 88° weg vom Auto), und stellen sich nach 5 s von selbst wieder auf
  (`scripts/falling_pole.gd`, Prüfwerkzeug `tools/pole_test.gd`, Zahlen in `docs/track.md`)
- [x] 22.11.: Flackern im unteren Teil der Garage behoben – der Werkstattboden liegt jetzt 4 cm über
  dem Grund (`GarageRoom.FLOOR_LIFT`), vorher lag er in einer Ebene mit Straße und Parkplatz-Linien
- [x] 22.11.: Karte (M) im City Block zeigt jetzt dieselbe Art Karte wie die endlose Welt – die Stadt
  wird beim Laden von oben gerastert (Höhenpuffer, 4 px/m, ~1,9 s): Straßen mit ihren Markierungen aus
  der eigenen Textur, Dächer nach Höhe schattiert, Parkplätze mit Stellplatzreihen
  (`scripts/city_map.gd`, Prüfwerkzeug `tools/city_map_test.gd`)
- [x] 22.11.: Auto steht in der Garage gerade auf der schwarzen Hebebühne – die Werkstatt dreht sich mit
  dem Auto (Yaw), die Platte liegt längs unter dem Auto (3,4 × 5,4 m) statt quer
  (`GarageRoom.build(..., yaw)`, `garage.gd:_build_room`)
- [x] 22.11.: Karte (M) im City Block größer und feiner: Beim Öffnen passt der ganze Block mit 4 % Rand
  auf den Bildschirm (rund 0,45 m/px bei 1280 × 800 statt fest 0,6 m/px), Mitte ist die Blockmitte;
  Kartenbild jetzt 5 px/m (2790 × 1170 px, ~3 s beim Laden statt 1,9 s) für neue Objekte auf der Karte
  (`BigMap._fit_city`, `CityMap.map_pixels_per_meter`)
