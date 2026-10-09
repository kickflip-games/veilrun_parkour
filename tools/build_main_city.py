#!/usr/bin/env python3
"""Editable city route -> Cyclops authoring manifest + Veilrun art batches.

Run this, then tools/export_main_city.gd in Godot. Runtime sectors contain no
Cyclops dependency. Distances are geometry measurements, never playtest times.
"""
from pathlib import Path
from collections import defaultdict
import math
import json
import argparse
import build_rooftop_city as art

ROOT = Path(__file__).resolve().parents[1]
SECTORS = [
    ("01_eaves", "THE EAVES", [(0,24,16),(0,24,-20),(-8,24,-65),(8,26,-110),(-6,26,-155),(8,28,-200),(0,28,-248)], 14),
    ("02_chimney_row", "CHIMNEY ROW", [(0,28,-248),(0,28,-270),(10,28,-310),(-10,30,-350),(10,30,-390),(-8,30,-430),(0,32,-472),(0,32,-492)], 16),
    ("03_blackglass", "BLACKGLASS DESCENT", [(0,32,-492),(-10,26,-550),(12,18,-615),(-10,12,-680),(0,8,-755)], 14),
    ("04_underway", "THE UNDERWAY", [(0,8,-755),(0,8,-805),(-10,8,-850),(10,8,-895),(-8,8,-935),(0,12,-990)], 12),
    ("05_bellmaker", "BELLMAKER'S TURN", [(0,12,-990),(0,12,-1075),(8,14,-1100),(24,16,-1118),(48,18,-1125),(72,18,-1118),(88,18,-1100),(96,18,-1075),(96,18,-1010),(115,18,-1000),(130,18,-1010),(130,18,-1070)], 16),
    ("06_high_ward", "THE HIGH WARD", [(130,18,-1070),(130,20,-1110),(155,28,-1150),(175,38,-1200),(155,48,-1240),(130,58,-1285),(130,68,-1340)], 14),
    ("07_long_fall", "THE LONG FALL", [(130,68,-1340),(105,60,-1390),(160,50,-1440),(115,38,-1490),(150,28,-1550),(130,24,-1600),(130,24,-1640)], 16),
]
EXTRA_ROUTES=[]
# Selected existing, stack-free first-row buildings. Distant scenery stays
# collision-free; these seven roofs provide small physical lateral excursions.
PLAYABLE_BUILDINGS={
    1:"EaveWatchRoof", 106:"SootsideRoof", 200:"BlackglassSideRoof",
    301:"UnderwayWorkshopRoof", 400:"BellCourtRoof",
    500:"WardServiceRoof", 616:"FinishClocksideRoof",
}


def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,n): return tuple(x*n for x in a)
def unit(a): return mul(a,1/math.sqrt(sum(x*x for x in a)))
def v(a): return "Vector3(%s)" % ", ".join(f"{x:.6f}" for x in a)
def route_length(points): return sum(math.dist(a,b) for a,b in zip(points,points[1:]))


def cross2(a,b,p): return (b[0]-a[0])*(p[2]-a[2])-(b[2]-a[2])*(p[0]-a[0])
def area(poly): return sum(a[0]*b[2]-b[0]*a[2] for a,b in zip(poly,poly[1:]+poly[:1]))/2


def half_clip(poly,a,b,sign,inside):
    result=[]
    previous=poly[-1]
    old=sign*cross2(a,b,previous)
    for current in poly:
        new=sign*cross2(a,b,current)
        before=old>=-1e-7 if inside else old<=1e-7
        after=new>=-1e-7 if inside else new<=1e-7
        if before!=after:
            result.append(add(previous,mul(sub(current,previous),old/(old-new))))
        if after:
            result.append(current)
        previous,old=current,new
    return result


def polygon_subtract(poly,cut):
    # Disjoint convex fragments outside a convex footprint. Keep the top Y by
    # interpolation, then weld connection vertices to the main roof plane.
    sign=1 if area(cut)>0 else -1
    working=poly
    result=[]
    for a,b in zip(cut,cut[1:]+cut[:1]):
        if len(working)<3:
            break
        outside=half_clip(working,a,b,sign,False)
        if len(outside)>=3 and abs(area(outside))>.01:
            result.append(outside)
        working=half_clip(working,a,b,sign,True)
    return result


def plane_height(poly,p):
    a,b,c=poly[:3]
    u,w=sub(b,a),sub(c,a)
    n=(u[1]*w[2]-u[2]*w[1],u[2]*w[0]-u[0]*w[2],u[0]*w[1]-u[1]*w[0])
    return a[1]-(n[0]*(p[0]-a[0])+n[2]*(p[2]-a[2]))/n[1]


def clip_braid_connections(sectors):
    main=[spec['top'] for sector in sectors for spec in sector['solids'] if spec['kind']=='safe']
    for sector in sectors:
        result=[]
        for spec in sector['solids']:
            if spec['kind'] not in ['fast','recovery','expert']:
                result.append(spec); continue
            fragments=[spec['top']]
            for cut in main:
                next_fragments=[]
                for poly in fragments:
                    if max(p[0] for p in poly)<min(p[0] for p in cut) or min(p[0] for p in poly)>max(p[0] for p in cut) or max(p[2] for p in poly)<min(p[2] for p in cut) or min(p[2] for p in poly)>max(p[2] for p in cut):
                        next_fragments.append(poly)
                    else:
                        next_fragments.extend(polygon_subtract(poly,cut))
                fragments=next_fragments
            for k,poly in enumerate(fragments):
                welded=[]
                for p in poly:
                    joins=[]
                    for cut in main:
                        for a,b in zip(cut,cut[1:]+cut[:1]):
                            dx,dz=b[0]-a[0],b[2]-a[2]
                            t=max(0,min(1,((p[0]-a[0])*dx+(p[2]-a[2])*dz)/(dx*dx+dz*dz)))
                            if math.hypot(p[0]-a[0]-t*dx,p[2]-a[2]-t*dz)<.025:
                                joins.append(plane_height(cut,p))
                    welded.append((p[0],max(joins) if joins else p[1],p[2]))
                # A boundary weld can twist the old quad. Triangular prisms give
                # visual and collision agreement with no nonplanar hull shortcut.
                for n in range(1,len(welded)-1):
                    triangle=[welded[0],welded[n],welded[n+1]]
                    if abs(area(triangle))>.005:
                        result.append(dict(spec,name=spec['name']+f'_Join{k}_{n}',top=triangle))
        sector['solids']=result


