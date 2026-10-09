# VEILRUN · Rooftop Trial

`rooftop_trial.tscn` is one original industrial fantasy city course. It uses the shared trial lifecycle and the opt-in momentum pull player. The course ID is `rooftop_pull_v1`; earlier courses retain their own IDs, movement profiles and best times.

The design target is a 45–75 second first competent run. This is a tuning target, not a human playtest result. The authored route spans about 436 metres forward and roughly 495 metres along the main ring/landing guide, with broad landing roofs and short alternatives that return before the next gate. A deliberately conservative scripted pull/landing route finishes cleanly in **52.53 seconds** at 60 Hz. Its countersteering and landing detours produce **518.7 metres of sampled body travel**; the guide estimate does not describe that actual trajectory.

## Course layout

Coordinates are Godot metres, with progress along negative Z. Deck heights are the collision top surfaces; grounded player origins sit approximately 0.50 metres above them. Building masses extend down to the street at Y −18, rather than floating as isolated platforms.

| Section | Extent | Safe line and temporary branch | Advanced line |
| --- | --- | --- | --- |
| The Eaves | Start Z 4 → CP1 −60, deck 12 | Broad 24–28 m roofs, forgiving 2 m gap. Intro ring leads toward landing; low catch bridge on the right rejoins the roof. | Earlier release carries speed through CP1. |
| Braided Span | CP1 −60 → CP2 −150, deck 12 | Left landing, broad diagonal transfer to right landing, straight exit ring. Continuous 6 m iron bridges provide a slower recovery route. | Central crane ring and narrow visible beam bypass the left/right landings. |
| Clockcourt | CP2 −150 → CP3 −243, decks 12/16/20/24 | Jump into the low ring, release the middle transfer onto its broad roof, then jump/pull to the high ring. A 7 m service ramp outside the east facade climbs continuously to the upper roof. | From the right approach, jump/pull directly to the high courtyard ring, coast until the top ring enters range, then release toward the tower roof. |
| Iron Current | CP3 −243 → CP4 −335, deck 24 | Three broad staggered roofs. Land after the diagonal transfer if needed; the west service bridge drops to 22 m and returns before CP4. | Successive timed releases steer a continuous three-ring corner without landing. |
| Last Light | CP4 −335 → Finish −426, deck 24 | Two generous roof steps connected by visible bridges; the final roof is 44 m wide. | Three short timed pulls carry incoming speed directly to the finish roof. |

All four checkpoint nodes are direct root children, `Checkpoint1` through `Checkpoint4`; `FinishGate`, `StartGate` and `Player` are also direct children. Each checkpoint’s `Respawn` marker is 4 m beyond its gate and sits on a broad collision roof. Gates are 34 m wide and 18 m high, so airborne intended routes still count in order. Practice retries clear force, carry speed, target cooldown, reduced capsule and camera effects, and cannot earn a clean PB.

## Ring map

The metal ring’s fixture and visual pulse do not move its collision/aim point. The sphere collision radius remains 0.35 m. New city fixtures hide the legacy ANCHOR label.

| Node | Position `(x, y, z)` |
| --- | --- |
| IntroRing | `(0,16,-37)` |
| GapLeftRing | `(-10,16,-101)` |
| GapRightRing | `(8,16,-117)` |
| GapExitRing | `(8,16,-134)` |
| GapSkipRing | `(0,19,-111)` |
| CourtyardLowRing | `(-8,23,-176)` |
| CourtyardMidRing | `(8,26,-192)` |
| CourtyardTopRing | `(0,30,-212)` |
| CourtyardSkipRing | `(0,30,-181)` |
| ChainLeftRing | `(-7,28,-267)` |
| ChainRightRing | `(7,29,-287)` |
| ChainExitRing | `(0,29,-310)` |
| FinalLeftRing | `(-8,28,-350)` |
| FinalRightRing | `(8,28,-378)` |
| FinishRing | `(0,29,-408)` |

The main consecutive ring spacings through the gap, courtyard and chain are approximately 18–25 m. Acquisition range is 26 m. Some advanced links enter range only after a short released coast: pressing too early should leave the next ring unselected. A retained tangent can orbit a diagonal ring if held indefinitely; the diagonal branch is designed around release and landing, not an automatic arrival on every link.

