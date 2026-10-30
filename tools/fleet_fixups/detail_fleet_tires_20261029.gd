extends SceneTree
## Detalhe dos pneus da frota redesenhada (pedido do jogador, 29/10/2026: "veja os pneus também: pneus diferentes,
## com escrita em alguns, nos carros de corrida"). O pneu é peça do .scn (nós Wheel_*/ServiceWheel_* com
## `wheel_center`, que o Vehicle.gd pendura num pivô e gira); nada dele é gerado em código no jogo.
##
## O que muda: só a superfície que já desenha o pneu ganha triângulos no FLANCO DE FORA (e nada na posição,
## bitola, raio ou eixo: centro, `wheel_center`, transformação do nó e vértices existentes ficam idênticos).
## - esportivo: borda do aro avançando no flanco (perfil baixo) e escrita clara no flanco;
## - muscle: escrita branca em relevo (o "raised white letters" dos muscle cars);
## - sedã/serviço leve: friso fino claro no flanco e talão escuro junto ao aro;
## - utilitário/off-road (jipes, picapes, SUVs, vans, buggies): cravos em relevo no ombro do flanco;
## - caminhão: friso e blocos chapados no ombro;
## - clássico: faixa branca (pulada se o modelo já assou uma, como os lowriders).
##
## Por que assim (custo no jogo): a geometria entra na MESMA superfície e no MESMO material com cor por vértice do
## pneu (zero desenho a mais, zero material novo, formato de vértice idêntico, conferido superfície a
## superfície; formato novo seria pipeline nova no jogo, runtime/FormatPrewarm.gd). A escrita é de quadradinhos
## de cor (fonte 3x5), não textura: textura pediria um material novo com textura e pré-aquecimento próprio nos
## formatos das rodas, e a 30 m a escrita só é lida de perto de qualquer jeito. Teto de +8% de triângulos por carro
## (desce de nível: menos segmentos, uma escrita só, sem borda de aro).
## O amassado e o recorte de porta já pulam as rodas; o estouro de pneu escala o pivô, então o detalhe murcha junto.
##
## Rodar de novo não duplica: o nó guarda em `fleet_tire_detail` quantos vértices/índices a superfície tinha antes,
## e a parte acrescentada é trocada.
## Uso (fila única; padrão = cópias em artifacts):
##   tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/detail_fleet_tires_20261029.gd -- \
##     [--dir=res://assets/fleet/redesigned] [--ids=a,b] [--dry] [--label=x]
const VERSION := "20261029"
const META := "fleet_tire_detail"
const DEFAULT_DIR := "res://artifacts/fleet-lamps-20261029/scn"
const REPORT_DIR := "res://artifacts/fleet-lamps-20261029"
const MAX_RATIO := .08
const LAYOUT_MASK := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TANGENT | Mesh.ARRAY_FORMAT_COLOR \
	| Mesh.ARRAY_FORMAT_TEX_UV | Mesh.ARRAY_FORMAT_TEX_UV2 | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 \
	| Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3 | Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS \
	| Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
const FLAG_MASK := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES | Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE \
	| Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS | Mesh.ARRAY_FLAG_USES_EMPTY_VERTEX_ARRAY