def weld_spire_balcony_rejoin(sectors):
    # Clipping inserts a y48 vertex on only one side of the last braid's
    # shared diagonal. Copy that breakpoint into the neighboring triangle
    # before retriangulating, eliminating its internal ~1m vertical face.
    # Main roofs, banks, route points and other braid volumes stay identical.
    sector=sectors[5]
    neighbors=[spec for spec in sector['solids'] if spec['name'].startswith('SpireLowerBalcony04')]
    vertices=[p for spec in neighbors for p in spec['top']]
    result=[]
    for spec in sector['solids']:
        if spec['name']!='SpireLowerBalcony04_T1_Join0_1':
            result.append(spec); continue
        outline=[]
        poly=spec['top']
        for a,b in zip(poly,poly[1:]+poly[:1]):
            outline.append(a)
            dx,dz=b[0]-a[0],b[2]-a[2]
            inserts={}
            for p in vertices:
                t=((p[0]-a[0])*dx+(p[2]-a[2])*dz)/(dx*dx+dz*dz)
                if 1e-6<t<1-1e-6 and math.hypot(p[0]-a[0]-t*dx,p[2]-a[2]-t*dz)<.002:
                    inserts[round(t,8)]=p
            outline.extend(inserts[t] for t in sorted(inserts))
        assert len(outline)==4, "Expected one Spire balcony shared-edge breakpoint"
        for n in range(1,len(outline)-1):
            result.append(dict(spec,name=spec['name']+f'_Weld{n}',top=[outline[0],outline[n],outline[n+1]]))
    sector['solids']=result


def road(manifest, name, points, width, kind="safe", material="Slate"):
    """Mitered top edges match exactly across seams; extrusion stays vertical."""
    edges=[]
    for i,p in enumerate(points):
        before=points[max(0,i-1)]
        after=points[min(len(points)-1,i+1)]
        previous=unit((p[0]-before[0],0,p[2]-before[2])) if i else unit((after[0]-p[0],0,after[2]-p[2]))
        following=unit((after[0]-p[0],0,after[2]-p[2])) if i<len(points)-1 else previous
        tangent=unit(add(previous,following))
        side=(-tangent[2],0,tangent[0])
        next_side=(-following[2],0,following[0])
        scale=width*.5/max(.5,sum(x*y for x,y in zip(side,next_side)))
        edges.append((add(p,mul(side,scale)),sub(p,mul(side,scale))))
    for i in range(len(points)-1):
        a,b=edges[i],edges[i+1]
        top=[a[0],a[1],b[1],b[0]]
        # Keep the exact shared miter vertices. A slope-turn quad can be twisted,
        # so export two planar triangular prisms instead of its convex hull.
        # Both neighboring segments share the complete seam, without a curb.
        for n,triangle in enumerate([[top[0],top[1],top[2]],[top[0],top[2],top[3]]]):
            manifest["solids"].append({"name":f"{name}{i:02}_T{n}","top":triangle,"depth":1.0,"material":material,"kind":kind})
    manifest["routes"].append({"name":name,"kind":kind,"points":points,"width":width,"length":route_length(points)})
    EXTRA_ROUTES.append((points,width))


def solid(manifest,name,pos,size,material="Brick",rotation=(0,0,0),kind="architecture"):
    manifest["solids"].append({"name":name,"position":pos,"size":size,"rotation":rotation,"material":material,"kind":kind})


def anchor(manifest,name,pos,kind="chimney_cap",support=None):
    manifest["anchors"].append({"name":name,"position":pos,"kind":kind})
    # Fixture is actually mounted to chimney, beam or a balcony bracket. Only
    # large support solids have collision; ornamental iron never snags a body.
    if support is None:
        support=add(pos,(0,-6,0))
    if kind=="chimney_cap":
        height=pos[1]-support[1]-.85
        art.box((pos[0],support[1]+height/2,pos[2]),(1.55,height,1.55),"Brick")
        art.box(add(pos,(0,-.78,0)),(2.1,.30,2.1),"Stone")
    elif kind=="weather_vane":
        art.beam(support,add(pos,(0,-.7,0)),.23,"Iron")
        art.box(add(support,(0,1.0,0)),(1.7,2.0,1.7),"Stone")
        art.beam(add(pos,(-1.5,-.7,0)),add(pos,(1.5,-.7,0)),.12,"Iron")
        art.beam(add(pos,(0,-.7,-1.5)),add(pos,(0,-.7,1.5)),.12,"Iron")
    elif kind=="roof_brace":
        art.beam(support,add(pos,(0,-.65,0)),.5,"Iron")
        art.beam(add(support,(3,0,0)),add(pos,(0,-.65,0)),.25,"Iron")
        art.box(add(pos,(0,-.7,0)),(2.2,.22,.6),"Iron")
    elif kind=="sign_bracket":
        sign=1 if pos[0]>=0 else -1
        outer=add(pos,(sign*10,0,0))
        art.beam(outer,add(pos,(0,-.7,0)),.30,"Iron")
        art.beam(add(outer,(0,-3,0)),add(pos,(0,-.7,0)),.16,"Iron")
        art.box(add(pos,(0,-1.6,0)),(2.8,1.1,.18),"Timber")
        art.box(add(pos,(0,-1.6,.11)),(1.8,.12,.06),"Warm")
    elif kind in ["balcony_brace","bell_mount"]:
        art.beam(support,add(pos,(0,-.7,0)),.40,"Iron")
        art.box(add(support,(0,-.25,0)),(4.0,.5,3.2),"Stone")
        art.beam(add(support,(-2,-1,0)),add(pos,(0,-.7,0)),.22,"Iron")
        art.box(add(pos,(0,-.7,0)),(2.6,.25,.5),"Iron")
    else:
        art.beam(support,add(pos,(0,-.7,0)),.32,"Iron")
        art.beam(add(pos,(-2,-.7,0)),add(pos,(2,-.7,0)),.24,"Iron")


