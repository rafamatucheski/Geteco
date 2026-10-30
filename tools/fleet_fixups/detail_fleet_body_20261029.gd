extends SceneTree
## Detalhe de lataria da frota redesenhada (29/10, pedido do jogador: "os carros precisam ter mais
## detalhes na lataria"). Assado uma vez, offline; nada roda no jogo.
##
## Regra central: cada detalhe entra NA MESMA SUPERFÍCIE da peça em que encosta (achada por raio
## contra os triângulos reais). Por isso:
## - nenhum material nem superfície nova: +0 draw, mesmo formato de vértice (o pré-aquecimento de
##   FormatPrewarm/VehicleMaterialVariantPrewarm continua cobrindo tudo; o script confere o formato);
## - detalhe na lataria pintada usa o material da pintura: repinta, suja, molha e quebra junto, e o
##   VehicleBodyDents o amassa com a mesma função de deslocamento da chapa (só superfícies "paint"
##   amassam; acabamento escuro/cromado solto na porta ficaria flutuando na frente do amassado);
## - detalhe escuro/cromado só vai sobre acabamento que já não amassa (grade, para-choque cromado):
##   fica parado junto com a base, como antes;
## - toda face do detalhe na lateral fica inclinada no máximo 45° da chapa (|normal.x| >= .58):
##   o VehicleDoorBuilder só leva para a folha faces voltadas para o lado, e uma face de topo de
##   maçaneta em caixa ficaria no casco, solta no ar com a porta aberta.
## Onde a pintura não usa cor de vértice (família de passeio), o detalhe é relevo na cor do carro;
## nas famílias com cor de vértice na pintura (utilitários, esportivos, civis novos) a cor de
## vértice escurece o friso/contorno, sem material novo.
##
## Uso (sempre pela fila: tools/run_godot_locked.sh --headless --path . --script <este> -- ...):
##   --inventory [--src=DIR] [--ids=a,b]          inventário em artifacts/fleet-body-20261029/inventory.json
##   --apply --src=DIR --dst=DIR [--ids=a,b]      grava os modelos detalhados em DIR de destino
##   --capture --src=DIR --label=L --ids=a,b      fotos de vitrine (precisa de janela, sem --headless)
## Padrão de --apply: cópias em artifacts/fleet-body-20261029/before -> after. Para aplicar nos
## reais: --src=res://assets/fleet/redesigned --dst=res://assets/fleet/redesigned (idempotente:
## modelo com a meta VERSION_META é pulado).

const OUT := "res://artifacts/fleet-body-20261029"
const SRC := "res://assets/fleet/redesigned"
const VERSION_META := "fleet_body_detail_20261029"
const MESH_KIT := preload("res://tools/fleet_fixups/FleetBatchMesh.gd")
const DOORS := preload("res://data/catalogs/VehicleDoorSpecs.gd")
const FLEET := preload("res://runtime/FleetCatalog.gd")
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const CELL := .08
## Base do detalhe fica 2 mm dentro da chapa: sem fresta visível na borda, sem z-fighting.
const SINK := .002
## Teto de triângulos acrescentados por carro (pedido: ~15%).
const BUDGET := .15

## Motos não têm lataria; o carro-forte tem montagem própria (ArmoredTruckModel).
const SKIP := ["bike_cruiser", "bike_sport", "bike_urban", "armored_truck"]
## Sem detalhe na lateral: adesivo de corrida a 6 mm da chapa (DesertCarLivery), faixas do táxi e da
## polícia, e as laterais/santantônio do jipe da trilha (desert_jeep_4x4), que outro agente está
## consertando nos .scn reais.
const NO_SIDE := ["desert_jeep_4x4", "desert_faisca_rally", "desert_coyote_drag", "desert_mirage_gt",
	"taxi_yellow", "police_cruiser", "police_suv", "police_transport", "beach_buggy", "dune_buggy"]
## Caçamba: nada na traseira (a tampa de uma picape está sendo consertada por outro agente).
const NO_REAR := ["atlas_crew_pickup", "bravio_crew", "lumber_pickup_4x4", "ranch_pickup", "ranch_single",
	"sertao_trail_pickup", "digo_amarok_2014", "toco_minitruck", "arctic_jeep", "desert_jeep_4x4",
	"cargo_flatbed_truck", "american_dump_truck", "american_tanker_truck", "towmaster", "snow_plow_truck"]
## Caminhões e serviço pesado: só o emblema (o resto já é cheio de peça).
const HEAVY := ["american_dump_truck", "american_tanker_truck", "cargo_flatbed_truck", "boxrunner",
	"towmaster", "rescue_pumper", "snow_plow_truck", "medic_box"]
const CHROME := Color(.80, .82, .85)
const RUBBER := Color(.045, .05, .055)

class Acc:
	var pos: Array = []
	var nrm: Array = []
	var col: Array = []
	var uv: Array = []

var model: Node3D
var model_id := ""
var parts: Array = []
var tri_pos := PackedVector3Array()
var tri_ref := PackedInt32Array()
var grids: Array = [{}, {}, {}]
## Acumuladores do detalhe em construção ("part:surface" -> Acc) e os já aceitos.
var pending: Dictionary = {}
var accepted: Dictionary = {}
var log_rows: Array = []
## Assinaturas de shader (mesma regra de VehicleMaterialVariantPrewarm.shader_signature) das pinturas
## da frota que já usam cor de vértice: só elas podem ser adotadas pela pintura de passeio.
var paint_signatures: Dictionary = {}
var flipped_paint: Array = []
## Pontos de apoio (acerto na chapa) de cada detalhe, para a simulação de amassado do relatório.
var pending_anchors: Array = []
var anchors: Array = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var src := OUT + "/before"
	var dst := OUT + "/after"
	var ids: Array = []
	var label := "antes"
	for arg in args:
		if arg.begins_with("--src="): src = arg.trim_prefix("--src=")
		if arg.begins_with("--dst="): dst = arg.trim_prefix("--dst=")
		if arg.begins_with("--ids="): ids = Array(arg.trim_prefix("--ids=").split(","))
		if arg.begins_with("--label="): label = arg.trim_prefix("--label=")
	if ids.is_empty():
		for file in DirAccess.get_files_at(src):
			if file.ends_with(".scn"): ids.append(file.get_basename())
	if "--inventory" in args: inventory(src, ids)
	if "--apply" in args: apply_all(src, dst, ids)
	if "--capture" in args: await capture(src, ids, label)
	quit()

# ---------------------------------------------------------------- aplicação