const TIRE_IDS := {
	"sport": ["tauro_v10", "raijin_gt", "kite_type_s", "lince_rs", "brisa_s", "sakura_s15", "rapina_r", "supra_a80",
		"vertice_midengine", "porto_rosso", "desert_mirage", "desert_mirage_gt", "monaliza", "jessica_jetta_gli",
		"rauhz_focus_mk1", "desert_faisca_rally", "sport_estate"],
	"muscle": ["potro_68", "jararaca_v10", "carcara_ss", "trovao_440", "caiman_454", "brasa_hc", "cobra_v8",
		"cobra_boss_ironback", "muscle_classic", "desert_coyote", "desert_coyote_drag"],
	"sedan": ["aurora_executive", "union_sedan", "taxi_yellow", "metro_hatch", "orbita_micro", "nordic_estate",
		"station_wagon", "vale_crossover", "beach_cabriolet", "desert_faisca", "desert_siroco", "digo_gol_1993",
		"police_cruiser", "police_suv", "police_transport", "medic_box"],
	"utility": ["arctic_jeep", "desert_jeep_4x4", "atlas_crew_pickup", "bravio_crew", "ranch_pickup", "ranch_single",
		"sertao_trail_pickup", "lumber_pickup_4x4", "digo_amarok_2014", "summit_suv", "winter_suv_heavy", "courier_van",
		"polar_van", "dock_delivery_van", "nimbus_minivan", "mare_microvan", "toco_minitruck", "beach_buggy", "dune_buggy",
		"desert_bison"],
	"truck": ["rescue_pumper", "towmaster", "armored_truck", "snow_plow_truck", "boxrunner", "cargo_flatbed_truck",
		"american_dump_truck", "american_tanker_truck"],
	"classic": ["bastiao_63", "imperador_64", "imperador_64_conv", "monte_rei_84", "duque_76", "besouro_1300",
		"sedan_classic", "surf_woody_wagon"],
}
## Carros de corrida do deserto com letra amarela (o resto da escrita é branca).
const YELLOW_LETTERS := ["desert_faisca_rally", "desert_coyote_drag", "desert_mirage_gt"]
const WORD := "GETECO"
## Fonte 3x5 (linha 0 em cima). Só as letras da palavra.
const GLYPHS := {
	"G": [".##", "#..", "#.#", "#.#", ".##"],
	"E": ["###", "#..", "##.", "#..", "###"],
	"T": ["###", ".#.", ".#.", ".#.", ".#."],
	"C": [".##", "#..", "#..", "#..", ".##"],
	"O": [".#.", "#.#", "#.#", "#.#", ".#."],
}
const WHITE := Color("ecebe4")
const YELLOW := Color("f0c23a")
const RIB := Color("50575c")
const BEAD := Color("131618")
const LUG := Color("3b4247")
const WALL := Color("e6e3d8")
const SATIN := Color("aeb6ba")
const EPS := .0022

var dir := DEFAULT_DIR
var dry := false
var label := ""
var _winding := -1.0
var _srgb := true
var _level := 0

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
	var report := {}
	var failed := 0
	for id in ids:
		var row := process(id)
		report[id] = row
		if row.get("status", "") == "error": failed += 1
		var short := {}
		for key in ["status", "reason", "family", "level", "wheels", "base_tris", "added_tris", "ratio", "format_ok", "lettered", "skipped_whitewall"]:
			if row.has(key): short[key] = row[key]
		print("TIRE_DETAIL ", id, " ", JSON.stringify(short))
	var name := "tires-%s%s.json" % ["dry-" if dry else "", label if not label.is_empty() else dir.get_file()]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	FileAccess.open(REPORT_DIR + "/" + name, FileAccess.WRITE).store_string(JSON.stringify({"version": VERSION, "dir": dir, "dry": dry, "models": report}, "\t"))
	print("TIRE_DETAIL_DONE models=", report.size(), " failed=", failed, " report=", REPORT_DIR + "/" + name)
	quit(1 if failed > 0 else 0)

static func family_of(id: String) -> String:
	for family in TIRE_IDS:
		if id in TIRE_IDS[family]: return family
	return ""

func process(id: String) -> Dictionary:
	if id.begins_with("bike_"): return {"status": "skipped", "reason": "moto"}
	var family := family_of(id)
	if family.is_empty(): return {"status": "skipped", "reason": "sem família declarada"}
	var path := dir + "/" + id + ".scn"
	# Um modelo por vez, fora do cache.
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if packed == null: return {"status": "error", "reason": "não carregou " + path}
	var model := packed.instantiate() as Node3D
	packed = null
	var row := build(id, family, model)
	if row.status == "ok" and not dry:
		var scene := PackedScene.new()
		var status := scene.pack(model)
		if status == OK: status = ResourceSaver.save(scene, path)
		if status != OK:
			row.status = "error"
			row.reason = "falha ao gravar (%d)" % status
	model.free()
	return row

