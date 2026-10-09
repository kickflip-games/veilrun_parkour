# VEILRUN · City Run

`MainCityRun.tscn` is the primary continuous course. One player and shared clock
serve seven modular geometry scenes under `CitySections`. The roughly 2.1 km
safe roof route has six invisible sector boundaries, short reconnecting braids,
lower catches, architectural pull fixtures and a downhill finish. The original
four courses remain under **COURSE STUDIES** for comparison.

## Reuse and rebuild

The existing player, camera, HUD, mobile router, attraction solver, air control,
reusable anchors, one-entry springs, clock, recorder and presentation systems are
extended. The city reuses Veilrun's sky, slate/brick/stone/iron materials, texture
provenance and spatial mesh-bake helpers. It does not instance four complete
course roots or import archived FPS systems.

All seven new geometry modules are rebuilt as city architecture. Eaves and
braids derive from Veilrun, 52° bank mechanics from Riptide, offset chimney apexes
from Switchyard, and aerial elevation, springs and a real 180° hairpin from
Switchback. The original course collision/fixture signatures remain unchanged.
Their controls use the new hold input; the old programmatic request API remains
available to validation tools.

## Sectors and racing lines

The times below are the ordinary-input engine route, with no position or velocity
replacement during the complete run. They are a conservative scripted baseline,
not measured human sector distributions or an expert time. The first competent
human-run design target remains 180–360 seconds.

| Order | Sector | Safe guide length | Scripted sector | Movement purpose and alternatives |
| --- | --- | ---: | ---: | --- |
| 1 | The Eaves | 272.5 m | 35.500 s | Broad roof flow and early pull timing; raised ridge braid and lower eave catch reconnect before Chimney Row. |
| 2 | Chimney Row | 259.4 m | 35.650 s | Offset stacks reward tighter apexes; wider central lines and a low side roof support recovery. |
| 3 | Blackglass Descent | 272.9 m | 34.933 s | Descending factory roofs and 52° banks store speed; a broad keel and lower factory roof return carry missed bank lines onward. |
| 4 | The Underway | 244.9 m | 33.050 s | Left/right sign brackets, canopy choice and a steam pressure launch; raised canopy braid and lower alley line merge before the bell quarter. |
| 5 | Bellmaker's Turn | 400.4 m | 55.200 s | Broad 180° bellhouse hairpin and slate banks; optional spring to a curved upper gallery, shorter pressure alley with steam return, and a speed-dependent gap above a lower catch. |
| 6 | The High Ward | 296.8 m | 41.050 s | Rising roof/balcony chain toward the spire; lower service balconies and an inner higher braid give short alternatives. |
| 7 | The Long Fall | 364.0 m | 45.267 s | Descending roofs, pressure ridge and crane pulls aim toward paired finish towers; a lower roof sequence catches missed transfers. |

The safe route is continuous, with broad contact surfaces rather than mandatory
precision gaps. Braids last roughly 5–15 seconds at useful racing speed and
return before the next boundary. Faster airborne lines can skip landings and
preserve speed into the following sector. The final safe guide winds through
364 m; a direct aerial guide is about 290 m. That geometric difference is not a
guaranteed time saving.

Pull points use actual iron rings on weather vanes, chimney caps,
roof braces, hanging signs, bell beams, balcony brackets and crane arms. Their
supports change by district. Anchor aim colliders stay fixed; ornamental supports
do not add body snags. Large chimney/bell/spire masses retain simple collision.
Timing areas have no visible race frames, arrows or floating labels.
Architectural launchers hide the inherited spring marker art during normal play.

## Bellmaker racing slice

The first racing redesign modifies only sector five. The existing wide bellhouse
hairpin, outer lower arc and checkpoint entry/exit remain intact. The other six
sector definitions and all seven neighboring-roof records are unchanged.

The frontage now offers three layers: the wide slate hairpin, a curved upper
workshop gallery reached by an optional ground spring, and a shorter pressure
alley below. The gallery also has an expert gap above the alley catch. A missed
gap can land below and return through the steam shaft rather than reset the run.
Two slate banks support momentum through the outer corner. The original straight
inner bridge is replaced by these choices.

The gallery's steep entry requires its spring; it is not a slow walking ramp.
The manifest marks that route with `requires_traversal`, its physical mechanism
and the continuous validation script. Ground alternatives remain available.