func apply_all(src: String, dst: String, ids: Array) -> void:
	var report := {}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dst))
	collect_paint_signatures(src)
	report["_vc_paint_signatures"] = paint_signatures.size()
	for id: String in ids:
		if id in SKIP:
			report[id] = {"skipped": "fora do escopo"}
			continue
		# Um modelo por vez na memória (pedido do usuário): carrega sem cache e libera antes do próximo.
		var packed := ResourceLoader.load(src + "/" + id + ".scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			report[id] = {"error": "não carregou"}
			continue
		var target := packed.instantiate() as Node3D
		if target.has_meta(VERSION_META):
			report[id] = {"skipped": "já detalhado"}
			target.free()
			continue
		var row := detail_model(id, target)
		if row.has("error"):
			push_error("%s: %s" % [id, row.error])
		elif int(row.added) > 0:
			target.set_meta(VERSION_META, {"triangles": row.added, "details": row.details})
			var status := MESH_KIT.save_model(target, dst + "/" + id + ".scn")
			row["saved"] = status == OK
		else:
			# Nada coube: a cópia de destino continua igual à de origem.
			if src != dst: DirAccess.copy_absolute(ProjectSettings.globalize_path(src + "/" + id + ".scn"), ProjectSettings.globalize_path(dst + "/" + id + ".scn"))
		report[id] = row
		print("DETAIL ", id, " ", JSON.stringify(row))
		target.free()
		packed = null
	var file := FileAccess.open(OUT + "/apply-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, " "))
	file.close()

func detail_model(id: String, target: Node3D) -> Dictionary:
	model = target
	model_id = id
	log_rows = []
	accepted = {}
	flipped_paint = []
	anchors = []
	build_context()
	var before := triangle_total()
	var family := family_of(id)
	var spec: Dictionary = FLEET.spec(id)
	var size: Array = spec.get("bounds_size", [2.0, 1.5, 4.8])
	var center: Array = spec.get("bounds_center", [0.0, .75, 0.0])
	var frame := {
		"half_w": float(size[0]) * .5, "height": float(size[1]), "half_l": float(size[2]) * .5,
		"cz": float(center[2]), "wheels": wheels(),
	}
	var door: Dictionary = DOORS.row(id)
	if door.is_empty(): door = DOORS.fallback(frame.half_l, frame.height)
	frame["door"] = door
	var budget := int(before * BUDGET)
	var style := str(model.get_meta("passenger_design_profile", ""))
	# Ordem = prioridade: o que mais muda a leitura a 5–30 m entra primeiro; o teto corta o resto.
	var jobs: Array[Callable] = []
	match family:
		"passenger":
			enable_paint_color()
			if id not in NO_SIDE:
				jobs.append(func() -> void: handles(frame))
				jobs.append(func() -> void: door_seams(frame))
				jobs.append(func() -> void: side_molding(frame, style))
			jobs.append(func() -> void: emblem(frame, "diamond" if style in ["classic", "executive", "taxi", "touring", "wood"] else "octagon"))
			jobs.append(func() -> void: bumper_rubber(frame, -1.0))
			if id not in NO_SIDE: jobs.append(func() -> void: fuel_cap(frame, 1.0, .060))
			jobs.append(func() -> void: hood_lines(frame))
			if id not in NO_REAR: jobs.append(func() -> void: bumper_rubber(frame, 1.0))
		"utility":
			if id not in NO_SIDE:
				jobs.append(func() -> void: rub_strip(frame, .30, .05, .30))
				jobs.append(func() -> void: fuel_cap(frame, -1.0, .070))
			jobs.append(func() -> void: emblem(frame, "bar"))
			jobs.append(func() -> void: hood_lines(frame))
			jobs.append(func() -> void: bumper_rubber(frame, -1.0))
			if id not in NO_REAR: jobs.append(func() -> void: bumper_rubber(frame, 1.0))
		"newciv":
			if id not in NO_SIDE:
				jobs.append(func() -> void: rub_strip(frame, .46, .022, .42))
				jobs.append(func() -> void: fuel_cap(frame, 1.0, .055))
			jobs.append(func() -> void: emblem(frame, "round"))
			jobs.append(func() -> void: hood_lines(frame))
		"sport":
			# Esportivos e muscle já têm vincos, maçanetas, saídas de ar e emblema de capô; só a tampa
			# de combustível, que faltava em todos.
			if id not in NO_SIDE: jobs.append(func() -> void: fuel_cap(frame, -1.0 if id.hash() % 2 == 0 else 1.0, .058))
			if not model.has_meta("hood_badge"): jobs.append(func() -> void: emblem(frame, "octagon"))
		"service":
			jobs.append(func() -> void: emblem(frame, "bar"))
			if id not in HEAVY:
				jobs.append(func() -> void: bumper_rubber(frame, -1.0))
				if id not in NO_REAR: jobs.append(func() -> void: bumper_rubber(frame, 1.0))
	var added := 0
	for job in jobs:
		pending = {}
		pending_anchors = []
		job.call()
		var cost := pending_triangles()
		if cost == 0: continue
		if added + cost > budget:
			log_rows.append("orçamento: recusado %d tri" % cost)
			continue
		added += cost
		anchors.append_array(pending_anchors)
		merge_pending()
	if added == 0 and not flipped_paint.is_empty():
		# Nenhum detalhe coube: a pintura volta a ser exatamente a de antes.
		for row: Array in flipped_paint:
			var material: StandardMaterial3D = row[0]
			material.vertex_color_use_as_albedo = false
			if row[1]: material.vertex_color_is_srgb = not material.vertex_color_is_srgb
	var surfaces_before := surface_total()
	var committed := commit_all()
	if committed.has("error"): return committed
	return {"family": family, "triangles_before": before, "added": added, "ratio": snappedf(float(added) / maxf(1.0, before), .001),
		"budget": budget, "surfaces_before": surfaces_before, "surfaces_after": surface_total(), "details": log_rows, "parts": committed.parts,
		"dents": dent_report(frame)}

## Mesma regra de VehicleMaterialVariantPrewarm.shader_signature (classe + flags bool/int + texturas
## presentes): duas pinturas com a mesma assinatura usam o mesmo shader do StandardMaterial3D.
static func signature(material: Material) -> String:
	var fields: PackedStringArray = [material.get_class()]
	for property in material.get_property_list():
		if not (property.usage & PROPERTY_USAGE_STORAGE): continue
		var value: Variant = material.get(property.name)
		match typeof(value):
			TYPE_BOOL, TYPE_INT: fields.append("%s=%s" % [property.name, value])
			TYPE_OBJECT:
				if property.name != "script": fields.append("%s=%s" % [property.name, value != null])
	return "|".join(fields)

## Lê (um modelo por vez) as pinturas com cor de vértice que a frota já desenha e o pré-aquecimento
## já compila: utilitários, esportivos, civis novos.
func collect_paint_signatures(src: String) -> void:
	paint_signatures = {}
	for file in DirAccess.get_files_at(src):
		if not file.ends_with(".scn") or file.get_basename() in SKIP: continue
		var packed := ResourceLoader.load(src + "/" + file, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null: continue
		var target := packed.instantiate() as Node3D
		for found in target.find_children("*", "MeshInstance3D", true, false):
			var part := found as MeshInstance3D
			if part.mesh == null: continue
			for s in part.mesh.get_surface_count():
				var material := part.get_active_material(s) as StandardMaterial3D
				if material != null and material.vertex_color_use_as_albedo and ROLES.key(part, s).get_slice("#", 0) == "paint":
					paint_signatures[signature(material)] = file.get_basename()
		target.free()
		packed = null

## Pintura de passeio sem cor de vértice: relevo na cor do carro mal aparece (capturas de 29/10). Liga
## a cor de vértice no MESMO material só se (a) a assinatura de shader resultante já existe na frota
## (o shader e as variantes de sujeira/dano/chuva já são compilados no pré-aquecimento) e (b) toda
## superfície com esse material tem cor de vértice branca (o que já existe fica idêntico).
func enable_paint_color() -> void:
	var materials := {}
	for entry: Dictionary in parts:
		for info: Dictionary in entry.surfaces:
			var material := info.material as StandardMaterial3D
			if material == null or material.vertex_color_use_as_albedo or info.role != "paint": continue
			materials[material] = true
	for material: StandardMaterial3D in materials:
		var probe := material.duplicate() as StandardMaterial3D
		probe.vertex_color_use_as_albedo = true
		var match_id: String = paint_signatures.get(signature(probe), "")
		# A pintura com cor de vértice da frota pode ler a cor como sRGB e a de passeio não: com vértices
		# brancos (1,1,1) as duas leituras dão o mesmo branco, então a flag pode acompanhar.
		var srgb_flip := false
		if match_id.is_empty():
			probe.vertex_color_is_srgb = not probe.vertex_color_is_srgb
			match_id = paint_signatures.get(signature(probe), "")
			srgb_flip = not match_id.is_empty()
			if not srgb_flip: probe.vertex_color_is_srgb = not probe.vertex_color_is_srgb
		if match_id.is_empty():
			# Diz o que separa da pintura com cor de vértice mais parecida (diagnóstico do relatório).
			var mine := signature(probe).split("|")
			var best: PackedStringArray = []
			for known: String in paint_signatures:
				var diff: PackedStringArray = []
				var theirs := known.split("|")
				for field in mine:
					if field not in theirs: diff.append(field)
				if best.is_empty() or diff.size() < best.size(): best = diff
			log_rows.append("pintura sem cor de vértice: assinatura nova (%s), só relevo" % ", ".join(best))
			continue
		var white := true
		for entry: Dictionary in parts:
			for info: Dictionary in entry.surfaces:
				if info.material != material: continue
				var arrays: Array = info.arrays
				if arrays[Mesh.ARRAY_COLOR] == null:
					white = false
					continue
				for color: Color in (arrays[Mesh.ARRAY_COLOR] as PackedColorArray):
					if color.r < .995 or color.g < .995 or color.b < .995:
						white = false
						break
		if not white:
			log_rows.append("pintura com cor de vértice não branca: só relevo")
			continue
		material.vertex_color_use_as_albedo = true
		if srgb_flip: material.vertex_color_is_srgb = probe.vertex_color_is_srgb
		flipped_paint.append([material, srgb_flip])
		for entry: Dictionary in parts:
			for info: Dictionary in entry.surfaces:
				if info.material == material: info["vc"] = true
		log_rows.append("pintura passa a usar cor de vértice%s (assinatura = %s)" % [" sRGB" if srgb_flip else "", match_id])

func family_of(id: String) -> String:
	if model.has_meta("passenger_redesign_version"): return "passenger"
	if model.has_meta("sport_fleet_version"): return "sport"
	if id in preload("res://runtime/NewCivilianFleet.gd").IDS: return "newciv"
	if str(model.get_meta("fleet_redesign_family", "")) in ["van", "pickup", "suv", "buggy"]: return "utility"
	return "service"

# ---------------------------------------------------------------- geometria de consulta

func node_transform(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor := node
	while cursor != model and cursor != null:
		if cursor is Node3D: xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf

func build_context() -> void:
	parts = []
	tri_pos = PackedVector3Array()
	tri_ref = PackedInt32Array()
	grids = [{}, {}, {}]
	var users := {}
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if part.mesh != null: users[part.mesh] = int(users.get(part.mesh, 0)) + 1
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if part.mesh == null or not part.visible or not part.mesh is ArrayMesh: continue
		var xf := node_transform(part)
		var entry := {"node": part, "xf": xf, "inv": xf.affine_inverse(), "wheel": part.has_meta("wheel_center"),
			"shared": int(users[part.mesh]) > 1, "surfaces": []}
		var part_index := parts.size()
		for s in part.mesh.get_surface_count():
			var material := part.get_active_material(s)
			var standard := material as StandardMaterial3D
			var arrays := part.mesh.surface_get_arrays(s)
			var info := {"role": ROLES.key(part, s).get_slice("#", 0), "material": material,
				"vc": standard != null and standard.vertex_color_use_as_albedo,
				"metal": standard.metallic if standard != null else 0.0, "rough": standard.roughness if standard != null else 1.0,
				"arrays": arrays}
			entry.surfaces.append(info)
			if part.mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for t in range(0, count - 2, 3):
				var ia := indices[t] if not indices.is_empty() else t
				var ib := indices[t + 1] if not indices.is_empty() else t + 1
				var ic := indices[t + 2] if not indices.is_empty() else t + 2
				var id := int(tri_ref.size() / 5.0)
				tri_pos.append(xf * vertices[ia])
				tri_pos.append(xf * vertices[ib])
				tri_pos.append(xf * vertices[ic])
				tri_ref.append_array(PackedInt32Array([part_index, s, ia, ib, ic]))
				_grid_insert(id)
		parts.append(entry)

func _grid_insert(id: int) -> void:
	var a := tri_pos[id * 3]
	var b := tri_pos[id * 3 + 1]
	var c := tri_pos[id * 3 + 2]
	var low := Vector3(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)), minf(a.z, minf(b.z, c.z)))
	var high := Vector3(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)), maxf(a.z, maxf(b.z, c.z)))
	for axis in 3:
		var u := (axis + 1) % 3
		var v := (axis + 2) % 3
		var grid: Dictionary = grids[axis]
		for cu in range(floori(low[u] / CELL), floori(high[u] / CELL) + 1):
			for cv in range(floori(low[v] / CELL), floori(high[v] / CELL) + 1):
				var key := Vector2i(cu, cv)
				# Array (referência): PackedInt32Array guardado em Dictionary copiaria a cada append.
				if not grid.has(key): grid[key] = []
				(grid[key] as Array).append(id)

