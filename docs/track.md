# Second map (City block)

Next to the endless landscape there is a second, fixed world: a city block
(a Sketchfab model in GTA style with a clinic, pawnshop, fish factory, laundromat,
projects, Paramount sign and basketball court, plus a parked yellow Lotus).
Free driving on the streets, no speed limits, no map. AI traffic drives the street
grid, the player can get out on foot (F) and steal an AI car.
The endless world is unchanged and is still the default.

## Starting it

The city is a **map inside the normal game**: main.tscn runs, and only the procedural
world (terrain, roads, traffic, water, map) is switched off while the city geometry is
loaded in its place. Car, garage, HUD, pause menu, weather, settings and photo mode are
the same code as in the endless world, so everything behaves the same:
**Esc opens the pause menu ("Game paused")**, not the other world.

| Way | Command |
| --- | --- |
| Start menu | "City block" (it turns into "Endless world" while the city is loaded) |
| Pause menu | same button, reloads the scene with the other map |
| Command line | `"Godot_v4.7.2-stable_win64.exe" --path . -- --track=city` |

Photos and measurements:

```
-- --shot=NAME --wait=6     photo after 6 s into screenshots/NAME.png, then quit
-- --bench=8                measure the frame rate for 8 s and print it
-- --spawn=X,Z --heading=G  different start position (metres, degrees; 0 = +Z, 90 = +X)
-- --time=18                time of day in hours
```

## Data

- `assets/tracks/city/city.fbx` — the model (7.4 MB), 558 × 234 m, 31 050 triangles,
  1325 meshes, 22 materials with real PNG textures, height 0 … 31.9 m.
- `assets/tracks/city/*.png` — the textures from the download. Godot imports the
  FBX itself (ufbx); there is no converter of our own any more.
- The folder `assets/tracks/` is in `.gitignore`: the licence of the model does not allow
  redistribution, the map stays local only.

## How the world is built

`scripts/city_map.gd` (the `CityMap` node in `scenes/main.tscn`) and the city branch in
`scripts/game.gd`:

- `CityMode` (in `scripts/city_mode.gd`) is a static flag: the menus set it and reload
  `main.tscn`, the game then loads the city instead of the endless world.
- Everything that needs roads or terrain is switched off (terrain, roads, traffic, water,
  grass, horizon ring, minimap, navigation, speed limits, race, viewpoints, fast travel,
  car reset, chill mode, tunnel effects, walking on foot). The nodes stay in the scene, so
  the rest keeps working.

1. **Merge**: all 1325 meshes are welded, with their world coordinates, into *one*
   surface per material (`SurfaceTool.append_from`). 1325 draw calls become 22 — the
   difference between 60 and 140 FPS. Takes ~0.45 s.
2. **Physics**: the same surfaces become a single trimesh
   (`ConcavePolygonShape3D`, 31 050 triangles). A separate physics file like the old
   Assetto Corsa track had is not needed at this size.
3. **Kerbs**: the pavement is 20 cm higher than the road, and the car body sits only
   a few millimetres above the road, so its collision box hit the kerb edge and the car
   stopped dead there. Now the two jobs are split:
   - **Drawing**: every ground vertex below 50 cm is squashed towards the road
     (`flatten_ground`, `kerb_squash` 0.15, `kerb_step` 2 cm, 6 495 vertices), so the
     kerb stays a visible 2 cm step. The ground is *not* snapped onto one plane any
     more: the map has 1 596 vertices at road level and 5 742 on the pavement, and one
     plane for both made the whole pavement flicker while driving (two surfaces at the
     same height — the depth buffer cannot decide which is in front).
   - **Physics**: the trimesh gets one flat ground (road level, `_physics_point`), so
     nothing can catch on the step; the wheels sink 2 cm into the pavement, which is
     invisible, and the car drives onto it everywhere. Check:
     `Godot --headless --path . -s res://tools/kerb_test.gd` — it drives from the road
     north over the kerb at six spots and prints where the car ends up.
   - The kerb faces are left out of the physics as well (`ignore_kerb_faces`).
4. **Parking**: `scripts/city_parking.gd` puts three parking lots on the empty ground
   (two large fields west and east of the blocks, one empty block in the middle). Each
   lot is an 8 cm slab with a 1.2 m slope all around, with white lines for the stalls
   (2.7 × 5 m, 6 m aisles). Heights matter here: at 2 cm the slab flickered against the
   flat ground of the map from a distance, and the lines 4 mm above the asphalt flickered
   right away — hence 8 cm for the slab and 3 cm for the paint. The slab keeps its height
   in the physics (`keep_physics_height`), so the car drives up the slope; the paint is
   drawing only (`skip_physics`), otherwise every stripe was a 3 cm bump. Spots and sizes
   are in `CityParking.LOTS`, the empty places were found with `tools/city_probe.gd` (it
   prints free 4 m cells and renders a top-down view).
