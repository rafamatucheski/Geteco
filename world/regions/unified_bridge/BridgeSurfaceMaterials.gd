extends RefCounted
## Dedicated bridge finishes. Shared, offline maps; no runtime image generation.
const PAVING := preload("res://world/urban_detail/HarborPaving.gd")
const ALBEDO := preload("res://assets/materials/bridge/concrete_albedo.png")
const NORMAL := preload("res://assets/materials/bridge/concrete_normal.png")
const ROUGHNESS := preload("res://assets/materials/bridge/concrete_roughness.png")
const METAL := preload("res://assets/roadside/surfaces/metal.jpg")
const METAL_NORMAL := preload("res://assets/roadside/surfaces/metal_normal.png")
const LITTER := preload("res://assets/materials/bridge/sidewalk_litter.png")
static var enabled := OS.get_environment("GETECO_BRIDGE_SURFACES") != "0"
static var _concrete: StandardMaterial3D
static var _steel: StandardMaterial3D
static var _covered: StandardMaterial3D
static var _sidewalk: StandardMaterial3D

static func concrete() -> StandardMaterial3D:
	if not enabled: return PAVING.material()
	if _concrete != null: return _concrete
	# Keep the city pavement material untouched. This cache belongs to the
	# bridge, including its tunnel lining and northern campaign structure.
	_concrete = PAVING.material().duplicate() as StandardMaterial3D
	_concrete.albedo_texture = ALBEDO
	_concrete.albedo_color = Color("87918b")
	_concrete.normal_enabled = true
	_concrete.normal_texture = NORMAL
	_concrete.normal_scale = .65
	_concrete.roughness_texture = ROUGHNESS
	_concrete.roughness = 1.0
	_concrete.metallic_specular = .18
	_concrete.uv1_scale = Vector3.ONE / 5.0
	return _concrete

static func steel() -> StandardMaterial3D:
	if _steel != null: return _steel
	_steel = StandardMaterial3D.new()
	if not enabled:
		_steel.albedo_color = Color("53676c")
		_steel.roughness = .7
		_steel.metallic = .32
		return _steel
	_steel.albedo_color = Color("66716c")
	_steel.albedo_texture = METAL
	_steel.normal_enabled = true
	_steel.normal_texture = METAL_NORMAL
	_steel.normal_scale = .22
	_steel.metallic = .55
	_steel.roughness = .74
	_steel.uv1_triplanar = true
	_steel.uv1_world_triplanar = true
	_steel.uv1_scale = Vector3.ONE * .5
	_steel.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return _steel

static func set_wetness(value: float) -> void:
	if not enabled: return
	var rain := clampf(value,0.0,1.0)
	var finish := concrete()
	finish.albedo_color = Color("87918b").lerp(Color("66736c"),rain)
	finish.roughness = lerpf(1.0,.72,rain)
	if _sidewalk != null:
		_sidewalk.albedo_color = finish.albedo_color
		_sidewalk.roughness = finish.roughness

static func sidewalk() -> StandardMaterial3D:
	if not enabled: return PAVING.material()
	if _sidewalk != null: return _sidewalk
	_sidewalk = concrete().duplicate() as StandardMaterial3D
	_sidewalk.albedo_texture = LITTER
	# Larger irregular tile: sheets stay life-sized and the litter pattern
	# repeats less often than the plain mineral detail on the structure.
	_sidewalk.uv1_scale = Vector3.ONE / 8.0
	_sidewalk.normal_scale = .45
	return _sidewalk

static func covered_concrete() -> StandardMaterial3D:
	if not enabled: return PAVING.material()
	if _covered != null: return _covered
	_covered = concrete().duplicate() as StandardMaterial3D
	_covered.albedo_color = Color("87918b")
	_covered.roughness = 1.0
	return _covered