Eight pull fixtures form three clusters at the frontage, bell corner and return,
replacing the former nineteen-fixture chain in this sector. Selected pulls have
a restrained cyan circular reticle with inward contraction. Contact springs,
directional pressure strips and steam shafts never lock on. Springs use the
existing one-entry impulse; pressure strips add forward speed while grounded;
updrafts add vertical acceleration while preserving horizontal velocity within
the shared cap. The active controls remain run, jump and held pull.

`route_manifest.json` records the slice in `bellmaker_slice`, including line
guides, input actions, gap edges, passive devices and fixture clusters. These
guides support reproducible engine probes; they are not required player paths.
The existing `veilrun_city_v1` save identity is retained. New optional lines alter
achievable times; saved records still require an ordered clean full finish.

At 60 Hz, the same ordinary-input racing policy produces these physical sampled
times from the actual CP4 practice entry, without replacing position or velocity
during a line. The shared sector clock differs by one trigger tick. The original
wide line also took 46.017 s before the redesign with this policy; an older,
slower steering policy took 53.367 s and is not the comparison used here.

| Line | Sampled time | Actual movement |
| --- | ---: | --- |
| Wide roof | 46.017 s | Continuous ground hairpin. |
| Corner pull | 32.667 s | One acquired held pull, followed by real roof landings. |
| Upper gallery | 27.600 s | One contact spring, then the curved 24 m roof. |
| Pressure alley | 24.217 s | Ground boost and upward pressure lift. |
| Expert gap | 26.717 s | Earned spring momentum crosses the gap and lands on its upper receiver. |
| Missed gap | 27.933 s | The same spring approach with 0.2 s of real backward input misses into the 7 m catch, then returns through boost/lift. |

The missed line costs 1.217 s against the clean expert line at this rate. The
alley is fastest in this driver despite 293.2 m of actual travel versus the
expert's 266.4 m. These are reproducible engine runs, not human records or a
claim that the current balance is final. Separate grounded Space probes clear
the actual unsupported 24 m gap at 24 m/s and land in its lower catch at 8 m/s.
The full expert line earns its velocity from a real spring rather than that
independent jump seed.

The slice passes 103 checks at each of 30, 60 and 120 Hz. All six lines physically
cross CP5 from the same single practice seed; acquisition, speed cap, capsule
restoration, real device forces, checkpoint order and save isolation are checked.
Miss penalties are 1.033 / 1.217 / 1.708 s across those rates. Outcomes remain
stable, while timings are rate-sensitive. Compact metrics are saved in
`build/bellmaker_racing_slice_summary.json`; each rate has a detailed log and JSON.

### Slice playtest assessment

| Question | Evidence and limit |
| --- | --- |
| More than one plausible line? | Wide, corner-pull, upper-gallery, alley and gap lines complete from the same entry. |
| Decisions rather than following anchors? | Wide, upper, alley and gap lines complete without pulls; the corner line uses one optional pull. |
| Readable at full speed? | Seven native views establish appearance and actual lock feedback. Full-speed first-run readability needs human play. |
| Targeted types distinguishable? | Pull is the sole remote type and has cyan inward circular feedback. Launch plates remain contact devices. |
| Passive components understandable without text? | Spring chevrons, steel pressure inlays and rising steam/hiss provide cues. Unprompted player understanding is unmeasured. |
| Do mistakes cost time? | A real missed gap lands in the lower catch and completes without recovery reset, with the measured time penalty above. |
| Does momentum matter? | The grounded 24 m/s gap jump succeeds where 8 m/s falls below; independent bank probes retain about 24.4–24.7 m/s and gain downhill tangent speed. |
| Are shortcuts discovered naturally? | The gap is physically viable; discovery needs an unfamiliar human player. |
| Does the section invite replay? | Not established by engine probes. Compare repeated human runs and line changes. |
| Can expert and beginner lines differ? | Ground hairpin, passive alley and earned airborne gap have distinct physical trajectories and inputs. Human skill distributions remain unmeasured. |

## Neighboring roofs

Seven existing first-row buildings now accept player landings, one per sector:
Eave Watch, Sootside, Blackglass Side, Underway Workshop, Bell Court, Ward Service
and Finish Clockside. Each has collision matching its building mass, cornice and
18 × 25 m gable, with walkable 24° slopes. These are optional lateral excursions;
nearby existing pull fixtures support returns to the main roof route. The
Underway workshop is lowered to make its roof reachable. Distant skyline scenery
remains collision-free.

