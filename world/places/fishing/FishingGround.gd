extends RefCounted
## O piso físico de bosque existente é dono de toda a transição grama/solo.
## As variantes de estrada e margem mantêm os pesos nativos fora da máscara do local.
const LOCATION := preload("res://runtime/FishingLocation.gd")
const RURAL := preload("res://world/urban_detail/RuralGroundMaterial.gd")
const LANDSCAPE := preload("res://activities/motocross/MotocrossGroundDetail.gd")
const GRAVEL := preload("res://assets/regions/source/world/harbor/UrbanGround.gd")
const ENTRANCE_AREA := Rect2(-523,-19,47,22)
static var _materials: Dictionary = {}

static func previous_finish() -> bool:
	return bool(Engine.get_meta("recreation_ground_before",false))

static func material(road_surface := false) -> Material:
	if previous_finish(): return RURAL.material() if road_surface else LANDSCAPE.ground_material()
	if _materials.has(road_surface): return _materials[road_surface]
	var result := ShaderMaterial.new()
	result.shader = preload("res://world/places/fishing/fishing_ground_road.gdshader") if road_surface else preload("res://world/places/fishing/fishing_ground.gdshader")
	var rural := RURAL.material()
	result.set_shader_parameter("grass_texture",rural.get_shader_parameter("grass_texture"))
	result.set_shader_parameter("earth_texture",rural.get_shader_parameter("earth_texture"))
	result.set_shader_parameter("gravel_texture",GRAVEL.texture("gravel"))
	result.set_shader_parameter("venue_origin",Vector2(LOCATION.ANCHOR.x,LOCATION.ANCHOR.z))
	result.set_shader_parameter("road_surface",road_surface)
	_materials[road_surface] = result
	return result

static func finish_entrance_roads(parent: Node3D,rect: Rect2) -> void:
	if previous_finish() or not ENTRANCE_AREA.intersects(rect): return
	# A geometria de estrada nativa já recortou e pôs estas malhas em lote. Só
	# o acabamento muda; fora da clareira o shader é a fórmula rural.
	for child in parent.get_children():
		if child is MeshInstance3D and child.name in ["HarborEarthRoad","EarthRoadVerge"]:
			child.material_override = material(true)
