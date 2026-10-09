#!/usr/bin/env python3
"""Bake VEILRUN's authored boxes and city dressing into spatial mesh batches.

Run from anywhere with Python 3. No external libraries or source asset path needed.
The course retains named transforms and explicit BoxShape collision; its metadata
is the editable box authoring source. Dressing never creates gameplay collision.
"""
from collections import defaultdict
from pathlib import Path
import math
import json
import re
import struct

ROOT = Path(__file__).resolve().parents[1]
COURSE = ROOT / "levels/parkour/rooftop_trial.tscn"
OUT = ROOT / "assets/rooftop_city/meshes"
DISTRICT = ROOT / "levels/parkour/rooftop_city_district.tscn"
BATCHES = defaultdict(list)
EXTRAS = []
MODEL_CACHE = {}


def vec(value):
    return tuple(float(x) for x in re.search(r"Vector3\(([^)]+)\)", value)[1].split(","))


def rotate(p, r):
    x, y, z = p
    # Godot's default Euler order YXZ: apply Z, X, then Y.
    cx, sx, cy, sy, cz, sz = math.cos(r[0]), math.sin(r[0]), math.cos(r[1]), math.sin(r[1]), math.cos(r[2]), math.sin(r[2])
    x, y = x * cz - y * sz, x * sz + y * cz
    y, z = y * cx - z * sx, y * sx + z * cx
    return (x * cy + z * sy, y, -x * sy + z * cy)


def transform(p, pos, rot=(0, 0, 0)):
    return tuple(a + b for a, b in zip(rotate(p, rot), pos))


def face(points, mat, layer="City", uv=None):
    # Local 64m batches allow ordinary frustum culling; landmark is separate.
    center_z = sum(p[2] for p in points) / len(points)
    sector = math.floor(-center_z / 64) if layer != "Landmark" else 0
    if uv is None:
        a, b, c = points[:3]
        width = math.dist(a, b) / 3
        height = math.dist(b, c) / 3
        uv = [(0, 0), (width, 0), (width, height), (0, height)][:len(points)]
    BATCHES[(layer, sector, mat)].append((points, uv))


def box(pos, size, mat, rot=(0, 0, 0), layer="City"):
    x, y, z = (s / 2 for s in size)
    pts = [(-x,-y,-z), (x,-y,-z), (x,y,-z), (-x,y,-z), (-x,-y,z), (x,-y,z), (x,y,z), (-x,y,z)]
    pts = [transform(p, pos, rot) for p in pts]
    for indices in [(0,3,2,1), (4,5,6,7), (0,4,7,3), (1,2,6,5), (3,7,6,2), (0,1,5,4)]:
        face([pts[i] for i in indices], mat, layer)


def beam(a, b, width=0.15, mat="Iron", layer="City"):
    delta = tuple(v-u for u,v in zip(a,b))
    length = math.dist(a,b)
    # A box aligned along local Y.
    yaw = math.atan2(delta[0], delta[2])
    pitch = math.acos(max(-1, min(1, delta[1] / length)))
    box(tuple((u+v)/2 for u,v in zip(a,b)), (width,length,width), mat, (pitch,yaw,0), layer)


def gable(pos, width, depth, rise, layer="City"):
    x, z = width/2, depth/2
    p = [transform(q,pos) for q in [(-x,0,-z),(x,0,-z),(0,rise,-z),(-x,0,z),(x,0,z),(0,rise,z)]]
    face([p[0],p[2],p[1]], "Brick", layer)
    face([p[3],p[4],p[5]], "Brick", layer)
    face([p[0],p[3],p[5],p[2]], "Slate", layer)
    face([p[1],p[2],p[5],p[4]], "Slate", layer)
    box((pos[0],pos[1]+rise,pos[2]),(.20,.18,depth+.4),"Iron",layer=layer)
    box((pos[0],pos[1]-.18,pos[2]),(width+.45,.35,depth+.5),"Stone",layer=layer)