func build(id: String, family: String, model: Node3D) -> Dictionary:
	var wheels: Array = []
	for child in model.get_children():
		var part := child as MeshInstance3D
		if part == null or not part.has_meta("wheel_center") or not part.get_meta("wheel_spins", true): continue
		if not part.mesh is ArrayMesh or (part.mesh as ArrayMesh).get_blend_shape_count() > 0: continue
		var info := _measure(part)
		if info.is_empty(): continue
		wheels.append(info)
	if wheels.is_empty(): return {"status": "skipped", "reason": "nenhum pneu reconhecido", "family": family}
	var base := 0
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if part.mesh != null: base += part.mesh.get_faces().size() / 3
	# Triângulos acrescentados antes (rodada anterior) não contam como base.
	for info in wheels: base -= int(info.previous_tris)
	var lettered: bool = family in ["sport", "muscle"]
	var letter_color := YELLOW if id in YELLOW_LETTERS else WHITE
	var budget := int(base * MAX_RATIO)
	var added := 0
	var builds: Array = []
	var level := 0
	for attempt in 4:
		_level = attempt
		level = attempt
		builds = []
		added = 0
		for info in wheels:
			var sink := {"pos": [], "nrm": [], "tan": [], "col": []}
			_srgb = info.srgb
			_winding = info.winding
			_decorate(info, family, lettered, letter_color, sink)
			builds.append(sink)
			added += (sink.pos as Array).size() / 3
		if added <= budget: break
	if added > budget: return {"status": "error", "reason": "passa de 8%% mesmo no nível 3 (%d > %d)" % [added, budget], "family": family}
	var format_ok := true
	var rows: Array = []
	for index in wheels.size():
		var info: Dictionary = wheels[index]
		var part: MeshInstance3D = info.part
		var old: ArrayMesh = part.mesh
		var mesh := _rebuild(old, info, builds[index])
		for surface in old.get_surface_count():
			if mesh.surface_get_format(surface) != old.surface_get_format(surface): format_ok = false
		if not format_ok: break
		part.mesh = mesh
		part.set_meta(META, {"version": VERSION, "surface": info.surface, "vertices": info.base_vertices, "indices": info.base_indices})
		rows.append({"wheel": str(part.name), "surface": info.surface, "R": snappedf(info.R, .001), "rim": snappedf(info.rim, .001),
			"side": info.side, "whitewall": info.whitewall, "added": (builds[index].pos as Array).size() / 3})
	if not format_ok: return {"status": "error", "reason": "formato de vértice mudou numa superfície", "family": family}
	return {"status": "ok", "family": family, "level": level, "wheels": wheels.size(), "base_tris": base, "added_tris": added,
		"ratio": snappedf(float(added) / maxf(1.0, base), .0001), "format_ok": format_ok, "lettered": lettered,
		"skipped_whitewall": family == "classic" and wheels[0].whitewall, "detail": rows}

