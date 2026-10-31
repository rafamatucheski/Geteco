extends Node
## Corte visual local só pela torre/escada/galeria. Uma instância só de sombra com a malha
## compartilhada preserva cada sombra sólida original e nenhuma colisão muda.
const SHADER := preload("res://world/places/coastal_lookout/LighthouseSightline.gdshader")
const LAYOUT := preload("res://world/places/coastal_lookout/LighthouseGeometry.gd")
var _player: CharacterBody3D
var _materials: Array[ShaderMaterial] = []
var _captured: Array[Dictionary] = []
var _active := false
var _idle_clock := 0.0

func configure(player: CharacterBody3D) -> void:
	_player = player
	if _captured.is_empty() and is_instance_valid(player): _capture()
	_set_enabled(false)
	_idle_clock = .20
	set_process(is_instance_valid(player))

func _capture() -> void:
	for child: Node in get_parent().get_children():
		if not child is MeshInstance3D or not str(child.name).begins_with("Lighthouse_"): continue
		if child.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF: continue
		var original := child.material_override as StandardMaterial3D
		if original == null or original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("albedo",original.albedo_color)
		material.set_shader_parameter("textured",original.albedo_texture!=null)
		if original.albedo_texture!=null: material.set_shader_parameter("albedo_texture",original.albedo_texture)
		material.set_shader_parameter("texture_scale",original.uv1_scale.x)
		material.set_shader_parameter("roughness_value",original.roughness)
		material.set_shader_parameter("metallic_value",original.metallic)
		material.set_shader_parameter("specular_value",original.metallic_specular)
		material.set_shader_parameter("emission_color",original.emission if original.emission_enabled else Color.BLACK)
		material.set_shader_parameter("emission_energy",original.emission_energy_multiplier if original.emission_enabled else 0.0)
		var shadow := MeshInstance3D.new()
		shadow.name = "TowerShadow_"+str(child.name)
		shadow.mesh = child.mesh
		shadow.transform = child.transform
		shadow.material_override = original
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		get_parent().add_child(shadow)
		_captured.append({"node":child,"material":original,"cast":child.cast_shadow,"shadow":shadow})
		child.material_override = material
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_materials.append(material)

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		_set_enabled(false)
		set_process(false)
		return
	# Idle distance checks are bounded; close walking updates every rendered
	# frame so a camera orbit or movement cannot expose a stale occluding wall.
	if not _active:
		_idle_clock += delta
		if _idle_clock<.20: return
		_idle_clock = 0.0
	var at := _player.global_position
	var camera := get_viewport().get_camera_3d()
	var near := Vector2(at.x-LAYOUT.BASE_CENTER.x,at.z-LAYOUT.BASE_CENTER.z).length()<8.0
	var walking: bool = not bool(_player.get("input_locked"))
	var enabled := near and at.y>LAYOUT.BASE_CENTER.y-.4 and at.y<LAYOUT.GALLERY_Y+2.0 and walking and is_instance_valid(camera) and camera.projection==Camera3D.PROJECTION_ORTHOGONAL
	_set_enabled(enabled)
	if not enabled: return
	for material in _materials:
		material.set_shader_parameter("player_foot",at)
		material.set_shader_parameter("camera_origin",camera.global_position)
		material.set_shader_parameter("camera_direction",camera.global_basis.z)

func _set_enabled(value: bool) -> void:
	if _active==value: return
	_active = value
	for material in _materials: material.set_shader_parameter("cut_enabled",value)

func _exit_tree() -> void:
	# Supports independent helper removal as well as normal whole-site unload.
	for record: Dictionary in _captured:
		if is_instance_valid(record.node) and not record.node.is_queued_for_deletion():
			record.node.material_override = record.material
			record.node.cast_shadow = record.cast
		if is_instance_valid(record.shadow): record.shadow.queue_free()
	_captured.clear()
	_materials.clear()
