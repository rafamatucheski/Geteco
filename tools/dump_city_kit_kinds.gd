extends SceneTree
## Medidas (AABB) e camadas de cada tipo procedural do kit da cidade, para remodelar no
## Blender no mesmo envelope. Uso: tools/run_godot_locked.sh --headless --path . --script res://tools/dump_city_kit_kinds.gd
const KIT := preload("res://world/city_look/CityPropKit.gd")
const FILL := preload("res://world/city_look/SidewalkFillKit.gd")
const KINDS := ["signal_pole", "stop_sign", "manhole", "drain", "hedge", "ac_unit", "vent", "antenna", "dish", "roof_hatch", "pipe_run", "billboard_frame",
	"window_ac", "flower_box", "fe_platform", "fe_stair", "fe_ladder", "drainpipe", "pigeons", "laundry", "posters", "beacon_mast", "satellite_row", "awning_small",
	"roof_garden", "roof_shed", "roof_chairs", "water_tank", "skylight", "solar_row", "cooling_tower"]

func _initialize() -> void:
	KIT.blender_props_enabled = false
	var out := {}
	for kind: String in KINDS + FILL.KINDS + ["street_tree", "street_tree_b", "pot_plant"]:
		var mesh := KIT.mesh(kind)
		var box := mesh.get_aabb()
		var tris := 0
		for s in mesh.get_surface_count(): tris += mesh.surface_get_array_len(s) / 3
		out[kind] = {"pos": [snappedf(box.position.x, .01), snappedf(box.position.y, .01), snappedf(box.position.z, .01)], "size": [snappedf(box.size.x, .01), snappedf(box.size.y, .01), snappedf(box.size.z, .01)], "layers": KIT.LAYERED.get(kind, []), "tris": tris}
		print(kind, " ", JSON.stringify(out[kind]))
	var file := FileAccess.open(ProjectSettings.globalize_path("res://evidence/blender-props/kit-kinds.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(out, "\t"))
	quit(0)