## Geometry and presentation

The city surrounds the original traversal with irregular Victorian roof rows, steep slate gables, dormers, soot-dark warehouses, recessed Gothic windows, balconies, drainpipes, clotheslines, shop awnings and cobbled alleys. A clocktower with corner pinnacles and a weather vane rises beyond FINISH at Z −451. The crane has street foundations, trussed arms and hanging iron fixtures; the central expert beam and courtyard bypass retain their original physical routes.

The LOW layer is visible cobbled streets at Y −18 with drain channels, opaque puddles and crates. It is scenery below the recovery height. The MID layer contains the validated lower bridges and service climb. The HIGH layer contains playable warehouse roof terraces, chimneys and pulls, framed by steep residential roof silhouettes. Residential roofs and facade props are decorative; the 15 playable building masses, 30 outer chimneys and 20 bridges/ramps/expert beam retain simple collision. All **65 original collision boxes** keep their dimensions and inherited transforms.

`rooftop_city_district.tscn` is a static visual scene with **129 spatial/material mesh batches and 89,656 triangles**. It replaces runtime CSG rendering, including the original boxes, with locally culled mesh chunks. Twelve-triangle opaque window relief cards avoid thousands of separate window meshes and transparency. Materials reuse a curated set of nearest-filtered Kenney textures; normalized Buildings facade panels and URBAN pipes/ducts provide selective relief. Source provenance and licenses are recorded in `assets/rooftop_city/SOURCES.md`.

The Compatibility environment uses cool moonlight, a dark sky gradient, distance/height fog and selective warm windows. Six shadowless amber lamps have 9 m ranges and distance fade; a single directional shadow fades within 80 m. Fog density is 0.0037 and lower streets dissolve into height mist. Volumetric fog and alpha surfaces are absent. Pull points are single iron rings on architectural brackets, with subdued target highlights and no visible sphere core. The current camera and screen effects remain in use; nearest textures provide the retro treatment without introducing vertex jitter or replacing the camera with the supplied Vulkan-oriented PSX fog shader.

To edit the bake, change named box transforms or `metadata/visual_size`, `metadata/visual_material`, and `metadata/solid` in the course, or change the composition in `tools/build_rooftop_city.py`, then run `python3 tools/build_rooftop_city.py`. The generator refreshes both meshes and owned collision shapes, and repeated runs are byte-identical. Generated meshes and the district scene are saved authoring outputs; the game does no procedural city construction at startup.

## Tuning controls

The rooftop player serializes `use_momentum_pull = true`, `vertical_look_enabled = true`, `surf_mode = false` and the 32 m/s shared cap. Force settings remain player defaults:

| Parameter | Value | Tuning effect |
| --- | --- | --- |
| `pull_acceleration` | 72 | Time to build speed toward the selected fixture. |
| `pull_tangent_retention` | 1.0 | Preserves lateral motion; lower values make diagonal links easier but reduce release expression. |
| `pull_upward_scale` | 1.1 | Modest upward support for the climb. |
| `pull_arrival_distance` | 1.8 m | Ends a close arrival while retaining its velocity. |
| `pull_max_duration` | 2.8 s | Upper bound on a held attraction. |
| `pull_air_acceleration`, `pull_air_turn_speed` | 24 m/s², 120°/s | Low-speed acceleration and horizontal direction control during attraction. |
| `parkour_speed_limit` |32 m/s | Bounded total speed. |
| `grapple_range` |26 m | Range set by the shared trial on this course only. |
| acquisition cone | 20° horizontal / 42° vertical | Ring lock cone; neutral aim excludes camera roll, dip and widened speed FOV. |
| `fall_height` | 4 m | Prompt checkpoint practice after leaving the roof system. |

Scene medal thresholds are Bronze 75 s, Silver 60 s, Gold 45 s and Developer 35 s. These are placeholders pending human runs. The scripted 52.53 s line meets Silver pace; it does not establish a human medal distribution or an optimized developer route.

The shared trial emits decoupled start/sample/finish signals. Its 10 Hz bounded transform recorder returns clean run data to a PB listener without storing a ghost or changing movement. The rooftop validation confirms an eligible recording from the actual physical finish.

