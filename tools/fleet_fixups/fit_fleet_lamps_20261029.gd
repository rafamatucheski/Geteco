extends SceneTree
## Encaixe da frota redesenhada (29/10/2026). Pedido do jogador: "garantir que os carros se
## encaixem, que não tenham lanterna voando ou mal encaixada".
##
## Os modelos de assets/fleet/redesigned/ são malhas juntadas por material: uma lanterna é um
## pedaço (ilha de triângulos ligados) dentro da superfície "tail"/"headlight"/"lens", e um
## retrovisor ou uma placa é um pedaço da superfície "detail". A auditoria antiga
## (audit_tail_lamps.gd) olha um MeshInstance3D por peça, como na frota achatada de
## res://assets/fleet/, e não enxerga nada aqui. Este script:
##  1. separa cada superfície em ilhas (vértices soldados a 1 mm);
##  2. monta o grafo de contato (vão <= 1 cm, ou aresta atravessando triângulo) e acha o que está
##     preso à carroceria a partir da maior ilha de pintura; o resto é peça solta, com o vão
##     medido pelo par de pontos mais próximo;
##  3. para cada lente (farol, lanterna, pisca, giroflex): se a face de fora está coberta por
##     lataria (enterrada) ou no mesmo plano dela (z-fighting), se tem par espelhado do outro
##     lado, se está do lado certo do carro, e onde o VehicleEquipment põe o projetor
##     (SpotLight3D) daquele lado, comparado com a lente de verdade;
##  4. com --fix, encosta a peça solta pela menor translação, tira a lente de dentro da lataria
##     pela normal e grava `headlight_mounts` quando o facho cairia fora do farol. Não deforma
##     nada: só translada ilhas inteiras, então o desenho fica igual.
##
## Uso (sempre pela fila):
##   auditoria (só lê):
##     tools/run_godot_locked.sh --headless --path . --script res://tools/fleet_fixups/fit_fleet_lamps_20261029.gd -- --label=antes
##   correção em cópias (lê os reais, grava as cópias e audita as cópias):
##     ... -- --fix --out=res://artifacts/fleet-fit-20261029/scn/ --label=audit
##   correção no lugar (quem aplica nos reais):
##     ... -- --fix --out=res://assets/fleet/redesigned/ --label=aplicado
##   opções: --src=<pasta res://> (padrão: a frota real), --ids=a,b,c
## Rodar duas vezes não empilha correção: o que já encosta não se move de novo.
## Relatórios em evidence/fleet-fit-20261029/<label>.md e .json (fora do Git, só o .md conta).

const ROLES := preload("res://runtime/VehicleSurfaceRoles.gd")
const SRC_DEFAULT := "res://assets/fleet/redesigned/"
const REPORT_DIR := "res://evidence/fleet-fit-20261029/"
## Vão acima disto é peça solta (o pedido fala em "> 1 cm").
const CONTACT := .01
const CELL := .08
## Acima disto a peça está em outro lugar de propósito ou o modelo precisa de mão: não move.
const FIX_MAX_GAP := .12
## Ao encostar, sobrepõe 1 mm para não sobrar fresta de arredondamento.
const SEAT := .001
## Lente coplanar com a lataria pisca (z-fighting): sai 1,5 mm para fora.
const LENS_LIFT := .0015
const COVER_RAY := .06
## Projetor a mais de 5 cm (no plano da lente) da lente daquele lado = facho fora do farol.
const PROJECTOR_SLACK := .05
## Jipes e picapes: outra sessão refaz as laterais/santantônio do jipe e a tampa da caçamba;
## aqui só lanternas, faróis, retrovisores, placas e para-choques desses modelos.
const RESTRICTED := ["arctic_jeep", "desert_jeep_4x4", "ranch_single", "ranch_pickup", "sertao_trail_pickup", "lumber_pickup_4x4", "atlas_crew_pickup", "digo_amarok_2014"]
const RESTRICTED_CATEGORIES := ["lanterna", "retrovisor", "placa", "para-choque"]
## Roda: face de fora do pneu mais de 1 cm além do para-lama = "espaçador" (pedido do jogador,
## 29/10). Corrige até 12 cm, deixando o pneu 4 mm para dentro da maior largura da lataria em
## volta do arco.
const WHEEL_OUT := .01
const WHEEL_FLUSH := .004
const WHEEL_MAX_SHIFT := .12
## Esterço máximo de Vehicle.gd (clampf(..., -0.48, 0.48)): a roda da frente puxada para dentro
## não pode raspar na caixa de roda girando.
const STEER := .48
const OTHER_LAMP_KEYS := ["lens", "indicator", "amber", "reverse", "marker", "side_marker", "fog", "beacon", "bar_left", "bar_right"]

var src_dir := SRC_DEFAULT
var out_dir := ""
var fix := false
var label := "auditoria"
var only: Array = []

func _initialize() -> void: run.call_deferred()

