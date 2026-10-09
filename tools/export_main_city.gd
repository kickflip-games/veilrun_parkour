extends SceneTree
## Offline authoring with Cyclops' own volumes and scene exporter. Retain the
## editable Cyclops scene; the game only loads the ordinary exported sectors.
const Block = preload("res://addons/cyclops_level_builder/nodes/cyclops_block.gd")
const Volume = preload("res://addons/cyclops_level_builder/math/convex_volume.gd")
const Exporter = preload("res://addons/cyclops_level_builder/io/exporter/exporter_godot_scene_wizard.gd")
const Anchor = preload("res://scenes/parkour/grapple_anchor.tscn")
var materials: Dictionary = {}

func _initialize() -> void:
	call_deferred("generate")

func vector(value: Array) -> Vector3:
	return Vector3(value[0],value[1],value[2])

func material_named(label: String) -> Material:
	if materials.has(label):
		return materials[label]
	if label == "Slate":
		materials[label] = load("res://scenes/parkour/city_roof.tres")
	else:
		var material := StandardMaterial3D.new()
		material.roughness = 0.92
		var colors := {"Brick":Color(0.32,0.33,0.37),"Stone":Color(0.40,0.43,0.48),"Iron":Color(0.13,0.15,0.19),"Cobble":Color(0.28,0.31,0.36)}
		material.albedo_color = colors.get(label,Color(0.32,0.35,0.4))
		var textures := {"Brick":"wall_brick_small_stone.png","Stone":"wall_stone.png","Cobble":"floor_stone_pattern.png"}
		if textures.has(label):
			material.albedo_texture = load("res://assets/rooftop_city/textures/" + textures[label])
			material.uv1_triplanar = true
			material.uv1_world_triplanar = true
			material.uv1_scale = Vector3.ONE * 0.25
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		materials[label] = material
	return materials[label]

