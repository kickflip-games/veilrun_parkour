extends Area3D
## Invisible sector boundary. Respawn supplies position and facing; velocity is
## authored in world metres/second to recreate a useful practice entry.
@export var checkpoint_id := ""
@export var sector_name := ""
@export_range(1, 32, 1) var order_index := 1
@export var initial_velocity := Vector3.ZERO

func practice_transform() -> Transform3D:
	return $Respawn.global_transform

func practice_velocity() -> Vector3:
	return initial_velocity if initial_velocity.is_finite() else Vector3.ZERO
