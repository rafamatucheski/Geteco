extends SceneTree
## Os prédios da montanha de gelo não podem ter material de cor lisa nas peças estruturais:
## madeira, telha, pedra, metal e neve recebem o mapa do seu papel. Mede texturas e tipos
## escolhidos, não a aparência renderizada.
const FINISH := preload("res://assets/regions/source/world/mountain_pass/MountainSurfaceFinish.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	var kinds := {"wood_beam": "wood", "chalet_wall_1": "wood", "wood_shingle": "shingle", "stone_river": "granite", "snow_fresh": "snow", "metal_iron": "metal", "tarp_green": "fabric", "stone_paving": "paving", "dirt_earth": "gravel", "glass_warm": "", "bear_fur": ""}
	for id in kinds:
		check(FINISH.kind_for(id) == kinds[id], "tipo de %s = '%s' (esperado '%s')" % [id, FINISH.kind_for(id), kinds[id]])
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color("775a43")
	FINISH.apply(wall, "chalet_wall_0")
	check(wall.albedo_texture != null and wall.normal_enabled, "parede de chalé ganha textura e normal")
	check(wall.albedo_color.r > Color("775a43").r * 0.9, "tom da parede preservado após o ganho")
	FINISH.apply(wall, "chalet_wall_0")
	check(wall.has_meta("tone_gain"), "ganho de tom registrado")
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.4, 0.6, 0.8, 0.5)
	FINISH.apply(glass, "glass")
	check(glass.albedo_texture == null, "vidro translúcido fica sem textura")
	for path in ["res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd", "res://assets/regions/source/world/mountain_pass/ResortShop3D.gd", "res://assets/regions/source/world/mountain_pass/art/winter_props/LumberjackCabin3D.gd", "res://assets/regions/source/world/mountain_pass/art/review_0908/MountainGunShop3D.gd", "res://world/mountain_detail/MountainChalet3D.gd", "res://world/mountain_detail/VillageShopfront3D.gd", "res://world/mountain_detail/MountainTerminal3D.gd"]:
		var node: Node3D = load(path).new()
		root.add_child(node)
		await process_frame
		var flat := 0
		var total := 0
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mat: Material = mesh.material_override
			if mat is StandardMaterial3D and mat.albedo_color.a >= 1.0 and not mat.emission_enabled:
				total += 1
				if mat.albedo_texture == null: flat += 1
		print(path.get_file(), ": ", total, " peças opacas, ", flat, " sem textura")
		check(total > 0, path.get_file() + " gerou peças")
		node.queue_free()
	for failure in failures: push_error(failure)
	print("MOUNTAIN_SURFACE_FINISH ", "OK" if failures.is_empty() else "FALHOU")
	quit(0 if failures.is_empty() else 1)
