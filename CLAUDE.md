# Night Chase – project instructions for Claude Code

## What this is

A 3D game in Godot: an endless, procedurally generated landscape with mountains, valleys,
rivers, lakes and a road network you drive through in a car. With a day/night cycle and
graphics that should feel as atmospheric and realistic as possible (the model is GTA and
Forza Horizon, on an indie scale). The world is deterministic: same seed (1337) = same world.
It is generated in tiles around the player and far-away tiles are removed again.
As a Windows program the game is called "Night Chase".

## About me (Nick)

- I study Business Information Systems and I am still a beginner at programming
  (basics in Python). GDScript and Godot are new to me.
- Answer me in English, casual and easy to follow.
- After every step explain in 2–4 sentences what you built and how I test it.
- When you make a decision that strongly affects the game
  (e.g. graphics vs performance), briefly tell me the options.

## Tech

- Godot 4.7.2 (stable, standard edition without .NET), GDScript only, with static types
  (`var speed: float = 10.0`), Forward+ renderer, Jolt 3D physics (built into Godot).
- Goal: a smooth 60 FPS on a normal Windows laptop, at least 60 on "High".
  Graphics features are switchable through quality levels (Low/Medium/High/Ultra).

## How we work (important!)

1. **One milestone or task at a time.** Do not run ahead.
2. **Plan first, then build.** Show me the plan and wait for my OK.
3. **Small steps.** Start the game after every sub-step (Godot MCP `run_project` /
   `get_debug_output` or terminal), fix every error and warning.
4. **Run `tools\test.ps1` after every part** (and the world checker when roads, terrain
   or tunnels are affected). A part is only done when it says "OK". See `docs/testen.md`.
5. **You cannot see the game.** Take photos with `--shot` and look at them. When it is about
   looks, also ask me concretely what to look for.
6. **Commit after every working step** with a clear English message, e.g.
   "Milestone 2: terrain chunks load in". Push only when I say so.
   Never `git add -A`; do not commit: `AGENTS.md`, `.codex/`, `PROMPTS.md`, `screenshots/`,
   models in `assets/models/`, `docs/screenshots/*.jpg.import`.
7. **Do not break what already works.** If a big rebuild is needed, ask first.
8. At the end of every task update "Progress" below and the matching file in `docs/`
   (decisions, numbers, measurements, test commands). Keep it short here, details go to `docs/`.

## Code rules

- Simple over clever. A readable script beats five class layers. No abstractions "for later".
  One script per task.
- Comments in English, variable and function names in English. Everything in English:
  code, docs, UI text, file names.
- Every important number (view distance, chunk size, car values) as an `@export` variable at
  the top of the script, so I can change it in the Godot editor myself.
- Procedural generation always through `FastNoiseLite` with a fixed seed.
- Heavy generation (terrain meshes, roads) in the `WorkerThreadPool`, never on the main thread.
- Scenes (.tscn) may be edited as text, but they must stay clean and valid.

## Folders

```
scenes/   .tscn scenes (main.tscn, car.tscn, …)     cars/    car profiles (*.tres)
scripts/  .gd scripts, one per task                  tools/   test and measurement tools, build
shaders/  .gdshader files                            docs/    technical notes, README images
assets/   models/ (not in the repo), textures/, hdri/, icon/, CREDITS.md (source + licence)
```

Assets only with a free licence (CC0 preferred: Poly Haven, Kenney, ambientCG), each listed in
`assets/CREDITS.md`. If one is missing: say exactly what I should download and where to put it,
use a placeholder until then. Car models are never in the repo because of their licences
(`assets/models/README.md`).

## Technical notes: which file for which topic

| Topic | File |
|---|---|
| Terrain, tiles, horizon ring, trees, grass, rocks | `docs/gelaende.md` |
| Country roads, pathfinding, junctions, guardrails, villages, viewpoints | `docs/strassen.md` |
| Motorway, interchanges, ramps, lanes, rest stops | `docs/autobahn.md` |
| Tunnels (generation, tube, equipment, holes in the terrain, checker) | `docs/tunnel.md` |
| Rivers, lakes, dams, waterfalls, landmark bridges, lake life | `docs/wasser.md` |
| Driving physics, profiles, models, lights, sound mix, plates, dyno, cockpit, rewind | `docs/autos.md` |
| AI traffic, speed limits, signs, cruise control, races | `docs/verkehr.md` |
| Weather, seasons, sky, moon, aurora, cloud shadows | `docs/wetter-himmel.md` |
| HUD, all keys, garage, map/nav, explorer map, photo mode, chill mode, settings | `docs/hud-menues.md` |
| Measuring FPS, quality levels, measurements | `docs/leistung.md` |
| Test commands, test run, checker tools | `docs/testen.md` |
| Building the Windows version, version and changelog, logo, README images | `docs/windows-app.md` |
| Second map "City block" (FBX import, merged meshes, physics) | `docs/track.md` |
| Everything done so far in detail, original milestones | `docs/fortschritt.md` |

