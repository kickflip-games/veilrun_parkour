extends StaticBody3D
## A reusable architectural fixture. Its collision/aim point never follows its pulse.
@export var targetable := true
@export var show_label := true
@export var architectural_fixture := false
@export var dormant_color := Color(0.24, 0.25, 0.26)
@export var available_color := Color(0.68, 0.68, 0.63)
@export var targeted_color := Color(0.35, 0.86, 0.92)
var feedback_state := 0 # 0 dormant, 1 available, 2 selected, 3 actively pulling.
var _pulse: Tween
var _ring_material: StandardMaterial3D
var _core_material: StandardMaterial3D

func is_grapple_available() -> bool:
    return targetable

func _ready() -> void:
    $Diamond.visible = targetable
    $HookSign.visible = targetable and show_label
    $Diamond/Core.visible = not architectural_fixture
    $Diamond/RingSide.visible = not architectural_fixture
    _ring_material = StandardMaterial3D.new()
    _ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX if architectural_fixture else BaseMaterial3D.SHADING_MODE_UNSHADED
    _ring_material.metallic = 0.45 if architectural_fixture else 0.0
    _ring_material.roughness = 0.86 if architectural_fixture else 1.0
    _core_material = _ring_material.duplicate()
    for mesh in $Diamond.find_children("*", "MeshInstance3D", true, false):
        mesh.material_override = _core_material if mesh.name == "Core" else _ring_material
        if architectural_fixture:
            # Fixtures are acquired within 30 m. Distant rings need neither
            # individual draws through the mist nor small dynamic shadows.
            mesh.visibility_range_end = 110.0
            mesh.visibility_range_end_margin = 8.0
            mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _apply_feedback()

func set_pull_feedback(in_range: bool, selected: bool, pulling: bool) -> void:
    var next := 0 if not targetable else (3 if pulling else (2 if selected else (1 if in_range else 0)))
    if feedback_state == next:
        return
    feedback_state = next
    _apply_feedback()

func _apply_feedback() -> void:
    if not is_instance_valid(_ring_material):
        return
    var tint := dormant_color if feedback_state == 0 else (available_color if feedback_state == 1 else targeted_color)
    if architectural_fixture:
        tint = Color("2f3945") if feedback_state == 0 else (Color("87929e") if feedback_state == 1 else targeted_color)
        _ring_material.emission_enabled = feedback_state >= 1
        _ring_material.emission = tint
        _ring_material.emission_energy_multiplier = 0.12 if feedback_state >= 2 else (0.035 if feedback_state == 1 else 0.0)
    _ring_material.albedo_color = tint
    _core_material.albedo_color = tint * (0.85 if feedback_state == 0 else 1.0)
    _core_material.emission_enabled = not architectural_fixture and feedback_state >= 2
    _core_material.emission = targeted_color
    _core_material.emission_energy_multiplier = 0.35 if feedback_state >= 2 else 0.0

func on_grapple_arrival() -> void:
    if _pulse and _pulse.is_valid():
        _pulse.kill()
    $Diamond.scale = Vector3.ONE * (1.06 if architectural_fixture else 1.15)
    _pulse = create_tween()
    _pulse.tween_property($Diamond, "scale", Vector3.ONE, 0.18)
