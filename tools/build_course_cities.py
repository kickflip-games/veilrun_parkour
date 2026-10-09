#!/usr/bin/env python3
"""Bake scenery for the comparison courses with VEILRUN's existing city kit.

First run tools/export_city_geometry.gd in Godot, then this script. This only
writes owned scenery meshes/scenes; it never rewrites gameplay or collision.
"""
import json
from pathlib import Path
import sys
sys.dont_write_bytecode = True
import build_rooftop_city as kit

ROOT = Path(__file__).resolve().parents[1]


def overlaps(a, b, padding=0):
    return all(a['min'][axis]-padding < b['max'][axis] and
               a['max'][axis]+padding > b['min'][axis] for axis in (0, 2))


def support_facades(solids, street):
    for index, solid in enumerate(solids):
        size = solid['size']
        if size[1] > 1.05 or min(size[0], size[2]) < 6 or solid['up'][1] < .99:
            continue
        # Stop below the lowest route in this footprint, including catch decks.
        # Sills/corner strips project outside the plain wall. Include adjacent
        # recovery floors when choosing height, even if footprints only touch.
        top = min(other['min'][1] for other in solids if overlaps(solid, other, .5)) - .08
        width = solid['max'][0] - solid['min'][0] - .12
        depth = solid['max'][2] - solid['min'][2] - .12
        x = (solid['max'][0] + solid['min'][0]) / 2
        z = (solid['max'][2] + solid['min'][2]) / 2
        if top < street + 4:
            continue
        kit.box((x, (top+street)/2, z), (width, top-street, depth), 'Brick')
        kit.facade((x, 0, z), width, depth, top, index, bottom=street)


def skyline(solids, street):
    z_start = max(s['max'][2] for s in solids)
    z_end = min(s['min'][2] for s in solids)
    rows = []
    for index, z in enumerate(range(int(z_start)+10, int(z_end)-30, -30)):
        nearby = [s for s in solids if s['min'][2]-22 < z < s['max'][2]+22]
        if not nearby:
            nearby = sorted(solids, key=lambda s: abs((s['min'][2]+s['max'][2])/2-z))[:1]
        left = min(s['min'][0] for s in nearby)
        right = max(s['max'][0] for s in nearby)
        roof = max(s['max'][1] for s in nearby)
        for side, edge in ((-1, left), (1, right)):
            width = 10 + index % 3 * 2
            depth = 20 + index % 2 * 3
            x = edge + side * (width/2 + 14 + index % 3 * 2)
            footprint = {'min':[x-width/2,street,z-depth/2], 'max':[x+width/2,roof+25,z+depth/2]}
            # Check the whole footprint, rather than just the row centre.
            while any(overlaps(footprint, s, 10) for s in solids):
                x += side * 8
                footprint['min'][0] += side * 8
                footprint['max'][0] += side * 8
            top = roof + 3 + (index * 7 + side) % 13
            kit.box((x, (top+street)/2, z), (width, top-street, depth), 'Plaster' if index%4 == 0 else 'Brick')
            kit.facade((x,0,z),width,depth,top,index+40,bottom=street)
            kit.gable((x,top,z),width+.5,depth+.5,4+index%3)
            kit.box((x+side*2,top+4,z-5),(1.3,8,1.4),'Brick')
            kit.box((x+side*2,top+8,z-5),(1.8,.28,1.9),'Iron')
            # The lower street and lamps never suggest an extra playable lane.
            lane_x = x-side*(width/2+5)
            kit.box((lane_x,street+.06,z),(8,.1,30),'Cobble',layer='Streets')
            kit.lamp((lane_x,street,z+6), True)
            rows.append((x,top,z))
    # A church-tower silhouette reuses the kit and sits beyond the final roof.
    last = min(solids, key=lambda s:s['min'][2])
    landmark_x = (last['min'][0]+last['max'][0])/2 + 60
    landmark_z = z_end-45
    kit.box((landmark_x,street+22,landmark_z),(12,44,12),'Stone',layer='Landmark')
    kit.gable((landmark_x,street+44,landmark_z),13,13,12,layer='Landmark')
    kit.window((landmark_x,street+34,landmark_z+6.12),(0,0,0),True,5,layer='Landmark')
    kit.EXTRAS.append(f'[node name="ClocktowerLandmark" type="Marker3D" parent="."]\nposition = Vector3({landmark_x}, {street+44}, {landmark_z})\n')
    kit.EXTRAS.append(f'[node name="LowerStreet" type="Marker3D" parent="."]\nposition = Vector3({rows[0][0]}, {street}, {rows[0][2]})\n')
    return rows


def main():
    geometry = json.loads((ROOT/'build/course_city_geometry.json').read_text())
    for name, data in geometry.items():
        kit.BATCHES.clear()
        kit.EXTRAS.clear()
        kit.OUT = ROOT / 'assets/rooftop_city/course_meshes' / name
        kit.DISTRICT = ROOT / f'levels/parkour/{name}_city_scenery.tscn'
        street = data['fall_height'] - 12
        support_facades(data['solids'], street)
        rows = skyline(data['solids'], street)
        lights = [(x, top+1, z) for x, top, z in rows[::max(1,len(rows)//6)][:6]]
        kit.write_meshes(lights, 'CityScenery')


if __name__ == '__main__':
    main()