def distance_to_route(p):
    closest=1e9
    for points,width in [(s[2],s[3]) for s in SECTORS]+EXTRA_ROUTES:
        for a,b in zip(points,points[1:]):
            dx,dz=b[0]-a[0],b[2]-a[2]
            t=max(0,min(1,((p[0]-a[0])*dx+(p[2]-a[2])*dz)/(dx*dx+dz*dz)))
            closest=min(closest,math.hypot(p[0]-a[0]-t*dx,p[2]-a[2]-t*dz)-width/2)
    return closest


def building(pos,width,depth,top,index,roof=True):
    bottom=-30
    art.box((pos[0],(top+bottom)/2,pos[2]),(width,top-bottom,depth),"Brick")
    art.facade((pos[0],0,pos[2]),width,depth,top,index,bottom=max(-12,top-13))
    art.box((pos[0],top+.3,pos[2]),(width+.5,.6,depth+.5),"Stone")
    if roof:
        art.gable((pos[0],top+.6,pos[2]),width,depth,4)
    # Soot-black stacks and occasional iron balconies make the skyline legible.
    if index%3==0:
        art.box((pos[0]+width*.26,top+3,pos[2]-depth*.2),(2.4,6,2.2),"Brick")
        art.box((pos[0]+width*.26,top+6,pos[2]-depth*.2),(2.9,.4,2.7),"Stone")


def playable_building(manifest,index,serial,center,top,entry,heading):
    """Collision volumes exactly match the existing body/cornice/gable art."""
    name=PLAYABLE_BUILDINGS[serial]
    assert serial%3!=0, "Selected roof needs a matching chimney collider"
    x,z=center[0],center[2]
    base=top+.6
    for suffix,pos,size,material in [
        ("Mass",(x,(top-30)/2,z),(18,top+30,25),"Brick"),
        ("Cornice",(x,top+.3,z),(18.5,.6,25.5),"Stone"),
    ]:
        solid(manifest,name+suffix,pos,size,material,kind="adjacent_roof")
        manifest["solids"][-1]["collision_only"]=True
    manifest["solids"].append({
        "name":name+"Gable", "base":[(x-9,base,z-12.5),(x+9,base,z-12.5),(x,base+4,z-12.5)],
        "extrude":(0,0,25), "material":"Slate", "kind":"adjacent_roof", "collision_only":True,
    })
    manifest.setdefault("playable_adjacent_roofs",[]).append({
        "id":name, "sector_index":index+1, "source_building_index":serial,
        "center":(x,base,z), "size":(18,25), "rise":4, "roof_top":base+4,
        "bounds":{"min":(x-9.25,-30,z-12.75),"max":(x+9.25,base+4,z+12.75)},
        "collider_parent":f"CitySections/Sector{index+1:02}/Architecture",
        "collider_names":[name+suffix for suffix in ["Mass","Cornice","Gable"]],
        "entry":entry, "heading":heading,
        "landing":(x,base+4+.6,z),
        "airborne_entry":(x,base+4+3,z+7),
        "approach_velocity":(0,0,-14), "landing_direction":(0,0,-1),
    })


def finish_playable_roofs(sectors):
    roofs=[]
    route_tops=[s["top"] for sector in sectors for s in sector["solids"] if s["kind"] in ["safe","fast","recovery","expert"]]
    for sector in sectors:
        for roof in sector.get("playable_adjacent_roofs",[]):
            x,base,z=roof["center"]
            # Whole cornice footprint, including capsule clearance, must miss
            # every route surface, not merely the nearest route centerline.
            rectangle=[(x-9.85,0,z-13.35),(x+9.85,0,z-13.35),(x+9.85,0,z+13.35),(x-9.85,0,z+13.35)]
            for poly in route_tops:
                clipped=rectangle
                sign=1 if area(poly)>0 else -1
                for a,b in zip(poly,poly[1:]+poly[:1]):
                    if not clipped: break
                    clipped=half_clip(clipped,a,b,sign,True)
                assert len(clipped)<3 or abs(area(clipped))<.001, f"{roof['id']} touches a route"
            p=roof["entry"]
            floors=[]
            for spec in sector["solids"]:
                if spec["kind"]!="safe": continue
                poly=spec["top"]; sign=1 if area(poly)>0 else -1
                if all(sign*cross2(a,b,p)>=-1e-5 for a,b in zip(poly,poly[1:]+poly[:1])):
                    floors.append(plane_height(poly,p))
            assert floors, f"{roof['id']} missing rejoin floor"
            roof["entry"]=(p[0],max(floors)+.6,p[2])
            roof["rejoin"]=roof["entry"]
            roof["route_rejoin"]=roof["entry"]
            target=min(sector["anchors"],key=lambda anchor:math.dist(anchor["position"],roof["landing"]))
            assert math.dist(target["position"],roof["landing"])<30, f"{roof['id']} return anchor too far"
            roof["nearby_return_anchor"]=f"CitySections/Sector{roof['sector_index']:02}/ArchitecturalAnchors/{target['name']}"
            roofs.append(roof)
    assert len(roofs)==len(PLAYABLE_BUILDINGS)
    return roofs


