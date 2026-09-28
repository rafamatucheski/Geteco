extends Node
## Exterior occlusion aid. Each officer owns a separate self-occlusion box.
const SHADER := preload("res://world/city_look/occluded_silhouette.gdshader")
const TINT := Color(0.22, 0.62, 1.0, 0.72)
const MAX_DISTANCE_SQUARED := 70.0 * 70.0
var _material: ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []
var _clock := 0.0

func _ready() -> void:
	process_priority = 101

func _process(delta: float) -> void:
	var officer := get_parent() as Node3D
	var gameplay = officer.get("controller")
	var active := not bool(officer.get("dead")) and officer.is_visible_in_tree()
	if not is_instance_valid(gameplay) or gameplay.get("state") == null:
		active = false
	elif not String(gameplay.state.place_id).is_empty():
		active = false
	var camera := officer.get_viewport().get_camera_3d()
	if camera == null or camera.global_position.distance_squared_to(officer.global_position) > MAX_DISTANCE_SQUARED:
		active = false
	if not active:
		_clear()
		_clock = 0.0
		if bool(officer.get("dead")): set_process(false)
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.set_shader_parameter("tint", TINT)
		_material.set_shader_parameter("minimum_occluder_height", 1.2)
	var inverse := officer.global_transform.affine_inverse()
	_material.set_shader_parameter("target_inverse", Projection(inverse))
	_clock -= delta
	if _clock > 0.0: return
	_clock = 0.25
	var bounds := AABB()
	var has_bounds := false
	var current: Array[GeometryInstance3D] = []
	for node in officer.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree() or geometry is Label3D or geometry is GPUParticles3D or geometry is CPUParticles3D: continue
		var part: AABB = (inverse * geometry.global_transform) * geometry.get_aabb()
		bounds = bounds.merge(part) if has_bounds else part
		has_bounds = true
		if geometry.material_overlay == null: geometry.material_overlay = _material
		if geometry.material_overlay == _material: current.append(geometry)
	for previous in _meshes:
		if is_instance_valid(previous) and previous not in current and previous.material_overlay == _material:
			previous.material_overlay = null
	_meshes = current
	bounds = bounds.grow(0.08)
	_material.set_shader_parameter("box_min", bounds.position)
	_material.set_shader_parameter("box_max", bounds.end)

func _clear() -> void:
	for geometry in _meshes:
		if is_instance_valid(geometry) and geometry.material_overlay == _material:
			geometry.material_overlay = null
	_meshes.clear()

func _exit_tree() -> void:
	_clear()
