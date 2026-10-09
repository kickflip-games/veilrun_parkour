# SWITCHBACK

A first-person parkour time-trial game. **VEILRUN · CITY RUN** connects seven
sectors of one misty industrial city. Build momentum, bend your trajectory with
architectural anchors, release into an arc and carry speed into the next sector.
Open the project and choose the city run. Earlier courses are available under
comparison courses:

- **VEILRUN:** five rooftop sectors, safe and fast lines, vertical pulls and prototype medals.
- **SWITCHBACK:** long circuit, springs, aerial links and a sky hairpin.
- **RIPTIDE:** downhill surf banks and sweeping transfers.
- **SWITCHYARD:** offset openings, slalom, split routes and bridge jumps.

WASD/arrows move, mouse looks and Space jumps with a short coyote window and
input buffer. Hold either mouse button or touch PULL to attract; release to fly.
Passing an anchor also releases automatically while preserving your trajectory.
The city supports vertical aiming, surf banks and momentum pulls.
R retries the city sector for practice; Shift+R starts a fresh full run.
Comparison courses keep R for a full retry. Backspace recovers; Escape pauses.
Touch controls provide the same actions. Each course saves its own clean-run
personal best and checkpoint splits on the device.

Movement feedback includes anchor highlights, short pull cues, speed-scaled wind,
particle bursts, peripheral streaks,
speed FOV, camera lean and a light edge distortion. **Effects strength** on the
menu scales presentation from 0–100% without changing movement or grapple locks.

This standalone project lives in `parkour_game` and
[`kickflip-games/veilrun_parkour`](https://github.com/kickflip-games/veilrun_parkour).
KILL BIT combat lives separately in `../fps_2d` and
[`kickflip-games/kill_bit`](https://github.com/kickflip-games/kill_bit).

`./publish.sh --build-only` builds `build/nightreach-web.zip`.
`./publish.sh` builds and uploads to [Nightreach](https://avivajpeyi.itch.io/nightreach).

The application is named **SWITCHBACK**. On native startup, existing personal bests and
presentation settings are imported from the legacy `Kill Bit` save directory
when their new destination files are missing. The import keeps the original
files and does not overwrite preferences or scores already saved by SWITCHBACK.

[Anchor-pull implementation and tuning](levels/parkour/ANCHOR_PULL.md) ·
[Continuous city audit](levels/parkour/CITY_CONSOLIDATION_AUDIT.md) ·
[Course details and validation](levels/parkour/README.md) ·
[Playtest and Web build](PLAYTEST.md)
