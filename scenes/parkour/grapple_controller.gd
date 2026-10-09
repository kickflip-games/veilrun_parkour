extends Node3D
## Anchor acquisition only. Camera effects never alter aim, reach or the lock window.

@export var hook_range: float = 20.0
@export_range(0.0, 30.0, 0.5) var lock_horizontal_degrees: float = 12.0
@export_range(0.0, 45.0, 0.5) var lock_vertical_degrees: float = 35.0
@export_range(0.0, 8.0, 0.25) var lock_retention_degrees: float = 2.0
@export_range(0.0, 2.0, 0.05) var movement_score_degrees := 0.75
@export_range(0.0, 1.0, 0.05) var trajectory_score_degrees := 0.5

@onready var raycast: RayCast3D = $RayCast3D
@onready var camera: Camera3D = get_parent().get_node("Camera3D")
var aim_assist_target: Node3D = null
var _lock_sound_cooldown := 0.0

func _process(delta: float) -> void:
	_lock_sound_cooldown = maxf(0.0, _lock_sound_cooldown - delta)
	var previous := aim_assist_target
	var target := _update_lock_target()
	_refresh_anchor_feedback(target)
	if target != previous and is_instance_valid(target) and get_parent().gameplay_active and _lock_sound_cooldown <= 0.0:
		SoundManager.play_pull_cue(SoundManager.SFX_ANCHOR_LOCK)
		_lock_sound_cooldown = 0.18

func _refresh_anchor_feedback(selected: Node3D) -> void:
	var body = get_parent()
	if get_world_3d() == null:
		return
	var origin: Vector3 = body.to_global(body._camera_base_pos)
	var space := get_world_3d().direct_space_state
	for candidate in get_tree().get_nodes_in_group("grapple_anchors"):
		var anchor := candidate as Node3D
		if not is_instance_valid(anchor) or not anchor.has_method("set_pull_feedback"):
			continue
		var point := _target_point(anchor)
		var available: bool = body.gameplay_active and can_hook_target(anchor) and origin.distance_to(point) <= hook_range and not camera.is_position_behind(point)
		if available:
			var query := PhysicsRayQueryParameters3D.create(origin, point, raycast.collision_mask, [body.get_rid()])
			query.collide_with_areas = raycast.collide_with_areas
			available = space.intersect_ray(query).get("collider") == anchor
		anchor.set_pull_feedback(available, anchor == selected, body.is_hooking and anchor == body._hook_target)

func _update_lock_target() -> Node3D:
	if not is_inside_tree() or get_world_3d() == null or not is_instance_valid(camera):
		aim_assist_target = null
	else:
		aim_assist_target = _find_lock_target(camera.global_position)
	return aim_assist_target

func can_hook_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or not target.is_in_group("grapple_anchors") or not target.has_method("is_grapple_available"):
		return false
	var body = get_parent()
	if not body.is_hooking:
		if body.global_position.distance_to(target.global_position) < 1.8:
			return false
		if target == body._recent_anchor and body._anchor_cooldown > 0.0:
			return false
	return target.is_grapple_available()

func request_hook() -> void:
	if not is_inside_tree() or get_world_3d() == null:
		return
	var body = get_parent()
	if not body.gameplay_active or get_tree().paused or body._is_debug_fly_active():
		return
	var target := _update_lock_target()
	if not body.is_hooking and can_hook_target(target):
		body.start_grapple(target)

func has_lock_target() -> bool:
	return get_lock_target() != null

func get_lock_target() -> Node3D:
	return _update_lock_target()

func _clear_pending() -> void:
	# Respawn/retry callers retain this reset API; grapples have no queued launch.
	aim_assist_target = null

func _target_point(anchor: Node3D) -> Vector3:
	var body_shape := anchor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return body_shape.global_position if body_shape else anchor.global_position

func _find_lock_target(origin: Vector3) -> Node3D:
	if not is_inside_tree() or get_world_3d() == null or not is_instance_valid(camera):
		return null
	var best_score := INF
	var best: Node3D = null
	var space_state := get_world_3d().direct_space_state
	var ray_length: float = raycast.target_position.length()
	var body = get_parent()
	var aim_basis: Basis = body.get_aim_basis() if body.has_method("get_aim_basis") else body.global_basis
	origin = body.to_global(body._camera_base_pos)
	var size := camera.get_viewport().get_visible_rect().size
	var aspect := size.x / maxf(size.y, 1.0)
	var vertical_tangent := tan(deg_to_rad(body._base_fov) * 0.5)
	var horizontal_tangent := vertical_tangent * aspect
	if camera.keep_aspect == Camera3D.KEEP_WIDTH:
		horizontal_tangent = vertical_tangent
		vertical_tangent /= aspect
	for candidate in get_tree().get_nodes_in_group("grapple_anchors"):
		var anchor := candidate as Node3D
		if not can_hook_target(anchor):
			continue
		var point := _target_point(anchor)
		var offset: Vector3 = point - origin
		var distance := offset.length()
		if distance > minf(ray_length, hook_range) or distance < 0.01:
			continue
		var local_dir: Vector3 = aim_basis.inverse() * (offset / distance)
		if local_dir.z >= 0.0:
			continue
		var horizontal_angle := absf(rad_to_deg(atan2(local_dir.x, -local_dir.z)))
		var vertical_angle := absf(rad_to_deg(atan2(local_dir.y, -local_dir.z)))
		if horizontal_angle > lock_horizontal_degrees or vertical_angle > lock_vertical_degrees:
			continue
		if absf(local_dir.x / local_dir.z) > horizontal_tangent or absf(local_dir.y / local_dir.z) > vertical_tangent:
			continue
		var query := PhysicsRayQueryParameters3D.create(origin, point)
		query.collision_mask = raycast.collision_mask
		query.collide_with_areas = raycast.collide_with_areas
		query.collide_with_bodies = raycast.collide_with_bodies
		query.exclude = [self, body]
		if space_state.intersect_ray(query).get("collider") != anchor:
			continue
		# Vertical aiming uses angular distance to the crosshair in both axes.
		# Keep the older yaw-only courses' acquisition ordering for comparison.
		var aim_angle := rad_to_deg(acos(clampf(-local_dir.z, -1.0, 1.0))) if body.vertical_look_enabled else horizontal_angle + vertical_angle * 0.01
		var score := aim_angle + distance * 0.001
		if body.use_momentum_pull:
			# These small angular-equivalent penalties break near-aim ties only.
			# The accepted cone/frustum/LOS stays exact and camera aim dominates.
			var horizontal_motion := Vector3(body.velocity.x, 0.0, body.velocity.z)
			var horizontal_target := Vector3(offset.x, 0.0, offset.z)
			if horizontal_motion.length() > 1.0 and not horizontal_target.is_zero_approx():
				var alignment := clampf(horizontal_motion.normalized().dot(horizontal_target.normalized()), -1.0, 1.0)
				score += movement_score_degrees * (1.0 - alignment) * 0.5
				var closest_time := offset.dot(body.velocity) / maxf(body.velocity.length_squared(), 0.01)
				score += trajectory_score_degrees * (1.0 - clampf(closest_time / 0.5, 0.0, 1.0))
		if anchor == aim_assist_target:
			score -= lock_retention_degrees
		if score < best_score:
			best_score = score
			best = anchor
	return best
