# SWITCHBACK — Agent Context

## Project

A first-person parkour time-trial game in Godot 4, targeting Web with the
Compatibility renderer. Players run, jump, surf banks, pull toward reusable anchors
and chase course-local clean-run personal bests. Keep the existing controls and
physics unless the user requests a movement change.

The combat game is maintained separately in `../fps_2d` and
`kickflip-games/kill_bit`. Keep combat systems outside this parkour repository.
Never SSH to Ozstar; prepare scripts for the user to run manually if needed.

## Active scenes and systems

| System | Path |
| --- | --- |
| Player and camera | `scenes/player/player.tscn`, `player.gd` |
| HUD and pause | `scenes/player/hud.gd`, HUD inside the player scene |
| Touch controls | `scenes/player/mobile_controls.gd` |
| Acceleration solver | `scenes/parkour/anchor_pull.gd` |
| Horizontal direction control | `scenes/parkour/air_control.gd` |
| Ghost-ready recorder | `scenes/parkour/run_recorder.gd` |
| Anchor acquisition | `scenes/parkour/grapple_controller.gd`, `grapple_controller.tscn` |
| Permanent anchors | `scenes/parkour/grapple_anchor.gd`, `grapple_anchor.tscn` |
| Directional springs | `scenes/parkour/spring_pad.gd`, `spring_pad.tscn` |
| Contact boosts / updrafts | `scenes/parkour/contact_traversal.gd`, `contact_traversal.tscn` |
| Shared course lifecycle | `levels/parkour/parkour_trial.gd` |
| Course clock and PBs | `scenes/parkour/trial_clock.gd` |
| Presentation | `scenes/parkour/parkour_juice.gd`, `parkour_particles.gd` |
| Screen effects | `scenes/player/speedlines.gdshader`, `scenes/parkour/speed_distortion.gdshader` |
| Effects preference | `scenes/parkour/presentation_settings.gd` |
| Shared city sky / roof | `scenes/parkour/city_sky.tres`, `city_roof.tres` |
| Course city scenery | `levels/parkour/*_city_scenery.tscn`; VEILRUN uses `rooftop_city_district.tscn` |

The primary `levels/parkour/MainCityRun.tscn` instances seven modular city sectors,
one player and six invisible timing boundaries. It combines momentum pull,
horizontal manual aim and surf, with a separate `veilrun_city_v1` PB identity. Its editable
Cyclops blocks live in `tools/city_authoring/MainCityCyclops.tscn`; regenerate
with `tools/build_main_city.py` and `tools/export_main_city.gd`, then validate
actual capsules, branches, checkpoint entry states and anchor LOS.

The reference `levels/parkour/rooftop_trial.tscn` (VEILRUN ROOFTOPS) opts into
`use_momentum_pull` and `vertical_look_enabled`. It has five sectors, four gates
and placeholder medals. The three comparison courses are `levels/parkour/parkour_trial.tscn` (SWITCHBACK),
`riptide.tscn` and `switchyard.tscn`. The long extension is `long_course.tscn`.
Course root fields select the title, ID, checkpoint paths, finish path, sectors,
fall height and grapple acquisition bounds. RIPTIDE and SWITCHYARD opt into
`surf_mode`; non-surf boosted landings decay smoothly back to ordinary running.

## Contracts

- The player owns body physics, jump, hook flight/release and capsule restoration.
  `player.grapple` owns acquisition and LOS. Production input uses `press_pull()`
  and `release_pull()`; `request_hook()` is the legacy programmatic toggle.
- InputMap action `grapple` covers hold-to-pull. `jump_or_dash` remains the jump
  action. Press acquires, release immediately disengages and preserves momentum.
  Auto-release consumes the press; acquiring again needs a fresh press. Pause,
  focus loss and recovery cancel held input. Touch uses the same hold/release
  dispatch; internal legacy signal names may remain.
- `AnchorPull` integrates attraction with incoming radial/tangential velocity,
  gravity and bounded horizontal steering. Release/arrival preserve velocity within the cap.
  Momentum pulls also release after approaching and passing the fixture. Arrival
  uses the actual collision-free body segment; colliding slide chords are not
  treated as swept arrivals. An outside-radius pass uses the release cue.
  Incoming motion away from the fixture may turn toward it before this guard arms.
  Release at the first actual closest pass without a minimum-progress gate;
  nearby overhead flybys at speed can release before building much lift.
  Earlier courses retain fixed-speed flight. Manual pitch affects roof aiming.