5. **Edge**: the map is an island; four invisible walls at its hull keep the car in
   (`boundary_walls`).
6. **Sky**: the endless world's day/night and weather systems keep running, so time of
   day, seasons and rain work on the city map too. The light surfaces of the model (the
   `*GLOW` materials: lit signs and windows) are given low emission from their texture,
   so they read as lit at night without turning into white blobs.
7. **Anti-aliasing**: temporal anti-aliasing is switched on for the city
   (`get_viewport().use_taa`), because the straight edges of buildings, poles and
   kerbs sparkle while driving without it.
8. **Loading**: the loading screen stays up until the car model is built
   (`CITY_CAR_TIMEOUT` 6 s at most). Until then the car is a painted box, and in the
   endless world the longer terrain loading always hid that moment.
9. **Big map (M)**: the city has no road network to draw, so the map would be empty. At
   load the city is rendered from above into a picture (`_build_map`), in the same dark
   style as the terrain map of the endless world: every triangle of the merged meshes is
   filled into a picture point grid at 5 px/m, and a height buffer decides which surface
   is on top (a roof wins over the street below). Streets and parking lots take their tone
   from their own albedo texture (`Roads_Grounds.png`), so the painted lane markings appear
   as light lines on dark asphalt; the luminance is compressed (`MAP_ASPHALT_TONE`,
   `MAP_ASPHALT_GAIN`, `MAP_ASPHALT_CURVE`) because the texture is much too bright as a
   map. Roofs are shaded by height (`MAP_LOW` → `MAP_HIGH`, like the mountains of the
   endless world) with a light from the north-west, trees and props stay dark, and the GLOW
   materials (windows, signs) are left out, they show nothing from above. The parking lots
   are drawn on top with their stall rows. The picture costs about 3 s once at load
   (2790 × 1170 px, `map_pixels_per_meter` 5.0); `tools/city_map_test.gd` builds just the
   picture and saves it as `screenshots/city_map.png`. The big map then draws it in world
   coordinates (`MapView.city_texture`), so zooming and dragging work as usual, with the
   car arrow on top. There is no navigation in the city (no roads to route along). The map
   opens on the centre of the block at the largest scale that still fits it on screen
   (`BigMap._fit_city`, about 0.45 m/px at 1280 × 800 instead of the old fixed 0.6 m/px),
   because the block is only 558 × 234 m and covered barely two thirds of the width.
10. **Start**: `spawn_point` (-250, 1, -68.3), `spawn_heading` 90° — right lane of the
   east–west street, looking east. The street runs at z ≈ -83 … -65, the
   double yellow line at z ≈ -71.7.
11. **Falling poles**: the model has 18 lamp posts and traffic light poles. They are not
    merged into the city surfaces: `_pole_of()` finds them (tall, and the bottom edge is
    narrow — the lamp sits on an arm that makes the whole mesh 2 m wide) and
    `_spawn_poles()` puts each one in as its own node, with the model mesh hanging below a
    pivot at its foot (`scripts/falling_pole.gd`). Driving into one with more than 5 km/h
    tips it over (88° away from the car, about 1 s) and switches its collision off while
    it lies there; 5 s later it stands up again by itself in 0.9 s. `falling_poles` on the
    `CityMap` node switches the whole thing off (then the posts stay in the merged mesh).
    Check: `Godot --headless --path . -s res://tools/pole_test.gd` — it drives into three
    posts and prints tilt, closest approach, whether they stood up and their height while
    lying down.

## Limits

- No pedestrians, no sign logic. The minimap and the navigation banner are
  hidden because the map has no road network for them.
- Map and chill mode are switched off in the pause menu while the city is loaded.
- The streets are flat: no slopes. The pavements look 2 cm high but are flat for
  the physics (see kerbs above), so the car never catches on an edge.
- Nothing exists beyond the edge of the map; the walls stop the car.
- Shadows of the city geometry cost frame rate (`geometry_shadows`).

## AI traffic (`scripts/city_traffic.gd`)