## Primeiro triângulo atingido. O enrolamento das malhas não é confiável (caixas viradas, vidro de
## face dupla): a normal volta orientada contra o raio.
func cast(origin: Vector3, direction: Vector3, length := 4.0) -> Dictionary:
	var axis := 0
	if absf(direction.y) > absf(direction[axis]): axis = 1
	if absf(direction.z) > absf(direction[axis]): axis = 2
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var keys := {}
	for step in 3:
		var p := origin + direction * length * step * .5
		keys[Vector2i(floori(p[u] / CELL), floori(p[v] / CELL))] = true
	var best := {}
	var best_distance := length
	var seen := {}
	var grid: Dictionary = grids[axis]
	for key in keys:
		if not grid.has(key): continue
		for id: int in (grid[key] as Array):
			if seen.has(id): continue
			seen[id] = true
			var a := tri_pos[id * 3]
			var b := tri_pos[id * 3 + 1]
			var c := tri_pos[id * 3 + 2]
			var hit: Variant = Geometry3D.ray_intersects_triangle(origin, direction, a, b, c)
			if hit == null: continue
			var distance := origin.distance_to(hit)
			if distance >= best_distance: continue
			var normal := (b - a).cross(c - a)
			if normal.length_squared() < 1e-12: continue
			normal = normal.normalized()
			if normal.dot(direction) > 0: normal = -normal
			best_distance = distance
			best = {"point": hit, "normal": normal, "tri": id, "part": tri_ref[id * 5], "surface": tri_ref[id * 5 + 1]}
	if not best.is_empty(): _attributes(best)
	return best

## Cor e UV da base no ponto (baricêntrico), para o detalhe herdar o tom da chapa.
func _attributes(hit: Dictionary) -> void:
	var id: int = hit.tri
	var entry: Dictionary = parts[int(hit.part)]
	var info: Dictionary = entry.surfaces[int(hit.surface)]
	hit["role"] = info.role
	hit["vc"] = info.vc
	# Peça inteira levada pela folha da porta (FleetBatchMesh): a caixa dela não pode crescer, e
	# retrovisor não é chapa. Roda idem.
	hit["wheel"] = entry.wheel or str((entry.node as Node).name).begins_with("DoorTrim")
	var arrays: Array = info.arrays
	var a := tri_pos[id * 3]
	var b := tri_pos[id * 3 + 1]
	var c := tri_pos[id * 3 + 2]
	var weights := Geometry3D.get_triangle_barycentric_coords(hit.point, a, b, c)
	var ia := tri_ref[id * 5 + 2]
	var ib := tri_ref[id * 5 + 3]
	var ic := tri_ref[id * 5 + 4]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
	hit["color"] = colors[ia] * weights.x + colors[ib] * weights.y + colors[ic] * weights.z if not colors.is_empty() else Color.WHITE
	hit["uv"] = uvs[ia] * weights.x + uvs[ib] * weights.y + uvs[ic] * weights.z if not uvs.is_empty() else Vector2.ZERO

