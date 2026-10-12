extends SceneTree

## Gera todos os tipos de superfície urbana e confere que carregam sem erro; mede o custo
## de geração (a primeira chamada de cada tipo paga a textura, as seguintes são cache).

const SURF := preload("res://assets/urban_detail/UrbanSurfaces.gd")
const URBAN := preload("res://assets/urban_detail/UrbanMaterials.gd")
const ROUTE := preload("res://assets/harbor_route_detail/HarborRouteMaterials.gd")
const KINDS := ["brick", "paving", "granite", "concrete", "plaster", "tar", "gravel", "corrugated", "shingle", "wood", "metal", "fabric", "foliage"]

func _init() -> void:
	var failed := 0
	for kind in KINDS:
		var started := Time.get_ticks_usec()
		var mat: StandardMaterial3D = SURF.material("test_" + kind, kind, Color("808080"))
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		var ok: bool = mat.albedo_texture != null and mat.normal_texture != null and mat.albedo_color.get_luminance() > 0.05
		if not ok: failed += 1
		print("%s %s %.0f ms (albedo=%s)" % ["OK  " if ok else "FALHA", kind, ms, mat.albedo_color.to_html(false)])
	for name in ["brick_red", "wall_cream", "roof_tin", "roof_shingle", "wood_door_green", "awning_teal", "metal_steel", "sidewalk_stone"]:
		if (URBAN.new() as Object).call(name) == null: failed += 1
	var wall := URBAN.textured_wall(Color("7a463b"))
	if wall.normal_texture == null: failed += 1
	if ROUTE.sidewalk_concrete() == null or ROUTE.shrub_foliage() == null: failed += 1
	print("falhas: %d" % failed)
	quit(1 if failed else 0)
