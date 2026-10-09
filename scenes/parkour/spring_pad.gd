extends Area3D
## One impulse per entry. Enter from above, descending or walking forward.
## The launch replaces forward/up velocity; incoming horizontal velocity
## perpendicular to the horizontal launch heading is retained by lateral_retention.
@export var launch_direction := Vector3(0, 0.9, -1)
@export_range(1.0, 32.0, 0.5) var launch_strength := 20.0
@export_range(0.0, 1.0, 0.05) var lateral_retention := 0.65
@export var speed_limit := 32.0
@export var architectural_launcher := false
var activations := 0
var _occupants: Dictionary = {}
var _pulse: Tween

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Arrow points in the actual configured local launch direction.
	var direction := launch_direction.normalized()
	if direction.is_zero_approx():
		direction = Vector3.UP
	$Arrow.quaternion = Quaternion(Vector3.UP, direction)
	$Heading.visible = not architectural_launcher and Vector2(direction.x, direction.z).length() > 0.01
	$Heading.rotation.y = atan2(-direction.x, -direction.z)
	if architectural_launcher:
		$Arrow.hide()
		$Sign.hide()
		_build_architectural_direction(direction)

func _build_architectural_direction(direction: Vector3) -> void:
	# Flush metal chevrons show the horizontal launch direction without a
	# floating marker. They have no collision and stay inside the existing deck.
	if Vector2(direction.x,direction.z).length() <= .01:
		return
	var inlay := Node3D.new()
	inlay.name = "ArchitectureDirection"
	inlay.position.y = .085
	inlay.rotation.y = atan2(-direction.x,-direction.z)
	add_child(inlay)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.48,.29,.10)
	material.roughness = .85
	material.metallic = .2
	var strip := BoxMesh.new()
	strip.size = Vector3(.14,.025,.8)
	strip.material = material
	for offset in [-.55,.55]:
		for side in [-1,1]:
			var mark := MeshInstance3D.new()
			mark.mesh = strip
			mark.position = Vector3(side*.23,0,offset)
			mark.rotation.y = side*PI/4.0
			inlay.add_child(mark)

func launch_velocity(incoming: Vector3) -> Vector3:
	var direction := (global_basis * launch_direction).normalized()
	if direction.is_zero_approx():
		direction = Vector3.UP
	var heading := Vector3(direction.x, 0, direction.z).normalized()
	var lateral := Vector3(incoming.x, 0, incoming.z)
	if not heading.is_zero_approx():
		lateral -= heading * lateral.dot(heading)
	return (direction * launch_strength + lateral * lateral_retention).limit_length(speed_limit)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player") or _occupants.has(body.get_instance_id()):
		return
	_occupants[body.get_instance_id()] = true
	if not body.gameplay_active or body.global_position.y < global_position.y + 0.2 or body.velocity.y > 1.0:
		return
	var direction := (global_basis * launch_direction).normalized()
	var heading := Vector3(direction.x, 0, direction.z).normalized()
	if body.is_on_floor() and not heading.is_zero_approx() and body.velocity.dot(heading) < 1.0:
		return
	body.apply_spring_launch(launch_velocity(body.velocity))
	activations += 1
	SoundManager.play_sfx(SoundManager.SFX_SPRING)
	if _pulse and _pulse.is_valid():
		_pulse.kill()
	$Deck.scale = Vector3(1.1, 1, 1.1)
	_pulse = create_tween()
	_pulse.tween_property($Deck, "scale", Vector3.ONE, 0.2)

func _on_body_exited(body: Node3D) -> void:
	_occupants.erase(body.get_instance_id())
