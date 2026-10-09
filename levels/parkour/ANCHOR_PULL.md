# VEILRUN anchor-pull prototype

Choose **COURSE STUDIES → VEILRUN ROOFTOPS**, or run `rooftop_trial.tscn` in Godot. This is one
five-section rooftop experiment for judging whether chaining pulls is enjoyable
and worth replaying. The three earlier courses remain available as movement
comparisons. The archived FPS is excluded from imports and exports.

## Movement change

The previous flight overwrote velocity with a 38 m/s vector directly toward the
anchor, then applied a 22 m/s arrival impulse in the authored courses. VEILRUN
opts into an acceleration solver instead. Each physics step separates velocity
into radial and tangential components relative to the anchor, preserves the
incoming components, adds pull acceleration and gravity, then applies horizontal
player direction control. The resulting total velocity is capped at 32 m/s. Tangential retention is applied
per second rather than per frame. Upward attraction receives a small multiplier.

Hold the mouse button or touch PULL to acquire and pull; let go to release.
Auto-release consumes that press, so another anchor needs a fresh press.
Release and automatic arrival stop attraction without
replacing velocity or adding a synthetic boost. This makes incoming angle and
release timing matter: the player can sweep past a ring, climb, redirect around
a corner or carry an arc toward another ring. After an approach, passing the
closest point ends attraction so the old anchor cannot drag the player back.
Arrival checks the actual collision-free previous-to-current body segment against the
1.8 m radius, including a close pass between physics samples. A wider pass uses
the ordinary release cue and keeps the current velocity. Initial motion away
from an anchor is allowed before the approach guard arms, including upward and
sideways redirects. Colliding slide paths can bend, so their straight endpoint
chord does not count as a swept arrival. A pull lasts at most 2.8 seconds;
there is no rope, tether-length constraint or automatic next-anchor selection.
Mouse and touch LOOK now include pitch in this course, bounded to ±80 degrees.

`scenes/parkour/anchor_pull.gd` integrates attraction and uses the shared
`air_control.gd` helper for horizontal steering. The existing
CharacterBody still owns collision and movement. `get_pull_debug()` returns
active state, elapsed pull time, acceleration vector, velocity and speed for
instrumentation; course `show_developer_speed` adds a debug speed readout.

## Tuning locations

Values below are the rooftop defaults. Player exports can be overridden on the
course's Player instance. Range and lock angles are course-root overrides.

| Parameter | Default | Location and purpose |
| --- | --- | --- |
| `use_momentum_pull`, `vertical_look_enabled` | true on VEILRUN | `player.gd`; opt into new force and vertical aiming |
| `pull_acceleration` | 72 m/s² | `player.gd`; attraction strength |
| `pull_tangent_retention` | 1.0 per second | `player.gd`; retain lateral momentum, tunable 0.9–1.0 |
| `pull_upward_scale` | 1.1 | `player.gd`; scale only upward attraction |
| `pull_air_acceleration`, `pull_air_turn_speed` | 24 m/s², 120°/s | `player.gd`; low-speed acceleration and direction control during a pull |
| `pull_arrival_distance` | 1.8 m | `player.gd`; swept-segment arrival without a landing snap |
| `pull_max_duration` | 2.8 s | `player.gd`; bound sustained pulls |
| `parkour_speed_limit` | 32 m/s | `player.gd`; total pull/released speed cap |
| `parkour_air_acceleration`, `parkour_air_turn_speed` | 32 m/s², 240°/s | `player.gd`; low-speed acceleration and high-speed heading control |
| `parkour_air_braking`, `parkour_air_drag` | 56 m/s², 0.12/s | `player.gd`; opposing-input brake and no-input damping |
| `parkour_ground_momentum_drag`, `parkour_ground_coast_drag` | 0.65/s, 2/s | `player.gd`; smooth boosted landing decay while steering / coasting |
| `anchor_reuse_delay` | 0.45 s | `player.gd`; prevent immediate re-lock of the last ring |
| `hook_blocked_timeout` | 0.18 s | `player.gd`; release stalled force while retaining collision-projected velocity |
| `hook_capsule_scale` | 0.75 | `player.gd`; inherited flight capsule, safely restore on exit |
| `grapple_range` | 26 m | `rooftop_trial.tscn` / `parkour_trial.gd`; reach |
| `acquisition_horizontal_degrees`, `acquisition_vertical_degrees` | 20°, 42° | course root; aim-assistance cone, additionally limited by neutral camera frustum |
| `lock_retention_degrees` | 2° | `grapple_controller.gd`; favor the current valid target within the same accepted bounds |
| `camera_fov_boost`, `camera_roll_limit_degrees` | +14°, 7° | `player.gd`; speed FOV and maximum lean |
| Effects strength | 0–100% | menu / `presentation_settings.gd`; camera, particles, warp, new pull cues and wind |
| `targetable`, `show_label`, three feedback colors | true, rooftop labels off | `grapple_anchor.gd`; fixture availability and visual hierarchy |
| `medal_bronze`, `medal_silver`, `medal_gold`, `medal_developer` | 75 / 60 / 45 / 35 s | rooftop root; placeholder thresholds, inclusive |
| `fall_height` | 4 m | rooftop root; checkpoint recovery below roofs |
| Recorder `sample_rate`, `max_samples` | 10 Hz, 9,000 | `run_recorder.gd`; bounded ghost-ready sampling |

