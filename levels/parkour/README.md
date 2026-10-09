# Parkour time trials

Choose **THE CITY RUN** on the main menu for the continuous course; earlier
prototypes are under **COURSE STUDIES**. The active project is the
parkour game; the FPS game is maintained separately in `../fps_2d`
and excluded from active imports and exports.

| Course | Layout | Timing |
| --- | --- | --- |
| **VEILRUN · CITY RUN** | Roughly 2.1 km: eaves, chimney slalom, slate descent, alley, bell hairpin, high ward and final send | Six invisible boundaries; `veilrun_city_v1`; sector practice |
| **VEILRUN · ROOFTOP TRIAL** | Roughly 495 m: rooftop introduction, braided span, vertical courtyard, momentum chain and final shortcut | Four checkpoints; `rooftop_pull_v1`; prototype medals |
| **SWITCHBACK · LONG CIRCUIT** | Roughly 1.1 km: springs, rising bends, sky hairpin, beam cut and rhythm straight | Six checkpoints; `switchback_long_v2` |
| **RIPTIDE · SURF RUN** | Roughly 436 m: downhill drop, 52° V banks, diagonal transfer, offset bridge opening and exit rebound | Four checkpoints; `riptide_v1` |
| **SWITCHYARD · PRECISION RUN** | Roughly 387 m: offset windows, pillar slalom, low tunnel / high bank split, staggered bridge hops and a final right turn | Four checkpoints; `switchyard_v1` |

## Courses

[Continuous city implementation and validation](CITY_RUN.md) records the sector
order, braids, recovery routes, tuning, Cyclops authoring and measured engine run.
The comparison course descriptions below retain their prototype visual language.

**SWITCHBACK:** the familiar spring-to-anchor opening and wide/narrow route split
lead through a velocity drive, rising S bends, sky hairpin, downhill sweep,
spring chain and final sprint. The sky section offers a five-metre beam cut;
the spring chain has landing islands, a lower catch deck and a continuous side
lane. White edges and dark arrows mark the route. The static extension is
editable in `long_course.tscn`.

**RIPTIDE:** the start spring leads into a long descent. The first V channel has
alternating bank anchors and a continuous center keel. The next channel turns
right while descending. Before checkpoint 4, approach the bridge opening on
the right; its closed wall blocks a straight grapple. The final spring is
optional. Fall recovery begins below -34 m.

**SWITCHYARD:** steer toward each offset window, then weave around the pillars.
The split offers a left low tunnel or a right ramp and bank at 6 m. Both merge
before checkpoint 3. The narrow bridge line rewards diagonal jumps with
momentum; a continuous outer lane and lower catch floor offer recovery. The
final wall requires a right turn before FINISH. Fall recovery begins below -12 m.

RIPTIDE and SWITCHYARD opt into `player.surf_mode`. Shallow slopes accelerate
downhill, steep banks slide and momentum persists on landing. Steer across a
bank to adjust the line, then drop into the channel before a gate. Backward
input brakes; the wide lower routes support recovery with the same controls.
SWITCHBACK uses ordinary running below 8 m/s and smooth momentum decay after boosted landings.

## Controls and timing

WASD/arrows move, mouse looks, and Space jumps from floors. VEILRUN supports
vertical aiming; comparison courses retain horizontal look.
Hold either mouse button to pull toward the bracketed anchor; release immediately
disengages while preserving velocity. Auto-release needs a fresh press before
another acquisition. Touch PULL uses the same held gesture. Menu/pause presses
cannot replay on resume. Jumps have a short coyote window and input buffer.
Hold W while looking toward a landing to turn in the air; A/D also redirect
high-speed travel. Opposite input brakes before reversing. Touch uses MOVE/LOOK
(TURN in earlier courses), PULL and JUMP; partial stick movement gives gentler steering.

The main city uses **R** for sector practice and **Shift+R** for a clean full run.
Comparison courses use **R** for full retry, including while paused or finished.
**Backspace** returns to the latest checkpoint; before the first checkpoint it
restarts from the beginning. Falling below the selected course's fall height
returns to the last checkpoint (-12 m for SWITCHBACK / SWITCHYARD; -34 m for
RIPTIDE; 4 m for VEILRUN). **Escape** pauses. Touch RETRY / CHECKPOINT provide the same actions.
Recovery clears held sticks, grapple state, capsule reduction and spring entry
latches. Main-city sector recovery restores authored 12 m/s entry velocity;
comparison-course recovery starts at rest.