def window(center, rot, lit=False, height=2.0, layer="City"):
    # Opaque relief cards: twelve triangles instead of sixty per window.
    # Layered fronts and an actual projecting sill read at speed without overdraw.
    def card(offset,width,tall,mat,full_uv=False):
        x,y,z=offset
        points=[(x-width/2,y-tall/2,z),(x+width/2,y-tall/2,z),(x+width/2,y+tall/2,z),(x-width/2,y+tall/2,z)]
        face([transform(p,center,rot) for p in points],mat,layer,[(0,1),(1,1),(1,0),(0,0)] if full_uv else None)
    card((0,0,.04),1.35,height+.25,"Stone")
    card((0,0,.08),1.06,height,"Window" if lit else "Glass",True)
    card((0,0,.10),.08,height,"Iron")
    card((0,.1,.11),1.06,.08,"Iron")
    y=-height/2-.14
    card((0,y,.35),1.60,.15,"Stone")
    face([transform(p,center,rot) for p in [(-.8,y+.075,.04),(-.8,y+.075,.35),(.8,y+.075,.35),(.8,y+.075,.04)]],"Stone",layer)


def facade(center, width, depth, top, index, bottom=-18, layer="City"):
    # Repeated pieces are merged by material, not separate drawing nodes.
    height = top-bottom
    for side in [-1,1]:
        x = center[0]+side*width/2
        rot = (0,side*math.pi/2,0)
        for floor in range(max(1,int(height/5.5))):
            y = top-3.5-floor*5.5
            if y < bottom+3:
                continue
            for col in range(max(1,int(depth/5))):
                z = center[2]-depth/2+2.5+col*5
                window((x+side*.12,y,z),rot,(floor*7+col*3+index)%11==0,layer=layer)
        for z in [center[2]-depth/2+.6,center[2]+depth/2-.6]:
            box((x+side*.1,(top+bottom)/2,z),(.35,height,.6),"Stone",layer=layer)
        box((x+side*.15,top-5.4,center[2]),(.3,.22,depth),"Stone",layer=layer)
        # Drainpipe extends down the street facade, away from landing surfaces.
        box((x+side*.4,(top+bottom)/2,center[2]+depth/2-1.8),(.17,height,.17),"Iron",layer=layer)
    for side in [-1,1]:
        z = center[2]+side*depth/2
        rot = (0,0 if side==1 else math.pi,0)
        for floor in range(max(1,int(height/5.5))):
            y=top-3.5-floor*5.5
            for col in range(max(1,int(width/5))):
                x=center[0]-width/2+2.5+col*5
                window((x,y,z+side*.13),rot,(floor+col*5+index)%13==0,layer=layer)
        # Facade divisions make broad playable warehouses read as joined plots.
        for col in range(1,int(width/7)):
            x=center[0]-width/2+col*7
            box((x,(top+bottom)/2,z+side*.16),(.35,height,.35),"Stone",layer=layer)


def lamp(pos, street=False):
    x,y,z=pos
    box((x,y+1.5,z),(.15,3,.15),"Iron",layer="Streets" if street else "City")
    box((x,y+3.1,z),(.45,.65,.45),"Warm",layer="Streets" if street else "City")
    box((x,y+3.5,z),(.7,.16,.7),"Iron",layer="Streets" if street else "City")


def source_model(filename, pos, scale, rot=(0,0,0), mat="Iron", layer="City"):
    """Flatten only mesh-local geometry, stripping supplied demo layout offsets."""
    if filename not in MODEL_CACHE:
        path=ROOT/"assets/rooftop_city/source_models"/filename
        triangles=[]
        if path.suffix==".obj":
            vertices=[]
            for line in path.read_text().splitlines():
                if line.startswith("v "):
                    vertices.append(tuple(map(float,line.split()[1:4])))
                elif line.startswith("f "):
                    ids=[int(v.split("/")[0])-1 for v in line.split()[1:]]
                    for i in range(1,len(ids)-1):
                        triangles.append([vertices[j] for j in [ids[0],ids[i],ids[i+1]]])
        else:
            raw=path.read_bytes()
            offset=12
            doc=None
            binary=None
            while offset<len(raw):
                length,kind=struct.unpack_from("<II",raw,offset)
                chunk=raw[offset+8:offset+8+length]
                if kind==0x4E4F534A:
                    doc=json.loads(chunk)
                elif kind==0x004E4942:
                    binary=chunk
                offset+=length+8
            def accessor(index):
                spec=doc["accessors"][index]
                view=doc["bufferViews"][spec["bufferView"]]
                count={"SCALAR":1,"VEC2":2,"VEC3":3,"VEC4":4}[spec["type"]]
                kind={5121:"B",5123:"H",5125:"I",5126:"f"}[spec["componentType"]]
                fmt="<"+kind*count
                start=view.get("byteOffset",0)+spec.get("byteOffset",0)
                stride=view.get("byteStride",struct.calcsize(fmt))
                return [struct.unpack_from(fmt,binary,start+i*stride) for i in range(spec["count"])]
            for mesh in doc["meshes"]:
                for primitive in mesh["primitives"]:
                    vertices=accessor(primitive["attributes"]["POSITION"])
                    ids=[x[0] for x in accessor(primitive["indices"])] if "indices" in primitive else list(range(len(vertices)))
                    for i in range(0,len(ids),3):
                        triangles.append([vertices[j] for j in ids[i:i+3]])
        points=[p for t in triangles for p in t]
        lower=[min(p[i] for p in points) for i in range(3)]
        upper=[max(p[i] for p in points) for i in range(3)]
        center=((lower[0]+upper[0])/2,lower[1],(lower[2]+upper[2])/2)
        MODEL_CACHE[filename]=[[tuple(p[i]-center[i] for i in range(3)) for p in t] for t in triangles]
    for triangle in MODEL_CACHE[filename]:
        face([transform(tuple(p[i]*scale[i] for i in range(3)),pos,rot) for p in triangle],mat,layer,[(0,0),(1,0),(1,1)])