func lamp_or_glass(role: String) -> bool:
	return ROLES.is_headlight_lens(role) or ROLES.is_tail_lens(role) or role in ["lens", "glass", "windshield", "window", "bar_left", "bar_right"] or "glass" in role

func wheels() -> Array:
	var found := []
	for entry: Dictionary in parts:
		if not entry.wheel: continue
		var node: MeshInstance3D = entry.node
		var box: AABB = (entry.xf as Transform3D) * node.mesh.get_aabb()
		found.append({"center": node.get_meta("wheel_center") if node.get_meta("wheel_center") is Vector3 else box.get_center(), "radius": maxf(box.size.y, box.size.z) * .5})
	return found

func near_wheel(z: float, y: float, frame: Dictionary, margin: float) -> bool:
	for wheel: Dictionary in frame.wheels:
		var c: Vector3 = wheel.center
		if absf(z - c.z) < float(wheel.radius) + margin and y < c.y + float(wheel.radius) + margin: return true
	return false

# ---------------------------------------------------------------- emissão

func _acc(part: int, surface: int) -> Acc:
	var key := "%d:%d" % [part, surface]
	if not pending.has(key): pending[key] = Acc.new()
	return pending[key]

## Godot desenha a frente no sentido horário: (b-a)x(c-a) aponta para dentro.
func tri(target: Dictionary, a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color, uv: Vector2) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 1e-14: return
	var order := [a, b, c]
	if cross.dot(outward) > 0:
		order = [a, c, b]
	else:
		cross = -cross
	var normal := cross.normalized()
	var acc := _acc(int(target.part), int(target.surface))
	for point in order:
		acc.pos.append(point)
		acc.nrm.append(normal)
		acc.col.append(color)
		acc.uv.append(uv)

func quad(target: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color, uv: Vector2) -> void:
	tri(target, a, b, c, outward, color, uv)
	tri(target, a, c, d, outward, color, uv)

func tint(hit: Dictionary, factor: float, absolute := Color(0, 0, 0, 0)) -> Color:
	if not bool(hit.vc): return Color.WHITE
	if absolute.a > 0: return absolute
	var base: Color = hit.color
	return Color(base.r * factor, base.g * factor, base.b * factor, base.a)

func pending_triangles() -> int:
	var total := 0
	for key in pending: total += (pending[key] as Acc).pos.size() / 3
	return total

func merge_pending() -> void:
	for key in pending:
		var source: Acc = pending[key]
		if not accepted.has(key): accepted[key] = Acc.new()
		var into: Acc = accepted[key]
		into.pos.append_array(source.pos)
		into.nrm.append_array(source.nrm)
		into.col.append_array(source.col)
		into.uv.append_array(source.uv)
	pending = {}

func triangle_total() -> int:
	var total := 0
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if part.mesh == null or not part.visible: continue
		for s in part.mesh.get_surface_count():
			var count: int = part.mesh.surface_get_array_index_len(s) if part.mesh is ArrayMesh else 0
			if count == 0 and part.mesh is ArrayMesh: count = part.mesh.surface_get_array_len(s)
			total += count / 3
	return total

func surface_total() -> int:
	var total := 0
	for found in model.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if part.mesh != null and part.visible: total += part.mesh.get_surface_count()
	return total

## Acrescenta os vértices às superfícies existentes. As superfícies intocadas passam adiante com os
## bytes originais (`_surfaces`); a alterada sai de add_surface_from_arrays com as mesmas arrays de
## antes mais as novas, e o formato tem de bater com o original (senão o pré-aquecimento não cobre).
func commit_all() -> Dictionary:
	var by_part := {}
	for key: String in accepted:
		var part := int(key.get_slice(":", 0))
		if not by_part.has(part): by_part[part] = {}
		by_part[part][int(key.get_slice(":", 1))] = accepted[key]
	var touched := []
	for part_index: int in by_part:
		var entry: Dictionary = parts[part_index]
		if entry.shared: return {"error": "malha compartilhada entre peças: " + str(entry.node.name)}
		var node: MeshInstance3D = entry.node
		var mesh := node.mesh as ArrayMesh
		var raw: Array = (mesh.get("_surfaces") as Array).duplicate()
		var inverse: Transform3D = entry.inv
		var normal_basis := inverse.basis.inverse().transposed()
		for surface: int in by_part[part_index]:
			var acc: Acc = by_part[part_index][surface]
			var info: Dictionary = entry.surfaces[surface]
			var arrays: Array = (info.arrays as Array).duplicate()
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var base := vertices.size()
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
			var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			for k in acc.pos.size():
				vertices.append(inverse * (acc.pos[k] as Vector3))
				var normal: Vector3 = (normal_basis * (acc.nrm[k] as Vector3)).normalized()
				if arrays[Mesh.ARRAY_NORMAL] != null: normals.append(normal)
				if arrays[Mesh.ARRAY_TANGENT] != null:
					var tangent := normal.cross(Vector3.UP)
					if tangent.length_squared() < .01: tangent = normal.cross(Vector3.RIGHT)
					tangent = tangent.normalized()
					tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, 1.0]))
				if arrays[Mesh.ARRAY_COLOR] != null: colors.append(acc.col[k])
				if arrays[Mesh.ARRAY_TEX_UV] != null: uvs.append(acc.uv[k])
				if arrays[Mesh.ARRAY_TEX_UV2] != null: uv2s.append(Vector2.ZERO)
				if arrays[Mesh.ARRAY_INDEX] != null: indices.append(base + k)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			if arrays[Mesh.ARRAY_NORMAL] != null: arrays[Mesh.ARRAY_NORMAL] = normals
			if arrays[Mesh.ARRAY_TANGENT] != null: arrays[Mesh.ARRAY_TANGENT] = tangents
			if arrays[Mesh.ARRAY_COLOR] != null: arrays[Mesh.ARRAY_COLOR] = colors
			if arrays[Mesh.ARRAY_TEX_UV] != null: arrays[Mesh.ARRAY_TEX_UV] = uvs
			if arrays[Mesh.ARRAY_TEX_UV2] != null: arrays[Mesh.ARRAY_TEX_UV2] = uv2s
			if arrays[Mesh.ARRAY_INDEX] != null: arrays[Mesh.ARRAY_INDEX] = indices
			var scratch := ArrayMesh.new()
			scratch.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var fresh: Dictionary = (scratch.get("_surfaces") as Array)[0]
			var original: Dictionary = raw[surface]
			for field in ["material", "name"]:
				if original.has(field): fresh[field] = original[field]
				else: fresh.erase(field)
			raw[surface] = fresh
		var rebuilt := ArrayMesh.new()
		rebuilt.resource_name = mesh.resource_name
		rebuilt.blend_shape_mode = mesh.blend_shape_mode
		rebuilt.custom_aabb = mesh.custom_aabb
		rebuilt.shadow_mesh = mesh.shadow_mesh
		for meta in mesh.get_meta_list(): rebuilt.set_meta(meta, mesh.get_meta(meta))
		rebuilt.set("_surfaces", raw)
		if rebuilt.get_surface_count() != mesh.get_surface_count(): return {"error": "contagem de superfícies mudou em " + str(node.name)}
		for s in mesh.get_surface_count():
			if rebuilt.surface_get_format(s) != mesh.surface_get_format(s): return {"error": "formato de vértice mudou em %s/%d: %d -> %d" % [node.name, s, mesh.surface_get_format(s), rebuilt.surface_get_format(s)]}
			if rebuilt.surface_get_material(s) != mesh.surface_get_material(s): return {"error": "material mudou em %s/%d" % [node.name, s]}
		node.mesh = rebuilt
		touched.append(str(node.name))
	return {"parts": touched}

# ---------------------------------------------------------------- formas