def city_dressing(manifest,index,points,width):
    serial=index*100
    for j,(a,b) in enumerate(zip(points,points[1:])):
        tangent=unit((b[0]-a[0],0,b[2]-a[2]))
        side=(-tangent[2],0,tangent[0])
        count=max(1,round(math.dist(a,b)/37))
        for k in range(count):
            t=(k+.5)/count
            p=add(a,mul(sub(b,a),t))
            # The running slate surface is the roof of an actual broad building.
            # All roof trim stays below the contact plane or outside the lane.
            art.box((p[0],p[1]-15,p[2]),(width+2,29,math.dist(a,b)/count-2),"Brick",(0,math.atan2(tangent[0],tangent[2]),0))
            for sign in [-1,1]:
                c=add(p,mul(side,sign*(width/2+17)))
                if distance_to_route(c)<12:
                    continue
                top=p[1]+(18 if index==3 else (2 if (serial+sign)%4==0 else -4))
                if serial in PLAYABLE_BUILDINGS:
                    # One Underway workshop gets the same low, reachable roof
                    # as the other selected buildings; the tall canyon remains.
                    if index==3: top=p[1]-4
                    playable_building(manifest,index,serial,c,top,p,mul(side,sign))
                building(c,18,25,top,serial)
                serial+=1
                # Occupied upper windows, low lamps and bracket silhouettes.
                near=add(p,mul(side,sign*(width/2+2.1)))
                art.box(add(near,(0,-.25,0)),(.18,.12,math.dist(a,b)/count-2),"Iron",(0,math.atan2(tangent[0],tangent[2]),0))
    # No finite road-in-empty-space backdrop: low city masses continue at depth.
    for j,p in enumerate(points[1:-1]):
        for sign in [-1,1]:
            for row in [0,1]:
                c=add(p,(sign*(54+row*36+(j%3)*9),0,9+row*17))
                if distance_to_route(c)>26:
                    top=p[1]+10+((j+row+index)%4)*8
                    width=20+((j+row)%3)*5
                    art.box((c[0],(top-30)/2,c[2]),(width,top+30,28),"Silhouette")
                    art.gable((c[0],top,c[2]),width,28,6+((j+index)%3)*3)
                    if row==0:
                        art.box((c[0],top-1,c[2]),(width+.35,.3,28.35),"Stone")
                        for opening in [-1,0,1]:
                            art.window((c[0]+opening*width*.28,top-5,c[2]+14.03),(0,0,0),lit=(j+opening+index)%3==0,height=2.3)
                    if (j+row)%3==0:
                        art.box((c[0]+4,top+7,c[2]),(4,14,4),"Silhouette")
                        art.gable((c[0]+4,top+14,c[2]),6,6,10)
                    serial+=1