The city has no procedural road network, so `CityTraffic` carries its own street
grid (`H_ROADS` / `V_ROADS`), measured once from the road surface of the model
(the `Roads_Grounds` material, asphalt at y ≤ 0.10 m). Streets cross on a grid,
so every crossing becomes a graph node and every stretch between two crossings an
edge. Up to `COUNT` (16) cars drive kinematically on the right-hand side of the
road, keep a distance to the car in front, slow for corners and stop when the
player — on foot or in a car — is in their way.

The cars are real models from the downloads in `assets/models/npc/`: the Scion xD,
the Suzuki SX4, the Pontiac G8 GXP and the whole TrafficRider pack (BMW, VW, Ford,
Mazda, Škoda, vans, trucks …), 26 in all. Each model is measured once, scaled to a
sensible size, centred and dropped onto the ground, then copied per car (meshes are
shared). The list lives in `CityTraffic.NPC_MODELS` and shows up in the garage as the
**Traffic** page of the Collection (grouped by brand). A missing model falls back to
the box cars that the endless world's Traffic builds. Every car gets a solid body near
the player so the player's car can bump into it.

While on foot, pressing F next to an AI car steals it (the AI car vanishes and
the player's car is placed where it stood, then the player gets in).

## On foot (`scripts/on_foot.gd`)

F gets out when the car is standing (under 2.5 m/s), F gets back in when the
character is within 4 m. WASD walks relative to the camera, Shift runs, Space jumps
(about one metre high, with 0.12 s of coyote time after leaving a kerb), the mouse
looks around, the body turns into the walking direction and the legs and arms are
animated in code (`scripts/character_animator.gd`). Standing still, the character
breathes; in the air the legs tuck, and on touchdown a short crouch (0.34 s) and a
thud play, scaled by the fall speed. Footsteps are generated at startup
(`scripts/footsteps.gd`, three variants plus a landing sound, no audio files) and
are emitted by the animator at every foot contact.

The third-person camera is a **boom with collision**: a ray from the head to the
wanted spot (3.6 m behind, height 1.5 m) shortens the boom when a wall, a lamp post
or the kerb is in the way. It pulls in fast (`CAMERA_PULL_IN` 24/s) and goes back
out softly (`CAMERA_PULL_OUT` 5/s), keeps 28 cm of air to the wall and never comes
closer than 50 cm; below 95 cm the character body is hidden so it does not fill the
screen. The player capsule and the player's own car never block the camera, so the
camera does not snap when you get out next to the door.

Check: `Godot --headless --path . -s res://tools/on_foot_cam_test.gd` — it builds the
city, gets out, stands 1 m in front of the closest wall and turns the camera into it,
then turns around. It prints the boom length in both cases and `OK`/`FAIL`.
Without `--headless` it also saves `screenshots/on_foot_cam_wall.png` and
`on_foot_cam_open.png`.

Check movement: `Godot --headless --path . -s res://tools/on_foot_move_test.gd` — walks
2 s (8.4 m, 7 step sounds), jumps (apex 1.05 m, lands after 0.65 s), and measures the
air pose (lowest foot 8 cm higher, knee 60°) and the landing crouch (head 8.8 cm
lower). It prints `OK`/`FAIL`; with a window it also saves `on_foot_walk.png`,
`on_foot_jump.png` and `on_foot_land.png` (jump seen from the side).

## Using another map

1. Put the new model (FBX with its textures in the same folder) into `assets/tracks/<name>/`.
2. Point `city_file` on the `CityMap` node in `scenes/main.tscn` (or in the script export) at it.
3. `Godot --headless --path . --import`, then check with `-- --shot=test --wait=5`.
4. Adjust the start: try `-- --spawn=X,Z --heading=G` and copy the values into
   `spawn_point` / `spawn_heading`.

## Measurements (2026-11-21, RX 7700 XT, 1280 × 800)

- Merge + squash ~0.5 s, physics 28 212 triangles (parking included, 748 of them moved
  into the 18 poles), FBX import a few seconds. Start to drivable: ~7 s, most of it the
  car model.
- Pole test: all three posts tip over to 88° while the car drives into them and stand up
  again 6.1 s later (5 s rest + 0.9 s rise). While lying the mesh sits at y ≈ -0.1 … 0.2 m,
  i.e. on the asphalt.
- Kerb test: at -100 and -40 the car crosses the kerb and keeps going north at ~85 km/h;
  at the other spots it climbs the kerb and then stops against a building or fence
  behind the pavement (correct).
- `--bench=8`: **140 FPS average**, worst frame 7 FPS (start-up).
- The endless world still starts unchanged (no script errors).