## Centro e eixo no espaço do nó, superfície do pneu (a que tem mais vértices escuros no raio externo), raio
## externo, raio do aro (onde o flanco encontra a roda), perfil do flanco de fora (afastamento lateral por raio).
func _measure(part: MeshInstance3D) -> Dictionary:
	var mesh: ArrayMesh = part.mesh
	var inverse := part.transform.affine_inverse()
	var center: Vector3 = inverse * (part.get_meta("wheel_center") as Vector3)
	var axis := (inverse.basis * Vector3.RIGHT).normalized()
	var side := 1.0 if (part.get_meta("wheel_center") as Vector3).x >= 0.0 else -1.0
	var up := (inverse.basis * Vector3.UP).normalized()
	up = (up - axis * up.dot(axis)).normalized()
	var previous: Dictionary = part.get_meta(META, {})
	var best := {}
	var best_count := 0
	for surface in mesh.get_surface_count():
		var material := part.get_active_material(surface) as StandardMaterial3D
		if material == null or not material.vertex_color_use_as_albedo or mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors = arrays[Mesh.ARRAY_COLOR]
		if colors == null: continue
		var limit := vertices.size()
		if not previous.is_empty() and int(previous.surface) == surface: limit = int(previous.vertices)
		var radius := 0.0
		var dark: Array[int] = []
		for i in limit:
			if _lum(colors[i], material.vertex_color_is_srgb) < .30:
				dark.append(i)
				radius = maxf(radius, _radial(vertices[i], center, axis))
		var count := 0
		for i in dark:
			if _radial(vertices[i], center, axis) > radius * .8: count += 1
		if count > best_count:
			best_count = count
			best = {"surface": surface, "material": material, "arrays": arrays, "dark": dark, "R": radius, "limit": limit}
	if best.is_empty() or best_count < 12: return {}
	var vertices: PackedVector3Array = best.arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = best.arrays[Mesh.ARRAY_COLOR]
	var radius: float = best.R
	# Borracha = as cores escuras que chegam à banda (r ≥ 97% do raio): o miolo escuro do aro (cubo, raios
	# pintados de grafite) tem outra cor e não pode puxar o raio do aro nem o perfil do flanco.
	var rubber := {}
	for i in best.dark:
		if _radial(vertices[i], center, axis) >= radius * .97: rubber[colors[i].to_html()] = true
	var rim := radius
	var bins := {}
	for i in best.dark:
		if not rubber.has(colors[i].to_html()): continue
		var r := _radial(vertices[i], center, axis)
		var w := (vertices[i] - center).dot(axis) * side
		if w <= 0.0 or r < radius * .45: continue
		rim = minf(rim, r)
		var b := roundi(r / .004)
		bins[b] = maxf(float(bins.get(b, -INF)), w)
	if bins.size() < 2 or radius - rim < .03: return {}
	# Faixa branca já assada (lowriders): vértice claro no flanco de fora, entre aro e banda.
	var whitewall := false
	for i in best.limit:
		var r := _radial(vertices[i], center, axis)
		var w := (vertices[i] - center).dot(axis) * side
		if w > 0.0 and r > rim + .005 and r < radius - .01 and _lum(colors[i], best.material.vertex_color_is_srgb) > .70:
			var face_w := _profile(bins, r)
			if absf(w - face_w) < .012: whitewall = true
	var rim_color := _rim_color(part, center, axis, side, rim)
	var indices = best.arrays[Mesh.ARRAY_INDEX]
	var base_indices: int = int(previous.indices) if not previous.is_empty() and int(previous.surface) == best.surface else (indices.size() if indices != null else 0)
	return {"part": part, "surface": best.surface, "center": center, "axis": axis, "up": up, "side": side, "R": radius,
		"rim": rim, "bins": bins, "whitewall": whitewall, "rim_color": rim_color, "srgb": best.material.vertex_color_is_srgb,
		"winding": _measure_winding(best.arrays, best.limit), "base_vertices": best.limit, "base_indices": base_indices,
		"previous_tris": (vertices.size() - int(best.limit)) / 3 if not previous.is_empty() else 0}

static func _lum(color: Color, srgb: bool) -> float:
	var c := color if srgb else color.linear_to_srgb()
	return c.r * .2126 + c.g * .7152 + c.b * .0722

static func _radial(p: Vector3, center: Vector3, axis: Vector3) -> float:
	var d := p - center
	return (d - axis * d.dot(axis)).length()

## Afastamento lateral do flanco de fora no raio r (máximo do compartimento mais próximo, interpolado).
static func _profile(bins: Dictionary, r: float) -> float:
	var keys := bins.keys()
	keys.sort()
	var b := r / .004
	var lo = keys[0]
	var hi = keys[keys.size() - 1]
	for k in keys:
		if k <= b: lo = k
		if k >= b:
			hi = k
			break
	if hi == lo: return float(bins[lo])
	return lerpf(float(bins[lo]), float(bins[hi]), clampf((b - float(lo)) / float(hi - lo), 0.0, 1.0))

