extends SceneTree
## Detalhe das lanternas e faróis da frota redesenhada (pedido do jogador, 29/10/2026: "as lanternas dos
## carros precisam ter mais detalhes"). Só ACRESCENTA uma malha filha do nó que já carrega as lentes
## (HeadlightL e Tail nos modelos de um nó por lâmpada; Body nos modelos agrupados). Nenhum nó existente é
## movido nem tem a malha regravada: o encaixe das lanternas é outro passo, aplicado antes deste, e o detalhe
## é medido na geometria que a lente tiver na hora em que este script roda.
##
## Por que assim (custo no jogo):
## - nenhum material novo: a malha usa o MESMO material de acabamento com cor por vértice que o carro já
##   desenha (papel "trim" nos agrupados, "detail" nos de nó por lâmpada), então shader e pipeline já existem
##   e já entram nos pré-aquecimentos da frota; a cor de cada peça é dado do vértice, como no FleetBatchMesh;
## - o formato de vértice sai igual ao da superfície de onde o material veio e o script recusa o carro se não
##   bater (formato diferente = pipeline nova compilando no jogo, ver runtime/FormatPrewarm.gd);
## - uma superfície por malha: +1 malha no carro agrupado (frente e traseira moram no Body) e +2 no de nó por
##   lâmpada (frente debaixo de HeadlightL, traseira debaixo de Tail), sempre sem sombra projetada (peça rasa
##   por cima da lente; a sombra seria só mais desenho no passe de sombra);
## - nada emissivo: o brilho continua sendo a lente original (freio, farol aceso, lado quebrado no
##   VehicleEquipment não mudam); o detalhe é moldura, células e refletores por cima, que de noite recortam o
##   brilho em células e de dia separam vermelho/âmbar/branco, o que se lê de longe;
## - teto de +10% de triângulos por carro: passando, desce de nível (menos segmentos, sem refletor, sem saia).
## Marcas na malha nova: `lamp_detail_surface_material_keys` (papel de acabamento, então VehicleEquipment,
## VehiclePaint e o amassado a ignoram), `door_cut_exempt` (o recorte da porta não a percorre) e
## `fleet_lamp_detail` (versão; rodar de novo troca a malha anterior em vez de duplicar).
##
## Uso (sempre pela fila; padrão = cópias em artifacts, nunca os .scn reais sem --dir explícito):
##   tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/detail_fleet_lamps_20261029.gd -- \
##     [--dir=res://assets/fleet/redesigned] [--ids=a,b] [--dry] [--label=x]
## Motos ficam de fora (um farol redondo e acabamento próprio de moto).
const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const VERSION := "20261029"
const META := "fleet_lamp_detail"
const KEYS_META := "lamp_detail_surface_material_keys"
const DEFAULT_DIR := "res://artifacts/fleet-lamps-20261029/scn"
const REPORT_DIR := "res://artifacts/fleet-lamps-20261029"
const MAX_RATIO := .10
const SNAP := 2000.0
const LAYOUT_MASK := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR \
	| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 \
	| Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS \
	| Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES

## Família visual de cada modelo (decidida pelo desenho, não pelo construtor que o assou).
const FAMILY_IDS := {
	"sport": ["tauro_v10", "raijin_gt", "kite_type_s", "lince_rs", "brisa_s", "sakura_s15", "rapina_r", "supra_a80",
		"vertice_midengine", "porto_rosso", "desert_mirage", "desert_mirage_gt", "monaliza", "jessica_jetta_gli",
		"rauhz_focus_mk1", "desert_faisca_rally", "sport_estate"],
	"sedan": ["aurora_executive", "union_sedan", "taxi_yellow", "metro_hatch", "orbita_micro", "nordic_estate",
		"station_wagon", "vale_crossover", "beach_cabriolet", "desert_faisca", "desert_siroco", "digo_gol_1993"],
	"utility": ["arctic_jeep", "desert_jeep_4x4", "atlas_crew_pickup", "bravio_crew", "ranch_pickup", "ranch_single",
		"sertao_trail_pickup", "lumber_pickup_4x4", "digo_amarok_2014", "summit_suv", "winter_suv_heavy", "courier_van",
		"polar_van", "dock_delivery_van", "nimbus_minivan", "mare_microvan", "toco_minitruck", "beach_buggy", "dune_buggy",
		"desert_bison"],
	"service": ["police_cruiser", "police_suv", "police_transport", "medic_box", "rescue_pumper", "towmaster",
		"armored_truck", "snow_plow_truck", "boxrunner", "cargo_flatbed_truck", "american_dump_truck", "american_tanker_truck"],
	"classic": ["bastiao_63", "potro_68", "jararaca_v10", "carcara_ss", "trovao_440", "caiman_454", "brasa_hc",
		"imperador_64", "imperador_64_conv", "monte_rei_84", "duque_76", "besouro_1300", "sedan_classic", "muscle_classic",
		"cobra_v8", "cobra_boss_ironback", "surf_woody_wagon", "desert_coyote", "desert_coyote_drag"],
}

# Paleta em sRGB (convertida para linear quando o material não marca vertex_color_is_srgb, como o FleetBatchMesh).
const CHROME := Color("cdd2d6")
const SATIN := Color("8f979d")
const GRAPHITE := Color("1a1d20")
const RUBBER := Color("111315")
const SMOKE := Color("30363b")
const AMBER := Color("e98a17")
const REVERSE := Color("e3e7e8")

