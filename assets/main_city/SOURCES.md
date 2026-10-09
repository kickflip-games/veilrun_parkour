# Main city sources

The new sector geometry, roof prisms, skyline, iron fixtures, signs and landmark
compositions are generated locally by `tools/build_main_city.py` and
`tools/export_main_city.gd`. Their editable Cyclops blocks are retained in
`tools/city_authoring/MainCityCyclops.tscn`; exported runtime sectors use ordinary
Godot meshes and convex collision.

Materials reference the existing seven Kenney fantasy textures under
`assets/rooftop_city/textures`. Their original CC0 notice remains at
`assets/rooftop_city/textures/LICENSE-Kenney.txt`. No additional external art is
downloaded or copied for the main city. The existing city helper supplies the
mesh batching, roof, facade and window composition routines; the new city does
not call its external source-model importer.

See `assets/rooftop_city/SOURCES.md` for the provenance of the older comparison
city meshes. Those scenes and their original source notices remain intact.
