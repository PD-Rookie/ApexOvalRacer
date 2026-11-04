# Apex Oval Racer

A self-contained 3D arcade racer made with **Godot 4.7.2+**. It uses a
`VehicleBody3D` car, a procedurally built circuit with long straights, hills and
banked corners, four AI rivals, a live leaderboard, sequential checkpoints, lap
timing, a saved best lap, chase camera, and keyboard/gamepad/touch controls.
All geometry and materials are generated in code, so there are no imported art
assets.

The project is configured for the **Compatibility** renderer, which targets
WebGL2 on the web and OpenGL ES 3 on mobile.

## Quick start

1. Install Godot 4.7.2 or newer (standard build, not .NET).
2. Open `project.godot` in the Godot project manager.
3. Press **F5**. The countdown starts automatically.

To run from a terminal:

```powershell
godot --path C:\path\to\ApexOvalRacer
```

## Controls

| Action | Keyboard | Touch |
| --- | --- | --- |
| Accelerate | W / Up | GAS |
| Brake / reverse | S / Down | BRK / REV |
| Steer left | A / Left | Left half of steering bar |
| Steer right | D / Right | Right half of steering bar |
| Handbrake / drift | Space | DRIFT |
| Nitrous (hold) | N | NOS |
| Pause / resume | Esc / P | HUD **PAUSE** button |
| Reset to last checkpoint | R | Pause menu **RESET CAR** |

The car starts in **D**. While stopped or rolling slowly, hold **S**, **Down**,
or **BRK / REV** to reverse; release it to return to drive. The HUD gear shows
**R** while reversing. Nitrous works on its own (no GAS required), drains the
cyan meter, and recharges after a short delay. Pausing freezes the car, race
timer, and touch inputs.

Gamepad buttons can be added to the InputMap actions in
**Project > Project Settings > Input Map** without changing any code.

### Touch controls

- The overlay auto-enables on mobile platforms or when a touchscreen is
  detected.
- On desktop/web it is off by default. Press **TOUCH: OFF** at the top center to
  preview the overlay. Touch input is still required to press its buttons.
- Multi-touch is supported, so throttle, steering, and nitrous can be held at
  the same time.

## How the race works

- The 3-2-1 countdown starts when the scene loads; all five cars are frozen
  until GO.
- You race four AI opponents on a two-column starting grid. The standings panel
  at the top right shows every driver's position and current lap, and changes to
  **FIN** when a racer completes the race.
- The circuit has **six sequential checkpoints**. The first target is checkpoint
  1, because checkpoint 0 is the start/finish line.
- Skipping a checkpoint does not count. A lap only completes when checkpoint 0
  is crossed after checkpoints 1–5.
- The default race is **3 laps**. AI racers can finish before you; the race ends
  when the player crosses the line. The finish summary shows your final
  position.
- Best lap is stored in `user://apex_oval_racer.cfg`, so it persists on desktop,
  Android, iOS, and in browser local storage.
- Pressing **R**, using the HUD reset button, or flipping the car for too long
  respawns it at the last checkpoint.

## Project structure

```text
project.godot                 Project settings, InputMap, renderer, stretching
icon.svg                      Application icon
export_presets.cfg            Web, Android and iOS export presets
scenes/main.tscn              Main scene hierarchy
scenes/car.tscn               VehicleBody3D car with four wheels
scripts/main.gd               Environment, grid placement, AI spawning, race start
scripts/car_controller.gd     Driving, gears, nitrous, grip, drift, off-road, reset
scripts/ai_driver.gd          AI path following, speed control and recovery
scripts/track_builder.gd      Procedural track, walls, checkpoints, scenery
scripts/lap_manager.gd        Countdown, checkpoints, laps, pause-aware timing
scripts/chase_camera.gd       Smoothed follow camera with speed/nitrous FOV
scripts/hud.gd                Speedometer, gear, nitrous, timing, pause, finish
scripts/touch_hud.gd          Multi-touch overlay and debug toggle
```