The manifest's `playable_adjacent_roofs` records their collision paths, landing
areas, main-route rejoins and nearby return fixtures. Cyclops retains all 21 new
editable volumes. Runtime collision uses ordinary static bodies; their duplicate
exported meshes are hidden so the existing batched building art remains visible.
The final High Ward lower balcony also has a shared triangle edge welded to
remove a pre-existing internal collision step. Those neighboring-roof additions
preserve the main route and its existing banks; the Bellmaker slice is described
separately above.

## Input and assistance

Main-city mouse and touch aim turn horizontally; manual camera pitch is locked.
Jump, gravity, sloped collision and anchor attraction still move the body in
height. Elevated fixtures remain available inside the neutral view and vertical
acquisition bounds, so approaching them early still matters. The Veilrun rooftop
comparison retains its manual vertical look.

Hold either mouse button or touch PULL to acquire a valid fixture. Let go to
immediately stop attraction and retain the current velocity within the cap.
There is no physical-input toggle or polling that reacquires after auto-release.
Another pull requires lifting the held input and pressing again. Pause, focus
loss, recovery and finish cancel held inputs and jump windows.

Auto-release uses the existing collision-free swept arrival and actual closest
pass after approach. Wider passes use the release cue. Initial movement away
from a new fixture may turn toward it before the approach guard arms. Stalled
collision and maximum duration also end attraction. Collision-projected tangent
survives; release adds no synthetic boost. Nearby overhead fixtures at high
speed can release before providing much lift, so approach angle still matters.

Targeting keeps the real range, cone, neutral base-frustum and LOS gates. Aim
remains the main score; movement alignment and useful future trajectory provide
small tie-break preferences. Valid-lock retention reduces flicker without
extending acquisition through a wall or outside the frustum. Camera roll, dip
and speed FOV do not change accepted targets.

Space and touch JUMP use coyote time and buffering, including the landing
collision tick. Jump preserves horizontal velocity and any stronger upward
launch already present. Walkable roof slopes are tested; steep surf banks retain
their wall-slide classification, with the keel and pull fixtures available as
route choices. The city flow probe verifies transfer into the next bank.

| Parameter | Main-city value | Purpose |
| --- | ---: | --- |
| Pull acceleration | 72 m/s² | Adds attraction to incoming momentum. |
| Tangent retention | 1.0 | Retains the current lateral component. |
| Upward scale | 1.1 | Modest upward pull assistance. |
| Arrival radius | 1.8 m | Ends a close actual swept pass. |
| Maximum pull | 2.8 s | Bounds an unhelpful hold. |
| Speed cap | 32 m/s | Bounds total velocity. |
| Range / cone | 30 m / 20° horizontal / 42° vertical | Forgiving acquisition with LOS and base view checks. |
| Valid-lock retention | 2° | Stabilizes a valid selected fixture. |
| Movement / useful-arc score | Up to 0.75° / 0.5° | Small target-ordering preferences. |
| Coyote / jump buffer | 0.12 s / 0.14 s | Forgives late edge and early landing presses. |
| Jump minimum upward velocity | 5.5 m/s | Keeps stronger upward momentum. |
| Practice entry speed | 12 m/s after boundaries | Recreates a moving sector entry. |
| Major-fall recovery height | −36 m | Allows lower catches before checkpoint recovery. |

## Timing and practice

Six direct-root `Checkpoint1`–`Checkpoint6` Area3Ds carry `checkpoint_id`,
`sector_name`, `order_index` and world `initial_velocity`. Their child `Respawn`
marker is the authoritative position and facing, beyond the trigger on a clear
surface. `PlayerSpawn` provides the opening entry. All braids reconnect before
their sector's outgoing boundary, so they share ordered timing.

The compact HUD shows total/PB, current sector, sector elapsed/best and km/h.
Boundary feedback briefly shows sector time, sector PB difference and cumulative
run difference when available. READY controls disappear during a run.

R retries the current sector in place, retaining total elapsed and completed
boundaries while resetting that sector's timer and marking the run PRACTICE.
Shift+R and the full retry button recreate a clean READY run. R at the finish
also starts a fresh full run. Comparison courses retain R for full retry.
Recovery resets held input, hook force, reuse cooldown, capsule, camera, particles
and spring entry latches. There is no practice-selection menu yet; the checkpoint
data already supports later sector selection with realistic entry conditions.