Cross START to begin timing. All checkpoints must be crossed in order;
duplicate and out-of-order gates do not advance the run. The HUD shows km/h,
completed checkpoints, the next sector and checkpoint time differences against
the corresponding split of the personal best. Paused time does not count.

Checkpoint recovery marks the attempt **PRACTICE**. It can finish, but cannot
set a PB. R creates a clean attempt. Clean PBs and their matching cumulative
splits persist in `user://parkour_bests.cfg`, in the course sections above.
Old `switchback_v1` scores remain separate because the layout is longer. The
finish screen shows time, personal best, clean/practice status, retry and menu;
it also displays save errors.

SWITCHBACK uses its own Godot save directory. Native startup imports PB/settings
from the legacy `Kill Bit` directory only when each new destination is missing.
The import preserves the originals and never replaces existing new scores or
preferences.

## VEILRUN rooftop prototype

The menu now features `rooftop_trial.tscn`, course ID `rooftop_pull_v1`. It uses
momentum-preserving acceleration toward architectural rings and enables manual
vertical aiming. Five sectors braid forgiving roofs and recovery bridges with
shorter pull lines. R still retries immediately; four ordered checkpoints guard
clean PBs. Finish reports previous-PB delta and exported prototype medals.

[Implementation and all tuning parameters](ANCHOR_PULL.md) ·
[Roof geometry, routes and validation](ROOFTOP.md).

The transform recorder is separate from player physics, samples at 10 Hz with a
9,000-sample bound, and exposes run/PB signals for future ghosts. Recovery clears
recording, and only complete clean saved improvements are PB-eligible. Replay,
ghost-file persistence and online ranking are future work.

## Movement and presentation

The shared player owns physics and hook flight. `GrappleController` handles
permanent anchors through range, angular, base-frustum and line-of-sight checks.
In the earlier comparison courses, normal grounded speed is 8 m/s, jump impulse
5.5 m/s, hook flight 38 m/s and
arrival speed 22 m/s. Non-flight momentum is capped at 32 m/s. All courses share
horizontal air direction control at up to 240°/s, with 32 m/s² low-speed
acceleration and 56 m/s² opposing-input braking. Steering redirects momentum
without adding sideways speed or changing the vertical arc. No-input air drag
remains 0.12/s (0.03/s in surf courses). Boosted non-surf landings retain the
0.5 s exit grace, then decay smoothly at 0.65/s while steering or 2/s while
coasting; ordinary running remains 8 m/s. Grounded surf-bank acceleration stays
12 m/s² and retains momentum on landing. Early release preserves momentum within the cap.
The flight capsule is reduced; arrival does not automatically place the player
on a landing.

Comparison acquisition is 26 m with 18° horizontal / 40° vertical bounds, further
limited by the original 75° camera frustum. VEILRUN uses 20° / 42° bounds and balanced angular crosshair scoring with
manual pitch. Camera roll, dip and speed FOV do not affect which anchors can be acquired. Spring arrows show their configured
launch direction. Each spring triggers once per entry and retains a configured
fraction of perpendicular horizontal momentum. Chain springs use strength 24,
direction `(0, 0.42, -1)` and lateral retention 0.65.

`ParkourJuice` handles speed FOV (+14° maximum), lateral / turn / bank roll
(7° maximum), a damped landing dip, peripheral speed streaks and one-sample
edge distortion. The center stays clear and the effect draws below the HUD.
Controlled shader time freezes with pause. Jump, landing, spring, grapple,
checkpoint and finish events feed a bounded CPU particle pool. Graphite dust
reads against white floors; white motes read against banks and the void.
Checkpoint recovery clears old particles and camera offsets; the finish burst
fades naturally while trail and screen effects stop.

**Effects strength** (0–100%) controls presentation only and persists in
`user://parkour_settings.cfg`. Zero restores the neutral camera and hides FX, including the new pull cues and
speed wind. Anchor target highlights remain readable.

## Validation

The adapted active-project suite passed in Godot 4.8.dev6 on 2026-10-04:
SWITCHBACK 83 checks (84 with touch dispatch), surf routes 70 (72 with touch),
movement 16, actual banks 9, narrow/high lines 20, window grapples 17 and
presentation 40. The standalone clock suite passed 10 cases / 127 assertions.
The final runs exited cleanly; logs are under `/tmp/switchback_archive_*.log`.

