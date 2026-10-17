extends RefCounted
## Authored apron replaces the old square grid. One shared compressed albedo.
static var _concrete: StandardMaterial3D

static func concrete() -> StandardMaterial3D:
	if _concrete != null: return _concrete
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_texture = preload("res://assets/materials/harbor_paving/port_apron.png")
	_concrete.albedo_color = Color("858b81")
	_concrete.uv1_triplanar = true
	_concrete.uv1_world_triplanar = true
	_concrete.uv1_scale = Vector3.ONE / 16.0
	_concrete.roughness = .96
	_concrete.metallic_specular = .10
	_concrete.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _concrete