## Faixa chanfrada que segue a chapa: face externa a `height` e chanfros de 45° até 2 mm dentro.
## `samples` são acertos contíguos na MESMA superfície; `across` diz para onde fica a largura.
func strip(samples: Array, across: Vector3, width: float, height: float, colors: Array) -> void:
	if samples.size() < 2: return
	var kept := simplify(samples)
	var profiles := []
	for k in kept.size():
		var hit: Dictionary = kept[k]
		var p: Vector3 = hit.point
		var n: Vector3 = hit.normal
		var previous: Vector3 = (kept[maxi(k - 1, 0)] as Dictionary).point
		var following: Vector3 = (kept[mini(k + 1, kept.size() - 1)] as Dictionary).point
		var t := (following - previous).normalized()
		var b := n.cross(t).normalized()
		if b.dot(across) < 0: b = -b
		var half := width * .5
		profiles.append({"p": p, "n": n, "t": t, "b": b,
			"p0": p - b * (half + height) - n * SINK, "p1": p - b * half + n * height,
			"p2": p + b * half + n * height, "p3": p + b * (half + height) - n * SINK})
	pending_anchors.append_array(kept)
	var target: Dictionary = kept[0]
	var face: Color = colors[0]
	var bevel: Color = colors[1]
	var uv: Vector2 = target.uv
	for k in profiles.size() - 1:
		var a: Dictionary = profiles[k]
		var c: Dictionary = profiles[k + 1]
		var n: Vector3 = ((a.n as Vector3) + (c.n as Vector3)).normalized()
		var b: Vector3 = ((a.b as Vector3) + (c.b as Vector3)).normalized()
		quad(target, a.p0, a.p1, c.p1, c.p0, n - b, bevel, uv)
		quad(target, a.p1, a.p2, c.p2, c.p1, n, face, uv)
		quad(target, a.p2, a.p3, c.p3, c.p2, n + b, bevel, uv)
	for end in [0, profiles.size() - 1]:
		var e: Dictionary = profiles[end]
		var d: Vector3 = -(e.t as Vector3) if end == 0 else e.t
		var n: Vector3 = e.n
		var b: Vector3 = e.b
		var half := width * .5
		var q1: Vector3 = (e.p as Vector3) - b * half + d * height - n * SINK
		var q2: Vector3 = (e.p as Vector3) + b * half + d * height - n * SINK
		quad(target, e.p1, e.p2, q2, q1, n + d, bevel, uv)
		tri(target, e.p0, e.p1, q1, n - b + d, bevel, uv)
		tri(target, e.p3, e.p2, q2, n + b + d, bevel, uv)

## Mantém só as amostras onde a chapa dobra (chapa plana vira um quadrilátero só).
func simplify(samples: Array) -> Array:
	var kept := [samples[0]]
	var anchor := 0
	var j := 2
	while j < samples.size():
		var a: Vector3 = (samples[anchor] as Dictionary).point
		var c: Vector3 = (samples[j] as Dictionary).point
		var na: Vector3 = (samples[anchor] as Dictionary).normal
		var straight := true
		for k in range(anchor + 1, j):
			var p: Vector3 = (samples[k] as Dictionary).point
			var closest := Geometry3D.get_closest_point_to_segment(p, a, c)
			if p.distance_to(closest) > .003 or na.angle_to((samples[k] as Dictionary).normal) > deg_to_rad(5.0):
				straight = false
				break
		if not straight:
			anchor = j - 1
			kept.append(samples[anchor])
		j += 1
	kept.append(samples[samples.size() - 1])
	return kept

## Contorno 2D (u, v) de uma placa. `grow` alarga para a base do chanfro.
func outline(kind: String, a: float, b: float, grow: float) -> Array:
	var points := []
	match kind:
		"rect", "bar":
			for q in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]: points.append(Vector2(q.x * (a + grow), q.y * (b + grow)))
		"diamond":
			for q in [Vector2(-1, 0), Vector2(0, -1), Vector2(1, 0), Vector2(0, 1)]: points.append(Vector2(q.x * (a + grow * 1.41), q.y * (b + grow * 1.41)))
		_:
			var sides := 10 if kind == "round" else 8
			for i in sides:
				var angle := TAU * (i + .5) / sides
				points.append(Vector2(cos(angle) * (a + grow * 1.08), sin(angle) * (b + grow * 1.08)))
	return points

## Placa chanfrada sobre a chapa (maçaneta, tampa de combustível, emblema). `conform` projeta cada
## canto na superfície (chapa curva); sem ele a placa fica plana na frente da base (emblema sobre
## grade de barras). Recusa se algum canto cair fora da mesma superfície (borda de painel, vão).
func plate(hit: Dictionary, u_hint: Vector3, kind: String, a: float, b: float, height: float, colors: Array, conform := true) -> bool:
	var n: Vector3 = hit.normal
	var c: Vector3 = hit.point
	var u := (u_hint - n * u_hint.dot(n)).normalized()
	var v := n.cross(u).normalized()
	var top := outline(kind, a, b, 0.0)
	var foot := outline(kind, a, b, height)
	var outer := []
	var base := []
	var front := 0.0
	var corner_hits := []
	for list in [top, foot]:
		for q: Vector2 in list:
			var at := c + u * q.x + v * q.y
			var probe := cast(at + n * .06, -n, .14)
			if probe.is_empty():
				if conform: return false
				corner_hits.append({})
				continue
			if conform and (int(probe.part) != int(hit.part) or int(probe.surface) != int(hit.surface) or absf(((probe.point as Vector3) - at).dot(n)) > .02):
				return false
			corner_hits.append(probe)
			front = maxf(front, ((probe.point as Vector3) - c).dot(n))
	var index := 0
	for list in [top, foot]:
		for q: Vector2 in list:
			var at := c + u * q.x + v * q.y
			var probe: Dictionary = corner_hits[index]
			index += 1
			var surface_point: Vector3 = probe.point if conform else at + n * front
			if list == top: outer.append(surface_point + n * height)
			else: base.append(surface_point - n * SINK)
	pending_anchors.append(hit)
	var face: Color = colors[0]
	var bevel: Color = colors[1]
	var uv: Vector2 = hit.uv
	for k in range(1, outer.size() - 1): tri(hit, outer[0], outer[k], outer[k + 1], n, face, uv)
	for k in outer.size():
		var next := (k + 1) % outer.size()
		var middle: Vector3 = ((outer[k] as Vector3) + (outer[next] as Vector3)) * .5 - c
		quad(hit, outer[k], outer[next], base[next], base[k], n + (middle - n * middle.dot(n)).normalized(), bevel, uv)
	return true

# ---------------------------------------------------------------- detalhes

## Acertos válidos na lateral, em trechos contíguos na mesma superfície pintada.
func side_runs(side: float, y: float, frame: Dictionary, step := .04) -> Array:
	var runs := []
	var run := []
	var z: float = float(frame.cz) - float(frame.half_l) + .06
	var stop: float = float(frame.cz) + float(frame.half_l) - .06
	while z <= stop:
		var hit := {}
		if not near_wheel(z, y, frame, .07):
			hit = cast(Vector3(side * (float(frame.half_w) + .6), y, z), Vector3(-side, 0, 0), float(frame.half_w) + 1.4)
			if not hit.is_empty() and (hit.role != "paint" or hit.wheel or (hit.normal as Vector3).x * side < .8): hit = {}
		if not hit.is_empty() and not run.is_empty():
			var last: Dictionary = run[run.size() - 1]
			if int(last.part) != int(hit.part) or int(last.surface) != int(hit.surface) or absf((last.point as Vector3).x - (hit.point as Vector3).x) > .025:
				runs.append(run)
				run = []
		if hit.is_empty():
			if not run.is_empty(): runs.append(run)
			run = []
		else:
			run.append(hit)
		z += step
	if not run.is_empty(): runs.append(run)
	return runs.filter(func(r: Array) -> bool: return r.size() >= 2 and absf(((r[r.size() - 1] as Dictionary).point as Vector3).z - ((r[0] as Dictionary).point as Vector3).z) >= .25)