def tower():
    x,z=0,-451
    layer="Landmark"
    box((x,15,z),(15,66,15),"Brick",layer=layer)
    facade((x,0,z),15,15,48,100,layer=layer)
    for y,width in [(26,16),(42,16.6),(48,17.5),(56,16.8)]:
        box((x,y,z),(width,.55,width),"Stone",layer=layer)
    box((x,52,z),(14,8,14),"Stone",layer=layer)
    # Front clock: twelve warm inset markers and fixed metal hands, no texture or animation.
    box((x,52,z+7.16),(6.6,6.6,.25),"Iron",layer=layer)
    for n in range(12):
        a=n*math.tau/12
        box((x+math.sin(a)*2.65,52+math.cos(a)*2.65,z+7.35),(.23,.40,.12),"Window",(0,0,-a),layer)
    beam((x,52,z+7.43),(x,54.2,z+7.43),.16,"Window",layer)
    beam((x,52,z+7.43),(x+1.65,51.2,z+7.43),.16,"Window",layer)
    gable((x,56,z),17,17,13,layer)
    # Four corner pinnacles and the weather vane form an identifiable distant silhouette.
    for sx in [-1,1]:
        for sz in [-1,1]:
            px,pz=x+sx*7.7,z+sz*7.7
            box((px,58,pz),(1.6,8,1.6),"Stone",layer=layer)
            gable((px,62,pz),2.1,2.1,5,layer)
    box((x,71,z),(.22,6,.22),"Iron",layer=layer)
    box((x,73,z),(3.2,.18,.18),"Iron",layer=layer)


