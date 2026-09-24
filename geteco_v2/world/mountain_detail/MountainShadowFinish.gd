extends RefCounted

## Contato visual de construções da montanha. Sem luzes, colisão ou trabalho por quadro.

static var _texture: ImageTexture
static var _contact_materials: Dictionary = {}
static var _wall_material: StandardMaterial3D

static func attach(root: Node3D, footprint: Vector2, local_center: Vector3 = Vector3.ZERO) -> void:
	if footprint.x <= 0.0 or footprint.y <= 0.0: return
	var suffix := "_%d_%d" % [roundi(local_center.x * 16.0), roundi(local_center.z * 16.0)]
	_ground_layer(root, footprint + Vector2.ONE * 2.4, local_center, 0.068, false, suffix)
	_ground_layer(root, footprint + Vector2.ONE * 0.8, local_center, 0.070, true, suffix)
	var wall := MeshInstance3D.new()
	wall.name = "MountainWallContact" + suffix
	var quad := QuadMesh.new()
	quad.size = Vector2(footprint.x, 1.05)
	wall.mesh = quad
	wall.position = local_center + Vector3(0, 0.53, footprint.y * 0.5 + 0.018)
	wall.material_override = _wall_ao()
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wall)

static func _ground_layer(root: Node3D, size: Vector2, center: Vector3, height: float, tight: bool, suffix: String) -> void:
	var layer := MeshInstance3D.new()
	layer.name = ("MountainGroundContactTight" if tight else "MountainGroundContact") + suffix
	var quad := QuadMesh.new()
	quad.size = size
	layer.mesh = quad
	layer.rotation.x = -PI * 0.5
	layer.position = center + Vector3.UP * height
	layer.material_override = _contact(tight)
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(layer)

static func _contact(tight: bool) -> StandardMaterial3D:
	if _contact_materials.has(tight): return _contact_materials[tight]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = _soft_rect()
	material.albedo_color = Color(0.10, 0.13, 0.16, 0.32 if tight else 0.25)
	material.roughness = 1.0
	material.render_priority = -1
	_contact_materials[tight] = material
	return material

static func _soft_rect() -> ImageTexture:
	if _texture != null: return _texture
	var size := 64
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var u := absf((x + 0.5) / size * 2.0 - 1.0)
			var v := absf((y + 0.5) / size * 2.0 - 1.0)
			var alpha := 1.0 - smoothstep(0.55, 1.0, maxf(u, v))
			image.set_pixel(x, y, Color(1, 1, 1, alpha))
	_texture = ImageTexture.create_from_image(image)
	return _texture

static func _wall_ao() -> StandardMaterial3D:
	if _wall_material != null: return _wall_material
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.38, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.06), Color(0, 0, 0, 0.27)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.albedo_texture = texture
	material.albedo_color = Color(0.08, 0.11, 0.15)
	_wall_material = material
	return material