## Cor mais comum da roda de fora logo abaixo do aro (a borda do aro avançando no flanco usa a mesma).
func _rim_color(part: MeshInstance3D, center: Vector3, axis: Vector3, side: float, rim: float) -> Color:
	var votes := {}
	for surface in part.mesh.get_surface_count():
		var material := part.get_active_material(surface) as StandardMaterial3D
		if material == null or not material.vertex_color_use_as_albedo: continue
		var arrays := part.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors = arrays[Mesh.ARRAY_COLOR]
		if colors == null: continue
		for i in vertices.size():
			var r := _radial(vertices[i], center, axis)
			if r < rim * .78 or r > rim + .002 or (vertices[i] - center).dot(axis) * side <= 0.0: continue
			var c: Color = colors[i] if material.vertex_color_is_srgb else (colors[i] as Color).linear_to_srgb()
			if c.v < .45: continue
			var key := c.to_html(false)
			votes[key] = int(votes.get(key, 0)) + 1
	var best := ""
	for key in votes:
		if best.is_empty() or votes[key] > votes[best]: best = key
	return Color(best) if not best.is_empty() else SATIN

static func _measure_winding(arrays: Array, limit: int) -> float:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if normals == null: return -1.0
	var votes := 0.0
	var count: int = indices.size() if indices != null else limit
	for i in range(0, count - 2, 3):
		var ia: int = indices[i] if indices != null else i
		var ib: int = indices[i + 1] if indices != null else i + 1
		var ic: int = indices[i + 2] if indices != null else i + 2
		if ia >= limit or ib >= limit or ic >= limit: continue
		var cross := (vertices[ib] - vertices[ia]).cross(vertices[ic] - vertices[ia])
		votes += signf(cross.dot(normals[ia] + normals[ib] + normals[ic]))
	return 1.0 if votes > 0.0 else -1.0

# ------------------------------------------------------------------------------------------- desenho

func _decorate(info: Dictionary, family: String, lettered: bool, letter_color: Color, sink: Dictionary) -> void:
	var rim: float = info.rim
	var height: float = info.R - rim
	var f := func(x: float) -> float: return rim + height * x
	var segments: int = [16, 12, 10, 10][_level]
	match family:
		"sport":
			if _level < 2: _annulus(info, f.call(0.0), f.call(.24), info.rim_color, segments, sink)
		"muscle":
			pass
		"sedan":
			_annulus(info, f.call(.70), f.call(.75), RIB, segments, sink)
			if _level < 2: _annulus(info, f.call(0.0), f.call(.08), BEAD, segments, sink)
		"utility":
			# Nível 3 (buggy de 2,3 mil triângulos): cravo só com o topo.
			_lugs(info, 10 if _level < 2 else 8, f.call(.68), f.call(.97), .007, _level < 3, sink)
		"truck":
			_annulus(info, f.call(.62), f.call(.66), RIB, segments, sink)
			_lugs(info, 14 if _level < 2 else 10, f.call(.78), f.call(.97), .0, false, sink)
		"classic":
			if not info.whitewall: _annulus(info, f.call(.18), f.call(.52), WALL, segments, sink)
	if lettered:
		var base: float = f.call(.40 if family == "muscle" else .38)
		var size: float = height * (.36 if family == "muscle" else .32)
		size = minf(size, info.R - .006 - base)
		_text(info, WORD, base, size, 0.0, letter_color, sink)
		if _level == 0: _text(info, WORD, base, size, PI, letter_color, sink)

## Ponto do flanco de fora em (ângulo, raio): o ângulo parte de "cima" e cresce no sentido de leitura de quem olha
## de fora (para a frente do carro no lado direito, para trás no esquerdo), então a escrita não sai espelhada.
func _at(info: Dictionary, angle: float, r: float, lift := EPS) -> Vector3:
	var axis: Vector3 = info.axis
	var up: Vector3 = info.up
	var reading: Vector3 = -float(info.side) * axis.cross(up)
	var w := _profile(info.bins, r) + lift
	return (info.center as Vector3) + axis * float(info.side) * w + (up * cos(angle) + reading * sin(angle)) * r