func own_recursive(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		own_recursive(child,scene_root)

func add_solids(scene: Node3D, sector: Dictionary) -> void:
	var solids := Node3D.new()
	solids.name = "Architecture"
	scene.add_child(solids)
	solids.owner = scene
	for spec in sector.solids:
		var volume = Volume.new()
		if spec.has("top"):
			var top: Array[Vector3] = []
			for point in spec.top:
				top.append(vector(point))
			volume.init_prism(top,Vector3.DOWN * spec.depth,Transform2D.IDENTITY,0)
		elif spec.has("base"):
			var base: Array[Vector3] = []
			for point in spec.base:
				base.append(vector(point))
			volume.init_prism(base,vector(spec.extrude),Transform2D.IDENTITY,0)
		else:
			var size := vector(spec.size)
			volume.init_block(AABB(-size/2,size),Transform2D.IDENTITY,0)
		var block = Block.new()
		block.name = spec.name
		block.materials.append(material_named(spec.material))
		block.mesh_vector_data = volume.to_mesh_vector_data()
		block.collision_layer = 1
		block.collision_mask = 4
		if spec.has("position"):
			block.position = vector(spec.position)
			block.rotation = vector(spec.rotation)
		block.add_to_group("city_" + spec.kind,true)
		solids.add_child(block)
		block.owner = scene

func add_interactions(scene: Node3D, sector: Dictionary) -> void:
	var fixtures := Node3D.new()
	fixtures.name = "ArchitecturalAnchors"
	scene.add_child(fixtures)
	fixtures.owner = scene
	for spec in sector.anchors:
		var anchor = Anchor.instantiate()
		anchor.name = spec.name
		anchor.position = vector(spec.position)
		anchor.show_label = false
		anchor.architectural_fixture = true
		anchor.set_meta("fixture_kind",spec.kind)
		fixtures.add_child(anchor)
		anchor.owner = scene
	for spec in sector.launchers:
		var launcher = load("res://scenes/parkour/spring_pad.tscn").instantiate()
		launcher.name = spec.name
		launcher.position = vector(spec.position)
		launcher.launch_direction = vector(spec.direction)
		launcher.launch_strength = spec.strength
		launcher.architectural_launcher = true
		# Keep the tested trigger/one-entry behavior, restyle all visuals as an
		# aged iron pressure ridge. White arrows/text never enter the runtime.
		for node_name in ["Arrow","Heading","Sign"]:
			launcher.get_node(node_name).hide()
		var deck := BoxMesh.new()
		deck.size = Vector3(3,0.12,3)
		deck.material = material_named("Iron")
		launcher.get_node("Deck").mesh = deck
		launcher.get_node("Rim").material_override = material_named("Stone")
		for marker_mesh in launcher.get_node("Heading").find_children("*","MeshInstance3D",true,false):
			marker_mesh.mesh = null
		launcher.scene_file_path = ""
		scene.add_child(launcher)
		launcher.owner = scene
		own_recursive(launcher,scene)
	for spec in sector.get("contact_traversals",[]):
		var contact = load("res://scenes/parkour/contact_traversal.tscn").instantiate()
		contact.name = spec.name
		contact.position = vector(spec.position)
		contact.rotation = vector(spec.rotation)
		for property in ["mode","acceleration","minimum_forward_speed","maximum_forward_speed","lift_acceleration","maximum_upward_speed"]:
			contact.set(property,spec[property])
		contact.heading = vector(spec.heading)
		var shape := BoxShape3D.new()
		shape.size = vector(spec.size)
		contact.get_node("CollisionShape3D").shape = shape
		contact.get_node("CollisionShape3D").position = vector(spec.shape_position)
		contact.get_node("Deck").hide()
		contact.get_node("DirectionMarks").hide()
		contact.get_node("Steam").position = Vector3(0,1.4,0)
		contact.scene_file_path = ""
		scene.add_child(contact)
		contact.owner = scene
		own_recursive(contact,scene)

func generate() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/main_city/route_manifest.json"))
	var exporter = Exporter.new()
	var authoring := Node3D.new()
	authoring.name = "MainCityCyclopsAuthoring"
	var count := 0
	var selected_sector := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sector="):
			selected_sector = argument.get_slice("=",1)
	for sector in manifest.sectors:
		var scene := Node3D.new()
		scene.name = sector.slug
		scene.set_meta("sector_name",sector.title)
		scene.set_meta("safe_route_length",sector.safe_length)
		var points := PackedVector3Array()
		for point in sector.safe_points:
			points.append(vector(point))
		scene.set_meta("safe_route_points",points)
		add_solids(scene,sector)
		count += sector.solids.size()
		# Snapshot only editable blocks. Scene exporters operate on a duplicate.
		var editable := Node3D.new()
		editable.name = sector.slug
		add_solids(editable,sector)
		authoring.add_child(editable)
		editable.owner = authoring
		own_recursive(editable,authoring)
		if not selected_sector.is_empty() and selected_sector != sector.slug:
			scene.free()
			continue
		exporter.replace_blocks_recursive(scene,scene)
		for spec in sector.solids:
			if spec.get("collision_only",false):
				# Exact authoring volumes are retained, while existing batched
				# roof art stays the sole visible surface in the runtime.
				scene.get_node("Architecture/" + spec.name + "/mesh_instance").hide()
		add_interactions(scene,sector)
		var dressing = load("res://levels/parkour/city/%s_dressing.tscn" % sector.slug).instantiate()
		dressing.name = "CityDressing"
		scene.add_child(dressing)
		dressing.owner = scene
		var packed := PackedScene.new()
		var result := packed.pack(scene)
		assert(result == OK)
		result = ResourceSaver.save(packed,"res://levels/parkour/city/%s.tscn" % sector.slug)
		assert(result == OK)
		print("CITY_SECTOR_EXPORTED ",sector.slug," blocks=",sector.solids.size()," anchors=",sector.anchors.size()," length=",sector.safe_length)
		scene.free()
		await process_frame
	var editable_scene := PackedScene.new()
	assert(editable_scene.pack(authoring) == OK)
	assert(ResourceSaver.save(editable_scene,"res://tools/city_authoring/MainCityCyclops.tscn") == OK)
	print("MAIN_CITY_CYCLOPS_EXPORTED blocks=",count," safe_length=",manifest.safe_length)
	authoring.free()
	exporter.free()
	for audio in root.get_node("SoundManager").get_children():
		if audio is AudioStreamPlayer:
			audio.stop()
			audio.stream = null
	await process_frame
	await process_frame
	quit()