def dressing(nodes):
    # Add relief below the playable deck; no small snagging collision.
    buildings=[]
    for path,data in nodes.items():
        if path.endswith("/Building"):
            center=data["world"]
            w,h,d=data["size"]
            top=center[1]+h/2
            buildings.append((path,center,w,d,top))
    for i,(path,center,w,d,top) in enumerate(buildings):
        facade(center,w,d,top,i)
        # Curated relief panels break large facades below the traversal layer.
        model="building_church_side_bottom1.obj" if i in [6,7,8,14] else "building_factory.obj"
        source_model(model,(center[0],top-10,center[2]+d/2+.18),(1.2,1.7,1.0),mat="Stone")
        # Actual pack pipes/ducts sit beside existing collision chimneys.
        side=-1 if i%2 else 1
        px=center[0]+side*(w/2-1.6)
        source_model("duct_long.glb",(px,top+.08,center[2]-d/3),(.6,.6,.6),mat="Iron")
        source_model("pipe_corner_rusted.glb",(px,top+.1,center[2]+d/3),(.65,.65,.65),mat="Iron")
        source_model("pipe_rusted.glb",(px,top+.1,center[2]+d/3-1),(.6,1.2,.6),mat="Iron")
        # Broken slate coping, damp roof seams and exterior truss rhythm.
        for side in [-1,1]:
            box((center[0]+side*(w/2-.3),top+.14,center[2]),(.35,.18,d-.8),"Slate")
        for z in range(int(center[2]-d/2+3),int(center[2]+d/2-2),7):
            box((center[0],top+.071,z),(w-.8,.015,.05),"Iron")
        # Balcony and shop floor sit safely below the playable roof.
        bx=center[0]-w/2-1.15
        by=top-7.2
        box((bx,by,center[2]),(2.1,.24,5),"Iron")
        for z in [center[2]-2.4,center[2]+2.4]:
            box((bx,by+1,z),(2,.1,.1),"Iron")
        for dz in [-2,-1,0,1,2]:
            box((bx-1,by+.5,center[2]+dz),(.08,1,.08),"Iron")
        box((bx-1,by+1,center[2]),(.1,.1,5),"Iron")
        box((center[0],-14.7,center[2]+d/2+.2),(3.2,4.5,.24),"Timber",layer="Streets")
        box((center[0],-12,center[2]+d/2+1.1),(5,.3,2.5),"Timber",(.14,0,0),"Streets")
    # Close irregular rows create narrow streets on both sides of the route.
    # East climbing service lane / west chain recovery stay clear.
    heights=[18,25,21,31,24,19,29,23,34,22,27,20,32,24,28,21,30,26]
    for side in [-1,1]:
        for i in range(18):
            z=8-i*26
            x=side*(39+(i%3)*3)
            if (side==1 and -250<z<-155) or (side==-1 and -335<z<-245):
                x=side*49
            width=10+(i%3)*2
            depth=20+(i%2)*3
            top=heights[(i+(3 if side==1 else 0))%len(heights)]
            box((x,(top-18)/2,z),(width,top+18,depth),"Brick" if i%4 else "Plaster")
            facade((x,0,z),width,depth,top,i+40)
            gable((x,top,z),width+.5,depth+.5,5+(i%4)*1.4)
            # Dormer, tall chimney and narrow iron balcony on the inward eave.
            inward=x-side*(width/2-1)
            box((inward,top+1.5,z+5),(2.2,3,2.6),"Plaster")
            gable((inward,top+3,z+5),2.6,3,1.8)
            box((x+side*2,top+5,z-5),(1.3,10,1.4),"Brick")
            box((x+side*2,top+10,z-5),(1.8,.28,1.9),"Iron")
            lamp((x-side*(width/2+1.8),-18,z+6),True)
    # Cobble streets and thin reflective puddles are solid opaque geometry.
    for side in [-1,1]:
        box((side*27,-17.94,-210),(10,.1,476),"Cobble",layer="Streets")
        box((side*28,-17.86,-210),(.45,.12,476),"Iron",layer="Streets")
        for i in range(16):
            z=-i*29
            box((side*(25+i%3),-17.82,z),(2.4,.02,5),"Puddle",layer="Streets")
            # Crates and discarded timber make the lower city inhabited.
            box((side*30,-17.25,z+4),(1.6,1.4,1.6),"Timber",layer="Streets")
    for z in [-28,-95,-172,-260,-344,-397]:
        box((0,-17.94,z),(68,.1,7),"Cobble",layer="Streets")
        # Suspended clotheslines sit well below traversal and expose the alley.
        beam((-27,-6,z),(27,-7,z),.055,"Iron","Streets")
        for x in [-20,-16,17,21]:
            box((x,-7.5,z),(1.1,1.6,.035),"Plaster",(.05,.2,.07),"Streets")
    # Mid-level viaduct below the expert transfer, with narrow arched supports.
    for x in [-27,27]:
        box((x,-4,-116),(3,28,3),"Stone")
    box((0,8.7,-116),(57,1.4,3),"Stone")
    for x in range(-26,27,3):
        box((x,10,-116),(.13,1.2,.13),"Iron")
    box((0,10.6,-116),(57,.12,.12),"Iron")
    # The crane's rigging connects the expert ring with a believable hook.
    box((0,-3,-97),(1.15,30,1.15),"Iron")
    box((0,-17.5,-97),(3,1,3),"Stone",layer="Streets")
    for side in [-1,1]:
        beam((side*.55,12,-97),(side*.55,24,-97),.16)
        beam((side*.55,24,-97),(side*.55,24,-126),.16)
        for z in range(-124,-98,4):
            beam((side*.55,24,z),(side*.55,22.8,z+4),.1)
            beam((side*.55,22.8,z),(side*.55,24,z+4),.1)
    beam((0,24,-111),(0,19.6,-111),.12)
    # Anchor supports are above / outside the body travel, not new occluders.
    for path,data in nodes.items():
        if not path.endswith("Ring") or "size" in data:
            continue
        x,y,z=data["world"]
        if path in ["GapSkipRing","CourtyardSkipRing"]:
            continue
        # Ring hangs from a sign iron bolted to the neighboring warehouse eave.
        nearby=min(buildings,key=lambda b: abs(b[1][2]-z))
        w=nearby[2]
        side=-1 if x<=0 else 1
        sx=nearby[1][0]+side*(w/2-.7)
        beam((sx,nearby[4]+.3,z),(sx,y+.68,z),.16)
        beam((sx,y+.68,z),(x,y+.68,z),.18)
        beam((sx,y-1.4,z),(x+side*2,y+.68,z),.1)
    # Street-level gothic arch frame: angular low-poly voussoirs, no alpha.
    for x in [-28,28]:
        for side in [-1,1]:
            box((x+side*3,-14,-172),(1.0,8,2),"Stone",layer="Streets")
            beam((x+side*3,-10,-172),(x,-7.5,-172),.9,"Stone","Streets")
    tower()
    for name,pos in [("StreetCanyon",(27,-18,-116)),("AlleyPassage",(0,-18,-172)),("IndustrialCrane",(0,24,-111)),("ClocktowerLandmark",(0,52,-451)),("LowerCity",(-27,-18,-290))]:
        EXTRAS.append(f'[node name="{name}" type="Marker3D" parent="."]\nposition = Vector3{pos}\n')