Scenes are wired through groups rather than hard-coded paths:

- `race_racer`: every car in the race
- `player_car`: the player's `VehicleBody3D`
- `ai_car`: AI opponent cars
- `race_manager`: the lap manager
- `checkpoints`: the six `Area3D` checkpoints
- `touch_hud`: the touch overlay

## Tuning

The main values are exported on the `Car` root node (`car_controller.gd`) and on
the `Track` node (`track_builder.gd`).

Current baseline, measured headlessly on a flat test surface:

- 0–100 km/h: about **4.8 s**
- Top speed: about **141 km/h**
- Braking from 140 to 50 km/h: about **2 s**

Useful car exports:

- `engine_power` — force per driven rear wheel
- `low_speed_boost` — extra launch force
- `brake_force`, `handbrake_force`
- `low_speed_steer`, `high_speed_steer`
- `handbrake_grip`, `offroad_grip`
- `air_drag`, `downforce`
- `nitrous_force_multiplier`, `nitrous_min_throttle`, `nitrous_drain`,
  `nitrous_recharge`, `nitrous_recharge_delay`

If you change `mass`, retune `engine_power` and the suspension together.

Track exports include `segment_count`, `radius_x`, `radius_z`, `track_width`,
`straightness`, `checkpoint_count`, `wall_height`, `elevation_base`,
`hill_height`, `hill_height_2`, `bank_strength`, `max_bank`,
`bank_smoothing_passes`, and the road/grass/wall colors. `straightness` squares
the oval off into longer straights; the elevation and banking values shape the
hills and tilted corners.

AI opponents are configured in `main.gd` with a name, color, skill, lane offset
and start delay. `ai_driver.gd` uses the track's sampled centerline, look-ahead
point and curvature to steer, brake for corners, and recover if it gets stuck.

## Exporting

Install the matching **export templates** first:
**Editor > Manage Export Templates > Download and Install**.

### Web

1. Open **Project > Export**.
2. Select **Web**, then click **Export Project**.
3. Output goes to `build/web/index.html`, `index.js`, `index.wasm`, and the
   `.pck` file.
4. Serve the whole `build/web` folder over HTTP. Opening `index.html` directly
   with `file://` will not work.

Quick local test:

```powershell
python -m http.server 8000 --directory build/web
```

Then open `http://localhost:8000`.

Thread support is disabled in the preset, so the build does not require
cross-origin isolation headers for a basic static host. If you enable
`variant/thread_support`, your server must send:

```text
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

### Android

1. Install a JDK 17 and the Android SDK; set the SDK path and debug keystore in
   **Editor > Editor Settings > Export > Android**.
2. Open **Project > Export** and select **Android**.
3. For direct testing, keep **Use Gradle Build** off and export
   `build/android/ApexOvalRacer-debug.apk`, then install it on the device with
   `adb install -r build/android/ApexOvalRacer-debug.apk`.
4. For Google Play, enable **Use Gradle Build**, switch the export format to
   **AAB**, configure signing, and export.

`architectures/arm64-v8a` is enabled by default; enable `armeabi-v7a` only for
older 32-bit devices.

### iOS

iOS export requires macOS with Xcode installed.

1. Set your Apple team ID and a unique bundle identifier in the **iOS** preset.
2. Export the project. With **Export Project Only** enabled, Godot writes an
   Xcode project/archive to `build/ios`.
3. Open the exported project in Xcode, set signing, then run on a device or
   create an archive for App Store Connect.

## Notes

- The project uses only the Compatibility renderer; do not switch to Forward+
  if Web or low-end mobile support is required.
- The track is generated at runtime. If you replace it with a modeled track,
  keep its drivable surface on collision layer **2** and grass/off-road on layer
  **4**, or update `ROAD_LAYER`/`GRASS_LAYER` in `car_controller.gd`.
- Checkpoints must stay on collision layer **0** with mask **1**, and remain in
  the `checkpoints` group with an `index` metadata value.
