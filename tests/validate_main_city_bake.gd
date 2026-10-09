extends SceneTree
## Read-only authoring/export parity audit. PackedScene states retain editable
## block vertex data without instantiating the Cyclops editor nodes. Runtime
## sectors are instantiated outside the tree, so gameplay never starts or saves.
## Run: godot --headless --path . --script tests/validate_main_city_bake.gd
var failures: Array[String] = []
var checks := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("CITY_BAKE_FAIL ",label)
func vector(a: Array) -> Vector3:
	return Vector3(a[0],a[1],a[2])
func same_points(a: PackedVector3Array,b: PackedVector3Array) -> bool:
	for p in a:
		var found := false
		for q in b:
			if p.distance_to(q)<.002:
				found = true
				break
		if not found:return false
	for q in b:
		var found := false
		for p in a:
			if p.distance_to(q)<.002:
				found = true
				break
		if not found:return false
	return true
func run() -> void:
	var sound=root.get_node("SoundManager")
	for audio in sound.get_children():
		if audio is AudioStreamPlayer:audio.stop();audio.stream=null
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	var authoring: PackedScene=load("res://tools/city_authoring/MainCityCyclops.tscn")
	var state=authoring.get_state()
	var authored: Dictionary={}
	var authored_transforms: Dictionary={}
	for i in range(state.get_node_count()):
		var props:Dictionary={}
		for j in range(state.get_node_property_count(i)):
			props[state.get_node_property_name(i,j)]=state.get_node_property_value(i,j)
		if props.has("mesh_vector_data"):
			var data=props.mesh_vector_data.vertex_data["position"].data
			var points := PackedVector3Array()
			for j in range(0,data.size(),3):points.append(Vector3(data[j],data[j+1],data[j+2]))
			var path=str(state.get_node_path(i)).trim_prefix("./")
			authored[path]=points
			authored_transforms[path]=props.get("transform",Transform3D.IDENTITY)
	var total := 0
	for sector in manifest.sectors:
		var source=FileAccess.get_file_as_string("res://levels/parkour/city/%s.tscn" % sector.slug)
		check(not "cyclops" in source.to_lower(),sector.slug+" runtime contains no Cyclops dependency")
		var scene=load("res://levels/parkour/city/%s.tscn" % sector.slug).instantiate()
		for spec in sector.solids:
			var path=sector.slug+"/Architecture/"+spec.name
			check(authored.has(path),path+" retained editable block")
			var wrapper=scene.get_node("Architecture/"+spec.name)
			var body=wrapper.get_node("collision_body")
			var shape_node=body.get_node("collision_shape")
			var mesh_node=wrapper.get_node("mesh_instance")
			check(wrapper.transform.is_equal_approx(authored_transforms.get(path,Transform3D.IDENTITY)),path+" authored and runtime placement agree")
			check(mesh_node.transform.is_equal_approx(Transform3D.IDENTITY) and (body.transform*shape_node.transform).is_equal_approx(Transform3D.IDENTITY),path+" mesh and collision child transforms remain aligned")
			check(body is StaticBody3D and shape_node.shape is ConvexPolygonShape3D,path+" ordinary convex runtime collision")
			check(body.collision_layer==1 and body.collision_mask==4,path+" original collision filtering")
			check(same_points(authored.get(path,PackedVector3Array()),shape_node.shape.points),path+" authoring and runtime collision points agree")
			var visible_points := PackedVector3Array()
			for n in range(mesh_node.mesh.get_surface_count()):
				visible_points.append_array(mesh_node.mesh.surface_get_arrays(n)[Mesh.ARRAY_VERTEX])
			check(same_points(shape_node.shape.points,visible_points),path+" runtime mesh mirrors convex collision")
			check(mesh_node.visible!=spec.get("collision_only",false),path+" hidden duplicate roof policy")
			total+=1
		print("CITY_BAKE_SECTOR ",sector.slug," solids=",sector.solids.size())
		scene.free()
	check(authored.size()==total,"Every authored solid has a runtime counterpart")
	print("MAIN_CITY_BAKE_AUDIT checks=",checks," failures=",failures.size()," solids=",total)
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)
