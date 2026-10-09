extends Area3D
## Environmental forces require physical capsule overlap. They are never Pull
## targets and never read input; the player integrates their bounded velocity.
enum Mode { FLOOR_BOOST, PRESSURE_UPDRAFT }
@export var mode: Mode = Mode.FLOOR_BOOST
@export var heading := Vector3.FORWARD
@export_range(0.0, 80.0, 1.0) var acceleration := 20.0
@export_range(0.0, 8.0, .5) var minimum_forward_speed := 1.0
@export_range(8.0, 32.0, 1.0) var maximum_forward_speed := 24.0
@export_range(0.0, 80.0, 1.0) var lift_acceleration := 20.0
@export_range(0.0, 24.0, .5) var maximum_upward_speed := 10.0
const Settings = preload("res://scenes/parkour/presentation_settings.gd")
var _occupants: Dictionary = {}
var _pressure_cue_entries: Dictionary = {}
var cue_clock := 0.0
var contact_steps := 0
var entry_cues := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	add_to_group("contact_traversal")
	body_entered.connect(_body_entered)
	body_exited.connect(_body_exited)
	$DirectionMarks.visible = $DirectionMarks.visible and mode == Mode.FLOOR_BOOST
	$Steam.visible = mode == Mode.PRESSURE_UPDRAFT
	$Steam.emitting = false
	var horizontal := Vector3(heading.x,0,heading.z)
	if not horizontal.is_zero_approx():
		$DirectionMarks.rotation.y = atan2(-horizontal.x,-horizontal.z)

func _active(body: Node3D) -> bool:
	return is_instance_valid(body) and body.is_in_group("player") and body.gameplay_active and not get_tree().paused and not body._is_debug_fly_active()

func has_live_contact(body: Node3D) -> bool:
	if not is_inside_tree() or not is_instance_valid(body) or not body.is_inside_tree():
		return false
	var shape: CollisionShape3D = $CollisionShape3D
	# The broadphase may still report the previous body pose on a teleport
	# tick. Check the current capsule transform before accepting its engine hit.
	if not _current_capsule_overlaps_box(body,shape):
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = 4
	query.collide_with_areas = false
	query.margin = 0.0
	for hit in get_world_3d().direct_space_state.intersect_shape(query,4):
		if hit.get("collider") == body:
			return true
	return false

func _current_capsule_overlaps_box(body: Node3D, volume: CollisionShape3D) -> bool:
	var collision: CollisionShape3D = body._body_collision
	var capsule := collision.shape as CapsuleShape3D
	var box := volume.shape as BoxShape3D
	if capsule == null or box == null or collision.disabled or volume.disabled:
		return false
	var relative := volume.global_transform.affine_inverse()*collision.global_transform
	var half_axis := maxf(0.0,capsule.height*.5-capsule.radius)
	var start: Vector3 = relative*Vector3(0,-half_axis,0)
	var end: Vector3 = relative*Vector3(0,half_axis,0)
	# Authored volumes and the player use unit scale; this also bounds a scaled
	# capsule before the authoritative engine overlap query below.
	var capsule_scale := relative.basis.get_scale()
	var radius := capsule.radius*maxf(capsule_scale.x,maxf(capsule_scale.y,capsule_scale.z))
	return _segment_box_distance_squared(start,end,box.size*.5)<=radius*radius

