# SWITCHBACK playtest

Run the project (F5) and choose **VEILRUN · CITY RUN** for the continuous city.
Earlier prototypes remain under comparison courses. Each course has ordered
checkpoints, clean-run personal bests, practice recovery and a finish screen.

## Controls

- WASD / arrows move; mouse looks. VEILRUN supports upward/downward aiming.
- Hold either mouse button to pull toward the bracketed architectural fixture;
  let go to immediately release. Touch PULL uses the same hold/release action.
  Attraction adds to incoming momentum; release timing changes the arc.
  Space jumps with a short coyote window and buffer.
- VEILRUN releases automatically once you approach and pass a fixture, preserving
  your flight. A close swept pass counts as arrival; a wider pass releases. Initial
  motion away from an overhead/side fixture can still turn toward it before you approach.
  A nearby overhead flyby at speed may release before gaining much height; hook
  earlier or brake first when you need lift.
- Hold W and look toward a landing to turn in the air; A/D also redirect momentum.
  Opposite input brakes before reversing. Boosted landings slow smoothly, and
  glancing wall contacts preserve travel along the wall.
- In the main city, R retries the sector with its authored entry speed and
  marks the attempt PRACTICE; Shift+R creates a clean full run. Earlier courses
  keep R for a full retry. Backspace and major falls recover at the checkpoint.
- Escape pauses. Paused time does not count; retry and main menu remain available.

Touch controls use MOVE / LOOK sticks (TURN on older courses), PULL, JUMP, RETRY, CHECKPOINT and II for
pause. Pull MOVE backward to brake. Landscape orientation gives the controls
more room; `-- --mobile-controls` previews the layout in the native runtime.

## Movement feedback

Effects build above normal running speed. Peripheral streaks and wind motes show
acceleration; field of view widens, and the camera leans with lateral motion,
turns and surf banks. A small screen warp affects the world edges while keeping
the center and HUD clear. Jump, landing, spring, grapple and gate events produce
short particle bursts. Landing and takeoff add a damped camera dip.

**Effects strength** on the menu scales camera motion, particles, screen
effects, the new pull cues and speed-scaled wind. Zero gives a neutral camera and no movement FX. The setting persists
locally and does not change speed, steering, jumping, grapple acquisition or
timing. Checkpoint recovery clears effects; pause freezes their animation.

The comparison rooftop finish shows time, difference against your previous PB and medal.
Bronze / Silver / Gold / Developer are placeholder 75 / 60 / 45 / 35-second
thresholds. The 45–75-second first-run target needs human testing.
[Implementation, tuning and five playtest questions](levels/parkour/ANCHOR_PULL.md).

All four courses share the misty rooftop-city setting: slate roofs, masonry
facades, warm windows, lower streets and a night skyline. Their collision routes,
banks, checkpoints and personal-best IDs are preserved.

Useful feedback: is the sense of speed clear, do turns and landings feel good,
and can you read the next obstacle at full speed? Compare a run at 100% with a
lower effects setting. Device performance and comfort need human play.

## Build and share

`./build_web.sh` creates `build/web/index.html` and `build/nightreach-web.zip`.
It uses Godot Compatibility and matching Web templates from an isolated staging
copy. Only the runtime logger is staged from addons; editor tools and the native
profiling overlay stay in source. Authoring tools are also omitted from staging/export. Engine import/export errors
fail the build; `GODOT_BIN` can select the installed engine. Building does not
upload anything.

To preview, run:

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

Open http://127.0.0.1:8765 and click or tap a course to start audio. Desktop play
captures the mouse; mobile Web uses touch controls. Test a complete course,
pause, checkpoint recovery and retry in the browser before sharing the build.
Publication is a separate, explicitly requested action.
`./publish.sh` builds and uploads to `avivajpeyi/nightreach:html5`.
Set `ITCH_TARGET=account/game:channel` to override that destination.

The FPS sources are maintained separately in `../fps_2d`.
Native startup imports legacy `Kill Bit` PB/settings files only when the new
files are missing, preserving originals and existing new scores/settings.

## Validation

[The course guide](levels/parkour/README.md) lists the physics, route and clock
checks with rerun commands. The presentation harness separately checks camera
limits, real jump/landing/spring events, bounded particles, zero strength,
pause, checkpoint reset, finish fade and unchanged grapple acquisition.

The shader render probe checks that zero distortion reproduces the original
image and the aiming center remains clear. These checks establish technical
behavior; human runs judge handling, readability and device feel. Synthetic
mobile input is separate from a physical-device playtest.