## Friso lateral em relevo na cor do carro (família de passeio: pintura sem cor de vértice).
## A altura varia pelo estilo: os de passeio levam na meia-porta; esportivos/GT, vinco alto.
func side_molding(frame: Dictionary, style: String) -> void:
	var door: Dictionary = frame.door
	var sill := float(door.sill)
	var belt := float(door.belt)
	var share := .40
	var width := .022
	if style in ["muscle", "gt", "supercar", "touring_sport"]:
		share = .62
		width = .014
	elif style in ["urban", "cabriolet"]:
		share = .46
		width = .018
	var y := sill + (belt - sill) * share
	# Com cor de vértice: friso escuro (borracha dos anos 80/90) nos de passeio; vinco só sombreado
	# (meio-tom) nos esportivos. Sem ela: relevo na cor do carro.
	var shade := .62 if share > .5 else .30
	var pieces := 0
	for side in [-1.0, 1.0]:
		for run: Array in side_runs(side, y, frame):
			strip(run, Vector3.UP, width if shade > .5 else width * 1.4, .008, [tint(run[0], shade), tint(run[0], shade * .8)])
			pieces += 1
	if pieces > 0: log_rows.append("friso lateral y=%.2f (%d trechos)" % [y, pieces])

## Borrachão/friso escuro de proteção (utilitários e civis novos: pintura com cor de vértice).
func rub_strip(frame: Dictionary, share: float, width: float, darkness: float) -> void:
	var door: Dictionary = frame.door
	var y := float(door.sill) + (float(door.belt) - float(door.sill)) * share
	var pieces := 0
	for side in [-1.0, 1.0]:
		for run: Array in side_runs(side, y, frame):
			strip(run, Vector3.UP, width, .007, [tint(run[0], darkness), tint(run[0], darkness * .7)])
			pieces += 1
	if pieces > 0: log_rows.append("friso de proteção y=%.2f (%d trechos)" % [y, pieces])

## Maçanetas em relevo (passeio). 4 portas quando a porta da frente é curta e sobra lateral até a
## roda traseira; o resto é cupê de uma porta por lado.
func handles(frame: Dictionary) -> void:
	var door: Dictionary = frame.door
	var zr := float(door.zr)
	var zf := float(door.zf)
	var y := float(door.belt) - .075
	if y < float(door.sill) + .12: return
	var rear_arch := INF
	for wheel: Dictionary in frame.wheels:
		var c: Vector3 = wheel.center
		if c.z > 0: rear_arch = minf(rear_arch, c.z - float(wheel.radius))
	var spots := [zr - .13]
	if zr - zf < 1.05 and rear_arch - zr > .55: spots.append(rear_arch - .12)
	var made := 0
	for side in [-1.0, 1.0]:
		for z: float in spots:
			var hit := cast(Vector3(side * (float(frame.half_w) + .6), y, z), Vector3(-side, 0, 0), float(frame.half_w) + 1.4)
			if hit.is_empty() or hit.wheel or lamp_or_glass(str(hit.role)) or (hit.normal as Vector3).x * side < .8: continue
			if plate(hit, Vector3(0, 0, 1), "rect", .075, .014, .011, [tint(hit, .22, CHROME if hit.role != "paint" else Color(0, 0, 0, 0)), tint(hit, .12)]): made += 1
	if made > 0: log_rows.append("maçanetas %d" % made)

## Juntas das portas (linhas escuras na pintura) onde o modelo não tem: dentro do vão da porta
## (`VehicleDoorSpecs`), para a folha recortada levá-las inteiras; na 4 portas, também a borda de trás
## da porta traseira. Pula a posição em que já existe junta de acabamento (trim_dark do sedã).
func door_seams(frame: Dictionary) -> void:
	var door: Dictionary = frame.door
	var zf := float(door.zf)
	var zr := float(door.zr)
	var sill := float(door.sill)
	var belt := float(door.belt)
	var rear_arch := INF
	for wheel: Dictionary in frame.wheels:
		var c: Vector3 = wheel.center
		if c.z > 0: rear_arch = minf(rear_arch, c.z - float(wheel.radius))
	var spots := [zf + .006, zr - .006]
	if zr - zf < 1.05 and rear_arch - zr > .55: spots.append(rear_arch - .03)
	var made := 0
	for side in [-1.0, 1.0]:
		for z: float in spots:
			var existing := false
			for dz in [-.012, 0.0, .012]:
				var probe := cast(Vector3(side * (float(frame.half_w) + .6), (sill + belt) * .5, z + dz), Vector3(-side, 0, 0), float(frame.half_w) + 1.4)
				if not probe.is_empty() and probe.role != "paint" and not probe.wheel and absf((probe.point as Vector3).x) > float(frame.half_w) * .6: existing = true
			if existing: continue
			var run := []
			var y := sill + .04
			while y <= belt - .03:
				var hit := cast(Vector3(side * (float(frame.half_w) + .6), y, z), Vector3(-side, 0, 0), float(frame.half_w) + 1.4)
				var good: bool = not hit.is_empty() and hit.role == "paint" and not hit.wheel and (hit.normal as Vector3).x * side >= .75
				if good and not run.is_empty():
					var last: Dictionary = run[run.size() - 1]
					good = int(last.part) == int(hit.part) and int(last.surface) == int(hit.surface) and absf((last.point as Vector3).x - (hit.point as Vector3).x) < .02
				if good: run.append(hit)
				elif run.size() >= 2: break
				else: run = []
				y += .03
			if run.size() >= 3 and bool((run[0] as Dictionary).vc):
				strip(run, Vector3(0, 0, 1), .006, .0012, [tint(run[0], .22), tint(run[0], .22)])
				made += 1
	if made > 0: log_rows.append("juntas de porta %d" % made)

## Tampa de combustível sobre a roda traseira: aro escuro (cor de vértice) ou relevo (passeio).
func fuel_cap(frame: Dictionary, side: float, radius: float) -> void:
	var door: Dictionary = frame.door
	var rear: Dictionary = {}
	for wheel: Dictionary in frame.wheels:
		var c: Vector3 = wheel.center
		if signf(c.x) == side and (rear.is_empty() or c.z > (rear.center as Vector3).z): rear = wheel
	if rear.is_empty(): return
	var c: Vector3 = rear.center
	var y := clampf(float(door.belt) - .13, c.y + float(rear.radius) + .12, float(door.belt) - .06)
	for z in [c.z + .10, c.z + .22, c.z - .05]:
		var hit := cast(Vector3(side * (float(frame.half_w) + .6), y, z), Vector3(-side, 0, 0), float(frame.half_w) + 1.4)
		if hit.is_empty() or hit.role != "paint" or (hit.normal as Vector3).x * side < .75: continue
		if plate(hit, Vector3(0, 0, 1), "octagon", radius, radius, .005, [tint(hit, .93), tint(hit, .32)]):
			log_rows.append("tampa de combustível %s z=%.2f" % ["direita" if side > 0 else "esquerda", z])
			return