The Web export's Godot 4.6 runtime also passed the complete SWITCHBACK and surf
routes, surf touch dispatch, the five-anchor chain, all 40 presentation checks
and the 127 clock assertions. The menu, active course HUD and pause panel were
rendered and inspected in Compatibility. A mounted export-pack audit found all
three courses and the grapple controller, with no archive, combat or test files.

The harnesses use actual player capsules, collision bodies, anchor acquisition,
Area3D entries and ordinary movement inputs. All test PB paths are isolated from
`parkour_bests.cfg`; the juice harness changes the effects preference only in
memory and verifies that the real settings file is unchanged.

| Harness | Checks |
| --- | --- |
| `validate_parkour_course.gd` | SWITCHBACK wide/safe route, beam shortcut, real springs, representative anchor flight, six checkpoint respawns, finish order, fall recovery, pause and retry |
| `validate_surf_courses.gd` | Complete RIPTIDE / SWITCHYARD safe routes, actual gates and finish, checkpoint floors, practice PB protection and retry |
| `validate_surf_movement.gd` | Downhill acceleration, 55° bank contact after exit grace, landing momentum, braking, jumps, 32 m/s cap, wall collision and blocked acquisition |
| `validate_air_control.gd` | High-speed shallow/right-angle turns, opposing-input brake/reversal, touch analog/look routing, vertical arc, smooth landing through release grace, pull steering and glancing wall release |
| `validate_riptide_banks.gd` | Four actual course banks with live capsule contact, momentum retention and speed limits |
| `validate_switchyard_lines.gd` | High route and two narrow bridge jumps, intended landings with full capsules and clearance from the catch floor |
| `validate_switchyard_grapple.gd` | Five-anchor offset-window chain through real angular/range/LOS acquisition, flight and arrival |
| `validate_parkour_juice.gd` | Camera bounds, real event bursts, unchanged body state and acquisition edges, zero strength, pause/resume, reset, finish fade and fixed particle pool |
| `test_parkour_clock.gd` | Clock order, splits, persistence, course-version separation and practice PB protection |

Run the standalone probes with an installed Godot binary:

```sh
/path/to/Godot --headless --path . --script tests/validate_parkour_course.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_surf_courses.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_surf_movement.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_riptide_banks.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_switchyard_lines.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_switchyard_grapple.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_parkour_juice.gd --fixed-fps 60
```

Add `-- --mobile-controls` to the course or surf-course probe to exercise
synthetic touch CHECKPOINT / RETRY dispatch and clearing held sticks. Run the
standalone clock suite:

```sh
/path/to/Godot --headless --path . --script tests/test_parkour_clock.gd
```

A rendered Compatibility probe checks the shader's clear center and exact
zero-distortion output. Build and browser-preview instructions are in
[PLAYTEST.md](../../PLAYTEST.md). Controlled engine checks establish technical
behavior. Human play judges route readability, shortcut difficulty,
grapple-release timing and the urge to retry. Web frame rate, comfort and
physical-device touch handling need device playtesting.

## Anchor-pull validation

New probes run alongside the comparison-course suite:

```sh
/path/to/Godot --headless --path . --script tests/validate_anchor_pull.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_rooftop_course.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/validate_pull_feedback.gd --fixed-fps 60
/path/to/Godot --headless --path . --script tests/test_rooftop_time_trial.gd
/path/to/Godot --headless --path . --script tests/validate_rooftop_restart.gd --fixed-fps 60
```

Use 30 / 60 / 120 Hz for the force probe. It exercises actual CharacterBody
collision, pull arcs, manual release, arrival, chaining, steering, pause, wall
handling and capsule restoration. The feedback probe checks overhead collider
acquisition, balanced target scoring, neutral-camera invariance, independent
fixture materials, touch pitch, sound completion, wind pause/reset and unchanged
saved preferences. The time-trial suite covers medal boundaries, prior-PB delta,
practice protection, bounded recording and scene-level run/PB signal behavior.

All probes use isolated PB paths. Engine route timing is a scripted trace; human
balance, route readability, aiming comfort and the wish to retry remain playtest
questions. The built Web runtime also needs a fresh browser/device play pass.

The final implementation passed 142 rooftop route checks on 4.8 and 4.6, 39 force
checks at 30/60/120 Hz (and 4.6/60), 22 feedback checks, 92 time-trial assertions,
and the complete comparison-course regression suite. Real device 0 R/Space input
passes 45 headless checks and 49 rendered GPU checks on each engine, including
running, paused and repeated retry. A local browser smoke test confirms menu,
rooftop launch, pause, pause-button retry and physical R retry. It is not a full
browser course completion or mouse-capture/device playtest; the in-app browser
reported a generic Chromium input error and did not capture the pointer.