## Moldura (cor, largura por dentro e por fora da borda da lente, em m) e travessas por família. Medidas
## pensadas para a câmera do jogo (~36 px/m em 1080p): abaixo de ~1 cm a moldura some; as células de cor
## (âmbar, branco de ré, faixa fumê) é que leem de longe, a moldura e os refletores leem de perto.
const STYLE := {
	"sport": {"bezel": GRAPHITE, "w_in": .007, "w_out": .013, "line": .010, "line_color": GRAPHITE},
	"sedan": {"bezel": SATIN, "w_in": .007, "w_out": .013, "line": .010, "line_color": GRAPHITE},
	"utility": {"bezel": RUBBER, "w_in": .010, "w_out": .022, "line": .014, "line_color": RUBBER},
	"service": {"bezel": RUBBER, "w_in": .011, "w_out": .024, "line": .016, "line_color": RUBBER},
	"classic": {"bezel": CHROME, "w_in": .010, "w_out": .019, "line": .012, "line_color": CHROME},
}
# Alturas acima da lente (m): células < travessas = moldura < refletor. Separação de 1 mm basta com o
# depth reverso do Godot 4 a 30 m; as células são recortadas por dentro da moldura para não se sobreporem.
const EPS_CELL := .002
const EPS_LINE := .003
const EPS_RING := .003
const EPS_DISC := .0035
const EPS_DOT := .004

var dir := DEFAULT_DIR
var dry := false
var label := ""
var report := {}
# Estado do carro em montagem.
var _winding := -1.0
var _srgb := true
var _level := 0
# Faces que não são lente (lataria, acabamento, vidro) no espaço do modelo, para sondar o que já existe em volta.
var _others: Array = []