## Emblema na grade da frente: só se a base for acabamento (grade/para-choque, que não amassa).
func emblem(frame: Dictionary, kind: String) -> void:
	var front: float = float(frame.cz) - float(frame.half_l) - .8
	var runs := []
	var run := []
	var y := .22
	# Até 60% da altura: acima disso o raio da frente achava a asa traseira dos esportivos (bastiao,
	# rapina) e a moldura do para-brisa da micro-van (1ª rodada de 30/10).
	while y < float(frame.height) * .6:
		var hit := cast(Vector3(0, y, front), Vector3(0, 0, 1), 3.0)
		var good: bool = not hit.is_empty() and hit.role != "paint" and hit.role != "roof_paint" and not lamp_or_glass(str(hit.role)) and not hit.wheel and bool(hit.vc) and absf((hit.normal as Vector3).z) > .85
		if good and not run.is_empty() and absf(((run[run.size() - 1] as Dictionary).point as Vector3).z - (hit.point as Vector3).z) > .03:
			runs.append(run)
			run = []
		if good: run.append(hit)
		elif not run.is_empty():
			runs.append(run)
			run = []
		y += .012
	if not run.is_empty(): runs.append(run)
	# A grade é o trecho de acabamento mais alto e com pelo menos 7 cm; abaixo dela vem o para-choque.
	var chosen: Array = []
	for candidate: Array in runs:
		var span: float = ((candidate[candidate.size() - 1] as Dictionary).point as Vector3).y - ((candidate[0] as Dictionary).point as Vector3).y
		if span >= .07: chosen = candidate
	if chosen.is_empty(): return
	var middle: Dictionary = chosen[chosen.size() / 2]
	var span_y: float = ((chosen[chosen.size() - 1] as Dictionary).point as Vector3).y - ((chosen[0] as Dictionary).point as Vector3).y
	var a := .055 if kind == "bar" else .034
	var b := minf(.018 if kind == "bar" else .028, span_y * .35)
	if plate(middle, Vector3.RIGHT, kind, a, b, .008, [tint(middle, 1.0, CHROME), tint(middle, 1.0, CHROME * .7)], false):
		log_rows.append("emblema %s y=%.2f" % [kind, (middle.point as Vector3).y])

## Borrachão no para-choque: faixa escura na face do para-choque, só sobre acabamento.
func bumper_rubber(frame: Dictionary, end: float) -> void:
	var start_z: float = float(frame.cz) + end * (float(frame.half_l) + .8)
	var direction := Vector3(0, 0, -end)
	var samples := []
	var y := .15
	var nearest := INF
	while y < minf(.95, float(frame.height) * .6):
		var hit := cast(Vector3(0, y, start_z), direction, 3.0)
		if not hit.is_empty():
			var depth := absf((hit.point as Vector3).z - start_z)
			samples.append({"y": y, "hit": hit, "depth": depth})
			var ok: bool = hit.role != "paint" and not lamp_or_glass(str(hit.role)) and bool(hit.vc) and absf((hit.normal as Vector3).z) > .85
			if ok: nearest = minf(nearest, depth)
		y += .01
	if not is_finite(nearest): return
	# Faixa do para-choque: acabamento mais saliente, contíguo em altura.
	var band := []
	for row: Dictionary in samples:
		var hit: Dictionary = row.hit
		var ok: bool = hit.role != "paint" and not lamp_or_glass(str(hit.role)) and bool(hit.vc) and absf((hit.normal as Vector3).z) > .85 and float(row.depth) <= nearest + .012
		if ok: band.append(row)
		elif not band.is_empty() and float(row.y) > float((band[band.size() - 1] as Dictionary).y) + .015: break
	if band.size() < 2: return
	var low: float = (band[0] as Dictionary).y
	var high: float = (band[band.size() - 1] as Dictionary).y
	if high - low < .06: return
	var at_y := (low + high) * .5
	var center: Dictionary = cast(Vector3(0, at_y, start_z), direction, 3.0)
	if center.is_empty(): return
	var width := clampf((high - low) * .32, .025, .05)
	var runs := []
	for sign in [-1.0, 1.0]:
		var run := [center] if sign > 0 else []
		var x: float = .04 * sign
		while absf(x) < float(frame.half_w):
			var hit := cast(Vector3(x, at_y, start_z), direction, 3.0)
			if hit.is_empty() or int(hit.part) != int(center.part) or int(hit.surface) != int(center.surface) or absf((hit.normal as Vector3).z) < .8 or absf((hit.point as Vector3).z - (center.point as Vector3).z) > .03: break
			run.append(hit)
			x += .04 * sign
		if sign < 0: run.reverse()
		runs.append(run)
	var whole: Array = runs[0] + runs[1]
	if whole.size() < 4: return
	strip(whole, Vector3.UP, width, .006, [tint(center, 1.0, RUBBER), tint(center, 1.0, RUBBER)])
	log_rows.append("borrachão %s y=%.2f" % ["dianteiro" if end < 0 else "traseiro", at_y])

## Juntas do capô (linhas escuras na pintura com cor de vértice), visíveis da câmera de perseguição.
func hood_lines(frame: Dictionary) -> void:
	# Faixas de fechamento da cintura (top_gap_fill, 30/10) ficam na pintura, horizontais, na borda do
	# capô e dos para-lamas: uma junta de capô poderia cair em cima delas. Nesses carros, sem juntas.
	if model.has_meta("top_gap_fit_revision"):
		log_rows.append("juntas do capô puladas: faixas de fechamento da cintura")
		return
	var top := float(frame.height) + 1.0
	var front_z: float = float(frame.cz) - float(frame.half_l)
	var hood_start := INF
	var cowl := INF
	var z := front_z + .02
	while z < float(frame.cz) + .4:
		var hit := cast(Vector3(0, top, z), Vector3.DOWN, top + 1.0)
		if not hit.is_empty():
			if hit.role == "paint" and (hit.normal as Vector3).y > .7 and not is_finite(hood_start): hood_start = z
			elif lamp_or_glass(str(hit.role)) and is_finite(hood_start):
				cowl = z
				break
		z += .03
	if not is_finite(hood_start) or not is_finite(cowl) or cowl - hood_start < .45: return
	var mid := (hood_start + cowl) * .5
	var extent := 0.0
	var x := 0.0
	while x < float(frame.half_w):
		var hit := cast(Vector3(x, top, mid), Vector3.DOWN, top + 1.0)
		if hit.is_empty() or hit.role != "paint" or (hit.normal as Vector3).y < .8: break
		extent = x
		x += .02
	if extent < .35: return
	var made := 0
	for side in [-1.0, 1.0]:
		var run := []
		z = hood_start + .05
		while z < cowl - .06:
			var hit := cast(Vector3(side * (extent - .05), top, z), Vector3.DOWN, top + 1.0)
			if hit.is_empty() or hit.role != "paint" or (hit.normal as Vector3).y < .6: break
			if not run.is_empty() and (int(hit.part) != int((run[0] as Dictionary).part) or int(hit.surface) != int((run[0] as Dictionary).surface)): break
			run.append(hit)
			z += .05
		if run.size() >= 3:
			strip(run, Vector3(side, 0, 0), .009, .0015, [tint(run[0], .30), tint(run[0], .30)])
			made += 1
	var rear := []
	x = -(extent - .05)
	while x <= extent - .05:
		var hit := cast(Vector3(x, top, cowl - .05), Vector3.DOWN, top + 1.0)
		if hit.is_empty() or hit.role != "paint" or (hit.normal as Vector3).y < .6:
			rear = []
			break
		rear.append(hit)
		x += .05
	if rear.size() >= 3:
		strip(rear, Vector3.BACK, .009, .0015, [tint(rear[0], .30), tint(rear[0], .30)])
		made += 1
	if made > 0: log_rows.append("juntas do capô (%d linhas)" % made)

# ---------------------------------------------------------------- simulação de amassado