MATERIALS={
    "Brick":("wall_brick_small_stone.png",(.36,.36,.40),.93),
    "Stone":("wall_stone.png",(.43,.44,.49),.93),
    "Slate":("roof_clay_grey_center.png",(.30,.36,.46),.84),
    "Plaster":("wall_stone.png",(.34,.32,.33),.96),
    "Timber":("wall_timber.png",(.28,.22,.18),.95),
    "Cobble":("floor_stone_pattern.png",(.31,.34,.38),.45),
    "Iron":(None,(.105,.115,.14),.72),
    "Trim":(None,(.47,.48,.49),.90),
    "Glass":("window_tall_rounded.png",(.22,.27,.34),.55),
    "Puddle":(None,(.20,.25,.30),.25),
    "Warm":(None,(.85,.55,.24),1),
    "Window":("window_tall_rounded_lit.png",(.85,.66,.38),1),
    "Silhouette":(None,(.13,.16,.19),.96),
}


def write_meshes(light_positions=None, root_name="RooftopCityDistrict"):
    OUT.mkdir(parents=True,exist_ok=True)
    resources=[]
    instance_nodes=[]
    total=0
    used=set()
    for i,((layer,sector,mat),faces) in enumerate(sorted(BATCHES.items())):
        filename=f"{layer.lower()}_{sector}_{mat.lower()}.obj"
        used.add(filename)
        output=["# Static VEILRUN city batch. Generated by tools/build_rooftop_city.py"]
        origin=(0,0,-sector*64)
        index=1
        for points,uvs in faces:
            for p in points:
                output.append("v %.5f %.5f %.5f" % tuple(v-o for v,o in zip(p,origin)))
            for u,v in uvs:
                output.append("vt %.5f %.5f" % (u,v))
            # OBJ importer produces flat normals for these unshared corners.
            for j in range(1,len(points)-1):
                output.append("f " + " ".join(f"{k}/{k}" for k in [index,index+j,index+j+1]))
                total+=1
            index+=len(points)
        (OUT/filename).write_text("\n".join(output)+"\n")
        resource_path = (OUT / filename).relative_to(ROOT).as_posix()
        resources.append(f'[ext_resource type="ArrayMesh" path="res://{resource_path}" id="Mesh{i}"]')
        shadow=1 if mat in ["Brick","Slate","Plaster"] and layer!="Landmark" else 0
        instance_nodes.append(f'[node name="{layer}{sector}{mat}" type="MeshInstance3D" parent="."]\nposition = Vector3{origin}\nmesh = ExtResource("Mesh{i}")\nmaterial_override = SubResource("{mat}")\ncast_shadow = {shadow}\n')
    # Remove only prior outputs owned by this generator.
    for p in OUT.glob("*.obj"):
        if p.name not in used and p.read_text().startswith("# Static VEILRUN city batch."):
            p.unlink()
            p.with_suffix(".obj.import").unlink(missing_ok=True)
    sub=[]
    for mat,(texture,color,roughness) in MATERIALS.items():
        if texture:
            resources.append(f'[ext_resource type="Texture2D" path="res://assets/rooftop_city/textures/{texture}" id="Texture{mat}"]')
        s=f'[sub_resource type="StandardMaterial3D" id="{mat}"]\nalbedo_color = Color({color[0]}, {color[1]}, {color[2]}, 1)\nroughness = {roughness}\n'
        if texture:
            s+=f'albedo_texture = ExtResource("Texture{mat}")\ntexture_filter = 0\n'
        if mat in ["Warm","Window"]:
            s+='shading_mode = 0\nemission_enabled = true\nemission = Color(0.85, 0.55, 0.24, 1)\nemission_energy_multiplier = 0.3\n'
        sub.append(s)
    lights=[]
    if light_positions is None:
        light_positions = [(-10.85,14,-7),(24.85,14,-124),(24.85,22,-199),(-22.85,26,-274),(22.85,26,-389),(0,27,-426)]
    for i,(x,y,z) in enumerate(light_positions):
        lights.append(f'[node name="Gaslight{i}" type="OmniLight3D" parent="."]\nposition = Vector3({x}, {y}, {z})\nlight_color = Color(0.847, 0.608, 0.322, 1)\nlight_energy = 2.8\nomni_range = 9.0\nomni_attenuation = 1.6\nshadow_enabled = false\ndistance_fade_enabled = true\ndistance_fade_begin = 38.0\ndistance_fade_length = 12.0\n')
    DISTRICT.write_text('[gd_scene format=3]\n\n'+'\n'.join(resources)+'\n\n'+'\n'.join(sub)+f'\n[node name="{root_name}" type="Node3D"]\nmetadata/triangle_count = '+str(total)+'\nmetadata/batch_count = '+str(len(instance_nodes))+'\n\n'+'\n'.join(instance_nodes+EXTRAS+lights))
    print(f"{root_name}: {len(instance_nodes)} spatial/material batches, {total:,} triangles; {len(lights)} shadowless local lights")