func _initialize() -> void:
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--dir="): dir = arg.trim_prefix("--dir=").trim_suffix("/")
		elif arg.begins_with("--ids="):
			for id in arg.trim_prefix("--ids=").split(",", false): ids.append(id)
		elif arg == "--dry": dry = true
		elif arg.begins_with("--label="): label = arg.trim_prefix("--label=").validate_filename()
	if ids.is_empty():
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".scn"): ids.append(file.get_basename())
	ids.sort()
	var failed := 0
	for id in ids:
		var row := process(id)
		report[id] = row
		if row.get("status", "") == "error": failed += 1
		print("LAMP_DETAIL ", id, " ", JSON.stringify(_short(row)))
	var name := "report-%s%s.json" % ["dry-" if dry else "", label if not label.is_empty() else dir.get_file()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	FileAccess.open(REPORT_DIR + "/" + name, FileAccess.WRITE).store_string(JSON.stringify({"version": VERSION, "dir": dir, "dry": dry, "models": report}, "\t"))
	print("LAMP_DETAIL_DONE models=", report.size(), " failed=", failed, " report=", REPORT_DIR + "/" + name)
	quit(1 if failed > 0 else 0)

func _short(row: Dictionary) -> Dictionary:
	var keep := {}
	for key in ["status", "reason", "family", "level", "base_tris", "added_tris", "ratio", "meshes_added", "lamps", "material", "format_ok", "aabb_growth"]:
		if row.has(key): keep[key] = row[key]
	return keep

static func family_of(id: String) -> String:
	for family in FAMILY_IDS:
		if id in FAMILY_IDS[family]: return family
	return ""

# ---------------------------------------------------------------------------------------------- modelo

func process(id: String) -> Dictionary:
	if id.begins_with("bike_"): return {"status": "skipped", "reason": "moto"}
	var family := family_of(id)
	if family.is_empty(): return {"status": "skipped", "reason": "sem família declarada"}
	var path := dir + "/" + id + ".scn"
	# Um modelo carregado por vez e fora do cache: a RAM fica com um carro só.
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return {"status": "error", "reason": "não carregou " + path}
	var model := packed.instantiate() as Node3D
	packed = null
	var row := build(id, family, model)
	if row.status == "ok" and not dry:
		_assign_owner(model, model)
		var scene := PackedScene.new()
		var status := scene.pack(model)
		if status == OK: status = ResourceSaver.save(scene, path)
		if status != OK:
			row.status = "error"
			row.reason = "falha ao gravar (%d)" % status
	model.free()
	return row

func build(id: String, family: String, model: Node3D) -> Dictionary:
	# Rodar de novo troca o detalhe anterior: nada duplica.
	for old in model.find_children("LampDetail*", "MeshInstance3D", true, false):
		if old.has_meta(META):
			old.get_parent().remove_child(old)
			old.free()
	var base := _counts(model)
	var box_before := _model_aabb(model)
	var source := _pick_material(model)
	if source.is_empty(): return {"status": "error", "reason": "sem material de acabamento com cor por vértice", "family": family}
	var material := source.material as StandardMaterial3D
	_srgb = material.vertex_color_is_srgb
	_winding = _measure_winding(source.part, source.surface)
	var lamps := _collect(model)
	var ambers: Array = []
	var heads: Array = []
	var tails: Array = []
	for comp in lamps:
		if comp.kind == "amber": ambers.append(comp)
		elif comp.kind == "head": heads.append(comp)
		elif comp.kind == "tail": tails.append(comp)
	if heads.is_empty() and tails.is_empty(): return {"status": "skipped", "reason": "nenhuma lente de farol/lanterna", "family": family}
	# Anfitrião: o nó da lente (traseira: a maior lanterna; frente: o farol do lado esquerdo).
	var rear_host: MeshInstance3D = _host(tails, false)
	var front_host: MeshInstance3D = _host(heads, true)
	var budget := int(base.triangles * MAX_RATIO)
	var sinks := {}
	var level := 0
	var added := 0
	for attempt in 5:
		_level = attempt
		level = attempt
		sinks = {}
		for comp in heads: _decorate(comp, family, ambers, _sink(sinks, front_host if front_host != null else rear_host))
		for comp in tails: _decorate(comp, family, ambers, _sink(sinks, rear_host if rear_host != null else front_host))
		added = 0
		for host in sinks: added += (sinks[host].pos as Array).size() / 3
		if added <= budget: break
	if added > budget: return {"status": "error", "reason": "passa de 10%% mesmo no nível 4 (%d > %d)" % [added, budget], "family": family}
	var meshes_added := 0
	var format_ok := true
	var nodes: Array[String] = []
	var expected: int = (source.part as MeshInstance3D).mesh.surface_get_format(source.surface) & LAYOUT_MASK
	for host: MeshInstance3D in sinks:
		var sink: Dictionary = sinks[host]
		if (sink.pos as Array).is_empty(): continue
		var node := MeshInstance3D.new()
		var both := sinks.size() == 1
		node.name = "LampDetail" if both else ("LampDetailFront" if host == front_host else "LampDetailRear")
		node.mesh = _commit(sink, model, host, material)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta(KEYS_META, [source.role])
		node.set_meta("door_cut_exempt", true)
		node.set_meta(META, VERSION)
		host.add_child(node)
		meshes_added += 1
		nodes.append(str(model.get_path_to(node)))
		var got: int = node.mesh.surface_get_format(0) & LAYOUT_MASK
		if got != expected: format_ok = false
	if not format_ok: return {"status": "error", "reason": "formato de vértice diferente da superfície de origem", "family": family}
	model.set_meta(META, VERSION)
	var box_after := _model_aabb(model)
	return {"status": "ok", "family": family, "level": level, "base_tris": base.triangles, "base_meshes": base.meshes,
		"base_surfaces": base.surfaces, "added_tris": added, "ratio": snappedf(float(added) / maxf(1.0, base.triangles), .0001),
		"meshes_added": meshes_added, "surfaces_added": meshes_added, "nodes": nodes,
		"lamps": {"head": heads.size(), "tail": tails.size(), "amber_existing": ambers.size()},
		"components": _describe(heads + tails),
		"material": {"role": source.role, "part": str(source.part.name), "metallic": snappedf(material.metallic, .01),
			"roughness": snappedf(material.roughness, .01), "vertex_color_is_srgb": _srgb},
		"format": expected, "format_ok": format_ok, "winding": _winding,
		"aabb_growth": [snappedf(box_after.size.x - box_before.size.x, .001), snappedf(box_after.size.y - box_before.size.y, .001), snappedf(box_after.size.z - box_before.size.z, .001)]}

# ------------------------------------------------------------------------------------------ geometria

static func _to_model(model: Node, node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != model:
		if cursor is Node3D: xf = (cursor as Node3D).transform * xf
		cursor = cursor.get_parent()
	return xf

static func _key(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x * SNAP), roundi(p.y * SNAP), roundi(p.z * SNAP))

func _counts(model: Node3D) -> Dictionary:
	var result := {"meshes": 0, "surfaces": 0, "triangles": 0}
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		result.meshes += 1
		result.surfaces += part.mesh.get_surface_count()
		result.triangles += part.mesh.get_faces().size() / 3
	return result

func _model_aabb(model: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null: continue
		var b := _to_model(model, part) * part.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

## Material de acabamento branco com cor por vértice, opaco, sem textura nem emissão, já desenhado pelo carro.
## Preferência por metálico ~0,35 e rugosidade ~0,45 (cromado e plástico ficam críveis no mesmo material).
func _pick_material(model: Node3D) -> Dictionary:
	var best := {}
	var best_score := INF
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center") or not part.visible: continue
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part, surface).get_slice("#", 0)
			if role not in ["trim", "detail"]: continue
			var material := part.get_active_material(surface) as StandardMaterial3D
			if material == null or not material.vertex_color_use_as_albedo or material.emission_enabled: continue
			if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.albedo_texture != null or material.normal_enabled: continue
			if material.albedo_color.r < .95 or material.albedo_color.g < .95 or material.albedo_color.b < .95: continue
			if not part.mesh is ArrayMesh: continue
			var score := absf(material.metallic - .35) + absf(material.roughness - .45) * .6 + (0.0 if part.name == &"Body" else .05)
			if score < best_score:
				best_score = score
				best = {"part": part, "surface": surface, "material": material, "role": role}
	return best

## Sinal de (b-a)×(c-a)·normal nas faces do próprio acabamento: a malha nova segue a mesma ordem de vértices.
func _measure_winding(part: MeshInstance3D, surface: int) -> float:
	var arrays := part.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if normals == null: return -1.0
	var votes := 0.0
	var count: int = indices.size() if indices != null else vertices.size()
	for i in range(0, count - 2, 3):
		var ia: int = indices[i] if indices != null else i
		var ib: int = indices[i + 1] if indices != null else i + 1
		var ic: int = indices[i + 2] if indices != null else i + 2
		var cross := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		var n: Vector3 = normals[ia] + normals[ib] + normals[ic]
		votes += signf(cross.dot(n))
	return 1.0 if votes > 0.0 else -1.0

## Lentes do carro em componentes ligados, no espaço do modelo: farol (frente), lanterna (trás) e âmbar
## existente (só para não pôr uma seta em cima de outra).
func _collect(model: Node3D) -> Array:
	var result: Array = []
	_others = []
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh == null or part.has_meta("wheel_center") or part.has_meta(META): continue
		var xf := _to_model(model, part)
		var normal_xf := xf.basis.inverse().transposed()
		for surface in part.mesh.get_surface_count():
			var role := ROLES.key(part, surface)
			var material := part.get_active_material(surface) as StandardMaterial3D
			var kind := ""
			if ROLES.is_tail_lens(role): kind = "tail"
			elif ROLES.is_headlight_lens(role): kind = "head"
			elif role.get_slice("#", 0) in ["lens", "amber", "amber_turn", "indicator"] and material != null:
				var c := material.albedo_color
				if c.s > .45 and c.h > .04 and c.h < .17: kind = "amber"
			if kind.is_empty():
				if role.get_slice("#", 0) not in ["bar_left", "bar_right"]: _others.append(_faces_of(part, surface, xf, role))
				continue
			var arrays := part.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals = arrays[Mesh.ARRAY_NORMAL]
			var indices = arrays[Mesh.ARRAY_INDEX]
			var count: int = indices.size() if indices != null else vertices.size()
			var tris: Array = []
			for i in range(0, count - 2, 3):
				var ids := [indices[i], indices[i + 1], indices[i + 2]] if indices != null else [i, i + 1, i + 2]
				var p: Array = []
				var vn := Vector3.ZERO
				for j in ids:
					p.append(xf * vertices[j])
					if normals != null: vn += normal_xf * (normals[j] as Vector3)
				var cross: Vector3 = (p[1] - p[0]).cross(p[2] - p[0])
				if cross.length() < 1e-9: continue
				var n := cross.normalized()
				if vn.length() > 1e-6 and n.dot(vn) < 0.0:
					n = -n
					p = [p[0], p[2], p[1]]
				tris.append({"p": p, "n": n})
			for group in _components(tris):
				var comp := _analyze(group, kind, part)
				if not comp.is_empty(): result.append(comp)
	return result

func _faces_of(part: MeshInstance3D, surface: int, xf: Transform3D, role: String) -> Dictionary:
	var arrays := part.mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	var count: int = indices.size() if indices != null else vertices.size()
	for i in range(0, count - 2, 3):
		for j in 3: faces.append(xf * vertices[indices[i + j] if indices != null else i + j])
	var box := AABB(faces[0], Vector3.ZERO) if not faces.is_empty() else AABB()
	for f in faces: box = box.expand(f)
	var base := role.get_slice("#", 0)
	var cls := "paint" if base in ["paint", "roof_paint"] else ("glass" if "glass" in base else "trim")
	return {"faces": faces, "box": box, "cls": cls}

func _components(tris: Array) -> Array:
	var parent := range(tris.size())
	var owner_of := {}
	var find := func(i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i
	for i in tris.size():
		for p in tris[i].p:
			var k := _key(p)
			if owner_of.has(k):
				var a: int = find.call(i)
				var b: int = find.call(owner_of[k])
				if a != b: parent[a] = b
			else: owner_of[k] = i
	var groups := {}
	for i in tris.size():
		var root: int = find.call(i)
		if not groups.has(root): groups[root] = []
		groups[root].append(tris[i])
	return groups.values()

## Face visível da lente (patch), base local (U lateral, V "para cima" no plano da lente) e limites.
func _analyze(tris: Array, kind: String, part: MeshInstance3D) -> Dictionary:
	var box := AABB(tris[0].p[0], Vector3.ZERO)
	for t in tris:
		for p in t.p: box = box.expand(p)
	var center := box.get_center()
	if kind == "tail" and center.z <= 0.0: return {}
	if kind == "head" and center.z >= 0.0: return {}
	# Face que olha para fora pela ponta do carro; farol deitado no capô (escamoteável, bicudo) olha para cima.
	var end := 1.0 if center.z > 0.0 else -1.0
	var sum := Vector3.ZERO
	for out in [Vector3(0, 0, end), Vector3(0, .7, .7 * end).normalized(), Vector3.UP]:
		for t in tris:
			if t.n.dot(out) > .2: sum += t.n * _area(t)
		if sum.length() > 1e-6: break
	if sum.length() < 1e-6: return {}
	var normal := sum.normalized()
	var patch: Array = []
	for t in tris:
		if t.n.dot(normal) > .55: patch.append(t)
	if patch.is_empty(): return {}
	var u_axis := (Vector3.RIGHT - normal * Vector3.RIGHT.dot(normal)).normalized()
	var v_axis := normal.cross(u_axis)
	if v_axis.y < 0.0: v_axis = -v_axis
	var u0 := INF
	var u1 := -INF
	var v0 := INF
	var v1 := -INF
	var area := 0.0
	for t in patch:
		area += _area(t)
		t.uv = []
		for p in t.p:
			var uv := Vector2(p.dot(u_axis), p.dot(v_axis))
			t.uv.append(uv)
			u0 = minf(u0, uv.x)
			u1 = maxf(u1, uv.x)
			v0 = minf(v0, uv.y)
			v1 = maxf(v1, uv.y)
	# Peças minúsculas (refletor de 2 cm) não ganham detalhe; ficam como estão.
	if area < .0006 or u1 - u0 < .035 or v1 - v0 < .02: return {}
	var lo := INF
	var hi := -INF
	for t in tris:
		for p in t.p:
			lo = minf(lo, p.dot(normal))
			hi = maxf(hi, p.dot(normal))
	var flat := true
	for t in patch: flat = flat and t.n.dot(normal) > .998
	var comp := {"kind": kind, "part": part, "tris": tris, "patch": patch, "N": normal, "U": u_axis, "V": v_axis,
		"u0": u0, "u1": u1, "v0": v0, "v1": v1, "center": center, "box": box, "depth": hi - lo, "area": area, "flat": flat}
	comp.loops = _loops(comp)
	comp.convex = comp.loops.size() == 1 and _convex(comp.loops[0].pts, u_axis, v_axis)
	return comp

## Contornos da face visível (arestas de um triângulo só), orientados com o interior à esquerda vista de fora,
## e simplificados (Douglas-Peucker a 2 mm): o farol redondo de 24 lados vira ~12 e a moldura custa a metade.
func _loops(comp: Dictionary) -> Array:
	var edges := {}
	var normals := {}
	for t in comp.patch:
		for i in 3:
			var a: Vector3 = t.p[i]
			var b: Vector3 = t.p[(i + 1) % 3]
			edges[[_key(a), _key(b)]] = [a, b]
			var k := _key(a)
			normals[k] = (normals.get(k, Vector3.ZERO) as Vector3) + t.n
	var next := {}
	for pair in edges:
		if not edges.has([pair[1], pair[0]]): next[pair[0]] = [pair[1], edges[pair][0]]
	var loops: Array = []
	var used := {}
	for start in next:
		if used.has(start): continue
		var pts: Array = []
		var nrm: Array = []
		var k = start
		while not used.has(k) and next.has(k):
			used[k] = true
			pts.append(next[k][1])
			nrm.append((normals[k] as Vector3).normalized())
			k = next[k][0]
		if pts.size() >= 3: loops.append(_decimate({"pts": pts, "nrm": nrm}, comp.U, comp.V))
	return loops

static func _decimate(loop: Dictionary, u_axis: Vector3, v_axis: Vector3) -> Dictionary:
	var pts: Array = loop.pts
	var count := pts.size()
	if count <= 4: return loop
	var uv: Array = []
	for p in pts: uv.append(Vector2(p.dot(u_axis), p.dot(v_axis)))
	var far := 0
	var best := -1.0
	for i in count:
		var d: float = (uv[i] as Vector2).distance_to(uv[0])
		if d > best:
			best = d
			far = i
	var keep := {0: true, far: true}
	_dp(uv, 0, far, keep)
	_dp(uv, far, count, keep)
	var kept_pts: Array = []
	var kept_nrm: Array = []
	for i in count:
		if keep.has(i):
			kept_pts.append(pts[i])
			kept_nrm.append(loop.nrm[i])
	return {"pts": kept_pts, "nrm": kept_nrm}

static func _dp(uv: Array, a: int, b: int, keep: Dictionary) -> void:
	var count := uv.size()
	if b - a < 2: return
	var pa: Vector2 = uv[a % count]
	var pb: Vector2 = uv[b % count]
	var worst := -1.0
	var index := -1
	for i in range(a + 1, b):
		var q: Vector2 = uv[i % count]
		var d := Geometry2D.get_closest_point_to_segment(q, pa, pb).distance_to(q)
		if d > worst:
			worst = d
			index = i
	if worst > .002:
		keep[index % count] = true
		_dp(uv, a, index, keep)
		_dp(uv, index, b, keep)

static func _convex(pts: Array, u_axis: Vector3, v_axis: Vector3) -> bool:
	var sign := 0.0
	var count := pts.size()
	for i in count:
		var a := Vector2((pts[i] as Vector3).dot(u_axis), (pts[i] as Vector3).dot(v_axis))
		var b := Vector2((pts[(i + 1) % count] as Vector3).dot(u_axis), (pts[(i + 1) % count] as Vector3).dot(v_axis))
		var c := Vector2((pts[(i + 2) % count] as Vector3).dot(u_axis), (pts[(i + 2) % count] as Vector3).dot(v_axis))
		var turn := (b - a).cross(c - b)
		if absf(turn) < 1e-7: continue
		if sign == 0.0: sign = signf(turn)
		elif signf(turn) != sign: return false
	return true

## O que já existe em volta da lente: moldura de acabamento rente à borda (os esportivos 2.0 já assam uma) e
## detalhe por cima da face (faixa de LED, seta). Já desenhado = este passe não repete, para não brigar em
## profundidade com o que o construtor fez.
func _survey(comp: Dictionary, style: Dictionary) -> Dictionary:
	var zone: AABB = (comp.box as AABB).grow(.07)
	var near: Array = []
	for entry in _others:
		if not (entry.box as AABB).intersects(zone): continue
		var kept := PackedVector3Array()
		var faces: PackedVector3Array = entry.faces
		for i in range(0, faces.size(), 3):
			var tb := AABB(faces[i], Vector3.ZERO).expand(faces[i + 1]).expand(faces[i + 2])
			if tb.intersects(zone):
				kept.append(faces[i])
				kept.append(faces[i + 1])
				kept.append(faces[i + 2])
		if not kept.is_empty(): near.append({"faces": kept, "cls": entry.cls})
	var n: Vector3 = comp.N
	var framed := 0
	var samples := 0
	for loop in comp.loops:
		var count: int = loop.pts.size()
		for i in range(0, count, maxi(1, count / 12)):
			var a: Vector3 = loop.pts[i]
			var b: Vector3 = loop.pts[(i + 1) % count]
			var outward: Vector3 = (b - a).cross(loop.nrm[i]).normalized()
			var probe: Vector3 = (a + b) * .5 + outward * maxf(float(style.w_out) * .6, .007)
			var hit := _ray(probe + n * .03, -n, near, .08)
			samples += 1
			if not hit.is_empty() and hit.cls == "trim" and absf(float(hit.d) - .03) < .015: framed += 1
	var covered := 0
	for i in 5:
		for j in 3:
			var at := _surface(comp, lerpf(comp.u0, comp.u1, (i + .5) / 5.0), lerpf(comp.v0, comp.v1, (j + .5) / 3.0))
			if at.is_empty(): continue
			var hit := _ray(at[0] + at[1] * .03, -(at[1] as Vector3), near, .06)
			if not hit.is_empty() and hit.cls == "trim" and float(hit.d) < .0295 and float(hit.d) > .018: covered += 1
	return {"has_bezel": samples > 0 and framed >= samples * .6, "has_inner": covered >= 2, "framed": framed, "samples": samples, "covered": covered}

static func _ray(origin: Vector3, direction: Vector3, near: Array, limit: float) -> Dictionary:
	var best := {}
	var best_d := limit
	for entry in near:
		var faces: PackedVector3Array = entry.faces
		for i in range(0, faces.size(), 3):
			var hit = Geometry3D.ray_intersects_triangle(origin, direction, faces[i], faces[i + 1], faces[i + 2])
			if hit == null: continue
			var d := origin.distance_to(hit)
			if d < best_d:
				best_d = d
				best = {"d": d, "cls": entry.cls}
	return best

static func _describe(comps: Array) -> Array:
	var rows: Array = []
	for comp in comps:
		rows.append({"kind": comp.kind, "part": str(comp.part.name), "center": [snappedf(comp.center.x, .001), snappedf(comp.center.y, .001), snappedf(comp.center.z, .001)],
			"w": snappedf(comp.u1 - comp.u0, .001), "h": snappedf(comp.v1 - comp.v0, .001), "depth": snappedf(comp.depth, .001),
			"patch_tris": comp.patch.size(), "tris": comp.tris.size(), "normal": [snappedf(comp.N.x, .01), snappedf(comp.N.y, .01), snappedf(comp.N.z, .01)],
			"flat": comp.flat, "convex": comp.convex, "loop_points": comp.loops.map(func(l): return l.pts.size()), "survey": comp.get("survey", {})})
	return rows

static func _area(t: Dictionary) -> float:
	return (t.p[1] - t.p[0]).cross(t.p[2] - t.p[0]).length() * .5

func _host(comps: Array, left_first: bool) -> MeshInstance3D:
	var best: MeshInstance3D = null
	var best_score := -INF
	for comp in comps:
		var score: float = comp.area + (1.0 if left_first and comp.center.x < 0.0 else 0.0)
		if score > best_score:
			best_score = score
			best = comp.part
	return best

func _sink(sinks: Dictionary, host: MeshInstance3D) -> Dictionary:
	# Array comum: PackedArray dentro de dicionário é cópia por valor e o append se perderia.
	if not sinks.has(host): sinks[host] = {"pos": [], "nrm": [], "col": []}
	return sinks[host]

# --------------------------------------------------------------------------------------------- detalhe

func _decorate(comp: Dictionary, family: String, ambers: Array, sink: Dictionary) -> void:
	var style: Dictionary = STYLE[family]
	if not comp.has("survey"): comp.survey = _survey(comp, style)
	if _level < 4 and not comp.survey.has_bezel: _bezel(comp, style, sink)
	if comp.survey.has_inner: return
	var halves: Array = []
	# Lente única que atravessa o meio (barra de LED): cada metade recebe o desenho espelhado.
	if comp.u0 < -.05 and comp.u1 > .05:
		halves.append({"inner": 0.0, "outer": comp.u1, "split": true})
		halves.append({"inner": 0.0, "outer": comp.u0, "split": true})
	else:
		var right: bool = comp.center.x >= 0.0
		halves.append({"inner": comp.u0 if right else comp.u1, "outer": comp.u1 if right else comp.u0, "split": false})
	for half in halves:
		half.W = absf(half.outer - half.inner)
		half.H = comp.v1 - comp.v0
		half.amber_near = _amber_near(comp, half, ambers)
		for op in _layout(family, comp.kind, half): _apply(comp, half, style, op, sink)

func _amber_near(comp: Dictionary, half: Dictionary, ambers: Array) -> bool:
	var side := signf(half.outer)
	for amber in ambers:
		var c: Vector3 = amber.center
		if signf(c.z) != signf(comp.center.z) or (side != 0.0 and signf(c.x) != side): continue
		if absf(c.x - (comp.center.x if not half.split else half.outer * .7)) < .45 and absf(c.y - comp.center.y) < .35 and absf(c.z - comp.center.z) < .3: return true
	return false

## Desenho de cada família em coordenadas da metade da lente: s de dentro (0, lado do meio do carro) para
## fora (1); t de baixo (0) para cima (1). "cell" pinta a região, "vline"/"hline" são travessas, "disc" é
## refletor/projetor redondo (aro + miolo), com raio relativo à altura da lente.
func _layout(family: String, kind: String, half: Dictionary) -> Array:
	var ops: Array = []
	var wide: bool = half.W > half.H * 1.7
	var tall: bool = half.H > half.W * 1.15
	if kind == "head":
		match family:
			"sport":
				ops.append(["cell", 0.0, 1.0, 0.0, .26, SMOKE])
				ops.append(["hline", .26])
				if wide:
					ops.append(["disc", .30, .63, .30, GRAPHITE, CHROME])
					ops.append(["disc", .64, .63, .30, GRAPHITE, CHROME])
				else: ops.append(["disc", .45, .63, .30, GRAPHITE, CHROME])
				if not half.amber_near:
					ops.append(["cell", .88, 1.0, .26, 1.0, AMBER])
					ops.append(["vline", .88])
			"sedan":
				if not half.amber_near:
					ops.append(["cell", .78, 1.0, 0.0, 1.0, AMBER])
					ops.append(["vline", .78])
				ops.append(["disc", .38 if not half.amber_near else .5, .5, .38, SATIN, CHROME])
			"utility":
				if wide:
					ops.append(["disc", .27, .5, .42, CHROME, CHROME])
					ops.append(["disc", .70, .5, .42, CHROME, CHROME])
					if not half.amber_near:
						ops.append(["cell", .88, 1.0, 0.0, 1.0, AMBER])
						ops.append(["vline", .88])
				else: ops.append(["disc", .5, .5, .44, CHROME, CHROME])
			"service":
				if wide:
					ops.append(["vline", .5])
					ops.append(["disc", .25, .5, .36, CHROME, CHROME])
					ops.append(["disc", .75, .5, .36, CHROME, CHROME])
				else:
					ops.append(["hline", .5])
					ops.append(["disc", .5, .75, .2, CHROME, CHROME])
			"classic":
				if wide:
					ops.append(["disc", .26, .5, .44, CHROME, CHROME])
					ops.append(["vline", .52])
					ops.append(["disc", .76, .5, .44, CHROME, CHROME])
				else: ops.append(["disc", .5, .5, .40, CHROME, CHROME])
	else:
		match family:
			"sport":
				ops.append(["cell", 0.0, .16, 0.0, 1.0, REVERSE])
				ops.append(["vline", .16])
				ops.append(["hline", .36])
				ops.append(["hline", .66])
			"sedan":
				ops.append(["cell", 0.0, .22, 0.0, 1.0, REVERSE])
				ops.append(["vline", .22])
				if not half.amber_near:
					ops.append(["cell", .72, 1.0, 0.0, 1.0, AMBER])
					ops.append(["vline", .72])
			"utility", "service":
				if tall:
					ops.append(["cell", 0.0, 1.0, 0.0, .30, REVERSE])
					ops.append(["hline", .30])
					if not half.amber_near:
						ops.append(["cell", 0.0, 1.0, .30, .62, AMBER])
						ops.append(["hline", .62])
				else:
					ops.append(["cell", 0.0, .24, 0.0, 1.0, REVERSE])
					ops.append(["vline", .24])
					if not half.amber_near:
						ops.append(["cell", .70, 1.0, 0.0, 1.0, AMBER])
						ops.append(["vline", .70])
			"classic":
				ops.append(["cell", 0.0, .18, 0.0, 1.0, REVERSE])
				ops.append(["vline", .18])
				if half.W < half.H * 1.4: ops.append(["disc", .58, .5, .30, CHROME, CHROME])
				else: ops.append(["hline", .5])
	return ops

func _apply(comp: Dictionary, half: Dictionary, style: Dictionary, op: Array, sink: Dictionary) -> void:
	var w_in: float = style.w_in
	var line: float = style.line
	var u_of := func(s: float) -> float: return lerpf(half.inner, half.outer, s)
	var v_of := func(t: float) -> float: return lerpf(comp.v0, comp.v1, t)
	# Recorte por dentro da moldura (as bordas do meio de uma barra não são borda da lente).
	var ulo: float = comp.u0 + w_in
	var uhi: float = comp.u1 - w_in
	var vlo: float = comp.v0 + w_in
	var vhi: float = comp.v1 - w_in
	match op[0]:
		"cell":
			var a: float = u_of.call(op[1])
			var b: float = u_of.call(op[2])
			_cell(comp, maxf(minf(a, b), ulo), minf(maxf(a, b), uhi), maxf(v_of.call(op[3]), vlo), minf(v_of.call(op[4]), vhi), op[5], EPS_CELL, sink)
		"vline":
			var u: float = u_of.call(op[1])
			_cell(comp, maxf(u - line * .5, ulo), minf(u + line * .5, uhi), vlo, vhi, style.line_color, EPS_LINE, sink)
		"hline":
			var v: float = v_of.call(op[1])
			var a: float = u_of.call(0.0)
			var b: float = u_of.call(1.0)
			_cell(comp, maxf(minf(a, b), ulo), minf(maxf(a, b), uhi), maxf(v - line * .5, vlo), minf(v + line * .5, vhi), style.line_color, EPS_LINE, sink)
		"disc":
			if _level >= 2: return
			var radius: float = minf(float(op[3]) * half.H, half.W * .45)
			var segments := 10 if _level == 0 and radius > .035 else 6
			_disc(comp, u_of.call(op[1]), v_of.call(op[2]), radius, op[4], op[5], segments, sink)

## Moldura: faixa ao longo do contorno simplificado da face visível (por dentro w_in, por fora w_out, cantos em
## meia-esquadria) e, nas lentes em caixa, saia do aro externo até a carroceria cobrindo a lateral acesa.
func _bezel(comp: Dictionary, style: Dictionary, sink: Dictionary) -> void:
	var w_in: float = style.w_in
	var w_out: float = style.w_out
	var skirt: bool = _level < 3 and comp.flat and comp.depth >= .004
	var down: Vector3 = comp.N * clampf(comp.depth + .006, .006, .07)
	for loop in comp.loops:
		var pts: Array = loop.pts
		var count := pts.size()
		var outs: Array = []
		for i in count:
			outs.append(((pts[(i + 1) % count] as Vector3) - (pts[i] as Vector3)).cross(loop.nrm[i]).normalized())
		var inner: Array = []
		var outer: Array = []
		for i in count:
			var o1: Vector3 = outs[(i - 1 + count) % count]
			var o2: Vector3 = outs[i]
			var m := (o1 + o2).normalized() if (o1 + o2).length() > 1e-4 else o2
			var scale := 1.0 / maxf(m.dot(o2), .5)
			var n: Vector3 = loop.nrm[i]
			inner.append((pts[i] as Vector3) - m * w_in * scale + n * EPS_RING)
			outer.append((pts[i] as Vector3) + m * w_out * scale + n * EPS_RING)
		for i in count:
			var j := (i + 1) % count
			_quad(sink, inner[i], outer[i], outer[j], inner[j], ((loop.nrm[i] as Vector3) + (loop.nrm[j] as Vector3)).normalized(), style.bezel)
			if skirt: _quad(sink, outer[i], outer[j], (outer[j] as Vector3) - down, (outer[i] as Vector3) - down, outs[i], style.bezel)

## Região [umin,umax]×[vmin,vmax] recortada nos triângulos reais da face (segue lente curva ou redonda).
func _cell(comp: Dictionary, umin: float, umax: float, vmin: float, vmax: float, color: Color, eps: float, sink: Dictionary) -> void:
	if umax - umin < .003 or vmax - vmin < .003: return
	if comp.flat and comp.convex:
		var outline: Array = comp.loops[0].pts.duplicate()
		outline = _clip(outline, comp.U, umin, true)
		outline = _clip(outline, comp.U, umax, false)
		outline = _clip(outline, comp.V, vmin, true)
		outline = _clip(outline, comp.V, vmax, false)
		if outline.size() < 3: return
		var up: Vector3 = comp.N * eps
		for i in range(1, outline.size() - 1):
			_tri(sink, outline[0] + up, outline[i] + up, outline[i + 1] + up, comp.N, color)
		return
	for t in comp.patch:
		var poly: Array = [t.p[0], t.p[1], t.p[2]]
		poly = _clip(poly, comp.U, umin, true)
		poly = _clip(poly, comp.U, umax, false)
		poly = _clip(poly, comp.V, vmin, true)
		poly = _clip(poly, comp.V, vmax, false)
		if poly.size() < 3: continue
		var lift: Vector3 = t.n * eps
		for i in range(1, poly.size() - 1):
			_tri(sink, poly[0] + lift, poly[i] + lift, poly[i + 1] + lift, t.n, color)

static func _clip(poly: Array, axis: Vector3, limit: float, keep_above: bool) -> Array:
	var result: Array = []
	var sign := 1.0 if keep_above else -1.0
	for i in poly.size():
		var a: Vector3 = poly[i]
		var b: Vector3 = poly[(i + 1) % poly.size()]
		var da := (a.dot(axis) - limit) * sign
		var db := (b.dot(axis) - limit) * sign
		if da >= 0.0: result.append(a)
		if (da >= 0.0) != (db >= 0.0): result.append(a.lerp(b, da / (da - db)))
	return result

## Ponto da face da lente em (u, v), com a normal do triângulo; vazio se cair fora da face.
static func _surface(comp: Dictionary, u: float, v: float) -> Array:
	var q := Vector2(u, v)
	for t in comp.patch:
		var a: Vector2 = t.uv[0]
		var b: Vector2 = t.uv[1]
		var c: Vector2 = t.uv[2]
		var d := (b - a).cross(c - a)
		if absf(d) < 1e-10: continue
		var w1 := (q - a).cross(c - a) / d
		var w2 := (b - a).cross(q - a) / d
		if w1 < -1e-4 or w2 < -1e-4 or w1 + w2 > 1.0 + 1e-4: continue
		return [t.p[0] + (t.p[1] - t.p[0]) * w1 + (t.p[2] - t.p[0]) * w2, t.n]
	return []

## Refletor redondo: aro (cor `ring`) e miolo (cor `dot`), projetados ponto a ponto na face da lente.
## Se não couber dentro da face e da moldura, encolhe até 3 vezes e desiste.
func _disc(comp: Dictionary, uc: float, vc: float, radius: float, ring: Color, dot: Color, segments: int, sink: Dictionary) -> void:
	for attempt in 4:
		if radius < .012: return
		var inner := radius * .72
		var dot_r := radius * .22
		var rings: Array = []
		var ok := true
		for i in segments:
			var angle := TAU * i / segments
			var dir := Vector2(cos(angle), sin(angle))
			var o := _surface(comp, uc + dir.x * radius, vc + dir.y * radius)
			var n := _surface(comp, uc + dir.x * inner, vc + dir.y * inner)
			var d := _surface(comp, uc + dir.x * dot_r, vc + dir.y * dot_r)
			# A moldura cobre a borda: o aro tem que caber por dentro dela.
			var edge_ok: bool = uc + dir.x * radius >= comp.u0 + .006 and uc + dir.x * radius <= comp.u1 - .006 and vc + dir.y * radius >= comp.v0 + .006 and vc + dir.y * radius <= comp.v1 - .006
			if o.is_empty() or n.is_empty() or d.is_empty() or not edge_ok:
				ok = false
				break
			rings.append([o, n, d])
		var center := _surface(comp, uc, vc)
		if ok and not center.is_empty():
			for i in segments:
				var a: Array = rings[i]
				var b: Array = rings[(i + 1) % segments]
				_quad(sink, a[1][0] + a[1][1] * EPS_DISC, a[0][0] + a[0][1] * EPS_DISC, b[0][0] + b[0][1] * EPS_DISC, b[1][0] + b[1][1] * EPS_DISC, center[1], ring)
				_tri(sink, center[0] + center[1] * EPS_DOT, a[2][0] + a[2][1] * EPS_DOT, b[2][0] + b[2][1] * EPS_DOT, center[1], dot)
			return
		radius *= .82

# ------------------------------------------------------------------------------------------ montagem

func _tri(sink: Dictionary, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length() < 1e-10: return
	# Mesma ordem de vértices que o acabamento do carro usa para a face da frente.
	if signf(cross.dot(facing)) != _winding:
		var swap := b
		b = c
		c = swap
	var linear := color if _srgb else color.srgb_to_linear()
	var n := facing.normalized()
	for p in [a, b, c]:
		(sink.pos as Array).append(p)
		(sink.nrm as Array).append(n)
		(sink.col as Array).append(linear)

func _quad(sink: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, color: Color) -> void:
	_tri(sink, a, b, c, facing, color)
	_tri(sink, a, c, d, facing, color)

## Malha no espaço do nó anfitrião, montada como o FleetBatchMesh monta a frota (mesmo formato de vértice).
func _commit(sink: Dictionary, model: Node3D, host: MeshInstance3D, material: Material) -> ArrayMesh:
	var to_host := _to_model(model, host).affine_inverse()
	var normal_xf := to_host.basis.inverse().transposed()
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pos: Array = sink.pos
	var nrm: Array = sink.nrm
	var col: Array = sink.col
	for i in pos.size():
		var local: Vector3 = to_host * (pos[i] as Vector3)
		tool.set_normal((normal_xf * (nrm[i] as Vector3)).normalized())
		tool.set_uv(Vector2((pos[i] as Vector3).x, (pos[i] as Vector3).y))
		tool.set_color(col[i])
		tool.add_vertex(local)
	tool.index()
	tool.set_material(material)
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	mesh.resource_name = "LampDetail"
	return mesh

static func _assign_owner(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		if child.owner == null: child.owner = owner_node
		_assign_owner(child, owner_node)
