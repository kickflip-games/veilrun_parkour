# Rooftop City asset sources

A small curated subset of local assets supplies the district. The source root is
`/Users/avi/Documents/game_dev/godot/assets/retro_assets/`.

## Fantasy surfaces

The seven PNGs in `textures/` were copied unchanged from
`kenney_retro-textures-fantasy/PNG/`:

- `roof_clay_grey_center.png` — slate-like overlapping roof tiles.
- `wall_brick_small_stone.png` — soot-dark masonry after material tint.
- `wall_stone.png` — civic stone and parapet trim.
- `wall_timber.png` — weathered timber.
- `floor_stone_pattern.png` — uneven patterned stone for the street canyon.
- `window_tall_rounded.png` — dark Gothic window recesses.
- `window_tall_rounded_lit.png` — occasional inhabited windows.

The roof and floor tiles are 64 x 64 pixels; the five facade/window maps are
64 x 128 pixels. Kenney identifies this pack as CC0 in the included
`textures/LICENSE-Kenney.txt`; attribution is optional. Texture colour maps are
used with nearest filtering and reused materials. The original art is retained.

## Facade relief and industrial props

`source_models/` preserves the following original files. Its `.gdignore` excludes
these raw originals from Godot imports and Web exports. Runtime geometry is
normalized into the adjacent `meshes/` directory so source demo-layout offsets,
source material dependencies and detailed collision do not enter gameplay.

| Original source | Geometry | Local XYZ extents |
| --- | --- | --- |
| `Buildings/obj/building_church_side_bottom1.obj` and `.mtl` | 272 triangles; shallow facade relief | 5.238 x 5.003 x 0.551 |
| `Buildings/obj/building_factory.obj` and `.mtl` | 70 triangles; shallow facade relief | 3.994 x 4.999 x 0.150 |
| `URBAN/Pipes/pipe_rusted.glb` | 12 triangles; one embedded colour map | 0.433 x 1.000 x 0.500 |
| `URBAN/Pipes/pipe_corner_rusted.glb` | 40 triangles; one embedded colour map | 0.717 x 0.717 x 0.500 |
| `URBAN/Vents/duct_long.glb` | 32 triangles; one embedded colour map | 2.000 x 1.042 x 1.042 |

The OBJ facade meshes use Y as the vertical axis and face approximately +Z.
Church vertices span `(-2.618940, -0.001498, -0.086880)` to
`(2.619042, 5.001521, 0.463633)`; factory vertices span
`(-1.997012, 0.004470, -0.051437)` to `(1.997012, 5.003270, 0.098588)`.
These are facade panels, not complete buildings or roofs. Their source MTL files
reference unavailable absolute Windows paths; runtime applies project materials.

The GLBs contain source layout translations: pipe `(32.661766, 3.367647, -4.867647)`,
corner `(32.161766, 2.867647, -6.867647)`, duct `(32.000000, 0.000000, 0.000000)`.
Normalized runtime geometry must discard those translations.

No license or author notice was present in the supplied local `Buildings/` or
`URBAN/` folders. Their license status is unverified; these files are retained
from the user's expressly requested asset sources for local prototyping. This
note records that limitation rather than inventing a license.

## PSX reference

The supplied `PSX-Style-Camera-Shader-4.3-version-2/psx_camera/` pack is MIT, with
its notice in that pack's `LICENSE.txt`. It implements camera-quad depth fog,
colour quantization and dithering; it does not implement vertex snapping. Its
original depth reconstruction assumes a 0-to-1 depth range, so any reuse with
Compatibility must map depth to the OpenGL -1-to-1 NDC range. The district should
preserve the current camera and targeting contracts. No source pack files from
that reference are copied here.