The new identity is `veilrun_city_v1` in `user://parkour_bests.cfg`. Independent
sector records live in `veilrun_city_v1:sectors`, separate from the cumulative
splits belonging to one complete PB. They save only on a clean finish; a slower
clean full run may improve a sector. Artificial practice entries cannot save
either record. Bounded recordings remain eligible only for clean saved full-run
improvements. Existing course IDs, saves and presentation preferences remain
intact. Background music stays off; short movement feedback still uses SFX.

## Authoring and reproduction

`tools/build_main_city.py` defines route points, braided lines, fixture supports,
landmarks and static dressing. It writes `assets/main_city/route_manifest.json`
and seven spatially batched dressing scenes. `tools/export_main_city.gd` uses
Cyclops' ConvexVolume, CyclopsBlock and official scene exporter, retaining editable
blocks in `tools/city_authoring/MainCityCyclops.tscn`. The runtime scene contains
ordinary meshes and convex bodies with no Cyclops dependency. Editor interaction
itself is separate from this scripted authoring/export check.

From the project root, with a Godot 4 executable:

```sh
python3 tools/build_main_city.py
godot --headless --path . --editor --quit
godot --headless --path . --script tools/export_main_city.gd
godot --headless --path . --script tests/validate_main_city_bake.gd
godot --headless --path . --script tests/validate_main_city_geometry.gd --fixed-fps 60
godot --headless --path . --script tests/validate_main_city_geometry.gd --fixed-fps 60 -- --braids-only
godot --headless --path . --script tests/validate_main_city_flow.gd --fixed-fps 60
godot --headless --path . --script tests/validate_horizontal_camera.gd --fixed-fps 60
godot --headless --path . --script tests/validate_main_city_horizontal_aim.gd --fixed-fps 60
godot --headless --path . --script tests/validate_adjacent_city_roofs.gd --fixed-fps 60
godot --headless --path . --script tests/validate_adjacent_roof_clearance.gd --fixed-fps 60
godot --headless --path . --script tests/validate_bellmaker_racing_slice.gd --fixed-fps 60 -- --flow-fps=60
godot --headless --path . --script tests/validate_contact_traversal.gd --fixed-fps 60 -- --flow-fps=60
godot --headless --path . --script tests/validate_sector_retry.gd --fixed-fps 60 -- --city
godot --headless --path . --script tests/validate_grapple_click.gd --fixed-fps 60
godot --headless --path . --script tests/validate_movement_assistance.gd --fixed-fps 60
godot --path . --script tests/render_main_city.gd --resolution 1280x720
godot --path . --script tests/render_main_city.gd --resolution 1280x720 -- --adjacent-roofs
godot --path . --script tests/render_main_city.gd --resolution 1280x720 -- --bellmaker-slice
godot --path . --script tests/render_main_city.gd --resolution 1280x720 -- --pull-feedback
./build_web.sh
```

Tests use process-specific score paths. See the shared course guide for existing
air, surf, hook-pass, clock, presentation and comparison-course regression probes.
For slice/contact rate checks, set both `--fixed-fps` and `--flow-fps` to 30 or
120; the report includes the engine's actual physics rate.
Main-city snapshots are under `build/main_city_previews`; Web output is
`build/web/index.html` and `build/nightreach-web.zip`. Building does not publish.

## Evidence and remaining tuning

The ordinary-input full safe route reached a clean finish in 280.650 seconds
(4:40.650), with 2,092.146 m of actual body travel. Authored route length is
2,110.894 m; trigger offsets account for part of the difference. Separate seeded
flow probes exercise production hold/release input, bank contacts, upward pulls
and the final launch; they are not a complete expert run. Jump assistance and
actual closest-pass release are checked independently at 30/60/120 Hz. The full
authored city baseline is a 60 Hz equivalent engine check.

The final geometry harness passes 99 checks, including 2,718 capsule support and
shoulder samples, all 84 fixture approach/LOS checks and six moving practice
entries. A separate 122-check run physically walks the twelve ground braids and
verifies the gallery's declared spring and continuous validation resource. The
gallery's actual launch and entry-to-checkpoint motion are exercised by the slice
harness. The five city flow probes pass 37 checks
at each of 30, 60 and 120 Hz. Opening, bell, spire and final ridge/pull probes
reach actual roof landings; Blackglass establishes sustained bank contact and
bank-to-bank transfer. Hold input passes 61 checks, jump assistance 26 per rate,
closest-pass release 52 per rate, main-city sector retry 72, and comparison city
preservation 65. The original four geometry signatures remain unchanged. Real
save files are byte-identical after the city flow tests.

