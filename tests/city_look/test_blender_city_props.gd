extends SceneTree
## Adereços da cidade vindos do Blender (assets/city_props/*.glb, feitos por
## tools/blender/build_city_*.py). Confere que cada um entra no kit como a versão
## procedural: mesmo envelope (colisão, encaixe e destroço continuam valendo), origem no
## chão, mesmo material e mesmo formato de vértice (sem shader novo), camadas na ordem do
## LAYERED, a lente do poste no mesmo lugar (a mancha de luz sai das constantes) e o
## interruptor GETECO_BLENDER_PROPS=0 devolvendo as antigas.
## Não mede desempenho nem aparência: para isso, export release e
## tools/capture_city_trash_can.gd.
const KIT := preload("res://world/city_look/CityPropKit.gd")
const DRESSING := preload("res://world/city_look/CityChunkDressing.gd")
const FORMAT_MASK := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_COLOR | Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
## Triângulos por peça: o kit é desenhado em MultiMesh com alcance de 44 m, então dezenas
## de cópias na tela ainda somam pouco; o teto só segura exagero.
const MAX_TRIANGLES := 3000
var failures: Array[String] = []

func _initialize() -> void:
	check(KIT.blender_props_enabled, "interruptor ligado por padrão")
	# "vent" segue procedural: é a referência de formato do kit.
	var reference_format := KIT.mesh("vent").surface_get_format(0) & FORMAT_MASK
	var modeled := {}
	var all_kinds: Array = KIT.BLENDER_WHOLE.keys() + KIT.WAVE3_KINDS.keys()
	for kind: String in all_kinds:
		var mesh := KIT.mesh(kind)
		modeled[kind] = mesh
		var layers: Array = KIT.LAYERED.get(kind, [])
		check(mesh.get_surface_count() == maxi(1, layers.size()), "%s: %d superfície(s)" % [kind, mesh.get_surface_count()])
		for index in mesh.get_surface_count():
			var expected := KIT.layer_material(layers[index]) if not layers.is_empty() else KIT.material()
			check(mesh.surface_get_material(index) == expected, "%s: material do kit na superfície %d" % [kind, index])
			check(mesh.surface_get_format(index) & FORMAT_MASK == reference_format, "%s: formato de vértice do kit (%d x %d)" % [kind, mesh.surface_get_format(index) & FORMAT_MASK, reference_format])
		check(_triangles(mesh) < MAX_TRIANGLES, "%s: %d triângulos" % [kind, _triangles(mesh)])
	# A lixeira e seus destroços.
	check(_close(_first_color(modeled.trash_can, Color("2f5a43")), Color("2f5a43")), "trash_can: cor gravada crua (sRGB)")
	check(_max_z_of_color(modeled.trash_can, Color("c9c4ab")) > .25, "trash_can: plaquinha na frente (+Z)")
	check(absf(KIT.blender_mesh("trash_can", "TrashCanLid").get_aabb().get_center().y) < .03, "trash_can: tampa solta com origem no centro")
	check(KIT.blender_mesh("trash_can", "TrashCanBody").get_aabb().end.y < .92, "trash_can: corpo solto sem a tampa")
	# Frente para +Z: janela da banca, fenda da caixa de correio, saída grande do hidrante.
	check(_max_z_of_color(modeled.news_box, Color("dfe7e8")) > .2, "news_box: janelas na frente (+Z)")
	check(_max_z_of_color(modeled.mailbox, Color("0f152b")) > .2, "mailbox: fenda na frente (+Z)")
	check(_max_z_of_color(modeled.hydrant, Color("d8c24a")) > .19, "hydrant: bocal grande na frente (+Z)")
	# Camadas: pedra primeiro, folhas depois.
	check(_has_color(modeled.planter, 0, Color("5f625d")) and _has_color(modeled.planter, 1, Color("37443b")), "planter: pedra na superfície 0, folhas na 1")
	var blender_lamp := {"pole": DRESSING._lamp_mesh("pole"), "head": DRESSING._lamp_mesh("head")}
	for part in blender_lamp:
		var mesh: ArrayMesh = blender_lamp[part]
		check(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR == 0, "poste/%s: sem cor de vértice (material liso)" % part)
		check(mesh.surface_get_material(0) == null, "poste/%s: sem material próprio" % part)
	# Agora as procedurais, para comparar envelope.
	KIT.blender_props_enabled = false
	for kind: String in all_kinds: KIT._meshes.erase(kind)
	DRESSING._lamp_meshes.clear()
	for kind: String in all_kinds:
		var old := KIT.mesh(kind)
		check(old != modeled[kind], "%s: interruptor 0 volta à procedural" % kind)
		var a: AABB = modeled[kind].get_aabb()
		var b := old.get_aabb()
		# Peças de fachada ficam presas na parede, acima ou abaixo do ponto de encaixe:
		# o que vale é a mesma base da procedural, não o chão.
		check(absf(a.position.y - b.position.y) < .05, "%s: mesma base da procedural (y mín %.3f x %.3f)" % [kind, a.position.y, b.position.y])
		check(_near(a.size.x, b.size.x, .15) and _near(a.size.z, b.size.z, .2), "%s: pegada %.2f x %.2f (antes %.2f x %.2f)" % [kind, a.size.x, a.size.z, b.size.x, b.size.z])
		check(_near(a.size.y, b.size.y, .35), "%s: altura %.2f (antes %.2f)" % [kind, a.size.y, b.size.y])
	var head_shift: float = blender_lamp.head.get_aabb().get_center().distance_to(DRESSING._lamp_mesh("head").get_aabb().get_center())
	check(head_shift < .1, "poste: lente no mesmo lugar (desvio %.3f m)" % head_shift)
	check(_near(blender_lamp.pole.get_aabb().end.y, DRESSING._lamp_mesh("pole").get_aabb().end.y, .05), "poste: mesma altura")
	for failure in failures: print("FALHOU: ", failure)
	print("test_blender_city_props: ", "OK" if failures.is_empty() else "%d falha(s)" % failures.size())
	quit(0 if failures.is_empty() else 1)

func _triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for index in mesh.get_surface_count():
		var count := mesh.surface_get_array_index_len(index)
		total += (count if count > 0 else mesh.surface_get_array_len(index)) / 3
	return total

func _colors(mesh: ArrayMesh, surface: int) -> Array:
	var arrays := mesh.surface_get_arrays(surface)
	return [arrays[Mesh.ARRAY_COLOR], arrays[Mesh.ARRAY_VERTEX]]

func _has_color(mesh: ArrayMesh, surface: int, color: Color) -> bool:
	for item in _colors(mesh, surface)[0]:
		if _close(item, color): return true
	return false

func _first_color(mesh: ArrayMesh, color: Color) -> Color:
	for item in _colors(mesh, 0)[0]:
		if _close(item, color): return item
	return Color.BLACK

func _max_z_of_color(mesh: ArrayMesh, color: Color) -> float:
	var data := _colors(mesh, 0)
	var result := -INF
	for i in (data[0] as PackedColorArray).size():
		if _close(data[0][i], color): result = maxf(result, data[1][i].z)
	return result

func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < .01 and absf(a.g - b.g) < .01 and absf(a.b - b.b) < .01

func _near(a: float, b: float, tolerance: float) -> bool:
	return absf(a - b) <= maxf(b, .05) * tolerance

func check(ok: bool, label: String) -> void:
	if not ok: failures.append(label)
	else: print("ok: ", label)