func _out(info: Dictionary) -> Vector3:
	return (info.axis as Vector3) * float(info.side)

func _annulus(info: Dictionary, r0: float, r1: float, color: Color, segments: int, sink: Dictionary) -> void:
	# Faixa larga segue o abaulado do flanco com um anel no meio.
	var radii: Array = [r0, r1] if r1 - r0 < .025 else [r0, (r0 + r1) * .5, r1]
	var normal := _out(info)
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		for k in radii.size() - 1:
			_quad(sink, _at(info, a0, radii[k]), _at(info, a1, radii[k]), _at(info, a1, radii[k + 1]), _at(info, a0, radii[k + 1]), normal, color, a0)

## Blocos no ombro do flanco. Em relevo (utilitário): topo e as duas faces que olham no sentido do giro, que são as
## que aparecem de lado e de cima; chapados (caminhão): só o topo, rente ao flanco.
func _lugs(info: Dictionary, count: int, r0: float, r1: float, raise: float, sides: bool, sink: Dictionary) -> void:
	var normal := _out(info)
	var half := PI / count * .46
	for k in count:
		var c := TAU * k / count
		var a0 := c - half
		var a1 := c + half
		var top := EPS + raise
		var t := [_at(info, a0, r0, top), _at(info, a1, r0, top), _at(info, a1, r1, top), _at(info, a0, r1, top)]
		var color := LUG if raise > 0.0 else LUG.darkened(.08)
		_quad(sink, t[0], t[1], t[2], t[3], normal, color, c)
		if sides and raise > 0.0:
			var b := [_at(info, a0, r0), _at(info, a1, r0), _at(info, a1, r1), _at(info, a0, r1)]
			var tangent0: Vector3 = (t[1] - t[0]).normalized()
			_quad(sink, b[0], b[3], t[3], t[0], -tangent0, color.darkened(.15), c)
			_quad(sink, b[1], t[1], t[2], b[2], tangent0, color.darkened(.15), c)

## Palavra em fonte 3x5 ao longo do arco, base no raio `base` e altura `size`; cada letra vira poucos retângulos
## (corridas da linha, emendadas na vertical quando a coluna se repete).
func _text(info: Dictionary, word: String, base: float, size: float, start: float, color: Color, sink: Dictionary) -> void:
	if size < .012: return
	var px := size / 5.0
	var mid := base + size * .5
	var total := (word.length() * 4 - 1) * px
	var normal := _out(info)
	for index in word.length():
		var glyph: Array = GLYPHS.get(word[index], [])
		for rect in _rects(glyph):
			var x0: float = index * 4 * px + rect[0] * px - total * .5
			var x1: float = index * 4 * px + (rect[1] + 1) * px - total * .5
			var top: float = base + (5 - rect[2]) * px
			var bottom: float = base + (5 - rect[3] - 1) * px
			var a0 := start + x0 / mid
			var a1 := start + x1 / mid
			_quad(sink, _at(info, a0, bottom, EPS * 1.4), _at(info, a1, bottom, EPS * 1.4), _at(info, a1, top, EPS * 1.4), _at(info, a0, top, EPS * 1.4), normal, color, a0)

static func _rects(glyph: Array) -> Array:
	var open: Array = []
	var done: Array = []
	for y in glyph.size():
		var row: String = glyph[y]
		var runs: Array = []
		var x := 0
		while x < row.length():
			if row[x] == "#":
				var x1 := x
				while x1 + 1 < row.length() and row[x1 + 1] == "#": x1 += 1
				runs.append([x, x1])
				x = x1 + 1
			else: x += 1
		var still: Array = []
		for rect in open:
			var extended := false
			for run in runs:
				if run[0] == rect[0] and run[1] == rect[1]:
					rect[3] = y
					runs.erase(run)
					extended = true
					break
			if extended: still.append(rect)
			else: done.append(rect)
		for run in runs: still.append([run[0], run[1], y, y])
		open = still
	done.append_array(open)
	return done