def bellmaker_racing_slice(manifest):
    # The original wide roof and outside catch stay the dependable race line.
    # The optional frontage forms a high gallery, a physical speed gap and an
    # inhabited pressure alley below it. Passive devices never become anchors.
    gallery=[(8,12,-1044),(15,12,-1044),(18,18,-1038),(30,24,-1033),(34,24,-1014),(62,24,-1008),(76,24,-1022),(88,18,-1022),(96,18,-1022)]
    road(manifest,"BellUpperGallery",gallery,6,"expert","Slate")
    manifest["routes"][-1]["requires_traversal"]=True
    manifest["routes"][-1]["traversal"]={"mechanism":"BellGallerySpring","validation":"tests/validate_bellmaker_racing_slice.gd","reason":"The 43-degree first ascent uses the optional directional spring; slow grounded walking is not a supported entry."}
    # Find the exact top-edge departure on the expert gap's center line, rather
    # than counting the widened miter at the gallery fork as empty air.
    edges=[]
    for spec in manifest["solids"]:
        if not spec["name"].startswith("BellUpperGallery") or min(p[0] for p in spec["top"])>45: continue
        for a,b in zip(spec["top"],spec["top"][1:]+spec["top"][:1]):
            if (a[2]+1033)*(b[2]+1033)<=0 and abs(b[2]-a[2])>.0001:
                t=(-1033-a[2])/(b[2]-a[2])
                if 0<=t<=1: edges.append(a[0]+t*(b[0]-a[0]))
    departure=max(edges)
    landing=departure+24
    receiving=[(landing,24,-1033),(76,24,-1033),(76,24,-1022)]
    road(manifest,"BellGapLanding",receiving,6,"expert","Slate")
    alley=[(14,7,-1033),(54,7,-1033),(76,9,-1040),(88,18,-1044),(96,18,-1044)]
    road(manifest,"BellPressureAlley",alley,8,"recovery","Cobble")
    # Two passive slate wings outside the ordinary main roof shoulders.
    points=SECTORS[4][2]
    for j in [3,4]:
        a,b=points[j],points[j+1]
        tangent=unit((b[0]-a[0],0,b[2]-a[2])); side=(-tangent[2],0,tangent[0])
        center=add(mul(add(a,b),.5),add(mul(side,-10.05),(0,1.75,0)))
        if j==3:
            # The entry wing begins flush with the incoming y16 roof. Its
            # outside edge rises progressively, so the proven pull entry
            # never meets the old box bank's abrupt raised vertical endcap.
            inner_a=add(a,mul(side,-8.4)); outer_a=add(a,mul(side,-12.4))
            inner_b=add(b,mul(side,-8.4)); outer_b=add(add(b,mul(side,-12.4)),(0,4*math.tan(math.radians(38)),0))
            for n,top in enumerate([[inner_a,outer_a,outer_b],[inner_a,outer_b,inner_b]]):
                manifest["solids"].append({"name":f"BellSlateBank{j}_T{n}","top":top,"depth":.6,"material":"Slate","kind":"surf"})
        else:
            solid(manifest,f"BellSlateBank{j}",center,(5,.6,math.dist(a,b)-2),"Slate",(0,math.atan2(tangent[0],tangent[2]),-math.radians(38)),"surf")
        art.box(add(center,(0,-7,0)),(5,11,math.dist(a,b)-3),"Brick",(0,math.atan2(tangent[0],tangent[2]),0))
    # Scaffolding / upper workshop gives the gallery a physical architectural
    # setting. Its facade sits north of the low pressure corridor.
    solid(manifest,"BellFrontWorkshop",(55,-3.5,-1014),(40,53,16),"Brick")
    art.box((55,23.3,-1014),(41,.6,17),"Stone")
    art.facade((55,0,-1014),40,16,23,850,bottom=10)
    for x in [34,47,62,77,84]:
        art.beam((x,18,-1022),(x,23,-1018),.36,"Iron")
        art.box((x,4,-1021),(1.6,36,1.6),"Brick")
    for x in [24,42,60,78]:
        # Piers remain outside the eight-metre floor, and support overhead
        # arches at y13 so full standing capsules have ample alley clearance.
        for z in [-1027,-1039]:
            art.box((x,-8,z),(1.5,44,1.5),"Brick")
            art.box((x,13,z),(2,.4,2),"Stone")
        art.beam((x,13,-1027),(x,13,-1039),.30,"Iron")
        art.box((x,12.5,-1038.8),(1.6,.65,.10),"Warm")
    for x in range(27,58,3):
        art.box((x,7.06,-1033),(2.4,.10,5.6),"Iron")
        for z in [-1035,-1033,-1031]:art.box((x,7.13,z),(.09,.018,.45),"Stone")
    for x in [70,74,78,82,86]:
        art.box((x,8.4,-1038),(2.4,.10,7),"Iron")
        for z in [-1040,-1038,-1036]:art.box((x,8.48,z),(.13,.035,1.7),"Stone")
    # Tall narrow windows, ribs and clockwork braces break up the tower wall.
    for x in [38,48,58]:
        art.window((x,35,-1095.55),(0,math.pi,0),lit=x==48,height=9)
        art.beam((x-2.3,25,-1095.7),(x-2.3,45,-1095.7),.22,"Stone")
        art.beam((x+2.3,25,-1095.7),(x+2.3,45,-1095.7),.22,"Stone")
        art.beam((x-2.3,45,-1095.7),(x,48,-1095.7),.25,"Stone")
        art.beam((x,48,-1095.7),(x+2.3,45,-1095.7),.25,"Stone")
    # Spring is an off-centre architectural lane choice, clear of the main
    # route's centre and +/-4m shoulder samples.
    spring_pos=(11.5,12,-1044)
    manifest["launchers"].append({"name":"BellGallerySpring","position":spring_pos,"direction":(1,.86,.27),"strength":27})
    manifest["contact_traversals"]=[
        {"name":"BellPressureBoost","position":(42,7,-1033),"rotation":(0,0,0),"size":(30,2,7),"shape_position":(0,1,0),"mode":0,"heading":(1,0,0),"acceleration":24,"minimum_forward_speed":1,"maximum_forward_speed":24,"lift_acceleration":20,"maximum_upward_speed":10},
        {"name":"BellPressureReturn","position":(68,7,-1038),"rotation":(0,0,0),"size":(28,16,12),"shape_position":(0,7,0),"mode":1,"heading":(1,0,0),"acceleration":20,"minimum_forward_speed":1,"maximum_forward_speed":24,"lift_acceleration":32,"maximum_upward_speed":12},
    ]
    # Intent is expressed at three fixture clusters, instead of an evenly
    # spaced approach chain. Existing IDs used by roof return tests survive.
    for name,pos in [
        ("BellMount00",(20,28,-1033)),("BellMount01",(-7,21,-1025.0625)),
        ("BellMount02",(12,16,-1048)),("BellMount03",(7,21,-1067.5625)),
        ("BellMount06",(41.56,26.3,-1115.83)),
        ("BellMount10",(89,27,-1060.916667)),("BellMount11",(103,27,-1039.25)),
    ]:
        anchor(manifest,name,pos,"bell_mount",add(pos,(0,-7,0)))
    body=lambda p:add(p,(0,.6,0))
    prefix=[(0,12.6,-999),(0,12.6,-1024),(0,12.6,-1044)]
    suffix=[(96,18.6,-1010),(115,18.6,-1000),(130,18.6,-1010),(130,18.6,-1070),(130,18.6,-1080)]
    mid=prefix+[body(p) for p in SECTORS[4][2][1:]]+[(130,18.6,-1080)]
    high=prefix+[body(p) for p in gallery]+suffix
    low=prefix+[(7.5,12.6,-1044)]+[body(p) for p in alley]+suffix
    expert=prefix+[body(p) for p in gallery[:4]]+[(departure-.6,24.6,-1033)]+[body(p) for p in receiving]+[(88,18.6,-1022),(96,18.6,-1022)]+suffix
    manifest["racing_slice"]={
        "sector_index":5,"entry":(0,12.6,-999),"rejoin":(130,18.6,-1080),
        "decision":{"position":(0,12.6,-1044),"fixtures":["BellMount00","BellMount01","BellMount02","BellMount03"]},
        "gap":{"takeoff":(departure-.6,24.6,-1033),"landing":(landing+.6,24.6,-1033),"takeoff_edge":(departure,24,-1033),"landing_edge":(landing,24,-1033),"forward":(1,0,0),"span":24,"low_speed":8,"high_speed":24,"catch_name":"BellPressureAlley","landing_name":"BellGapLanding"},
        "fixture_clusters":[{"name":"FrontageChoice","fixtures":["BellMount00","BellMount01","BellMount02","BellMount03"]},{"name":"BellCorner","fixtures":["BellMount06","OuterBellRing"]},{"name":"GalleryReturn","fixtures":["BellMount10","BellMount11"]}],
        "passive_devices":[{"name":"BellGallerySpring","path":"CitySections/Sector05/BellGallerySpring","type":"spring"},{"name":"BellPressureBoost","path":"CitySections/Sector05/BellPressureBoost","type":"boost"},{"name":"BellPressureReturn","path":"CitySections/Sector05/BellPressureReturn","type":"updraft"}],
        "lines":[{"name":"safe","points":mid,"actions":[]},{"name":"mid","points":mid,"actions":[{"type":"pull","position":(24,16.6,-1118),"trigger_distance":3,"target":"OuterBellRing","hold_seconds":.35}]},{"name":"high","points":high,"actions":[]},{"name":"low","points":low,"actions":[]},{"name":"expert","points":expert,"actions":[],"speed_source":"BellGallerySpring"}],
        "failed_expert":{"name":"failed_expert","points":prefix+[body(p) for p in gallery[:4]]+[(departure-.6,24.6,-1033),(departure+10,7.6,-1033)]+[body(p) for p in alley[1:]]+suffix,"actions":[{"type":"brake","position":(30,25.8,-1033),"trigger_distance":3,"hold_seconds":.2,"heading":(1,0,0)}]},
    }