## Mesma função de VehicleBodyDents._compute (peso (1-(d/r)²)² × cintura, teto .34 m), com amassados de
## profundidade máxima espalhados pelo contorno (laterais r=1,0 e frente/trás r=1,25, altura presa como
## em `impact`). Mede, em cada ponto de apoio de detalhe sobre chapa que amassa:
## - `paint_cm`: quanto o detalhe na pintura fica para FORA da chapa amassada (a chapa é interpolada
##   entre os vértices dela; o detalhe segue a função no próprio vértice). Negativo = afunda e some;
## - `static_cm`: quanto um detalhe de acabamento parado ficaria para fora no mesmo lugar (alternativa).
## Não substitui ver um carro batido no jogo.
func dent_report(frame: Dictionary) -> Dictionary:
	var height := clampf(float(frame.height), 1.1, 3.6)
	var half_w := float(frame.half_w)
	var half_l := float(frame.half_l)
	var cz := float(frame.cz)
	var y := clampf(.5, .35, minf(.8, height * .5))
	var dents := []
	var z := -half_l
	while z <= half_l + .001:
		dents.append([Vector3(-half_w, y, cz + z), Vector3(1, 0, 0), 1.0])
		dents.append([Vector3(half_w, y, cz + z), Vector3(-1, 0, 0), 1.0])
		z += .2
	var x := -half_w
	while x <= half_w + .001:
		dents.append([Vector3(x, y, cz - half_l), Vector3(0, 0, 1), 1.25])
		dents.append([Vector3(x, y, cz + half_l), Vector3(0, 0, -1), 1.25])
		x += .2
	var worst_paint := 0.0
	var worst_static := 0.0
	var counted := 0
	for anchor: Dictionary in anchors:
		var entry: Dictionary = parts[int(anchor.part)]
		var info: Dictionary = entry.surfaces[int(anchor.surface)]
		if info.role != "paint": continue
		counted += 1
		var id: int = anchor.tri
		var a := tri_pos[id * 3]
		var b := tri_pos[id * 3 + 1]
		var c := tri_pos[id * 3 + 2]
		var p: Vector3 = anchor.point
		var n: Vector3 = anchor.normal
		var w := Geometry3D.get_triangle_barycentric_coords(p, a, b, c)
		for dent: Array in dents:
			var skin := (_dent(a, dent, height) * w.x + _dent(b, dent, height) * w.y + _dent(c, dent, height) * w.z).dot(-n)
			var own := _dent(p, dent, height).dot(-n)
			worst_paint = maxf(worst_paint, skin - own)
			worst_static = maxf(worst_static, skin)
	return {"anchors_on_paint": counted, "paint_cm": snappedf(worst_paint * 100.0, .1), "static_cm": snappedf(worst_static * 100.0, .1)}

func _dent(rest: Vector3, dent: Array, height: float) -> Vector3:
	var belt := 1.0 - smoothstep(height * .58, height * .82, rest.y)
	var distance := rest.distance_to(dent[0]) / float(dent[2])
	if distance >= 1.0: return Vector3.ZERO
	return (dent[1] as Vector3) * .34 * pow(1.0 - distance * distance, 2) * belt

# ---------------------------------------------------------------- inventário e fotos

func inventory(src: String, ids: Array) -> void:
	var report := {}
	for id: String in ids:
		var packed := ResourceLoader.load(src + "/" + id + ".scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null: continue
		var target := packed.instantiate() as Node3D
		var row := {"meta": {}, "parts": [], "door": DOORS.row(id)}
		var spec: Dictionary = FLEET.spec(id)
		row["bounds_size"] = spec.get("bounds_size", [])
		row["bounds_center"] = spec.get("bounds_center", [])
		for key in target.get_meta_list(): row.meta[key] = str(target.get_meta(key)).left(80)
		for node in target.find_children("*", "", true, false):
			var entry := {"name": str(target.get_path_to(node)), "class": node.get_class()}
			var metas := {}
			for key in node.get_meta_list(): metas[key] = str(node.get_meta(key)).left(160)
			entry["meta"] = metas
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var part := node as MeshInstance3D
				var mesh := part.mesh
				entry["visible"] = part.visible
				entry["mesh_path"] = mesh.resource_path
				var surfaces := []
				for i in mesh.get_surface_count():
					var material := part.get_active_material(i)
					var info := {"role": ROLES.key(part, i)}
					if material is StandardMaterial3D:
						var m := material as StandardMaterial3D
						info["mat_name"] = m.resource_name
						info["albedo"] = m.albedo_color.to_html(false)
						info["metal"] = snappedf(m.metallic, .01)
						info["rough"] = snappedf(m.roughness, .01)
						info["vcolor"] = m.vertex_color_use_as_albedo
					if mesh is ArrayMesh:
						info["format"] = (mesh as ArrayMesh).surface_get_format(i)
						info["verts"] = (mesh as ArrayMesh).surface_get_array_len(i)
						info["index"] = (mesh as ArrayMesh).surface_get_array_index_len(i)
						var points: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
						if not points.is_empty():
							var box := AABB(part.transform * points[0], Vector3.ZERO)
							for p in points: box = box.expand(part.transform * p)
							info["aabb"] = [snappedf(box.position.x, .01), snappedf(box.position.y, .01), snappedf(box.position.z, .01), snappedf(box.end.x, .01), snappedf(box.end.y, .01), snappedf(box.end.z, .01)]
					surfaces.append(info)
				entry["surfaces"] = surfaces
			row.parts.append(entry)
		report[id] = row
		target.free()
		packed = null
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := FileAccess.open(OUT + "/inventory.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, " "))
	file.close()
	print("INVENTORY_DONE ", report.size())

## Fotos de vitrine (não é medição de FPS): mesma luz e câmeras antes e depois.
func capture(src: String, ids: Array, label: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("captura precisa de janela")
		return
	root.size = Vector2i(1280, 800)
	var folder := "res://evidence/fleet-body-20261029"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var world := Node3D.new()
	root.add_child(world)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("86969e")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c4d4de")
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -38, 0)
	sun.light_color = Color("ffe2b8")
	sun.light_energy = 1.6
	sun.shadow_enabled = true
	world.add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color("545c60")
	ground_material.roughness = .88
	ground.material_override = ground_material
	world.add_child(ground)
	var camera := Camera3D.new()
	camera.near = .05
	world.add_child(camera)
	camera.make_current()
	for id: String in ids:
		var packed := ResourceLoader.load(src + "/" + id + ".scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null: continue
		var target := packed.instantiate() as Node3D
		world.add_child(target)
		var spec: Dictionary = FLEET.spec(id)
		var paint := preload("res://runtime/VehiclePaint.gd").new()
		paint.bind(target, id)
		var palette: Array = spec.get("colors", [])
		if not palette.is_empty(): paint.apply(Color.html(str(palette[0])))
		var size: Array = spec.get("bounds_size", [2.0, 1.5, 4.8])
		var scale := maxf(float(size[2]) / 4.8, float(size[1]) / 1.6)
		var focus := Vector3(0, float(size[1]) * .45, 0)
		# Lado: o que mais muda com friso e maçaneta; 3/4 frente e trás: grade, emblema, para-choque;
		# "longe": a ~22 m, a distância de rua em que o jogador diz que falta detalhe.
		var views := [
			{"id": "lado", "at": Vector3(-8.6, 1.6, -.6), "fov": 32},
			{"id": "frente34", "at": Vector3(-5.2, 2.2, -6.2), "fov": 32},
			{"id": "tras34", "at": Vector3(5.4, 2.3, 6.0), "fov": 32},
			{"id": "perto", "at": Vector3(-3.4, 1.35, -1.8), "fov": 40},
			{"id": "longe", "at": Vector3(-15.0, 4.0, -16.0), "fov": 22},
		]
		for view: Dictionary in views:
			camera.fov = float(view.fov)
			camera.position = (view.at as Vector3) * scale
			camera.look_at(focus)
			for frame in 6: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("%s/%s-%s-%s.png" % [folder, id, label, view.id])
		print("CAPTURE ", label, " ", id)
		target.free()
		packed = null
		await process_frame
	world.free()