## Most important keys

WASD drive, Space handbrake, R reset, Esc pause menu (settings), G garage, M map,
P photo mode, L lights, F flash, Q/E indicators, X hazard lights, H horn, N cruise control
(+/−, B distance), V windows, Tab camera (chase/cockpit/ego), U 2WD (M5), hold Backspace = rewind,
F5 weather, J season, T time lapse, F3 FPS.
All keys: `docs/hud-menues.md`.

## Most important test commands

```
$G = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"   # PowerShell; adjust the path to your install
& $G --path . --always-on-top -- --shot=NAME --pos=X,Z --heading=G   # photo into screenshots\
& $G --path . -- --shot=NAME --car=m2 --view=cockpit --steer=left      # cockpit photo (or --view=ego)
& $G --path . -- --bench=30 --highway --full --quality=high           # FPS (docs/leistung.md)
& $G --headless --path . --import                                    # after new class_name
& $G --path . -- --track=city                                        # second map, City block
tools\build_windows.ps1 [-Install | -Download]                       # Windows build, full or download (docs/windows-app.md)
tools\test.ps1 [--app] [--shots]                                     # test run: OK or list of errors
& $G --headless --path . -s res://tools/world_check.gd -- --size=12  # world checker (40 = everything, ~25 min)
```

All arguments are at the top of `scripts/debug_tools.gd`, more in `docs/testen.md`.

## Progress

- [x] M0 setup · M1 driving physics · M2 terrain chunks · M3 sky, day/night, fog, shadows ·
  M4 road network · M5 rivers, lakes, bridges · M6 vegetation · M7 BMW M2 with lights, tyre
  marks, sound · M8 pause menu, settings, quality levels · M9 villages and AI traffic
- [x] Extras: garage with 8 cars (BMW, Mercedes-AMG) and dyno · minimap and nav · weather
  and seasons · tunnels · glass-style HUD · motorway without a speed limit, with interchanges,
  lanes and rest stops · viewpoints and photo mode · pops & bangs, turbo · rainbow,
  cloud shadows, aurora, moon phases, shooting stars · grip levels, indicators, horn ·
  traffic with real models · speed limits, cruise control with ACC · flash-to-pass races · windows,
  licence plates, puddles, autumn leaves · dams, waterfalls, landmark bridges, lake life ·
  explorer map, place collection · chill mode · Windows program "Night Chase" · README in
  English, GitHub (nicks2d/Car-Driving-World), releases with the download version
- [x] Clean-up: CLAUDE.md split into `docs/` · test run `tools\test.ps1` and world checker
- [x] Road bugs, wider ramps · tunnels sealed from the outside · reset to safe spots ·
  licence plate at the position of the original · cars visible in the exported game (export setting)
- [x] Cockpit and ego view (Tab): steering wheel 14:1, instrument cluster, mirrors, head movement ·
  camera with spring, body dives and rolls, collisions with sparks and loops ·
  indicators in the lamp glass, welcome light, headlights with cut-off line ·
  M5 2WD mode, rewind up to 10 s (with traffic) · drops, snow and ice on the car,
  contact shadow · 48 kHz sound, limiter, ducking, room reverb
- [x] Right of way at junctions (signs, stop lines, AI waits) · traffic by time of day, rush hour, jams ·
  tunnel equipment (SOS, escape route, fans, lay-bys, name) · trees in 3 steps with
  impostors, soft LOD transitions, forest edges, clearings, reeds · rock without repetition, grass edge,
  patches, rounded crests · stutter hunt (slow BENCH), preparing shaders
- [x] Loading screen with images, progress and tips · soft menu animations · toasts without overlap ·
  key hints (rest stop, rest area, viewpoint, dyno) · version 1.0.0, CHANGELOG.md, "What's new" ·
  Windows build in two variants (full local only, download with CC-BY models only) · release v1.0.0 on GitHub
- [x] Second map "City block" (Sketchfab FBX, 558 × 234 m, merged meshes, single trimesh physics) ·
  old Assetto Corsa track removed · real BMW M2 model instead of the placeholder box
- [x] City block is a map inside main.tscn: car, garage, HUD, pause menu (Esc), weather and
  settings all work as in the endless world; kerbs are drivable (flat ground) · English sweep
  started (CLAUDE.md, START-HERE.md, docs/track.md)