func _segment_box_distance_squared(start: Vector3, end: Vector3, half: Vector3) -> float:
	var motion := end-start
	var intervals: Array[float] = [0.0,1.0]
	for axis in range(3):
		if absf(motion[axis])<.000001:
			continue
		for boundary in [-half[axis],half[axis]]:
			var time: float = (boundary-start[axis])/motion[axis]
			if time>0.0 and time<1.0:
				intervals.append(time)
	intervals.sort()
	var distance := INF
	# Between box-plane crossings, squared distance is a quadratic. Its
	# clamped minimum gives the exact segment-to-box distance for the capsule.
	for index in range(intervals.size()-1):
		var midpoint := start+motion*((intervals[index]+intervals[index+1])*.5)
		var quadratic := 0.0
		var linear := 0.0
		for axis in range(3):
			if absf(midpoint[axis])>half[axis]:
				var boundary := clampf(midpoint[axis],-half[axis],half[axis])
				quadratic += motion[axis]*motion[axis]
				linear += motion[axis]*(start[axis]-boundary)
		var time := clampf(-linear/quadratic,intervals[index],intervals[index+1]) if quadratic>0.0 else intervals[index]
		var point := start+motion*time
		var closest := point.clamp(-half,half)
		distance = minf(distance,point.distance_squared_to(closest))
	return distance

func _body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("register_contact_traversal"):
		_occupants[body.get_instance_id()] = body
		body.register_contact_traversal(self)

func _body_exited(body: Node3D) -> void:
	_occupants.erase(body.get_instance_id())
	_pressure_cue_entries.erase(body.get_instance_id())
	if body.has_method("unregister_contact_traversal"):
		body.unregister_contact_traversal(self)

func _physics_process(_delta: float) -> void:
	# Refresh actual overlap after a reset inside a volume. No stored impulse or
	# old overlap can apply at a recovery destination outside the physical area.
	for body in get_overlapping_bodies():
		if body.is_in_group("player") and has_live_contact(body):
			_body_entered(body)

func reset_contact_state(body: Node3D = null) -> void:
	if body != null:
		_body_exited(body)
		return
	for occupant in _occupants.values():
		if is_instance_valid(occupant):
			_body_exited(occupant)
	_occupants.clear()
	_pressure_cue_entries.clear()

func _exit_tree() -> void:
	reset_contact_state()

func step_velocity(body: Node3D, incoming: Vector3, delta: float) -> Vector3:
	if delta <= 0.0 or not _active(body) or not has_live_contact(body):
		return incoming
	var limit: float = body.parkour_speed_limit
	if mode == Mode.PRESSURE_UPDRAFT:
		var vertical_budget := sqrt(maxf(0.0,limit*limit-Vector2(incoming.x,incoming.z).length_squared()))
		var ceiling := minf(maximum_upward_speed,vertical_budget)
		if incoming.y >= ceiling or lift_acceleration <= 0.0:
			return incoming
		contact_steps += 1
		if not _pressure_cue_entries.has(body.get_instance_id()):
			_pressure_cue_entries[body.get_instance_id()] = true
			entry_cues += 1
			get_node("/root/SoundManager").play_pressure_hiss()
		return Vector3(incoming.x,minf(incoming.y+lift_acceleration*delta,ceiling),incoming.z)
	var direction: Vector3 = global_basis*heading
	direction.y = 0.0
	if not body.is_on_floor() or direction.is_zero_approx():
		return incoming
	direction = direction.normalized()
	var forward := incoming.dot(direction)
	if forward < minimum_forward_speed:
		return incoming
	var retained := incoming-direction*forward
	var forward_budget := sqrt(maxf(0.0,limit*limit-retained.length_squared()))
	var ceiling := minf(maximum_forward_speed,forward_budget)
	if forward >= ceiling:
		return incoming
	contact_steps += 1
	return retained+direction*minf(forward+acceleration*delta,ceiling)

func _process(delta: float) -> void:
	if get_tree().paused:
		return
	# Ambient rising steam makes the volume readable before the race starts.
	# Its presentation is independent of the guarded physical force.
	$Steam.emitting = mode == Mode.PRESSURE_UPDRAFT and Settings.effects_strength > 0.0
	cue_clock += delta
	# Only the decorative panel pulses. Collision and force stay independent.
	$DirectionMarks.scale = Vector3.ONE*(1.0+sin(cue_clock*4.0)*.015*Settings.effects_strength)