## Reproducible validation

From the project root, use a Godot 4 executable:

```sh
godot --headless --path . --script tests/validate_rooftop_course.gd --fixed-fps 60
godot --headless --path . --script tests/validate_anchor_pull.gd --fixed-fps 60
godot --headless --path . --script tests/test_rooftop_time_trial.gd --fixed-fps 60
godot --headless --path . --script tests/validate_rooftop_city.gd --fixed-fps 60
godot --headless --path . --script tests/validate_rooftop_restart.gd --fixed-fps 60
```

The current city passes **142/142 checks** in `validate_rooftop_course.gd` on Godot 4.6.stable. It performs a complete clean route from the actual spawn with movement inputs, camera aim, grounded jumps and ordinary pull/release requests; no player transform or velocity is replaced during that attempt. It physically crosses START, all four ordered checkpoints and FINISH, verifies the course recording and saves the result only to a process-specific test file.

Four independent advanced probes seed only their incoming approach state, then acquire and release real fixtures, sweep the authored geometry and land on real roofs. The gap bypass, high courtyard bypass, uninterrupted momentum chain and stored-speed finale all pass. All 20 tested pull paths have zero upright geometry contacts. Separate actual walking probes verify the intro catch, gap bridges, courtyard service climb and low chain return. Four checkpoint probes begin with live force/reduced capsule state and verify full recovery clearance. Actual best-time and presentation preference files remain byte-identical, and the isolated score file is deleted.

The current city passes 142 route checks, 91 city checks, 49 keyboard-retry checks, 22 pull-feedback checks, and six time-trial cases / 92 assertions on Godot 4.6. An independent complete run on the pre-city collision scene gives the same time; sampled travel differs by only 0.000254 m across the whole run. Floor heights, normals and straight walking also agree. The current scripted route looks toward the next gap ring and physically coasts one tick after arrival to clear the previous ring's real LOS collider. Final logs are `/tmp/rooftop_city_validate_rooftop_course_final_source.log`, `/tmp/rooftop_city_validate_rooftop_city_final_source.log` and `/tmp/rooftop_city_validate_rooftop_restart_final_source.log`. Prior 4.8 route validation predates this environment pass.

`tests/render_rooftop_city.gd` rendered five 1280×720 Compatibility views on an Apple M4 Pro. Static-view samples after warmup measured 65–222 draw calls and 79–100 FPS; GPU timer results were unavailable. These are desktop snapshots, not browser/mobile frame-rate evidence. PNGs are under `build/city_previews/` and the log is `/tmp/rooftop_city_render_final.log`.

The Web build passes import/export diagnostics, ZIP integrity and the mounted-PCK audit (all courses present, no archive/combat/tests/editor addons). A fresh local browser smoke check confirms the exported city, pause and R retry. The in-app browser reports a Chromium pointer-capture error, so mouse aiming, complete browser runs and physical-device performance remain unverified. Nothing was published. Independent force tests previously covered 30/60/120 Hz; this authored course pass covers 60 Hz.

## Playtest questions and remaining debt

1. On the first run, can a player identify the next ring, landing roof and gate without stopping to search? In particular, does the right-side service climb read as a safe option?
2. Does releasing a diagonal pull feel controllable, or do the gap and chain need wider landings or a more explicit release cue? Observe full player travel, not only the guide estimate.
3. Is the courtyard jump/pull step understandable without prior explanation, and can a missed pull recover on a lower roof or the service ramp?
4. Does the clocktower remain recognizable from the pre-final roof through the mist and lead attention toward FINISH?
5. After several runs, does the central gap skip/high courtyard line feel discoverable and meaningfully faster? Use those runs to set medal times rather than treating the current placeholders as calibrated.

Outstanding work is human timing/readability, complete browser/mobile and lower-frame-rate validation, and final art/audio balance. Keep the shared solver stable until those observations show whether geometry or force tuning is the actual limiting factor. The authored ramps were adjusted after real swept-body tests exposed flat crosspiece lips and facade intersections; any further geometry edits should rerun the fallback probes.

The same night sky, slate/masonry palette and city kit now dress all comparison
courses. Their static scenery is fitted around the original routes and checked
for decorative mesh intrusions; see the shared-city section in `README.md`.