func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--fix": fix = true
		elif arg.begins_with("--src="): src_dir = _dir(arg.get_slice("=", 1))
		elif arg.begins_with("--out="): out_dir = _dir(arg.get_slice("=", 1))
		elif arg.begins_with("--label="): label = arg.get_slice("=", 1)
		elif arg.begins_with("--ids="): only = Array(arg.get_slice("=", 1).split(",", false))
	if fix and out_dir.is_empty():
		push_error("FIT --fix exige --out=<pasta>")
		quit(2)
		return
	var ids: Array = []
	for file in DirAccess.get_files_at(src_dir):
		if file.ends_with(".scn") and (only.is_empty() or file.get_basename() in only): ids.append(file.get_basename())
	ids.sort()
	if fix: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIR))
	var before_rows: Array = []
	var after_rows: Array = []
	var failures := 0
	var started := Time.get_ticks_msec()
	for id: String in ids:
		var clock := Time.get_ticks_msec()
		var packed := ResourceLoader.load(src_dir + id + ".scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		if packed == null:
			failures += 1
			print("FIT %s: não carregou" % id)
			continue
		var model := packed.instantiate() as Node3D
		packed = null
		var scan := Scan.new(id, model)
		var row := scan.audit()
		before_rows.append(row)
		if fix:
			var applied: Array = scan.apply_fixes(row)
			row["applied"] = applied
			var saved := OK
			if not applied.is_empty() or src_dir != out_dir:
				var out := PackedScene.new()
				saved = out.pack(model)
				if saved == OK: saved = ResourceSaver.save(out, out_dir + id + ".scn")
			if saved != OK:
				failures += 1
				print("FIT %s: falha ao gravar (%d)" % [id, saved])
		row.erase("_loose")
		row.erase("_lamps")
		row.erase("_wheels")
		model.free()
		scan = null
		if fix:
			var reread := ResourceLoader.load(out_dir + id + ".scn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			if reread != null:
				var again := reread.instantiate() as Node3D
				reread = null
				var check := Scan.new(id, again)
				var checked := check.audit()
				checked.erase("_loose")
				checked.erase("_lamps")
				checked.erase("_wheels")
				if src_dir != out_dir: checked["integrity"] = _integrity(src_dir + id + ".scn", out_dir + id + ".scn")
				after_rows.append(checked)
				again.free()
		print("FIT %s: %s (%d ms)" % [id, _short(before_rows.back(), after_rows.back() if fix and not after_rows.is_empty() else {}), Time.get_ticks_msec() - clock])
	var report := {"label": label, "src": src_dir, "out": out_dir, "fix": fix, "before": before_rows, "after": after_rows, "seconds": (Time.get_ticks_msec() - started) / 1000.0}
	var json := FileAccess.open(REPORT_DIR + label + ".json", FileAccess.WRITE)
	json.store_string(JSON.stringify(report, "\t"))
	json.close()
	var md := FileAccess.open(REPORT_DIR + label + ".md", FileAccess.WRITE)
	md.store_string(_markdown(report))
	md.close()
	print("FIT_DONE models=%d failures=%d report=%s" % [ids.size(), failures, ProjectSettings.globalize_path(REPORT_DIR + label + ".md")])
	quit(1 if failures else 0)

## Cópia corrigida x original: mesmas malhas, superfícies, materiais, contagem de vértices e
## metas; só posições mudam. Devolve o maior deslocamento de vértice (m) e o que divergiu.
static func _integrity(src_path: String, out_path: String) -> Dictionary:
	var issues: Array = []
	var moved := 0.0
	var a := (ResourceLoader.load(src_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	var b := (ResourceLoader.load(out_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	var root_a := Array(a.get_meta_list())
	var root_b := Array(b.get_meta_list())
	root_b.erase(&"headlight_mounts")
	root_a.erase(&"headlight_mounts")
	if root_a != root_b: issues.append("metas da raiz mudaram: %s → %s" % [root_a, root_b])
	var parts_a := a.find_children("*", "MeshInstance3D", true, false)
	var parts_b := b.find_children("*", "MeshInstance3D", true, false)
	if parts_a.size() != parts_b.size(): issues.append("malhas %d → %d" % [parts_a.size(), parts_b.size()])
	for i in mini(parts_a.size(), parts_b.size()):
		var pa := parts_a[i] as MeshInstance3D
		var pb := parts_b[i] as MeshInstance3D
		if pa.name != pb.name or Array(pa.get_meta_list()) != Array(pb.get_meta_list()):
			issues.append("%s: nome ou metas mudaram" % pa.name)
			continue
		if pa.transform != pb.transform:
			# Malha primitiva (BoxMesh) não tem vértice editável: anda pelo nó.
			if pa.mesh is PrimitiveMesh and pa.transform.basis == pb.transform.basis: moved = maxf(moved, pa.transform.origin.distance_to(pb.transform.origin))
			else: issues.append("%s: transformação mudou" % pa.name)
		if pa.mesh == null or pb.mesh == null or pa.mesh.get_surface_count() != pb.mesh.get_surface_count():
			issues.append("%s: superfícies mudaram" % pa.name)
			continue
		for s in pa.mesh.get_surface_count():
			if pa.get_active_material(s) != null and pb.get_active_material(s) != null and pa.get_active_material(s).resource_name != pb.get_active_material(s).resource_name:
				issues.append("%s/%d: material mudou" % [pa.name, s])
			var va: PackedVector3Array = pa.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var vb: PackedVector3Array = pb.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			if va.size() != vb.size():
				issues.append("%s/%d: vértices %d → %d" % [pa.name, s, va.size(), vb.size()])
				continue
			for k in va.size(): moved = maxf(moved, va[k].distance_to(vb[k]))
	a.free()
	b.free()
	return {"issues": issues, "max_move": snappedf(moved, .0001)}

static func _cm(value: float) -> String:
	return "—" if value <= -.99 else "%.1f" % (value * 100.0)

static func _dir(path: String) -> String:
	return path if path.ends_with("/") else path + "/"

static func _short(row: Dictionary, after: Dictionary) -> String:
	var text := "soltas=%d (máx %.1f cm) cobertas=%d coplanares=%d facho=%d assim=%d rodas=%d (máx %s cm)" % [row.loose_exterior, row.max_gap * 100.0, row.lamps_covered, row.lamps_coplanar, row.projector_errors, row.lamps_asymmetric, row.wheels_out, _cm(row.max_wheel_out)]
	if not after.is_empty():
		text += " -> soltas=%d (máx %.1f cm) cobertas=%d coplanares=%d facho=%d rodas=%d (máx %s cm); %d correções" % [after.loose_exterior, after.max_gap * 100.0, after.lamps_covered, after.lamps_coplanar, after.projector_errors, after.wheels_out, _cm(after.max_wheel_out), row.get("applied", []).size()]
	return text

# ------------------------------------------------------------------ relatório

static func _markdown(report: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("# Encaixe da frota redesenhada — %s" % report.label)
	lines.append("")
	lines.append("Gerado por `tools/fleet_fixups/fit_fleet_lamps_20261029.gd` (origem `%s`%s), %.0f s." % [report.src, (", cópias corrigidas em `%s`" % report.out) if report.fix else "", report.seconds])
	lines.append("Vão medido entre triângulos (par de pontos mais próximo). Peça solta = vão > 1 cm até a parte presa à carroceria.")
	lines.append("\"Externa\" = vista de fora sem passar por vidro; interna/escondida não entra na correção.")
	lines.append("")
	var rows: Array = report.before
	var after: Dictionary = {}
	for row in report.after: after[row.id] = row
	lines.append("## Resumo por modelo")
	lines.append("")
	lines.append("| modelo | soltas ext. | maior vão (cm) | soltas int. | lentes cobertas | coplanares | sem par | lado errado | facho fora | rodas p/ fora (máx cm) | correções | depois: soltas / maior vão / cobertas / coplanares / facho / rodas (máx cm) |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
	var sorted := rows.duplicate()
	sorted.sort_custom(func(a, b): return _score(a) > _score(b))
	for row in sorted:
		var tail := "—"
		if after.has(row.id):
			var a: Dictionary = after[row.id]
			tail = "%d / %.1f / %d / %d / %d / %d (%s)" % [a.loose_exterior, a.max_gap * 100.0, a.lamps_covered, a.lamps_coplanar, a.projector_errors, a.wheels_out, _cm(a.max_wheel_out)]
		lines.append("| %s | %d | %.1f | %d | %d | %d | %d | %d | %d | %d (%s) | %d | %s |" % [row.id, row.loose_exterior, row.max_gap * 100.0, row.loose_interior, row.lamps_covered, row.lamps_coplanar, row.lamps_asymmetric, row.lamps_wrong_side, row.projector_errors, row.wheels_out, _cm(row.max_wheel_out), row.get("applied", []).size(), tail])
	lines.append("")
	lines.append("## Piores peças soltas externas (antes)")
	lines.append("")
	lines.append("| modelo | categoria | superfícies | centro (m) | tamanho (m) | vão (cm) | direção do encaixe | corrigível |")
	lines.append("|---|---|---|---|---|---|---|---|")
	var loose: Array = []
	for row in rows:
		for item in row.loose:
			if item.visibility == "externa": loose.append([row.id, item])
	loose.sort_custom(func(a, b): return a[1].gap > b[1].gap)
	for pair in loose.slice(0, 60):
		var item: Dictionary = pair[1]
		lines.append("| %s | %s | %s | %s | %s | %.1f | %s | %s |" % [pair[0], item.category, item.keys, _v(item.center), _v(item.size), item.gap * 100.0, _v(item.direction), item.fixable])
	lines.append("")
	lines.append("## Rodas: face de fora do pneu contra o para-lama (antes → depois)")
	lines.append("")
	lines.append("Positivo = pneu para fora da maior largura da lataria em volta do arco. \"flanco\" = só a lateral na altura do eixo. Folga do arco = do topo do pneu à caixa de roda.")
	lines.append("")
	lines.append("| modelo | roda | estado | pneu além do para-lama (cm) | além do flanco no eixo (cm) | folga do arco (cm) | depois (cm) |")
	lines.append("|---|---|---|---|---|---|---|")
	var wheel_rows: Array = []
	for row in rows:
		for wheel in row.wheels:
			if wheel.state == "para fora" or wheel.has("buried"): wheel_rows.append([row.id, wheel])
	wheel_rows.sort_custom(func(a, b): return float(a[1].get("over", 0.0)) > float(b[1].get("over", 0.0)))
	for pair in wheel_rows.slice(0, 80):
		var wheel: Dictionary = pair[1]
		var later := "—"
		if after.has(pair[0]):
			for other in after[pair[0]].wheels:
				if other.wheel == wheel.wheel and absf(float(other.center[2]) - float(wheel.center[2])) < .01: later = "%.1f" % (float(other.get("over", 0.0)) * 100.0)
		var flank_text := "—" if wheel.get("over_flank") == null else "%.1f" % (float(wheel.over_flank) * 100.0)
		var gap_text := "—" if wheel.get("arch_gap") == null else "%.1f" % (float(wheel.arch_gap) * 100.0)
		lines.append("| %s | %s | %s%s | %.1f | %s | %s | %s |" % [pair[0], wheel.wheel, wheel.state, (" (pneu %.1f cm dentro do para-lama)" % (float(wheel.buried) * 100.0)) if wheel.has("buried") else "", float(wheel.get("over", 0.0)) * 100.0, flank_text, gap_text, later])
	var exposed := {}
	for row in rows:
		for wheel in row.wheels:
			if wheel.state == "exposta": exposed[row.id] = true
	lines.append("")
	lines.append("Rodas sem para-lama em volta (não medidas, não corrigidas): %s." % (", ".join(exposed.keys()) if not exposed.is_empty() else "nenhuma"))
	lines.append("")
	lines.append("## Lentes com problema (antes)")
	lines.append("")
	lines.append("| modelo | lente | centro (m) | problema |")
	lines.append("|---|---|---|---|")
	var lens_lines := 0
	for row in rows:
		for lamp in row.lamps:
			if lamp.problems.is_empty() or lens_lines >= 120: continue
			lens_lines += 1
			lines.append("| %s | %s %s | %s | %s |" % [row.id, lamp.family, lamp.key, _v(lamp.center), "; ".join(lamp.problems)])
	lines.append("")
	lines.append("## Projetores (SpotLight3D do VehicleEquipment) fora do farol (antes)")
	lines.append("")
	for row in rows:
		for item in row.projectors:
			if not item.problems.is_empty(): lines.append("- %s lado %s: projetor em %s; %s" % [row.id, item.side, _v(item.at), "; ".join(item.problems)])
	if report.fix:
		lines.append("")
		lines.append("## Correções aplicadas nas cópias")
		lines.append("")
		for row in rows:
			for line in row.get("applied", []): lines.append("- %s: %s" % [row.id, line])
		lines.append("")
		lines.append("## Integridade das cópias (malhas, superfícies, materiais, vértices e metas iguais ao original)")
		lines.append("")
		for row in report.after:
			if not row.has("integrity"): continue
			var integrity: Dictionary = row.integrity
			if integrity.issues.is_empty() and float(integrity.max_move) == 0.0: continue
			lines.append("- %s: maior deslocamento de vértice %.1f cm%s" % [row.id, float(integrity.max_move) * 100.0, ("; DIVERGE: " + "; ".join(integrity.issues)) if not integrity.issues.is_empty() else "; estrutura igual"])
		lines.append("")
		lines.append("## Ainda soltas/cobertas depois (externas)")
		lines.append("")
		for row in report.after:
			for item in row.loose:
				if item.visibility == "externa": lines.append("- %s: %s %s em %s, vão %.1f cm (%s)" % [row.id, item.category, item.keys, _v(item.center), item.gap * 100.0, item.reason])
			for lamp in row.lamps:
				if not lamp.problems.is_empty(): lines.append("- %s: lente %s %s em %s: %s" % [row.id, lamp.family, lamp.key, _v(lamp.center), "; ".join(lamp.problems)])
			for item in row.projectors:
				if not item.problems.is_empty(): lines.append("- %s: projetor lado %s: %s" % [row.id, item.side, "; ".join(item.problems)])
	lines.append("")
	return "\n".join(lines)

static func _score(row: Dictionary) -> float:
	return row.loose_exterior * 10.0 + row.max_gap * 100.0 + (row.lamps_covered + row.lamps_coplanar + row.projector_errors + row.lamps_wrong_side + row.wheels_out) * 5.0 + row.lamps_asymmetric + maxf(0.0, row.max_wheel_out) * 100.0

static func _v(value) -> String:
	if value is Array: return "(%.2f, %.2f, %.2f)" % [value[0], value[1], value[2]]
	return str(value)

# ------------------------------------------------------------------ análise de um modelo

class Scan:
	var id: String
	var model: Node3D
	var restricted := false
	var pickup := false
	# Triângulos no espaço do modelo, com a ilha de cada um e a normal média de vértice
	# (lado de fora, a que o sombreamento usa; não depende do sentido de enrolamento).
	var ta := PackedVector3Array()
	var tb := PackedVector3Array()
	var tc := PackedVector3Array()
	var tn := PackedVector3Array()
	var tarea := PackedFloat32Array()
	var tisl := PackedInt32Array()
	var tbox: Array[AABB] = []
	var grid := {}
	var islands: Array[Dictionary] = []
	var surfaces: Array[Dictionary] = []
	var adjacency: Array[Dictionary] = []
	var attached := {}
	var body_box := AABB()
	var root := -1
	var wheels: Array[Dictionary] = []

	func _init(model_id: String, target: Node3D) -> void:
		id = model_id
		model = target
		restricted = id in RESTRICTED
		pickup = id.contains("pickup") or id.begins_with("ranch_") or id == "digo_amarok_2014"

	func audit() -> Dictionary:
		_build()
		_contacts()
		_attach()
		var loose := _loose_components()
		var lamps := _lamps()
		var projectors := _projectors()
		var lights := _scene_lights()
		var wheel_rows := _wheel_audit()
		var row := {"id": id, "wheels": [], "wheels_out": 0, "max_wheel_out": -1.0, "islands": islands.size(), "triangles": ta.size(), "loose": [], "lamps": [], "projectors": projectors, "scene_lights": lights,
			"loose_exterior": 0, "loose_interior": 0, "max_gap": 0.0, "lamps_covered": 0, "lamps_coplanar": 0, "lamps_asymmetric": 0, "lamps_wrong_side": 0, "lamps_overhang": 0, "projector_errors": 0}
		for item in loose:
			row.loose.append(_public(item))
			if item.visibility == "externa":
				row.loose_exterior += 1
				row.max_gap = maxf(row.max_gap, item.gap)
			else: row.loose_interior += 1
		for lamp in lamps:
			row.lamps.append(_public(lamp))
			if lamp.covered: row.lamps_covered += 1
			if lamp.coplanar: row.lamps_coplanar += 1
			if lamp.asymmetric: row.lamps_asymmetric += 1
			if lamp.wrong_side: row.lamps_wrong_side += 1
			if lamp.overhang > .015 and lamp.overhang < .25: row.lamps_overhang += 1
		for item in projectors:
			if not item.problems.is_empty(): row.projector_errors += 1
		for item in wheel_rows:
			row.wheels.append(_public(item))
			if item.state == "para fora": row.wheels_out += 1
			if item.has("over"): row.max_wheel_out = maxf(row.max_wheel_out, item.over)
		row["_wheels"] = wheel_rows
		row["_loose"] = loose
		row["_lamps"] = lamps
		return row

	## Tira o que é só de trabalho (índices, vetores) da linha que vai para o JSON.
	static func _public(item: Dictionary) -> Dictionary:
		var result := {}
		for key: String in item:
			if key.begins_with("_"): continue
			var value = item[key]
			result[key] = FitHelpers.arr(value) if value is Vector3 else value
		return result

	# ---------------------------------------------------------- ilhas e grade

	func _build() -> void:
		for part in model.find_children("*", "MeshInstance3D", true, false):
			var mesh_part := part as MeshInstance3D
			if mesh_part.mesh == null or not mesh_part.visible: continue
			# Rodas giram e esterçam em pivôs próprios; o piloto assado da moto é trocado em jogo.
			if mesh_part.has_meta("wheel_center"):
				_collect_wheel(mesh_part)
				continue
			if mesh_part.get_meta("motorcycle_rider", false): continue
			var xf := FitHelpers.model_transform(model, mesh_part)
			var normal_basis := xf.basis.inverse().transposed()
			for s in mesh_part.mesh.get_surface_count():
				if mesh_part.mesh is ArrayMesh and (mesh_part.mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES: continue
				var arrays: Array = mesh_part.mesh.surface_get_arrays(s)
				var local: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				if local.is_empty(): continue
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
				var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
				else:
					indices.resize(local.size())
					for i in local.size(): indices[i] = i
				var key := ROLES.key(mesh_part, s)
				var material := mesh_part.get_active_material(s)
				var entry := {"part": mesh_part, "surface": s, "key": key, "xf": xf, "local": local}
				surfaces.append(entry)
				_split(entry, local, normals, colors, indices, xf, normal_basis, material)
		for t in ta.size():
			var box := AABB(ta[t], Vector3.ZERO).expand(tb[t]).expand(tc[t]).grow(CONTACT)
			tbox.append(box)
			var lo := Vector3i((box.position / CELL).floor())
			var hi := Vector3i((box.end / CELL).floor())
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var cell := Vector3i(x, y, z)
						if not grid.has(cell): grid[cell] = []
						grid[cell].append(t)
		_wheel_envelopes()
		var first := true
		for island in islands:
			if island.wheelish: continue
			body_box = island.box if first else body_box.merge(island.box)
			first = false

	## Ilhas de uma superfície: triângulos ligados por vértices na mesma posição (1 mm).
	func _split(entry: Dictionary, local: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array, xf: Transform3D, normal_basis: Basis, material: Material) -> void:
		var count := local.size()
		var rep := PackedInt32Array()
		rep.resize(count)
		var weld := {}
		for i in count:
			var k := Vector3i((local[i] * 1000.0).round())
			if weld.has(k): rep[i] = weld[k]
			else:
				weld[k] = i
				rep[i] = i
		var parent := PackedInt32Array()
		parent.resize(count)
		for i in count: parent[i] = i
		for t in range(0, indices.size() - 2, 3):
			var r0 := FitHelpers.find(parent, rep[indices[t]])
			for k in [1, 2]:
				var r1 := FitHelpers.find(parent, rep[indices[t + k]])
				if r0 != r1: parent[r1] = r0
		var by_root := {}
		var key: String = entry.key
		var base := key.get_slice("#", 0)
		var emissive: bool = material is StandardMaterial3D and (material as StandardMaterial3D).emission_enabled
		var glass: bool = base.contains("glass") or base.contains("window") or (material is StandardMaterial3D and (material as StandardMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED)
		for t in range(0, indices.size() - 2, 3):
			var i0 := indices[t]
			var i1 := indices[t + 1]
			var i2 := indices[t + 2]
			var a := xf * local[i0]
			var b := xf * local[i1]
			var c := xf * local[i2]
			var area := (b - a).cross(c - a).length() * .5
			if area < 1e-9: continue
			var root_id := FitHelpers.find(parent, rep[i0])
			if not by_root.has(root_id):
				by_root[root_id] = islands.size()
				islands.append({"id": islands.size(), "surface_index": surfaces.size() - 1, "part": entry.part.name, "key": key, "base": base,
					"family": FitHelpers.family(key, emissive), "glass": glass, "paint": base in ["paint", "roof_paint", "body"],
					"wheelish": false, "tris": [], "vidx": {}, "points": {}, "box": AABB(a, Vector3.ZERO), "area": 0.0,
					"normal": Vector3.ZERO, "color": Color(0, 0, 0, 0)})
			var island: Dictionary = islands[by_root[root_id]]
			var tri := ta.size()
			ta.append(a)
			tb.append(b)
			tc.append(c)
			var n := Vector3.ZERO
			if normals.size() == count: n = (normal_basis * (normals[i0] + normals[i1] + normals[i2])).normalized()
			if n == Vector3.ZERO: n = (b - a).cross(c - a).normalized()
			tn.append(n)
			tarea.append(area)
			tisl.append(island.id)
			island.tris.append(tri)
			island.area += area
			island.normal += n * area
			island.box = island.box.expand(a).expand(b).expand(c)
			for i in [i0, i1, i2]:
				island.vidx[i] = true
				island.points[Vector3i((local[i] * 1000.0).round())] = xf * local[i]
				if colors.size() == count: island.color += colors[i]

	func _cell(p: Vector3) -> Vector3i:
		return Vector3i((p / CELL).floor())

	# ---------------------------------------------------------- contato

	func _contacts() -> void:
		adjacency.resize(islands.size())
		for i in islands.size(): adjacency[i] = {}
		for island in islands:
			var i: int = island.id
			var found: Dictionary = adjacency[i]
			for p: Vector3 in island.points.values():
				var cell := _cell(p)
				if not grid.has(cell): continue
				for t: int in grid[cell]:
					var j := tisl[t]
					if j == i or found.has(j): continue
					if not tbox[t].has_point(p): continue
					if p.distance_squared_to(FitHelpers.closest_on_triangle(p, ta[t], tb[t], tc[t])) <= CONTACT * CONTACT:
						found[j] = true
						adjacency[j][i] = true
			# Peça que atravessa a lataria (haste do retrovisor, lente meio enterrada) tem os
			# vértices longe da superfície mas a aresta a cruza. A carroceria grande dispensa:
			# a peça pequena acha o cruzamento pelo lado dela.
			if island.tris.size() > 2500: continue
			for t0: int in island.tris:
				var corners: Array[Vector3] = [ta[t0], tb[t0], tc[t0]]
				for e in 3:
					var u: Vector3 = corners[e]
					var v: Vector3 = corners[(e + 1) % 3]
					var seg := AABB(u, Vector3.ZERO).expand(v)
					var lo := _cell(seg.position)
					var hi := _cell(seg.end)
					for x in range(lo.x, hi.x + 1):
						for y in range(lo.y, hi.y + 1):
							for z in range(lo.z, hi.z + 1):
								var cell := Vector3i(x, y, z)
								if not grid.has(cell): continue
								for t: int in grid[cell]:
									var j := tisl[t]
									if j == i or found.has(j): continue
									if not tbox[t].intersects_segment(u, v): continue
									if Geometry3D.segment_intersects_triangle(u, v, ta[t], tb[t], tc[t]) != null:
										found[j] = true
										adjacency[j][i] = true

	## Extensão de cada roda (raio, face de dentro e de fora) e as ilhas da carroceria que moram
	## dentro dela: pinça de freio e cubo assados na malha da lataria (sedan_classic tem as pinças
	## na superfície "trim"). Elas acompanham a roda: não contam como peça solta, não contam como
	## para-lama e andam junto quando a roda é puxada para dentro.
	func _wheel_envelopes() -> void:
		for index in wheels.size():
			var group: Dictionary = wheels[index]
			var c: Vector3 = group.center
			var tris: PackedVector3Array = group.tris
			var side := signf(c.x) if absf(c.x) > .15 else 0.0
			var x_out := -INF
			var x_in := INF
			var radius := 0.0
			for p in tris:
				x_out = maxf(x_out, side * p.x)
				x_in = minf(x_in, side * p.x)
				radius = maxf(radius, Vector2(p.y - c.y, p.z - c.z).length())
			group["side"] = side
			group["x_out"] = x_out
			group["x_in"] = x_in
			group["radius"] = radius
			group["inside"] = []
			if tris.is_empty(): continue
			# Roda central (moto): a largura vale para os dois lados do eixo.
			var half_width := 0.0
			if side == 0.0:
				for p in tris: half_width = maxf(half_width, absf(p.x - c.x))
			for island in islands:
				if island.paint or island.family != "" or island.glass: continue
				var box: AABB = island.box
				var at := box.get_center()
				if maxf(box.size.y, box.size.z) > radius * 1.6: continue
				if Vector2(at.y - c.y, at.z - c.z).length() > radius * .92: continue
				if side == 0.0:
					if absf(at.x - c.x) > half_width + .12: continue
				elif side * at.x < x_in - .12 or side * at.x > x_out + .01: continue
				island.wheelish = true
				island["wheel_group"] = index
				(group.inside as Array).append(island.id)

	## Conjuntos ligados de todas as ilhas (pelo grafo de contato) e a área de cada um. A
	## carroceria é o conjunto de maior área, não a maior ilha de pintura: a lâmina do limpa-neve
	## (uma ilha só, enorme) virava a "carroceria" e o caminhão inteiro aparecia solto a 25 cm.
	var comp_of := PackedInt32Array()
	var comp_area: Array[float] = []

	func _attach() -> void:
		comp_of.resize(islands.size())
		comp_of.fill(-1)
		for island in islands:
			var start: int = island.id
			if comp_of[start] >= 0 or island.wheelish: continue
			var index := comp_area.size()
			var area := 0.0
			var pending: Array[int] = [start]
			comp_of[start] = index
			while not pending.is_empty():
				var i: int = pending.pop_back()
				area += float(islands[i].area)
				for j: int in adjacency[i]:
					if comp_of[j] >= 0 or islands[j].wheelish: continue
					comp_of[j] = index
					pending.append(j)
			comp_area.append(area)
		var best := -1
		for index in comp_area.size():
			if best < 0 or comp_area[index] > comp_area[best]: best = index
		for island in islands:
			if island.wheelish or (best >= 0 and comp_of[island.id] == best): attached[island.id] = true
			if attached.has(island.id) and root < 0 and not island.wheelish: root = island.id

	# ---------------------------------------------------------- peças soltas

	func _loose_components() -> Array:
		var result: Array = []
		var seen := {}
		var total := float(ta.size())
		for island in islands:
			var start: int = island.id
			if attached.has(start) or seen.has(start): continue
			var members: Array[int] = []
			var pending: Array[int] = [start]
			seen[start] = true
			while not pending.is_empty():
				var i: int = pending.pop_back()
				members.append(i)
				for j: int in adjacency[i]:
					if seen.has(j) or attached.has(j): continue
					seen[j] = true
					pending.append(j)
			var box: AABB = islands[members[0]].box
			var tris := 0
			var keys := {}
			var lamp := false
			var paint_area := 0.0
			for i in members:
				box = box.merge(islands[i].box)
				tris += islands[i].tris.size()
				keys[islands[i].key] = true
				lamp = lamp or islands[i].family != ""
				if islands[i].paint: paint_area += islands[i].area
			var item := {"islands": members.size(), "keys": ",".join(keys.keys()), "center": box.get_center(), "size": box.size, "triangles": tris, "_members": members, "lamp": lamp}
			item["category"] = _category(box, lamp, members)
			item["visibility"] = _visibility(members, box, item.category)
			var near := _closest(members, box)
			item["gap"] = near.get("gap", 9.99)
			item["direction"] = (near.q - near.p).normalized() if near.has("q") else Vector3.ZERO
			item["_near"] = near
			var reason := ""
			if item.visibility != "externa": reason = "não é externa"
			elif not near.has("q"): reason = "nada da carroceria a menos de 50 cm"
			elif item.gap > FIX_MAX_GAP: reason = "vão grande demais para encostar sem desenho novo"
			elif tris > total * .25 or paint_area > .5 or maxf(box.size.x, maxf(box.size.y, box.size.z)) > 5.0: reason = "peça grande (painel), não se move"
			elif restricted and item.category not in RESTRICTED_CATEGORIES: reason = "jipe/picape: só lanternas, retrovisores, placas e para-choques"
			elif pickup and not lamp and box.get_center().z > body_box.end.z - .35 and box.get_center().y > .55: reason = "zona da tampa da caçamba (outra sessão)"
			item["fixable"] = reason.is_empty()
			item["reason"] = reason if not reason.is_empty() else "encosta"
			result.append(item)
		result.sort_custom(func(a, b): return a.gap > b.gap)
		return result

	func _category(box: AABB, lamp: bool, members: Array[int]) -> String:
		var c := box.get_center()
		var half_w := body_box.size.x * .5
		var half_l := body_box.size.z * .5
		var z_from_center := c.z - body_box.get_center().z
		if lamp: return "lanterna"
		if box.size.z < .045 and box.size.x > .25 and box.size.x < .7 and box.size.y > .05 and box.size.y < .26 and absf(c.x) < .12 and absf(z_from_center) > half_l - .4: return "placa"
		if absf(z_from_center) > half_l - .45 and box.size.x > .9 and box.size.y < .45 and c.y < 1.0: return "para-choque"
		if maxf(box.size.x, maxf(box.size.y, box.size.z)) < .42 and absf(c.x) > half_w - .28 and c.y > .55 and c.y < 1.7 and z_from_center < .4 and z_from_center > -half_l * .8: return "retrovisor"
		if absf(c.x) < half_w - .15 and absf(z_from_center) < half_l - .6 and c.y > .2 and c.y < body_box.end.y - .05: return "interior"
		return "peça externa"

	## Vista de fora (sem passar por vidro) por algum dos 9 raios → externa; só pelo vidro → interna.
	func _visibility(members: Array[int], box: AABB, category: String) -> String:
		var own := {}
		for i in members: own[i] = true
		var samples := _samples(members, 6, Vector3.ZERO)
		var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK, Vector3.UP,
			Vector3(1, .6, 1).normalized(), Vector3(-1, .6, 1).normalized(), Vector3(1, .6, -1).normalized(), Vector3(-1, .6, -1).normalized()]
		var through_glass := false
		for p: Vector3 in samples:
			for d: Vector3 in dirs:
				var origin := p + d * 4.0
				var hit := _ray(origin, -d, 4.0 + .002, {}, false)
				if hit.is_empty() or own.has(hit.island): return "externa" if category != "interior" else "interna"
				if not through_glass:
					var clear := _ray(origin, -d, 4.0 + .002, {}, true)
					if clear.is_empty() or own.has(clear.island): through_glass = true
		return "interna" if through_glass or category == "interior" else "escondida"

	## Centros dos maiores triângulos (de frente para `facing`, se dado).
	func _samples(members: Array[int], wanted: int, facing: Vector3) -> Array:
		var pool: Array = []
		for i in members:
			for t: int in islands[i].tris:
				if facing != Vector3.ZERO and tn[t].dot(facing) < .5: continue
				pool.append([tarea[t], t])
		pool.sort_custom(func(a, b): return a[0] > b[0])
		# Centro e três pontos a meio caminho dos cantos: lente de caixa tem só 2 triângulos
		# de frente, e um centro só decidia "coberta" por metade da face.
		var result: Array = []
		for entry in pool:
			if result.size() >= wanted: break
			var t: int = entry[1]
			var center := (ta[t] + tb[t] + tc[t]) / 3.0
			result.append(center)
			for corner: Vector3 in [ta[t], tb[t], tc[t]]: result.append(center.lerp(corner, .6))
		return result.slice(0, wanted)

	## Par de pontos mais próximo entre a peça e a parte presa, com raio crescente.
	func _closest(members: Array[int], box: AABB) -> Dictionary:
		var own := {}
		for i in members: own[i] = true
		var own_comp := comp_of[members[0]]
		var own_area: float = comp_area[own_comp] if own_comp >= 0 else 0.0
		for radius in [.03, .08, .2, .5]:
			var candidates := {}
			var grown := box.grow(radius)
			var lo := _cell(grown.position)
			var hi := _cell(grown.end)
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var cell := Vector3i(x, y, z)
						if not grid.has(cell): continue
						for t: int in grid[cell]:
							var other: int = tisl[t]
							if own.has(other) or islands[other].glass: continue
							if attached.has(other) or (comp_of[other] >= 0 and comp_area[comp_of[other]] > own_area): candidates[t] = true
			if candidates.is_empty(): continue
			var best := {"gap": radius}
			var limit: float = radius * radius
			for i in members:
				for p: Vector3 in islands[i].points.values():
					for t: int in candidates:
						if not tbox[t].grow(radius).has_point(p): continue
						var q := FitHelpers.closest_on_triangle(p, ta[t], tb[t], tc[t])
						var d2 := p.distance_squared_to(q)
						if d2 < limit:
							limit = d2
							best = {"gap": sqrt(d2), "p": p, "q": q}
			var own_tris: Array[int] = []
			for i in members: own_tris.append_array(islands[i].tris)
			for t: int in candidates:
				for q: Vector3 in [ta[t], tb[t], tc[t]]:
					if not grown.has_point(q): continue
					for o in own_tris:
						var p := FitHelpers.closest_on_triangle(q, ta[o], tb[o], tc[o])
						var d2 := p.distance_squared_to(q)
						if d2 < limit:
							limit = d2
							best = {"gap": sqrt(d2), "p": p, "q": q}
			if best.has("q"): return best
		return {}

	## Raio pela grade (Amanatides-Woo). `skip`: ilhas ignoradas; `skip_glass`: vidro não tapa.
	func _ray(origin: Vector3, direction: Vector3, length: float, skip: Dictionary, skip_glass: bool) -> Dictionary:
		var cell := _cell(origin)
		var step := Vector3i(int(signf(direction.x)), int(signf(direction.y)), int(signf(direction.z)))
		var t_max := Vector3.ZERO
		var t_delta := Vector3.ZERO
		for axis in 3:
			if absf(direction[axis]) > 1e-9:
				var boundary: float = (cell[axis] + (1 if step[axis] > 0 else 0)) * CELL
				t_max[axis] = (boundary - origin[axis]) / direction[axis]
				t_delta[axis] = CELL / absf(direction[axis])
			else:
				t_max[axis] = INF
				t_delta[axis] = INF
		var best_t := length
		var best := -1
		var seen := {}
		var t := 0.0
		var guard := 0
		while t <= best_t and guard < 400:
			guard += 1
			if grid.has(cell):
				for tri: int in grid[cell]:
					if seen.has(tri): continue
					seen[tri] = true
					var island: int = tisl[tri]
					if skip.has(island) or (skip_glass and islands[island].glass): continue
					var hit = Geometry3D.ray_intersects_triangle(origin, direction, ta[tri], tb[tri], tc[tri])
					if hit == null: continue
					var d := origin.distance_to(hit)
					if d < best_t:
						best_t = d
						best = tri
			if t_max.x < t_max.y and t_max.x < t_max.z:
				t = t_max.x
				t_max.x += t_delta.x
				cell.x += step.x
			elif t_max.y < t_max.z:
				t = t_max.y
				t_max.y += t_delta.y
				cell.y += step.y
			else:
				t = t_max.z
				t_max.z += t_delta.z
				cell.z += step.z
		return {} if best < 0 else {"t": best_t, "tri": best, "island": tisl[best]}

	# ---------------------------------------------------------- lentes

	func _lamps() -> Array:
		var result: Array = []
		var lamp_islands: Array = []
		for island in islands:
			if island.family != "": lamp_islands.append(island)
		var half_l := body_box.size.z * .5
		var half_w := body_box.size.x * .5
		var mid_z := body_box.get_center().z
		for island in lamp_islands:
			var box: AABB = island.box
			var c := box.get_center()
			var out := Vector3.ZERO
			if island.area > 0.0 and (island.normal as Vector3).length() / island.area > .55: out = (island.normal as Vector3).normalized()
			elif c.z - mid_z < -half_l * .55: out = Vector3.FORWARD
			elif c.z - mid_z > half_l * .55: out = Vector3.BACK
			elif absf(c.x) > half_w * .6: out = Vector3(signf(c.x), 0, 0)
			else: out = Vector3.UP
			var members: Array[int] = [island.id]
			var item := {"key": island.key, "family": island.family, "part": island.part, "center": c, "size": box.size, "out": out, "_island": island.id,
				"attached": attached.has(island.id), "covered": false, "cover_depth": 0.0, "coplanar": false, "asymmetric": false, "wrong_side": false, "overhang": 0.0, "problems": []}
			var visibility := _visibility(members, box, "lanterna")
			item["visibility"] = visibility
			var samples := _samples(members, 24, out)
			if samples.is_empty(): samples = _samples(members, 6, Vector3.ZERO)
			var skip := {island.id: true}
			var covered := 0
			var coplanar := 0
			var depths: Array[float] = []
			for p: Vector3 in samples:
				var hit := _ray(p + out * .0005, out, COVER_RAY, skip, true)
				if not hit.is_empty():
					covered += 1
					depths.append(float(hit.t) + .0005)
				var flat := _ray(p - out * .0015, out, .003, skip, true)
				if not flat.is_empty() and absf(tn[flat.tri].dot(out)) > .9: coplanar += 1
			if not samples.is_empty():
				if covered * 5 >= samples.size() * 3:
					depths.sort()
					item.covered = true
					item.cover_depth = depths[depths.size() / 2]
					item.problems.append("face de fora coberta por lataria (%.1f cm à frente, %d/%d amostras)" % [item.cover_depth * 100.0, covered, samples.size()])
				elif coplanar * 10 >= samples.size() * 3:
					item.coplanar = true
					item.problems.append("no mesmo plano da lataria (z-fighting, %d/%d amostras)" % [coplanar, samples.size()])
			if not item.attached: item.problems.append("solta da carroceria")
			# Lado: farol na frente, lanterna atrás (giroflex e pisca podem estar em qualquer lugar).
			if island.family == "farol" and c.z - mid_z > 0:
				item.wrong_side = true
				item.problems.append("farol na metade de trás")
			if island.family == "lanterna" and c.z - mid_z < 0:
				item.wrong_side = true
				item.problems.append("lanterna na metade da frente")
			if (island.family == "farol" or island.family == "lanterna") and (c.y < .12 or c.y > body_box.end.y - .03):
				item.wrong_side = true
				item.problems.append("altura fora da carroceria (y=%.2f)" % c.y)
			# Par espelhado do outro lado.
			if absf(c.x) > .05:
				var error := INF
				for other in lamp_islands:
					if other.id == island.id or other.family != island.family: continue
					var o: Vector3 = (other.box as AABB).get_center()
					var s: Vector3 = (other.box as AABB).size
					var grow: Vector3 = (s - box.size).abs()
					error = minf(error, maxf(maxf(absf(o.x + c.x), absf(o.y - c.y)), maxf(absf(o.z - c.z), maxf(grow.x, maxf(grow.y, grow.z)))))
				if error > .015:
					item.asymmetric = true
					item.problems.append("sem par espelhado (melhor par a %.1f cm)" % (error * 100.0) if error < INF else "sem par espelhado")
			elif box.size.x > .3 and absf(c.x) > .01:
				item.asymmetric = true
				item.problems.append("lente central fora do eixo (x=%.3f)" % c.x)
			# Lente de canto mais larga que a lataria naquele ponto (sobra para o lado).
			if absf(c.x) > .2 and out.dot(Vector3(signf(c.x), 0, 0)) < .7:
				var side := signf(c.x)
				var outer: float = box.end.x if side > 0 else -box.position.x
				var behind := c.z - signf(out.z) * (box.size.z * .5 + .03) if absf(out.z) > .3 else c.z
				var flank := _ray(Vector3(side * 5.0, c.y, behind), Vector3(-side, 0, 0), 5.0, _lamp_set(lamp_islands), true)
				if not flank.is_empty() and attached.has(flank.island):
					var face: float = absf(5.0 - float(flank.t))
					item.overhang = outer - face
					if item.overhang > .015 and item.overhang < .25: item.problems.append("sobra %.1f cm para fora da lateral" % (item.overhang * 100.0))
			result.append(item)
		return result

	func _lamp_set(lamp_islands: Array) -> Dictionary:
		var result := {}
		for island in lamp_islands: result[island.id] = true
		return result

	# ---------------------------------------------------------- rodas

	## Junta as malhas da mesma roda (pneu e aro giram; pinça e para-lama da moto só esterçam):
	## Vehicle.gd põe todas no pivô da `wheel_center`, então mover a roda é mover o grupo inteiro
	## e a meta junto, senão a pinça fica para trás. A física não usa a roda: o casco de colisão
	## sai de bounds_size do catálogo, e a roda é só apresentação presa ao pivô.
	func _collect_wheel(part: MeshInstance3D) -> void:
		var center: Vector3 = part.get_meta("wheel_center")
		var key := Vector3i((center * 1000.0).round())
		var group := {}
		for existing in wheels:
			if existing.key == key: group = existing
		if group.is_empty():
			group = {"key": key, "center": center, "parts": [], "tris": PackedVector3Array()}
			wheels.append(group)
		group.parts.append(part)
		if not part.get_meta("wheel_spins", true): return
		var xf := FitHelpers.model_transform(model, part)
		var faces := part.mesh.get_faces()
		var tris: PackedVector3Array = group.tris
		for v in faces: tris.append(xf * v)
		group.tris = tris

	## Quanto a face de fora do pneu passa da lataria em volta do arco. A referência é a maior
	## largura da carroceria na faixa do arco (do eixo até 15 cm acima do pneu, 15 cm à frente e
	## atrás dele): raios de fora na altura do eixo e sobre o pneu, mais os vértices nessa faixa
	## (pega o lábio do para-lama alargado, que um raio só pode errar).
	func _wheel_audit() -> Array:
		var result: Array = []
		var lamp_ids := {}
		for island in islands:
			if island.family != "": lamp_ids[island.id] = true
		for group in wheels:
			var c: Vector3 = group.center
			var tris: PackedVector3Array = group.tris
			if absf(c.x) < .15 or tris.is_empty(): continue
			var side: float = group.side
			var x_out: float = group.x_out
			var x_in: float = group.x_in
			var radius: float = group.radius
			var item := {"wheel": "%s %s" % ["esq" if side < 0 else "dir", "diant" if c.z < body_box.get_center().z else "tras"], "center": c, "radius": snappedf(radius, .001),
				"tire_out": snappedf(x_out, .001), "tire_in": snappedf(x_in, .001), "_group": group}
			var fender := -INF
			var flank := -INF
			var band := AABB(Vector3(-20, c.y + .02, c.z - radius - .15), Vector3(40, radius + .15, 2.0 * radius + .3))
			var x_a: float = side * (x_in - .3)
			var x_b: float = side * (x_out + .4)
			var lo := _cell(Vector3(minf(x_a, x_b), band.position.y, band.position.z))
			var hi := _cell(Vector3(maxf(x_a, x_b), band.end.y, band.end.z))
			for x in range(lo.x, hi.x + 1):
				for y in range(lo.y, hi.y + 1):
					for z in range(lo.z, hi.z + 1):
						var cell := Vector3i(x, y, z)
						if not grid.has(cell): continue
						for t: int in grid[cell]:
							var island: int = tisl[t]
							if islands[island].glass or islands[island].wheelish or lamp_ids.has(island): continue
							for q: Vector3 in [ta[t], tb[t], tc[t]]:
								if band.has_point(q): fender = maxf(fender, side * q.x)
			var probes := [[c.y + radius + .03, c.z, false], [c.y + radius + .03, c.z - .15, false], [c.y + radius + .03, c.z + .15, false],
				[c.y + radius * .7, c.z - radius * .85, false], [c.y + radius * .7, c.z + radius * .85, false],
				[c.y, c.z - radius - .06, true], [c.y, c.z + radius + .06, true]]
			var skip_ray := lamp_ids.duplicate()
			for i: int in group.inside: skip_ray[i] = true
			for probe in probes:
				var hit := _ray(Vector3(side * 6.0, probe[0], probe[1]), Vector3(-side, 0, 0), 6.0, skip_ray, true)
				if hit.is_empty(): continue
				var at: float = 6.0 - float(hit.t)
				fender = maxf(fender, at)
				if probe[2]: flank = maxf(flank, at)
			item["fender"] = snappedf(fender, .001) if fender > -INF else null
			item["flank_axle"] = snappedf(flank, .001) if flank > -INF else null
			if fender == -INF or fender < x_in:
				item["state"] = "exposta"
				result.append(item)
				continue
			var over := x_out - fender
			item["over"] = snappedf(over, .001)
			item["over_flank"] = snappedf(x_out - flank, .001) if flank > -INF else null
			item["state"] = "para fora" if over > WHEEL_OUT else ("para dentro" if over < -.05 else "ok")
			# Folga do arco: raios do meio do pneu para cima (60°–120°); começam a 60% do raio
			# para não pegar suspensão perto do cubo.
			var gap := INF
			var buried := 0.0
			for degrees in [60.0, 90.0, 120.0]:
				var angle := deg_to_rad(degrees)
				var direction := Vector3(0, sin(angle), -cos(angle))
				var start := Vector3(side * (x_out + x_in) * .5, c.y, c.z) + direction * radius * .6
				var hit := _ray(start, direction, radius * .4 + .25, skip_ray, true)
				if hit.is_empty(): continue
				var reach: float = radius * .6 + float(hit.t)
				gap = minf(gap, reach - radius)
				if reach < radius - .005: buried = maxf(buried, radius - reach)
			item["arch_gap"] = snappedf(gap, .001) if gap < INF else null
			if buried > 0.0: item["buried"] = snappedf(buried, .001)
			result.append(item)
		return result

	## Arestas do pneu que atravessam lataria com a roda deslocada `shift` para dentro e
	## esterçada `steer` rad em torno do pivô. Amostra até ~700 triângulos do pneu.
	func _wheel_hits(group: Dictionary, shift: float, steer: float, crossed_islands: Dictionary = {}) -> int:
		var c: Vector3 = group.center
		var side := signf(c.x)
		var turn := Basis(Vector3.UP, steer)
		var offset := Vector3(-side * shift, 0, 0)
		var tris: PackedVector3Array = group.tris
		var count: int = tris.size() / 3
		var stride := maxi(1, ceili(count / 700.0))
		var hits := 0
		var own := {}
		for i: int in group.inside: own[i] = true
		for k in range(0, count, stride):
			# Abaixo do eixo o pneu já cruza assoalho/soleira escondidos dentro dele (sedan_classic):
			# contar isso recusava qualquer ajuste. O que aparece é o pneu entrando no arco.
			if (tris[k * 3].y + tris[k * 3 + 1].y + tris[k * 3 + 2].y) / 3.0 < c.y: continue
			var corners: Array[Vector3] = []
			for j in 3: corners.append(c + turn * (tris[k * 3 + j] - c) + offset)
			for e in 3:
				var u: Vector3 = corners[e]
				var v: Vector3 = corners[(e + 1) % 3]
				var seg := AABB(u, Vector3.ZERO).expand(v)
				var lo := _cell(seg.position)
				var hi := _cell(seg.end)
				var crossed := false
				for x in range(lo.x, hi.x + 1):
					for y in range(lo.y, hi.y + 1):
						for z in range(lo.z, hi.z + 1):
							var cell := Vector3i(x, y, z)
							if crossed or not grid.has(cell): continue
							for t: int in grid[cell]:
								var other: int = tisl[t]
								if islands[other].glass or own.has(other) or (steer != 0.0 and not islands[other].paint): continue
								if not tbox[t].intersects_segment(u, v): continue
								if Geometry3D.segment_intersects_triangle(u, v, ta[t], tb[t], tc[t]) != null:
									crossed = true
									crossed_islands[other] = true
									break
				if crossed: hits += 1
		return hits

	## Puxa a roda para dentro até alinhar com o para-lama; recua o deslocamento (100/75/50/25%)
	## se o pneu passar a atravessar mais lataria do que já atravessava, parado ou esterçado.
	func _wheel_allowance(item: Dictionary) -> Dictionary:
		var group: Dictionary = item._group
		var c: Vector3 = group.center
		var front: bool = c.z < body_box.get_center().z
		# Medida que não dá para confiar não vira deslocamento: pneu já dentro do para-lama (caminhão
		# com para-lama solto), sem arco em cima do pneu, ou mais de 15 cm (desenho, não espaçador).
		if item.has("buried"): return {"shift": 0.0, "note": "o pneu já entra %.1f cm no para-lama; medir à mão" % (float(item.buried) * 100.0)}
		if item.get("arch_gap") == null: return {"shift": 0.0, "note": "sem arco medido sobre o pneu"}
		if float(item.over) > .15: return {"shift": 0.0, "note": "mais de 15 cm é desenho, não espaçador"}
		var wanted := minf(float(item.over) + WHEEL_FLUSH, WHEEL_MAX_SHIFT)
		var steers: Array = [0.0, -STEER, STEER] if front else [0.0]
		var baseline := {}
		for steer in steers: baseline[steer] = _wheel_hits(group, 0.0, steer)
		var chosen := 0.0
		var blockers := {}
		for fraction in [1.0, .75, .5, .25]:
			var shift: float = wanted * fraction
			var ok := true
			for steer in steers:
				var crossed := {}
				if _wheel_hits(group, shift, steer, crossed) > int(baseline[steer]):
					ok = false
					if blockers.is_empty():
						for i: int in crossed: blockers[i] = "%s %s%s" % [islands[i].key, FitHelpers.fmt((islands[i].box as AABB).get_center()), " esterçando" if steer != 0.0 else ""]
					break
			if ok:
				chosen = shift
				break
		var blocked_by := ", ".join(blockers.values().slice(0, 3))
		if chosen <= 0.0: return {"shift": 0.0, "note": "puxar para dentro faz o pneu atravessar %s" % blocked_by}
		return {"shift": chosen, "note": "" if is_equal_approx(chosen, wanted) else "parcial: mais atravessava %s" % blocked_by}

	func _shift_wheel(item: Dictionary, chosen: float, moves: Dictionary) -> void:
		var group: Dictionary = item._group
		var c: Vector3 = group.center
		var side := signf(c.x)
		var delta := Vector3(-side * chosen, 0, 0)
		for part: MeshInstance3D in group.parts:
			var xf := FitHelpers.model_transform(model, part)
			if part.mesh is ArrayMesh:
				var shift := xf.basis.inverse() * delta
				var changed := {}
				for s in part.mesh.get_surface_count():
					var local: PackedVector3Array = part.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
					for i in local.size(): local[i] += shift
					changed[s] = local
				FitHelpers.rebuild(part, changed)
			else:
				part.position += (part.get_parent() as Node3D).transform.basis.inverse() * delta if part.get_parent() != model else delta
			part.set_meta("wheel_center", (part.get_meta("wheel_center") as Vector3) + delta)
		for i: int in group.inside: moves[i] = delta

	## Roda do outro lado do mesmo eixo (centro espelhado em x, mesma altura e posição).
	func _mirror_wheel(item: Dictionary, rows: Array) -> Dictionary:
		var c: Vector3 = (item._group as Dictionary).center
		for other in rows:
			if other == item: continue
			var o: Vector3 = (other._group as Dictionary).center
			if absf(o.x + c.x) < .03 and absf(o.y - c.y) < .03 and absf(o.z - c.z) < .03: return other
		return {}

	# ---------------------------------------------------------- projetores do VehicleEquipment

	## Refaz em espaço do modelo o que VehicleEquipment._ready faz com as lentes: centro da
	## superfície de farol (ou `headlight_mounts`), média por lado, +6 cm à frente.
	func _projectors() -> Array:
		# Meio comprimento pela própria carroceria, não por FleetCatalog: o catálogo puxa meio jogo
		# (PoliceGroundModels → CityPropKit…) e um script quebrado de outra sessão derrubava a
		# ferramenta. Só serve para o limiar das lentes antigas sem chave (35% do comprimento).
		var half_length: float = body_box.size.z * .5
		var mounts: Array[Vector3] = []
		if model.has_meta("headlight_mounts"):
			for mount: Vector3 in model.get_meta("headlight_mounts"): mounts.append(mount)
		else:
			for entry in surfaces:
				var part: MeshInstance3D = entry.part
				if part.material_override != null and int(entry.surface) > 0: continue
				var s: int = entry.surface
				var key := ROLES.key(part, s)
				var original := part.get_active_material(s) as StandardMaterial3D
				if original == null: continue
				if key == "" and is_equal_approx(original.roughness, .1) and original.albedo_color.is_equal_approx(Color("f5f6fa")) and original.emission_enabled: key = "headlight"
				var local: PackedVector3Array = entry.local
				var bounds := AABB(local[0], Vector3.ZERO)
				for v in local: bounds = bounds.expand(v)
				var center: Vector3 = (entry.xf as Transform3D) * bounds.get_center()
				var headlight := false
				if ROLES.is_headlight_lens(key): headlight = center.z < 0
				elif key == "" and original.emission_enabled:
					var color := original.albedo_color
					headlight = center.z < -half_length * .35 and color.s < .35 and color.v > .8
				if headlight: mounts.append(center)
		var single := id.begins_with("bike_")
		var heads: Array = []
		for island in islands:
			if island.family == "farol" and (island.box as AABB).get_center().z < body_box.get_center().z: heads.append(island)
		var result: Array = []
		if mounts.is_empty():
			if not heads.is_empty(): result.append({"side": "ambos", "at": [0, 0, 0], "problems": ["sem lente de farol reconhecida: o VehicleEquipment usa o casco (±0,7 da largura, y=0,8)"]})
			return result
		for side in ([0] if single else [-1, 1]):
			var center := Vector3.ZERO
			var count := 0
			for mount in mounts:
				if side == 0 or (mount.x < 0) == (side < 0):
					center += mount
					count += 1
			var lenses: Array = []
			for island in heads:
				var x: float = (island.box as AABB).get_center().x
				if side == 0 or (x < 0) == (side < 0): lenses.append(island)
			var side_name := "centro" if side == 0 else ("esquerdo" if side < 0 else "direito")
			if count == 0:
				if not lenses.is_empty(): result.append({"side": side_name, "at": [0, 0, 0], "problems": ["farol deste lado sem projetor (as lentes estão numa superfície só)"]})
				continue
			var at := center / count + Vector3(0, 0, -.06)
			var item := {"side": side_name, "at": FitHelpers.arr(at), "problems": []}
			if lenses.is_empty():
				item.problems.append("projetor sem lente de farol deste lado")
			else:
				var best := INF
				for island in lenses:
					var box: AABB = island.box
					var dx := maxf(0.0, maxf(box.position.x - at.x, at.x - box.end.x))
					var dy := maxf(0.0, maxf(box.position.y - at.y, at.y - box.end.y))
					best = minf(best, Vector2(dx, dy).length())
				item["off_lens"] = snappedf(best, .001)
				if best > PROJECTOR_SLACK: item.problems.append("facho %.1f cm fora da lente no plano do farol" % (best * 100.0))
			result.append(item)
		return result

	func _scene_lights() -> Array:
		var result: Array = []
		for light in model.find_children("*", "Light3D", true, false):
			var at := FitHelpers.model_transform(model, light).origin
			var best := INF
			for island in islands:
				if island.family == "": continue
				var box: AABB = island.box
				best = minf(best, at.distance_to(box.get_center()))
			result.append({"name": light.name, "class": light.get_class(), "at": FitHelpers.arr(at), "nearest_lens": best})
		return result

	# ---------------------------------------------------------- correções

	func apply_fixes(row: Dictionary) -> Array:
		var moves := {}
		var applied: Array = []
		for item in row._loose:
			if not item.fixable: continue
			var near: Dictionary = item._near
			var delta: Vector3 = (near.q - near.p).normalized() * (float(item.gap) + SEAT)
			# Par espelhado (farol, retrovisor de cada lado): o par de pontos mais próximo sai um
			# pouco diferente por lado e os faróis do caminhão ficavam 2,7 cm fora de simetria.
			# Os dois andam a média espelhada.
			var center: Vector3 = item.center
			for other in row._loose:
				if other == item or not other.fixable or other.category != item.category: continue
				var o: Vector3 = other.center
				if absf(o.x + center.x) > .03 or absf(o.y - center.y) > .03 or absf(o.z - center.z) > .03 or absf(center.x) < .03: continue
				var o_near: Dictionary = other._near
				var o_delta: Vector3 = (o_near.q - o_near.p).normalized() * (float(other.gap) + SEAT)
				delta = (delta + Vector3(-o_delta.x, o_delta.y, o_delta.z)) * .5
				break
			for i: int in item._members: moves[i] = delta
			applied.append("%s %s em %s encostado: vão %.1f cm, move %s" % [item.category, item.keys, FitHelpers.fmt(item.center), item.gap * 100.0, FitHelpers.fmt(delta)])
		for lamp in row._lamps:
			if lamp.visibility != "externa" or not lamp.attached: continue
			var i: int = lamp._island
			if moves.has(i): continue
			if lamp.covered and lamp.cover_depth <= .04:
				var delta: Vector3 = lamp.out * (float(lamp.cover_depth) + LENS_LIFT)
				moves[i] = delta
				applied.append("lente %s %s em %s saiu de dentro da lataria: move %s" % [lamp.family, lamp.key, FitHelpers.fmt(lamp.center), FitHelpers.fmt(delta)])
			elif lamp.coplanar:
				var delta: Vector3 = lamp.out * LENS_LIFT
				moves[i] = delta
				applied.append("lente %s %s em %s desencostada do plano da lataria: move %s" % [lamp.family, lamp.key, FitHelpers.fmt(lamp.center), FitHelpers.fmt(delta)])
		var allowance := {}
		for item in row._wheels:
			if item.state == "para fora": allowance[item] = _wheel_allowance(item)
		for item in row._wheels:
			if item.state != "para fora": continue
			var own: Dictionary = allowance[item]
			var shift: float = own.shift
			var note: String = own.note
			var mirror := _mirror_wheel(item, row._wheels)
			if not mirror.is_empty():
				# O outro lado sem espaçador (dentro do para-lama) não segura este: só o que também
				# sobra para fora e não pode entrar tanto.
				var other: float = float(allowance[mirror].shift) if allowance.has(mirror) else shift
				if other < shift - .001:
					shift = other
					note = ("igualado ao outro lado do eixo" + ("; " + note if not note.is_empty() else "")) if shift > 0.0 else "o outro lado do eixo não pode entrar (%s)" % allowance[mirror].note
			if shift <= 0.0:
				applied.append("roda %s: %.1f cm para fora, fica: %s" % [item.wheel, float(item.over) * 100.0, note])
				continue
			_shift_wheel(item, shift, moves)
			applied.append("roda %s: pneu %.1f cm para fora do para-lama; roda e wheel_center %.1f cm para dentro%s" % [item.wheel, float(item.over) * 100.0, shift * 100.0, (" (" + note + ")") if not note.is_empty() else ""])
		# Um _move só: ele parte dos vértices originais de cada superfície, então duas chamadas
		# na mesma superfície (pinça e para-choque na "trim" do sedan) desfariam a primeira.
		_move(moves)
		# Facho fora do farol: grava onde está a lente de cada lado (VehicleEquipment prefere
		# `headlight_mounts` ao centro da superfície juntada).
		var off := false
		for item in row.projectors: off = off or not item.problems.is_empty()
		if off:
			var mounts: Array = []
			for side in ([0] if id.begins_with("bike_") else [-1, 1]):
				var sum := Vector3.ZERO
				var weight := 0.0
				for island in islands:
					if island.family != "farol": continue
					var box: AABB = island.box
					var c := box.get_center()
					if c.z >= body_box.get_center().z or (side != 0 and (c.x < 0) != (side < 0)): continue
					var shift: Vector3 = moves.get(island.id, Vector3.ZERO)
					sum += (c + shift) * island.area
					weight += island.area
				if weight > 0.0: mounts.append(sum / weight)
			if not mounts.is_empty():
				model.set_meta("headlight_mounts", mounts)
				applied.append("headlight_mounts = %s (projetor no centro de cada farol)" % ", ".join(mounts.map(func(m): return FitHelpers.fmt(m))))
		return applied

	func _move(moves: Dictionary) -> void:
		if moves.is_empty(): return
		var by_surface := {}
		for i: int in moves:
			var s: int = islands[i].surface_index
			if not by_surface.has(s): by_surface[s] = []
			by_surface[s].append(i)
		var by_part := {}
		for s: int in by_surface:
			var entry: Dictionary = surfaces[s]
			var part: MeshInstance3D = entry.part
			if not by_part.has(part): by_part[part] = {}
			var local: PackedVector3Array = (entry.local as PackedVector3Array).duplicate()
			var inverse := (entry.xf as Transform3D).basis.inverse()
			for i: int in by_surface[s]:
				var shift: Vector3 = inverse * (moves[i] as Vector3)
				for v: int in islands[i].vidx: local[v] += shift
			by_part[part][entry.surface] = local
		for part: MeshInstance3D in by_part:
			if part.mesh is ArrayMesh:
				FitHelpers.rebuild(part, by_part[part])
				continue
			# BoxMesh/CylinderMesh: não dá para mover vértice; a peça inteira anda pelo nó se todas
			# as ilhas dela pediram o mesmo deslocamento.
			var shifts := {}
			for s: int in by_surface:
				if surfaces[s].part != part: continue
				for i: int in by_surface[s]: shifts[moves[i]] = true
			var count := 0
			for island in islands:
				if surfaces[island.surface_index].part == part: count += 1
			var all_moved := 0
			for s: int in by_surface:
				if surfaces[s].part == part: all_moved += (by_surface[s] as Array).size()
			if shifts.size() == 1 and all_moved == count:
				var world_shift: Vector3 = shifts.keys()[0]
				var up := part.get_parent() as Node3D
				part.position += world_shift if up == model else FitHelpers.model_transform(model, up).basis.inverse() * world_shift
			else: push_warning("FIT %s: malha primitiva com ilhas de deslocamento diferente, ficou" % part.name)

## Funções sem estado, fora da classe interna para ela poder usá-las como estáticas.
class FitHelpers:
	static func arr(value: Vector3) -> Array:
		return [snappedf(value.x, .001), snappedf(value.y, .001), snappedf(value.z, .001)]

	static func fmt(value) -> String:
		if value is Array: return "(%.3f, %.3f, %.3f)" % [value[0], value[1], value[2]]
		var v: Vector3 = value
		return "(%.3f, %.3f, %.3f)" % [v.x, v.y, v.z]

	static func find(parent: PackedInt32Array, i: int) -> int:
		while parent[i] != i:
			parent[i] = parent[parent[i]]
			i = parent[i]
		return i

	static func model_transform(model: Node3D, node: Node3D) -> Transform3D:
		var xf := node.transform
		var up := node.get_parent()
		while up != null and up != model:
			if up is Node3D: xf = (up as Node3D).transform * xf
			up = up.get_parent()
		return xf

	static func family(key: String, emissive: bool) -> String:
		if ROLES.is_headlight_lens(key): return "farol"
		if ROLES.is_tail_lens(key): return "lanterna"
		var base := key.get_slice("#", 0)
		if base in ["bar_left", "bar_right", "beacon"]: return "giroflex"
		if base in OTHER_LAMP_KEYS: return "pisca"
		if emissive: return "emissiva"
		return ""

	## Ponto do triângulo mais próximo de p (Ericson, Real-Time Collision Detection 5.1.5).
	static func closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
		var ab := b - a
		var ac := c - a
		var ap := p - a
		var d1 := ab.dot(ap)
		var d2 := ac.dot(ap)
		if d1 <= 0.0 and d2 <= 0.0: return a
		var bp := p - b
		var d3 := ab.dot(bp)
		var d4 := ac.dot(bp)
		if d3 >= 0.0 and d4 <= d3: return b
		var vc := d1 * d4 - d3 * d2
		if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0: return a + ab * (d1 / (d1 - d3))
		var cp := p - c
		var d5 := ab.dot(cp)
		var d6 := ac.dot(cp)
		if d6 >= 0.0 and d5 <= d6: return c
		var vb := d5 * d2 - d1 * d6
		if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0: return a + ac * (d2 / (d2 - d6))
		var va := d3 * d6 - d5 * d4
		if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0: return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
		var denom := 1.0 / (va + vb + vc)
		return a + ab * (vb * denom) + ac * (vc * denom)

	## Refaz a malha da peça com as superfícies trocadas; material, nome e compressão ficam.
	static func rebuild(part: MeshInstance3D, changed: Dictionary) -> void:
		var old := part.mesh as ArrayMesh
		if old == null:
			push_warning("FIT %s: malha primitiva, não dá para mover só uma ilha" % part.name)
			return
		var mesh := ArrayMesh.new()
		mesh.resource_name = old.resource_name
		mesh.custom_aabb = old.custom_aabb
		mesh.blend_shape_mode = old.blend_shape_mode
		for i in old.get_blend_shape_count(): mesh.add_blend_shape(old.get_blend_shape_name(i))
		var keep: int = Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES | Mesh.ARRAY_FLAG_USE_2D_VERTICES | Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE | Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		for k in 4: keep |= Mesh.ARRAY_FORMAT_CUSTOM_MASK << (Mesh.ARRAY_FORMAT_CUSTOM_BASE + k * Mesh.ARRAY_FORMAT_CUSTOM_BITS)
		for s in old.get_surface_count():
			var arrays: Array = old.surface_get_arrays(s)
			if changed.has(s): arrays[Mesh.ARRAY_VERTEX] = changed[s]
			mesh.add_surface_from_arrays(old.surface_get_primitive_type(s), arrays, old.surface_get_blend_shape_arrays(s), {}, old.surface_get_format(s) & keep)
			mesh.surface_set_material(s, old.surface_get_material(s))
			mesh.surface_set_name(s, old.surface_get_name(s))
		if old.shadow_mesh != null: push_warning("FIT %s: shadow_mesh antigo descartado (geometria mudou)" % part.name)
		part.mesh = mesh
