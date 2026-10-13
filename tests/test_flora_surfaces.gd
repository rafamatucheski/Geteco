extends SceneTree
## Copas, troncos e cactos precisam ter textura de papel (folhagem, casca, costelas) e
## manter a cor do vértice. Mede mapas e tons dos materiais, não a aparência renderizada.
const FLORA := preload("res://assets/urban_detail/FloraSurfaces.gd")
const DRY := preload("res://world/desert/DesertDryFlora.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)

func _run() -> void:
	var crown := FLORA.foliage(Color("465d3f"))
	check(crown.albedo_texture != null and crown.normal_enabled and crown.vertex_color_use_as_albedo, "copa com textura, normal e cor de vértice")
	check(crown.albedo_color.g > Color("465d3f").g * 0.9, "tom da copa preservado após o ganho")
	check(FLORA.foliage(Color("465d3f")) == crown, "copa de mesma cor reaproveita o material")
	check(FLORA.bark().albedo_texture != null and FLORA.bark().vertex_color_is_srgb, "casca texturizada com vértice em sRGB")
	check(FLORA.cactus().albedo_texture != null and FLORA.cactus() != FLORA.bark(), "cacto tem mapa próprio")
	var root := Node3D.new()
	get_root().add_child(root)
	var made := 0
	for cx in 10:
		for cz in 6:
			made += DRY.build_chunk(root, Rect2(Vector2(-1140.0 + cx * 58.0, -1936.0 + cz * 61.3), Vector2(58, 61.3)), 7, func(_p): return 0.0)
	var plants := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if node.name.begins_with("DesertBreakableFlora"):
			plants += 1
			check((node.material_override as StandardMaterial3D) != null and (node.material_override as StandardMaterial3D).albedo_texture != null, "planta quebrável sem textura")
	print("flora do deserto: %d plantas, %d quebráveis" % [made, plants])
	check(plants > 0, "nenhuma planta quebrável gerada no deserto")
	root.queue_free()
	if failures.is_empty():
		print("test_flora_surfaces OK")
		quit(0)
	else:
		for f in failures: printerr("FALHA: ", f)
		quit(1)
