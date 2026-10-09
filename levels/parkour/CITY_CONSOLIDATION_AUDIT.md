# Continuous city audit — 4 October 2026

This audit records the inspected source before the consolidation changes. The
implementation follows the user's supplied city-run brief; that brief supersedes
the earlier toggle-input and full-run R contracts.

## Existing foundation

1. **Veilrun structure.** `rooftop_trial.tscn` has five contiguous sectors,
   four ordered checkpoint areas, a start/finish, broad roof landings, short
   braided alternatives, service bridges and a courtyard climb. Its shared
   lifecycle is `parkour_trial.gd`; baked scenery is `rooftop_city_district.tscn`.
2. **Visual strengths.** Building masses reach toward the streets, silhouettes
   use steep slate roofs and a clocktower, and iron fixtures sit on architectural
   supports. Warm windows, cool distance fog, spatial mesh batches and simple
   collision give it an environmental identity. Existing render probes and
   route tests provide a useful foundation; perceived handling still needs play.
3. **Anchor implementation.** Reusable anchor bodies belong to `grapple_anchors`.
   The controller checks range, angular cone, neutral camera frustum and actual
   line of sight. The momentum solver adds attraction to incoming velocity and
   preserves tangents. It does not simulate a rope.
4. **Movement.** The player owns capsule physics, horizontal steering, jump,
   gravity, surf banks, springs and recovery. Momentum pulls and vertical aim
   are currently enabled for Veilrun; the comparison courses use older flight.
   Jumps preserve horizontal speed but currently require a grounded press.
5. **Release.** Desktop presses and touch taps toggle attachment. Mouse-up does
   nothing. Momentum pulls already release on collision-free swept arrival,
   actual closest pass, stalled collision or the duration bound. Replace the
   physical input dispatch with hold/release and retain the tested pass solver.
6. **Timing.** READY/RUNNING/FINISHED, strict checkpoint order, pause exclusion,
   cumulative PB splits and bounded recordings already work. Recovery marks
   practice and cannot overwrite a PB. R currently reloads the whole course;
   respawns currently have no authored entry velocity or independent sector PB.

## Mechanics to consolidate

7. **Riptide.** Keep downward acceleration, steep V banks, sweeping transfers,
   the low keel and recovery routes. Translate these into slate factory roofs,
   roof valleys and service streets. Remove white rails, gate frames and labels
   from the new playable city.
8. **Switchyard.** Keep offset navigation, slalom apex choices, short high/low
   splits and staggered transfers. Use chimneys, buttresses, signs and narrow
   roof gaps rather than window-test walls and arrows.
9. **Switchback.** Keep elevation changes, long aerial links, directional launch
   mechanics, a real hairpin, a narrow cut and catch decks. Translate these into
   roof ridges, cranes, belfry supports and connecting service roofs.
10. **Reusable geometry.** Preserve the original comparison scenes as references.
    Reuse the player, anchor, spring, clock, recorder, effects, sky, material and
    city-mesh helpers. Reuse proven surface dimensions and bank slopes where
    useful, fitting their collision to the new connected route.
11. **Redesign.** New sector modules replace the prototypes' presentation rather
    than nesting four complete courses with four players, clocks and menus.
    New geometry retains Cyclops authoring and exports ordinary runtime meshes
    and bodies. Existing courses remain available for comparison.
12. **Remove from normal play.** No white test frames, floating anchor cores,
    giant arrows, permanent controls blocks, debug labels or visible timing
    gates in the main run. Retain small HUD timing, speed and transient hints.

## Route and integration plan

13. **Sector order.** The Eaves → Chimney Row → Blackglass Descent → The Underway
    → Bellmaker's Turn → The High Ward → The Long Fall. The opening establishes
    roof/pull rhythm, the slalom rewards apex choice, descent stores speed, the
    alley chains release timing, the bell turn tests entry/exit momentum, the
    high ward climbs, and the final descent launches toward a visible finish.
    The intended first competent completion is 3–6 minutes, subject to measured
    human runs; sector targets are approximately 20–60 seconds.
14. **Connectors.** Broad roof terraces and continuous service routes meet each
    sector boundary. Lower catch roofs connect back through shallow ramps.
    Short high/low braids merge before timing boundaries. Turns need roomy
    landing alternatives and fixture supports outside the swept body corridor.
15. **Risks and validation.** Four independent roots cannot simply be instanced:
    they would duplicate lifecycle, audio, players and PB identities. Use one
    root and seven geometry modules. Check actual capsules at seams and ramps,
    anchor range/LOS, checkpoint coverage on every braid and realistic restart
    clearances. Surf plus momentum pulls may change approach speeds. New layout
    and sector records need a new course ID. Editor addon data must stay out of
    Web staging; exported scenes must load without Cyclops. Dense city meshes
    require fresh import/render and Web-pack checks. Automated completion cannot
    establish intuitive handling, human run length, comfort or device FPS.

The next step is additive implementation of the new course and small extensions
to the existing controller/lifecycle, followed by physical route, input, timing,
visual and export checks. No public upload is requested.