# ------------------------------------------------------------------------------------------ montagem

func _tri(sink: Dictionary, a: Vector3, b: Vector3, c: Vector3, facing: Vector3, color: Color, angle: float) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length() < 1e-12: return
	if signf(cross.dot(facing)) != _winding:
		var swap := b
		b = c
		c = swap
	var linear := color if _srgb else color.srgb_to_linear()
	var n := facing.normalized()
	# Tangente ao longo do giro (só para preencher o atributo que o formato já tem).
	var tangent := (b - a).normalized()
	for p in [a, b, c]:
		(sink.pos as Array).append(p)
		(sink.nrm as Array).append(n)
		(sink.tan as Array).append(tangent)
		(sink.col as Array).append(linear)

func _quad(sink: Dictionary, a: Vector3, b: Vector3, c: Vector3, d: Vector3, facing: Vector3, color: Color, angle: float) -> void:
	_tri(sink, a, b, c, facing, color, angle)
	_tri(sink, a, c, d, facing, color, angle)

## Mesma malha, superfície por superfície; só a do pneu recebe os vértices novos no fim (os antigos, os
## índices antigos, materiais e nomes ficam como estavam).
func _rebuild(old: ArrayMesh, info: Dictionary, sink: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.resource_name = old.resource_name
	for surface in old.get_surface_count():
		var arrays := old.surface_get_arrays(surface)
		if surface == info.surface: arrays = _append(arrays, info, sink)
		mesh.add_surface_from_arrays(old.surface_get_primitive_type(surface), arrays, [], {}, old.surface_get_format(surface) & FLAG_MASK)
		mesh.surface_set_material(surface, old.surface_get_material(surface))
		mesh.surface_set_name(surface, old.surface_get_name(surface))
	if old.custom_aabb.has_volume(): mesh.custom_aabb = old.custom_aabb.grow(.02)
	return mesh

func _append(arrays: Array, info: Dictionary, sink: Dictionary) -> Array:
	var keep: int = info.base_vertices
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	vertices = vertices.slice(0, keep)
	var normals = arrays[Mesh.ARRAY_NORMAL]
	var tangents = arrays[Mesh.ARRAY_TANGENT]
	var colors = arrays[Mesh.ARRAY_COLOR]
	var uvs = arrays[Mesh.ARRAY_TEX_UV]
	var uv2s = arrays[Mesh.ARRAY_TEX_UV2]
	var indices = arrays[Mesh.ARRAY_INDEX]
	if normals != null: normals = (normals as PackedVector3Array).slice(0, keep)
	if tangents != null: tangents = (tangents as PackedFloat32Array).slice(0, keep * 4)
	if colors != null: colors = (colors as PackedColorArray).slice(0, keep)
	if uvs != null: uvs = (uvs as PackedVector2Array).slice(0, keep)
	if uv2s != null: uv2s = (uv2s as PackedVector2Array).slice(0, keep)
	if indices != null: indices = (indices as PackedInt32Array).slice(0, int(info.base_indices))
	var pos: Array = sink.pos
	for i in pos.size():
		vertices.append(pos[i])
		if normals != null: normals.append(sink.nrm[i])
		if tangents != null:
			var t: Vector3 = sink.tan[i]
			tangents.append_array(PackedFloat32Array([t.x, t.y, t.z, 1.0]))
		if colors != null: colors.append(sink.col[i])
		if uvs != null: uvs.append(Vector2.ZERO)
		if uv2s != null: uv2s.append(Vector2.ZERO)
		if indices != null: indices.append(keep + i)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	if normals != null: arrays[Mesh.ARRAY_NORMAL] = normals
	if tangents != null: arrays[Mesh.ARRAY_TANGENT] = tangents
	if colors != null: arrays[Mesh.ARRAY_COLOR] = colors
	if uvs != null: arrays[Mesh.ARRAY_TEX_UV] = uvs
	if uv2s != null: arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	if indices != null: arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
