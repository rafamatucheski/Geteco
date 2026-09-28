extends RefCounted
## Curated roof/body combinations. The body color is the persisted source of truth.
const MODELS := ["union_sedan","sedan_classic","metro_hatch"]
const PALETTES := ["e6e4dfff","92979cff","40464cff","171b20ff","354552ff","722e30ff"]
static func roof_color(body: Color) -> Color:
	# Only neutral paint gets a contrasting roof; colored cars remain single tone.
	var spread := maxf(body.r,maxf(body.g,body.b))-minf(body.r,minf(body.g,body.b))
	if spread > .085: return body
	if body.v < .16: return Color("dedcd5")
	if body.v > .30: return Color("171b20")
	return body

static func decorate(id: String, model: Node3D) -> void:
	if id not in MODELS: return
	for part: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
		if part.mesh == null or part.mesh.get_surface_count() != 1: continue
		var bounds: AABB = part.transform*part.get_aabb()
		if bounds.position.y < 1.3 or bounds.size.y > .12 or bounds.size.x < 1: continue
		if preload("res://runtime/VehicleSurfaceRoles.gd").key(part,0) != "paint": continue
		for key in part.get_meta_list():
			if str(key).ends_with("material_key"): part.set_meta(key,"roof_paint")
		part.set_meta("finish_material_key","roof_paint")
		var material := part.get_active_material(0).duplicate() as StandardMaterial3D
		material.resource_name = "roof_paint"
		part.material_override = material