Inherited run speed (8 m/s), jump impulse (5.5 m/s), mouse sensitivity and 0.5 s
exit-slide grace remain constants in `player.gd`. Gravity comes from project
settings. The older courses retain fixed-speed flight and their arrival impulse;
`hook_exit_speed` and `hook_exit_vertical_fraction` apply only to that mode.
There is intentionally no additional release-boost parameter.

## Routes and atmosphere

The course is a roughly 495 m safe line through five sectors. Broad roofs,
service bridges and ramps provide recovery; shorter anchor lines reconnect at
the next ordered checkpoint. Roofs have building masses extending to the street,
with chimneys, iron fixtures, lamps, cranes, towers and mist. This remains a
simple greybox rather than finished environment art.

1. **THE EAVES:** forgiving run-up, short gap and one ring teach aim, pull and
   release through geometry.
2. **BRAIDED SPAN:** side roofs and several rings form the safe route; a central
   higher fixture offers a direct transfer with fewer landings.
3. **CLOCKCOURT:** rising side roofs/rings and a service ramp climb the courtyard;
   a high central ring offers a more demanding upward launch.
4. **IRON CURRENT:** offset rings reward smooth releases and carrying speed;
   broad landings and an outside service bridge allow slower recovery.
5. **LAST LIGHT:** two staggered steps lead to a clearly marked finish; stored
   momentum permits a straighter final transfer.

The authored guide is about 495 m; the conservative scripted line covers 518.7 m
and finishes in 52.53 s. These are distinct from first-time human timing.

The 45–75 second first-competent-run target and medal times are design targets,
not measured human results. See `ROOFTOP.md` for geometry, route probes and their
limits. Alternate lines are authored candidates, not certified skill tiers.

## Reused systems and recording boundary

The existing movement inputs, jump, capsule sweeps/restoration, collision masks, anchor range/cone/base-frustum/LOS checks, target retention,
wall timeout and reuse cooldown remain. Presentation roll, dip and FOV stay out
of acquisition. The player action and API still use internal `grapple`/`hook`
names; visible action text is PULL. Anchors use per-instance restrained metal
rings with dormant, reachable, selected and pulling states. Original procedural
lock/activation/release cues and a speed-scaled wind loop provide feedback.

The ordered clock, checkpoint practice recovery, local PB/splits, pause and
immediate R scene retry are reused. Finish UI compares against the **previous**
PB, then shows the achieved medal. Practice can show medal pace but cannot save
a PB. New course PBs use `rooftop_pull_v1` in `parkour_bests.cfg`.

`run_recorder.gd` is a separate bounded transform sampler. The shared trial emits
`run_started`, `run_sampled`, `run_finished` and `personal_best_recorded`. Only a
complete, untruncated, clean, successfully saved improvement is PB-ghost eligible.
Practice recovery clears recording; pause stops sampling. A future replay can
consume sample times and transforms without owning or changing player physics.
No ghost replay, recording persistence or online leaderboard is implemented.

## Known debt and playtest questions

The shared player has a legacy flight branch for comparison courses, and internal
hook naming remains. Air direction control now redirects earned speed, scales
with touch-stick strength and brakes opposite intent before reversing. Boosted
landings shed speed smoothly after exit grace; glancing wall contact preserves
the collision-projected tangent. Human runs still need to judge this tuning.
Reduced flight capsules can make tight clearances forgiving, so every shortcut
still needs human fairness checks. A momentum pull now ends at a close swept
arrival or an approached fixture's closest pass; manual release still controls
earlier arcs. A nearby overhead fixture at high lateral speed can reach its first
closest pass almost immediately, leaving little upward gain. Hook earlier while
the fixture is ahead, or brake before hooking when you need lift. The duration
cap remains a safety bound. Placeholder medals need
a measured balance pass, and the authored city still needs human readability checks.
Transform samples record body pose, not camera/input state, and remain in memory.
Local browser launch, pause and R retry were checked. The in-app browser did not
capture the mouse pointer, so capture/aiming needs an ordinary browser playtest.
Browser performance, touch aiming and camera comfort need device playtests.

1. Does a pull feel powerful immediately, and is releasing at the right moment satisfying?
2. Can you predict how incoming sideways speed and early/late release change your arc?
3. Can you read the main route and discover a faster line without stopping to search?
4. When a landing or ring is missed, does recovery feel fair and quick enough?
5. After a finish, do you want to press R and improve one specific part of your run?