The final 4.6 Web build has no import/export errors or warnings; ZIP integrity
passes. `tests/audit_web_pack.gd` mounts the generated PCK and verifies all four
courses, force solver and recorder, while rejecting archive, combat, tests and
editor addons. Build staging keeps only the runtime logger from `addons/` and
omits the native profiling overlay. Source authoring tools remain available.


## Responsive steering validation

The responsive-steering pass on 2026-10-04 passed 45 actual-body checks at
30/60/120 Hz on Godot 4.8 and at 60 Hz on the Web export's Godot 4.6 runtime.
A 30° turn at 32 m/s aligned within 0.2 s while retaining 31.24 m/s; 45°/90°
turns aligned within 0.5 s. Full touch input matched keyboard intent; partial
touch input produced gentler steering. The authored routes and presentation
matrix passed 553 checks; rooftop and landing probes also passed on 4.6.
Independent checks verified unchanged no-input air/pull traces and preserved
vertical force while steering. These measurements do not establish human feel.

```sh
/path/to/Godot --headless --path . --script tests/validate_air_control.gd --fixed-fps 60 -- --air-fps=60
```

Use matching 30 / 60 / 120 values for `--fixed-fps` and `--air-fps`. Logs are
`/tmp/air_control_{30,60,120}.log` and `/tmp/air_control_stable_60.log`.
The rebuilt local browser version launches, pauses and retries; the in-app
browser still fails pointer capture, so desktop aiming/comfort needs a normal
browser playtest.


## Shared rooftop-city setting

All four courses use the existing rooftop city's night sky, masonry/slate
palette, textured facades, warm windows and lower street layer. Each comparison
course has a static, route-aware `CityScenery` instance; VEILRUN keeps its
original `CityDistrict`. Lower streets sit below the fall plane, and decorative
roof supports end below the lowest overlapping route, including catch decks.
The old red void visuals are hidden. All authored collision shapes, anchors,
springs, gates, respawns and movement/acquisition tuning remain unchanged.

The comparison scenery is baked with the shared city kit, without runtime CSG,
new collision or imported source-model copies. It uses 118 / 90 / 73 spatial
material batches and 102,438 / 73,530 / 49,758 triangles for SWITCHBACK / RIPTIDE /
SWITCHYARD, with six bounded shadowless lamps each. The slate roof material uses
world triplanar mapping so tile size remains consistent on long roads and banks.
Sky and fog are explicit per course; RIPTIDE's height fog follows its lower city.

To regenerate the comparison scenery from actual course geometry:

```sh
/path/to/Godot --headless --path . --script tools/export_city_geometry.gd
python3 tools/build_course_cities.py
/path/to/Godot --headless --path . --script tests/validate_city_courses.gd --fixed-fps 60
/path/to/Godot --path . --script tests/render_city_courses.gd --resolution 1280x720
```

Import regenerated OBJ files before the mesh audit or rendering. The audit
compares pre-dressing collision/config signatures, preserved physics functions,
actual checkpoint floors, scene budgets and imported mesh triangles against
body-height route corridors. This catches decorative posts that could look solid
while having no collision. Screenshots live in `build/city_previews/`.

`tests/validate_grapple_click.gd` checks raw left/right mouse and first-finger
touch press/release, quick double-clicks, continued unheld flight, automatic
arrival/timeout, paused/inactive guards, actual GUI Resume clicks and reset.
It passes 55 checks on Godot 4.6 and 4.8 in headless and native Compatibility
runs. These input checks are separate from physical-device/browser play feel.

VEILRUN momentum pulls release after an approach and closest pass, preserving
the current trajectory. Arrival uses the actual swept body segment against the
1.8 m radius when that movement did not collide, so a fast pass between ticks
still counts without claiming an arrival through a bent wall-slide path. An outside-radius pass
uses release feedback. Initial motion away from the fixture may redirect toward
it before the approach guard arms. Earlier fixed-speed flight is unchanged.

The final environment/input pass on 2026-10-04 passed 65 scene/mesh checks on
Godot 4.6 and 4.8 in source and clean staging; all three adapted districts had
zero triangles in the route body corridors. The complete route/presentation
matrix passed 553 checks with clean exits. Six native Compatibility views were
rendered from the export staging and inspected. The Web build and ZIP integrity
passed, and the mounted PCK contains all city scenes while excluding archive,
combat, tests, authoring tools and editor addons. Browser performance and
physical-device feel still need playtesting.