- `AirControl` redirects horizontal momentum, scales rates with analog strength,
  and brakes opposing input before reversing. Keep vertical/no-input arcs and
  grounded surf-bank behavior; wall contact retains the collision-projected tangent.
- Acquire anchors through angular, range, base-frustum and collision checks.
  Camera roll, dip and speed FOV must not change accepted targets.
- `spring_pad.gd` owns one launch per physical entry. It checks approach height,
  vertical velocity and forward movement, and resets its entry latch on exit.
- Contact boosts and pressure updrafts never join the remote targeting group.
  They request bounded velocity changes through the player only during actual
  capsule overlap. Boosts require grounded forward movement; updrafts retain
  horizontal motion. Pause, inactive gameplay and debug flight suppress forces;
  recovery clears cached contacts.
- Recording is bounded and separate from body physics. Practice clears samples;
  only clean saved improvements emit PB-eligible recordings. Medals are per course.
- The course clock advances only while RUNNING and unpaused. Checkpoints are
  ordered. Recovery marks PRACTICE; a practice finish cannot replace a PB.
- Retry recreates READY. Checkpoint recovery clears inputs, hook state, capsule
  reduction, spring latches, camera offsets and particles.
- The continuous main city opts into in-place sector retry on R and full clean
  retry on Shift+R. Sector retry uses authored entry pose/velocity and marks the
  full run PRACTICE. Comparison courses retain R for full retry. Sector records
  and full-run PBs remain separate; artificial entry states cannot save records.
- `ParkourJuice` is presentation only. It must never change body velocity,
  transforms, collision, inputs, timing or grapple scoring. Strength zero is
  neutral; pause freezes its clock and particle lifetimes. Finish bursts fade
  naturally after gameplay becomes inactive.
- HUD uses `PROCESS_MODE_ALWAYS` for pause controls; body and particles pause.
  World screen distortion draws at CanvasLayer 0 before the HUD at layer 1.

## Saves, rendering and audio

PBs/splits live in `user://parkour_bests.cfg`; effects strength lives in
`user://parkour_settings.cfg`. Native startup imports each legacy
`Kill Bit` file only if its destination is missing. Keep both originals and new
files intact. Tests must use isolated PB paths and never save real preferences.

City background scenery is static and collision-free. Selected adjacent buildings
in the main city have authored simplified body/roof collision for landings and
walking; keep it aligned with their visible roofs. Preserve route body-corridor
clearance, including lower recovery lanes; import rebaked OBJ meshes before visual audits.

Use the Compatibility renderer and explicit `WorldEnvironment` /
`DirectionalLight3D` in each course. Keep screen effects simple, aspect-aware and
clear in the center; preserve zero-strength color output. Duplicate effect
materials per player instance. The particle pool must remain bounded.

`SoundManager` owns background music and short feedback sounds. Its
`AudioStreamPlayer` children clean up on completion. Accelerated headless tests
should stop playback before teardown so the audio mixer can release resources.
`Log` provides the project logger; do not add frame-by-frame logs to normal play.

## Validation and build

Cyclops Level Builder 1.5.0 is installed and enabled in the source project
(`addons/cyclops_level_builder/plugin.cfg`). Use it for future level geometry and
blockouts: block/prism/cylinder/stair creation, face/edge/vertex editing, clipping,
snapping and UV/material editing. Keep the editable authoring scene. Its Godot
scene exporter converts Cyclops blocks to ordinary meshes and optional convex
collision bodies, preserving collision layers/masks. Validate the exported
capsule clearances, anchor LOS and checkpoints before replacing playable geometry.
Current courses use authored boxes and baked meshes; they have no CyclopsBlock
dependency. Web staging excludes Cyclops scripts and its autoload, so exported
runtime scenes must work without the editor addon. Installation/configuration is
confirmed from source; editor interaction is a separate check.

Read `levels/parkour/README.md`, `ANCHOR_PULL.md`, `ROOFTOP.md` and `PLAYTEST.md` for commands and evidence limits.
Use the actual capsule and collision geometry for route, jump, surf and hook
checks. Preserve acquisition boundary, wall/LOS, checkpoint, clock persistence,
pause and touch-dispatch assertions when refactoring. Engine validation is
separate from human balance, comfort and physical-device handling.

`./build_web.sh` stages the active project and creates `build/web/index.html`
and `build/nightreach-web.zip`. Publish to `avivajpeyi/nightreach:html5`.
Do not publish or claim a public release without explicit user authorization
and fresh browser evidence. Keep game logic outside `addons/`; retain required
test/dev tools without importing FPS code.