The retained Cyclops/runtime bake audit passes 2,912 checks across all 363 solids.
Editable vertex sets and transforms match ordinary runtime convex collision and
visible mesh transforms within 2 mm; the 21 duplicate neighboring-roof meshes
remain hidden. Playable sectors contain no Cyclops dependency.

The horizontal-camera revision passes 29 mouse/touch, elevated pull and retry
checks, plus 91 route-acquisition checks. All 84 fixtures can be selected from
forward approaches on actual safe-roof collision with camera pitch zero. The
city flow harness now uses level aim and passes 37 checks at 60 Hz. Body physics
is unchanged by this camera revision.

The adjacent-roof harness passed 125 checks at each of 30, 60 and 120 Hz for the
neighboring-roof revision; a fresh 60 Hz run passes all 125 after the Bellmaker
export. It
checks visible gable/collision alignment, actual 24 m/s lateral capsule landings,
momentum retention, traversal and edge departure on all seven roofs. Independently
seeded held-pull returns reach real main-route roof bodies at 14.9–30.6 m/s. One
continuous opening detour uses an initial main-route approach seed, then actual
jump input, roof landing and held-pull return without intermediate position or
velocity replacement. The clearance harness passes 32 checks and 8,535 actual
capsule queries across 20 safe/fast/expert/recovery corridors, all six checkpoint
respawns, and out-of-order checkpoint/finish guards. Main-city flow remains
37/37 at 60 Hz after the final geometry export. Real saves remain byte-identical.
Human detour handling and shortcut balance have not been measured.

Contact traversal and Pull presentation pass 51 checks at each of 30, 60 and
120 Hz, including current full/flight capsule overlap, force limits, pause,
inactive/debug state, reset outside the volume and a rounded capsule corner.
One quiet pressure hiss accompanies the first actual lift on entry, then stops
and frees its voice after 0.3 s. Pause freezes it; exit/reset rearm it; muted
entries cannot produce a delayed cue when effects strength changes.
Presentation-only invariants pass 40 juice and 22 feedback checks. Six fresh
1280×720 native Compatibility views of the split, gallery, gap, alley, banked
apex and overview were inspected, with 301–492 draw calls and 24,640–40,504
rendered primitives. These bounded static captures establish appearance and
render diagnostics, not gameplay FPS or Web/mobile performance.
A separate native capture verifies the actual cyan circle/inward glyph and world
highlight on BellMount00 with manual camera pitch zero. The ground spring has no
lock indicator in that view.

The stable Godot 4.6 Web build passes import/export diagnostics, ZIP integrity
and a mounted-pack audit: 1,496 resources, no archived FPS/tests/tools/editor
addons, and the main city instances without Cyclops, including all 21 adjacent
building collision volumes and both passive contact Areas. An earlier local
in-app browser smoke check opens
the city, pauses, uses R from pause to enter opening PRACTICE,
and uses Shift+R to return to clean READY. Chromium pointer capture reports an
error in that browser, so mouse-look, a complete browser run and browser input
feel remain unverified. The build has not been published.

The offline Cyclops exporter retains a ConvexVolume reference-cycle warning at
process teardown. Runtime geometry, braid, input and packaged-scene checks are
clean; the authoring warning is separate from runtime dependencies.

The opening has deliberately generous running roofs and may feel too repetitive
after learning the first pull. The high ward's service ascent is forgiving and
may need a stronger reason to choose each braid. Bell exit setup matters: aiming
straight at a distant exit can cut inside the roof edge; a broad roof arc remains
available. Final airborne shortcuts need human timing to establish whether their
rewards outweigh recovery time. Good next shortcut candidates are a chimney
cross-roof cut, an earlier bell release linking directly into the high ward, and
a spire-to-final crane chain. They should follow measured player lines.

Human first-run readability, controller comfort, expert time savings and physical
mobile/browser FPS remain unverified. Static native Compatibility snapshots
establish appearance and rendering diagnostics, not a complete device playtest.
Medals for the main city are intentionally unset until human times are measured.