def sector_features(manifest,index,points,width):
    # Closely spaced fixtures are usable from an ordinary safe running line.
    serial=0
    for j,(a,b) in enumerate(zip(points,points[1:])):
        if index==4: break
        tangent=unit((b[0]-a[0],0,b[2]-a[2]))
        side=(-tangent[2],0,tangent[0])
        length=math.dist(a,b)
        for k in range(max(1,math.ceil(length/28))):
            t=(k+.65)/max(1,math.ceil(length/28))
            p=add(a,mul(sub(b,a),min(t,.96)))
            sign=-1 if serial%2 else 1
            target=add(p,add(mul(side,sign*(width/2-1)),(0,7 if index<4 else 9,0)))
            kind=["weather_vane","chimney_cap","roof_brace","sign_bracket","bell_mount","balcony_brace","crane_hook"][index]
            anchor(manifest,f"{['EaveRing','ChimneyRing','RoofBrace','SignBracket','BellMount','SpireBrace','CraneRing'][index]}{serial:02}",target,kind,support=add(target,(0,-7,0)))
            serial+=1
    if index==1:
        # Offset stacks cause wide safe apexes while leaving a 6m central margin.
        for j,p in enumerate(points[2:-1]):
            sign=-1 if j%2 else 1
            pos=add(p,(sign*5,3,0))
            solid(manifest,f"SootStack{j}",pos,(1.9,6,2.2))
            art.box(add(pos,(0,3.25,0)),(2.6,.5,2.8),"Stone")
    if index==2:
        # RIPTIDE's proven 52-degree bank language, dressed as factory roof slopes.
        for j,(a,b) in enumerate(zip(points,points[1:])):
            tangent=unit((b[0]-a[0],0,b[2]-a[2]))
            yaw=math.atan2(tangent[0],tangent[2])
            side=(-tangent[2],0,tangent[0])
            for sign in [-1,1]:
                p=add(add(a,b), (0,0,0)); p=mul(p,.5)
                # Inner bank contact edge meets safe roof at x=+/-7.
                center=add(p,add(mul(side,sign*(width/2+2.35)),(0,3.02,0)))
                solid(manifest,f"FactoryBank{j}_{sign}",center,(8,.8,math.dist(a,b)-3),"Slate",(0,yaw,sign*math.radians(52)),"surf")
                art.box(add(center,(0,-8,0)),(9,9,math.dist(a,b)-5),"Brick",(0,yaw,0))
    if index==0:
        road(manifest,"LowerEaveCatch",[(-8,24,-65),(-25,24,-68),(-30,20,-95),(-30,20,-135),(-27,26,-151),(-6,26,-155)],8,"recovery")
        road(manifest,"RidgeBraid",[(8,26,-110),(27,26,-113),(32,30,-133),(32,30,-164),(28,28,-195),(8,28,-200)],6,"fast")
    if index==1:
        road(manifest,"ChimneyLowBraid",[(10,28,-310),(10,28,-299),(31,28,-299),(34,24,-335),(34,24,-395),(30,30,-430),(-8,30,-430)],8,"recovery")
    if index==2:
        road(manifest,"FactoryLowCatch",[(-10,26,-550),(-34,26,-550),(-38,21,-575),(-38,11,-650),(-34,12,-680),(-10,12,-680)],10,"recovery")
    if index==3:
        road(manifest,"UpperCanopyBraid",[(0,8,-805),(22,8,-805),(27,15,-830),(27,15,-887),(24,8,-915),(-8,8,-935)],7,"fast","Iron")
        road(manifest,"AlleyLowCatch",[(-10,8,-850),(-32,8,-850),(-36,4,-875),(-36,4,-912),(-31,8,-935),(-8,8,-935)],9,"recovery","Cobble")
        # Steam mechanism uses existing one-entry launch physics with its markers hidden.
        manifest["launchers"].append({"name":"AlleySteamVent","position":(4,11.8,-982),"direction":(0,.55,-1),"strength":26})
    if index==4:
        # The broad 180-degree turn has a major bellhouse on its inside.
        solid(manifest,"Bellhouse",(48,30,-1083),(25,42,25),"Brick")
        building((48,0,-1083),25,25,51,504,roof=False)
        art.box((48,57,-1083),(18,12,18),"Stone")
        art.gable((48,63,-1083),20,20,17)
        # Copper bell mounting, warmer than the roof, is the visible corner apex.
        anchor(manifest,"OuterBellRing",(48,30,-1130),"bell_mount",(48,24,-1130))
        art.beam((36,29,-1130),(60,29,-1130),.5,"Iron")
        road(manifest,"BellLowArc",[(8,14,-1100),(-7,14,-1110),(7,10,-1145),(48,10,-1157),(91,10,-1145),(104,18,-1110),(88,18,-1100)],10,"recovery")
        bellmaker_racing_slice(manifest)
    if index==5:
        # Landmark core stays outside the actual body corridor, balconies wrap west.
        solid(manifest,"SpireCore",(199,30,-1224),(20,120,20),"Stone")
        building((199,0,-1224),20,20,90,605,roof=False)
        for y in [38,54,70,86]:
            art.box((199,y,-1224),(24,.6,24),"Stone")
        art.gable((199,90,-1224),22,22,35)
        anchor(manifest,"UpperSpireRing",(177,57,-1245),"balcony_brace",(190,52,-1245))
        road(manifest,"SpireLowerBalcony",[(155,28,-1150),(131,28,-1150),(119,24,-1180),(119,38,-1230),(130,48,-1244),(155,48,-1240)],8,"recovery","Stone")
        road(manifest,"SpireInnerBraid",[(155,28,-1150),(184,28,-1150),(225,45,-1176),(232,58,-1260),(160,58,-1293),(130,58,-1285)],6,"expert","Stone")
    if index==6:
        road(manifest,"FinalLowerRoofs",[(105,60,-1390),(78,60,-1390),(63,52,-1419),(65,28,-1510),(85,24,-1594),(130,24,-1600)],11,"recovery")
        manifest["launchers"].append({"name":"FinalPressureRidge","position":(135,66.5,-1349),"direction":(0,.32,-1),"strength":29})
        anchor(manifest,"FinalCraneHook",(137,58,-1420),"crane_hook",(160,58,-1420))
        art.beam((160,46,-1420),(160,62,-1420),.9,"Iron")
        art.beam((160,62,-1420),(132,62,-1420),.7,"Iron")
        art.beam((132,62,-1420),(137,58.8,-1420),.18,"Iron")
        # Paired amber clock faces form a distant, unmistakable finish landmark.
        for x in [110,150]:
            building((x,0,-1658),13,15,61,700,roof=False)
            art.gable((x,61,-1658),15,17,18)
            art.box((x,53,-1650.3),(7,7,.2),"Iron")
            for n in range(12):
                angle=n*math.tau/12
                art.box((x+math.sin(angle)*2.8,53+math.cos(angle)*2.8,-1650.12),(.28,.5,.1),"Warm",(0,0,-angle))
        art.beam((110,38,-1658),(150,38,-1658),.8,"Iron")


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--sector",choices=[s[0] for s in SECTORS],help="Only rewrite this sector's visual batches; always recompute the full manifest")
    args=parser.parse_args()
    out=ROOT/"assets/main_city"
    # Main-city skyline keeps Veilrun's brick texture, while the original
    # Veilrun palette remains untouched on disk and in its own generator.
    art.MATERIALS=dict(art.MATERIALS)
    art.MATERIALS['Silhouette']=("wall_brick_small_stone.png",(.25,.28,.32),.96)
    sectors=[]
    for index,(slug,title,points,width) in enumerate(SECTORS):
        art.BATCHES=defaultdict(list); art.EXTRAS=[]
        art.OUT=out/"meshes"/slug
        art.DISTRICT=ROOT/f"levels/parkour/city/{slug}_dressing.tscn"
        manifest={"slug":slug,"title":title,"safe_points":points,"width":width,"safe_length":route_length(points),"solids":[],"routes":[],"anchors":[],"launchers":[]}
        road(manifest,"RoofLine",points,width)
        sector_features(manifest,index,points,width)
        city_dressing(manifest,index,points,width)
        if args.sector is None or args.sector==slug:
            art.write_meshes(light_positions=[],root_name="CityDressing")
        sectors.append(manifest)
    clip_braid_connections(sectors)
    weld_spire_balcony_rejoin(sectors)
    playable_roofs=finish_playable_roofs(sectors)
    document={"generator":"tools/build_main_city.py","sectors":sectors,"safe_length":sum(s["safe_length"] for s in sectors),"playable_adjacent_roofs":playable_roofs}
    document["bellmaker_slice"]=sectors[4]["racing_slice"]
    document["geometry_repairs"]=[{"route":"SpireLowerBalcony","sector_index":6,"reason":"Insert the existing y48 shared-edge breakpoint into the adjacent final rejoin triangle, removing an internal vertical collision face.","changed_original_solids":["SpireLowerBalcony04_T1_Join0_1"],"main_route_and_banks_unchanged":True}]
    (out/"route_manifest.json").write_text(json.dumps(document,indent=2)+"\n")
    header=['[gd_scene format=3]', '[ext_resource type="Script" path="res://levels/parkour/parkour_trial.gd" id="Trial"]', '[ext_resource type="PackedScene" path="res://scenes/player/player.tscn" id="Player"]', '[ext_resource type="Script" path="res://scenes/parkour/city_checkpoint.gd" id="CP"]', '[ext_resource type="Sky" path="res://scenes/parkour/city_sky.tres" id="Sky"]']
    for i,(slug,_,_,_) in enumerate(SECTORS): header.append(f'[ext_resource type="PackedScene" path="res://levels/parkour/city/{slug}.tscn" id="Sector{i}"]')
    header += ['[sub_resource type="Environment" id="Mist"]\nbackground_mode = 2\nsky = ExtResource("Sky")\nambient_light_source = 3\nambient_light_color = Color(0.48, 0.57, 0.70, 1)\nambient_light_energy = 0.72\nfog_enabled = true\nfog_light_color = Color(0.22, 0.28, 0.36, 1)\nfog_density = 0.0027\nfog_sky_affect = 0.30\nfog_height = -8.0\nfog_height_density = 0.015', '[sub_resource type="BoxShape3D" id="Gate"]\nsize = Vector3(24, 55, 5)']
    nodes=['[node name="MainCityRun" type="Node3D"]\nscript = ExtResource("Trial")\ncourse_id = "veilrun_city_v1"\ncourse_title = "VEILRUN · CITY RUN"\ncheckpoint_paths = Array[NodePath](['+', '.join(f'NodePath("Checkpoint{i}")' for i in range(1,7))+'])\nfinish_path = NodePath("FinishGate")\nsector_names = PackedStringArray('+', '.join(json.dumps(s[1]) for s in SECTORS)+')\nsector_retry_enabled = true\nfall_height = -36.0\ngrapple_range = 30.0\nacquisition_horizontal_degrees = 20.0\nacquisition_vertical_degrees = 42.0\ncourse_intro = "Hold PULL to bend your line · Let go to fly"\nmetadata/safe_route_length = %.3f\nmetadata/target_first_competent_seconds = Vector2(180, 360)' % document["safe_length"],
    '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]\nenvironment = SubResource("Mist")',
    '[node name="Sun" type="DirectionalLight3D" parent="."]\nrotation = Vector3(-0.9, -0.5, 0)\nlight_color = Color(0.65, 0.72, 0.85, 1)\nlight_energy = 0.95\nshadow_enabled = true\ndirectional_shadow_max_distance = 85.0\ndirectional_shadow_fade_start = 0.7',
    '[node name="Player" parent="." instance=ExtResource("Player")]\nposition = Vector3(0, 24.55, 12)\nparkour_mode = true\nsurf_mode = true\nuse_momentum_pull = true\nvertical_look_enabled = false\nparkour_speed_limit = 32.0',
    '[node name="PlayerSpawn" type="Marker3D" parent="."]\nposition = Vector3(0, 24.55, 12)',
    '[node name="CitySections" type="Node3D" parent="."]']
    for i,(slug,_,_,_) in enumerate(SECTORS): nodes.append(f'[node name="Sector{i+1:02}" parent="CitySections" instance=ExtResource("Sector{i}")]')
    nodes+=['[node name="StartGate" type="Area3D" parent="."]\nposition = Vector3(0, 28, 0)\ncollision_layer = 0\ncollision_mask = 4', '[node name="CollisionShape3D" type="CollisionShape3D" parent="StartGate"]\nshape = SubResource("Gate")']
    cps=[]
    for i in range(1,7):
        p=SECTORS[i][2][0]; following=SECTORS[i][2][1]
        heading=unit((following[0]-p[0],0,following[2]-p[2]))
        gate=add(p,mul(heading,5)); gate=add(gate,(0,20,0))
        yaw=math.atan2(-heading[0],-heading[2])
        seed=add(p,mul(heading,9))
        seed_roofs=[]
        for surface in sectors[i]['solids']:
            if surface['kind']!='safe':
                continue
            poly=surface['top']; sign=1 if area(poly)>0 else -1
            if all(sign*cross2(a,b,seed)>=-1e-5 for a,b in zip(poly,poly[1:]+poly[:1])):
                seed_roofs.append(plane_height(poly,seed))
        floor_delta=max(seed_roofs)-p[1]
        nodes+=[f'[node name="Checkpoint{i}" type="Area3D" parent="."]\nposition = {v(gate)}\nrotation = Vector3(0, {yaw:.6f}, 0)\ncollision_layer = 0\ncollision_mask = 4\nscript = ExtResource("CP")\ncheckpoint_id = "city_cp_{i}"\nsector_name = {json.dumps(SECTORS[i][1])}\norder_index = {i}\ninitial_velocity = {v(mul(heading,12))}', f'[node name="CollisionShape3D" type="CollisionShape3D" parent="Checkpoint{i}"]\nshape = SubResource("Gate")',f'[node name="Respawn" type="Marker3D" parent="Checkpoint{i}"]\nposition = Vector3(0, {floor_delta-19.45:.6f}, -4)']
        cps.append({"index":i,"sector":SECTORS[i][1],"gate":gate,"entry":p,"heading":heading,"yaw":yaw,"practice_speed":12})
    nodes+=['[node name="FinishGate" type="Area3D" parent="."]\nposition = Vector3(130, 42, -1635)\ncollision_layer = 0\ncollision_mask = 4', '[node name="CollisionShape3D" type="CollisionShape3D" parent="FinishGate"]\nshape = SubResource("Gate")']
    (ROOT/"levels/parkour/MainCityRun.tscn").write_text('\n\n'.join(header+nodes)+'\n')
    document["checkpoints"]=cps
    (out/"route_manifest.json").write_text(json.dumps(document,indent=2)+"\n")
    print("MAIN CITY SAFE LENGTH",round(document["safe_length"],3))
    print("SECTORS",[(s["title"],round(s["safe_length"],1)) for s in sectors])


if __name__=="__main__": main()