def main():
    text=COURSE.read_text()
    header,*blocks=re.split(r"(?=\[node )",text)
    solid_paths=set(re.findall(r'\[node name="Body" type="StaticBody3D" parent="([^"]+)"\]',text))
    # Rebuild our owned shapes every time so later metadata size edits update
    # both art and collision, including sizes that previously shared a shape.
    header=re.sub(r'\[sub_resource type="BoxShape3D" id="CityCollision\d+"\]\nsize = Vector3[^\n]+\n+',"",header)
    nodes={}
    converted=[]
    shapes=[]
    shape_ids={}
    for block in blocks:
        first=block.splitlines()[0]
        name=re.search(r'name="([^"]+)"',first)[1]
        parent=re.search(r'parent="([^"]+)"',first)
        path=(parent[1]+"/" if parent and parent[1]!="." else "")+name
        if parent and ((name=="Body" and parent[1] in solid_paths) or (name=="Shape" and parent[1].removesuffix("/Body") in solid_paths)):
            continue
        props={k:v for k,v in re.findall(r"^([\w/]+) = (.+)$",block,re.M)}
        pos=vec(props.get("position","Vector3(0,0,0)"))
        rot=vec(props.get("rotation","Vector3(0,0,0)"))
        world=pos
        if parent and parent[1] in nodes:
            world=transform(pos,nodes[parent[1]]["world"],nodes[parent[1]]["rot"])
        data={"world":world,"rot":rot}
        size=props.get("size",props.get("metadata/visual_size"))
        if size:
            data["size"]=vec(size)
            material=props.get("material")
            mat=re.search(r'SubResource\("([^"]+)"\)',material)[1] if material else props["metadata/visual_material"].strip('"')
            # Replace the sparse distant cuboids with an irregular roofscape.
            if not name.startswith(("CitySilhouette","CityCornice","CityStack")):
                box(world,data["size"],"Slate" if name=="Roof" else mat,rot)
            if 'type="CSGBox3D"' in first or "metadata/visual_size" in props:
                first=first.replace('type="CSGBox3D"','type="Node3D"')
                kept=[line for line in block.splitlines()[1:] if not line.startswith(("size =","material =","use_collision =","metadata/visual_size =","metadata/visual_material =","metadata/solid ="))]
                new=first+'\n'+'\n'.join(kept).strip()+f'\nmetadata/visual_size = {size}\nmetadata/visual_material = "{mat}"\n\n'
                if props.get("use_collision")=="true" or props.get("metadata/solid")=="true" or path in solid_paths:
                    new=new.rstrip()+"\nmetadata/solid = true\n\n"
                    key=data["size"]
                    if key not in shape_ids:
                        sid=f"CityCollision{len(shape_ids)}"
                        shape_ids[key]=sid
                        shapes.append(f'[sub_resource type="BoxShape3D" id="{sid}"]\nsize = {size}\n')
                    new+=f'[node name="Body" type="StaticBody3D" parent="{path}"]\n\n[node name="Shape" type="CollisionShape3D" parent="{path}/Body"]\nshape = SubResource("{shape_ids[key]}")\n\n'
                block=new
        if 'instance=ExtResource("Anchor")' in first and "architectural_fixture" not in block:
            block=block.rstrip()+"\narchitectural_fixture = true\n\n"
        nodes[path]=data
        converted.append(block)
    dressing(nodes)
    write_meshes()
    if shapes:
        header+='\n'.join(shapes)+'\n'
    if 'id="CityDistrict"' not in header:
        header=header.replace('\n\n[sub_resource', '\n[ext_resource type="PackedScene" path="res://levels/parkour/rooftop_city_district.tscn" id="CityDistrict"]\n\n[sub_resource',1)
        converted.append('[node name="CityDistrict" parent="." instance=ExtResource("CityDistrict")]\n')
    # Night palette and cheap height/depth mist, with near roofs still readable.
    for old,new in [
        ('background_color = Color(0.20, 0.25, 0.28, 1)','background_color = Color(0.095, 0.125, 0.17, 1)'),
        ('ambient_light_color = Color(0.42, 0.48, 0.53, 1)','ambient_light_color = Color(0.48, 0.57, 0.70, 1)'),
        ('ambient_light_energy = 0.7','ambient_light_energy = 0.62'),
        ('fog_light_color = Color(0.22, 0.27, 0.30, 1)','fog_light_color = Color(0.22, 0.28, 0.36, 1)'),
        ('fog_density = 0.0045','fog_density = 0.0037'),
    ]:
        header=header.replace(old,new)
    if 'fog_height =' not in header:
        header=header.replace('fog_sky_affect = 1.0','fog_sky_affect = 1.0\nfog_height = -5.0\nfog_height_density = 0.045')
    if 'id="CitySky"' not in header:
        sky='''[sub_resource type="ProceduralSkyMaterial" id="CitySkyMaterial"]
sky_top_color = Color(0.015, 0.026, 0.052, 1)
sky_horizon_color = Color(0.18, 0.23, 0.30, 1)
ground_bottom_color = Color(0.07, 0.09, 0.12, 1)
ground_horizon_color = Color(0.18, 0.23, 0.30, 1)
sun_angle_max = 1.5
sun_curve = 0.05

[sub_resource type="Sky" id="CitySky"]
sky_material = SubResource("CitySkyMaterial")

'''
        header=header.replace('[sub_resource type="Environment" id="Mist"]',sky+'[sub_resource type="Environment" id="Mist"]')
        header=header.replace('background_mode = 1','background_mode = 2\nsky = SubResource("CitySky")')
        header=header.replace('fog_sky_affect = 1.0','fog_sky_affect = 0.35')
    result=header+''.join(converted)
    result=result.replace('light_color = Color(0.77, 0.82, 0.85, 1)','light_color = Color(0.48, 0.60, 0.78, 1)').replace('light_energy = 1.1','light_energy = 0.85')
    if 'directional_shadow_max_distance' not in result:
        result=result.replace('light_energy = 0.85','light_energy = 0.85\nshadow_enabled = true\ndirectional_shadow_max_distance = 80.0\ndirectional_shadow_fade_start = 0.7')
    COURSE.write_text(result)


if __name__=="__main__":
    main()
