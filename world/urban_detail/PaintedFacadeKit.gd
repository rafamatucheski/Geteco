extends RefCounted
class_name PaintedFacadeKit

## Prédio inteiro pintado, no jeito do GTA III/Vice City: as quatro paredes e o
## telhado são imagens (assets/facades/<estilo>/, geradas por
## tools/build_painted_facades.py) em vez de dezenas de caixas. Só fica em 3D o que
## muda a silhueta ou se mexe: a cornija do topo (laje plana) e as portas, que giram
## na dobradiça para dentro de um corredor escuro atrás do vão.
##
## Cada estilo traz no style.json o tamanho do módulo da frente (prédio mais largo
## repete o módulo, como geminados), os vãos (porta com folha, garagem sem folha) e
## a empena da lateral (casa de telhado inclinado). A frente é montada em volta dos
## vãos (sem transparência), então tudo continua na passada opaca e funde por trecho.
##
## Interruptor: ligado por padrão desde 15/10; GETECO_PAINTED_FACADES=0 volta aos
## prédios de caixas (A/B).

const ROOT := "res://assets/facades/"
const MODULE_W := 6.0
const SIDE_W := 8.0
const STYLES := ["tijolo-vermelho", "reboco-creme", "concreto-cinza", "rosa-praia", "tijolo-londrino",
	"pastilha-60", "madeira-azul", "fabrica-tijolo", "comercio-terreo"]
## Estilos de moradia: galpão e loja não viram sobrado residencial.
const RESIDENTIAL := ["tijolo-vermelho", "reboco-creme", "concreto-cinza", "rosa-praia", "tijolo-londrino",
	"pastilha-60", "madeira-azul"]
const PLAYER_LAYER := 2
## Porta empurrada pela mão, não de mola: abre devagar e fecha mais devagar ainda,
## com uma pausa antes de fechar. 0,45 s lia como porta automática de shopping.
const DOOR_OPEN_SECONDS := 1.8
const DOOR_CLOSE_SECONDS := 2.4
const DOOR_CLOSE_DELAY := 1.2
## Ângulo máximo: 80° em vez de 90°, folha não bate rente na parede do corredor.
const DOOR_MAX_ANGLE := deg_to_rad(80.0)
## Só abre com o jogador ao alcance do braço (antes 3 m: abria de longe).
const DOOR_REACH := 1.0
const ROOF_OVERHANG := 0.35

static var _materials := {}
static var _styles := {}


static func enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_FACADES") != "0"


static func residential_style(key: String) -> String:
	return RESIDENTIAL[posmod(hash(key), RESIDENTIAL.size())]


## Todos os estilos importados (pastas de assets/facades com style.json).
static func all_styles() -> Array:
	var list: Array = []
	for folder in DirAccess.get_directories_at(ROOT):
		if FileAccess.file_exists(ROOT + folder + "/style.json"): list.append(folder)
	return list


static func style_data(style: String) -> Dictionary:
	if not _styles.has(style):
		var text := FileAccess.get_file_as_string(ROOT + style + "/style.json")
		_styles[style] = JSON.parse_string(text) if not text.is_empty() else {}
	return _styles[style]


## Tamanho natural do estilo: largura e altura do módulo da frente e largura da
## lateral, em metros (do style.json).
static func natural_size(style: String) -> Vector3:
	var data := style_data(style)
	var module: Array = data.get("module", [MODULE_W, 7.0])
	var side: Array = data.get("side", [SIDE_W, 7.0])
	return Vector3(float(module[0]), float(module[1]), float(side[0]))


## Altura da cumeeira acima do chão para uma parede de `wall_h` (sem empena = wall_h).
static func ridge_height(style: String, wall_h: float) -> float:
	var eave := float(style_data(style).get("eave", 0.0))
	return wall_h + (wall_h * eave / maxf(0.05, 1.0 - eave) if eave > 0.0 else 0.0)


## Vãos de um lado ("front"/"back"): [{rect, leaf}]. Aceita o style.json antigo
## (só "doors", uma porta com folha).
static func openings(style: String, side: String) -> Array:
	var data := style_data(style)
	var list: Array = data.get("openings", {}).get(side, [])
	if not list.is_empty(): return list
	var rect: Array = data.get("doors", {}).get(side, [])
	return [{"rect": rect, "leaf": true}] if rect.size() == 4 else []


## Centro (x local, frente em +Z) do vão com folha mais próximo de `wanted`.
static func nearest_door_x(style: String, width: float, wanted: float) -> float:
	var module_w := natural_size(style).x
	var modules := maxi(1, roundi(width / module_w))
	module_w = width / float(modules)
	var best := wanted
	var best_distance := INF
	for index in modules:
		for opening in openings(style, "front"):
			if not opening.leaf: continue
			var rect: Array = opening.rect
			var center := -width * 0.5 + module_w * (float(index) + (float(rect[0]) + float(rect[2])) * 0.5)
			if absf(center - wanted) < best_distance:
				best_distance = absf(center - wanted)
				best = center
	return best


## Material de uma peça (front/back/side/roof/roof_clear/door_*); paredes têm luz noturna.
static func material(style: String, part: String) -> StandardMaterial3D:
	var key := style + "/" + part
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ROOT + style + "/" + part + ".jpg")
	mat.roughness = 0.88
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Telhado de duas águas é visto por baixo no beiral.
	if part.begins_with("roof"): mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if part in ["front", "back", "side"]:
		mat.emission_enabled = true
		# Operador ADD soma a cor à textura: preto deixa só a máscara acender.
		mat.emission = Color.BLACK
		mat.emission_texture = load(ROOT + style + "/" + part + "_glow.jpg")
		PaintedWindow.register_night(mat)
	_materials[key] = mat
	return mat


static func _corridor_material() -> StandardMaterial3D:
	if _materials.has("corridor"): return _materials["corridor"]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("2a2724")
	mat.roughness = 0.95
	# Só as faces de dentro: de fora se vê o fundo e o chão do corredor pelo vão.
	mat.cull_mode = BaseMaterial3D.CULL_FRONT
	_materials["corridor"] = mat
	return mat


## Monta o prédio com a frente em +Z, base em y=0 e centro em (0, 0). `size` é
## largura (X), altura da parede até o beiral (Y) e profundidade (Z). Devolve o nó
## visual; a colisão vai para `collision_parent` (se houver) como uma caixa só.
## `walk_in_x`: x local da entrada de verdade (prédio com interior), cuja folha
## fica sem corredor. `options.snow`: false usa o telhado sem neve (se houver).
##
## Estilo com empena (style.json "eave" > 0) ganha laterais com o triângulo pintado
## e telhado de duas águas com cumeeira paralela à frente; sem empena, laje plana
## com cornija em anel.
static func build(parent: Node3D, style: String, size: Vector3, collision_parent: Node3D = null, walk_in_x := NAN, options := {}) -> Node3D:
	var root := Node3D.new()
	root.name = "PaintedFacade_" + style
	parent.add_child(root)
	var data := style_data(style)
	var half := size * 0.5
	var module_w := natural_size(style).x
	var modules := maxi(1, roundi(size.x / module_w))
	module_w = size.x / float(modules)
	var eave := float(data.get("eave", 0.0))
	var gable_h := ridge_height(style, size.y) - size.y
	var front_openings := openings(style, "front")
	var back_openings := openings(style, "back")
	# As pinturas trazem embasamento e degrau: a soleira da porta fica 0,7-1 m acima
	# da base da imagem e o prédio lia como pousado num degrau gigante. Afunda o
	# prédio até a soleira mais baixa da frente encostar na calçada; o embasamento
	# que sobra fica abaixo do chão. `options.ground_door = false` desliga.
	var sink := 0.0
	if bool(options.get("ground_door", true)):
		var lowest := INF
		for opening in front_openings:
			if bool(opening.leaf): lowest = minf(lowest, (1.0 - float(opening.rect[3])) * size.y)
		if lowest < INF: sink = maxf(0.0, lowest - 0.03)
	root.position.y -= sink
	root.set_meta("ground_sink", sink)
	# Frente e fundos: faixas de parede em volta de cada vão.
	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in modules:
		var x0 := -half.x + module_w * float(index)
		var front_xform := Transform3D(Basis.IDENTITY, Vector3(x0, 0, half.z))
		# Fundos olham para -Z: gira 180° e começa do outro canto.
		var back_xform := Transform3D(Basis(Vector3.UP, PI), Vector3(-x0, 0, -half.z))
		_face_with_openings(front, front_xform, module_w, size.y, front_openings)
		_face_with_openings(back, back_xform, module_w, size.y, back_openings)
		for opening in front_openings:
			var rect: Array = opening.rect
			var center := x0 + module_w * (float(rect[0]) + float(rect[2])) * 0.5
			# Na entrada de verdade a folha pintada continua (é a porta que abre), mas sem
			# o corredor escuro: atrás dela fica o interior do acesso.
			var walk_in: bool = bool(opening.leaf) and not is_nan(walk_in_x) and absf(center - walk_in_x) <= 0.5
			_door(root, style, "front", rect, front_xform, module_w, size.y, collision_parent, walk_in, bool(opening.leaf))
		for opening in back_openings:
			_door(root, style, "back", opening.rect, back_xform, module_w, size.y, collision_parent, false, bool(opening.leaf))
	_add_mesh(root, "Front", front, material(style, "front"))
	_add_mesh(root, "Back", back, material(style, "back"))
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	if eave > 0.0:
		# A empena é um desenho só para a profundidade toda: estica em vez de repetir.
		var right := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(half.x, 0, half.z))
		var left := Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-half.x, 0, -half.z))
		for xform in [right, left]:
			_quad(sides, xform, size.z, size.y, Rect2(0, eave, 1, 1.0 - eave))
			_triangle(sides, xform, size.z, size.y, gable_h, eave)
	else:
		var side_modules := maxi(1, roundi(size.z / natural_size(style).z))
		var side_w := size.z / float(side_modules)
		for index in side_modules:
			var z0 := -half.z + side_w * float(index)
			# Lateral direita olha +X, começando do fundo; a esquerda é o espelho.
			_quad(sides, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(half.x, 0, z0 + side_w)), side_w, size.y, Rect2(0, 0, 1, 1))
			_quad(sides, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-half.x, 0, z0)), side_w, size.y, Rect2(0, 0, 1, 1))
	_add_mesh(root, "Sides", sides, material(style, "side"))
	var roof_part := "roof"
	if not bool(options.get("snow", true)) and bool(data.get("snow_roof", false)): roof_part = "roof_clear"
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	if eave > 0.0:
		_pitched_roof(roof, size, gable_h)
	else:
		_quad(roof, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-half.x, size.y, half.z)), size.x, size.z, Rect2(0, 0, 1, 1))
	_add_mesh(root, "Roof", roof, material(style, roof_part))
	if eave <= 0.0: root.add_child(_cornice(size))
	if collision_parent != null:
		var body := StaticBody3D.new()
		body.name = "PaintedFacadeSolid"
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0, half.y - sink, 0)
		body.add_child(shape)
		collision_parent.add_child(body)
	return root


static func _cornice(size: Vector3) -> MeshInstance3D:
	# Cornija: única peça de silhueta no topo, projeta sombra sobre a fachada.
	var cornice := MeshInstance3D.new()
	cornice.name = "Cornice"
	# Anel em volta da borda (uma malha só): tampa maciça escondia o telhado pintado.
	var ring := SurfaceTool.new()
	ring.begin(Mesh.PRIMITIVE_TRIANGLES)
	var band := 0.38
	var outer := Vector2(size.x + 0.3, size.z + 0.3)
	for piece in [[Vector3(0, 0, (outer.y - band) * 0.5), Vector3(outer.x, 0.32, band)],
			[Vector3(0, 0, -(outer.y - band) * 0.5), Vector3(outer.x, 0.32, band)],
			[Vector3((outer.x - band) * 0.5, 0, 0), Vector3(band, 0.32, outer.y - band * 2.0)],
			[Vector3(-(outer.x - band) * 0.5, 0, 0), Vector3(band, 0.32, outer.y - band * 2.0)]]:
		var box_mesh := BoxMesh.new()
		box_mesh.size = piece[1]
		ring.append_from(box_mesh, 0, Transform3D(Basis.IDENTITY, piece[0]))
	cornice.mesh = ring.commit()
	cornice.position = Vector3(0, size.y + 0.1, 0)
	cornice.material_override = UrbanMaterials.trim_stone()
	return cornice


## Quad de largura w e altura h com canto inferior esquerdo na origem de `xform`,
## olhando para +Z local; `uv` é o recorte da imagem (origem no topo).
static func _quad(st: SurfaceTool, xform: Transform3D, w: float, h: float, uv: Rect2) -> void:
	_quad_points(st, [xform * Vector3(0, 0, 0), xform * Vector3(w, 0, 0), xform * Vector3(w, h, 0), xform * Vector3(0, h, 0)],
		[Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position])


## Quad por quatro cantos (baixo-esq., baixo-dir., cima-dir., cima-esq., vistos de fora).
static func _quad_points(st: SurfaceTool, points: Array, uvs: Array) -> void:
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p3: Vector3 = points[3]
	var normal := (p1 - p0).cross(p3 - p0).normalized()
	# Godot usa sentido horário como face da frente.
	for index in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uvs[index])
		st.add_vertex(points[index])


## Triângulo da empena sobre a parede lateral (mesma orientação de `_quad`).
static func _triangle(st: SurfaceTool, xform: Transform3D, w: float, wall_h: float, gable_h: float, eave: float) -> void:
	var points := [xform * Vector3(0, wall_h, 0), xform * Vector3(w * 0.5, wall_h + gable_h, 0), xform * Vector3(w, wall_h, 0)]
	var uvs := [Vector2(0, eave), Vector2(0.5, 0), Vector2(1, eave)]
	var normal := xform.basis * Vector3.BACK
	for index in 3:
		st.set_normal(normal)
		st.set_uv(uvs[index])
		st.add_vertex(points[index])


## Duas águas com cumeeira em z=0, paralela à frente, e beiral saliente.
static func _pitched_roof(st: SurfaceTool, size: Vector3, gable_h: float) -> void:
	var half := size * 0.5
	var slope := gable_h / maxf(0.01, half.z)
	var eave_y := size.y - ROOF_OVERHANG * slope
	var ridge_y := size.y + gable_h
	var x := half.x + ROOF_OVERHANG
	var z := half.z + ROOF_OVERHANG
	var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	_quad_points(st, [Vector3(-x, eave_y, z), Vector3(x, eave_y, z), Vector3(x, ridge_y, 0), Vector3(-x, ridge_y, 0)], uvs)
	_quad_points(st, [Vector3(x, eave_y, -z), Vector3(-x, eave_y, -z), Vector3(-x, ridge_y, 0), Vector3(x, ridge_y, 0)], uvs)


## Parede de um módulo com os vãos abertos: faixas cheias entre os vãos e, em
## cada vão, o pedaço de cima (verga) e o de baixo (soleira).
static func _face_with_openings(st: SurfaceTool, xform: Transform3D, w: float, h: float, list: Array) -> void:
	var rects: Array = []
	for opening in list: rects.append(opening.rect)
	rects.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	var cursor := 0.0
	for rect in rects:
		var u0: float = rect[0]
		var v0: float = rect[1]
		var u1: float = rect[2]
		var v1: float = rect[3]
		if u0 > cursor:
			_quad(st, xform.translated_local(Vector3(cursor * w, 0, 0)), (u0 - cursor) * w, h, Rect2(cursor, 0, u0 - cursor, 1))
		# Coordenadas de mundo com origem embaixo: v da imagem cresce para baixo.
		var y_top := (1.0 - v0) * h
		var y_bottom := (1.0 - v1) * h
		_quad(st, xform.translated_local(Vector3(u0 * w, y_top, 0)), (u1 - u0) * w, h - y_top, Rect2(u0, 0, u1 - u0, v0))
		if y_bottom > 0.001:
			_quad(st, xform.translated_local(Vector3(u0 * w, 0, 0)), (u1 - u0) * w, y_bottom, Rect2(u0, v1, u1 - u0, 1.0 - v1))
		cursor = maxf(cursor, u1)
	if cursor < 1.0:
		_quad(st, xform.translated_local(Vector3(cursor * w, 0, 0)), (1.0 - cursor) * w, h, Rect2(cursor, 0, 1.0 - cursor, 1))


static func _add_mesh(root: Node3D, mesh_name: String, st: SurfaceTool, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	mesh.mesh = st.commit()
	mesh.material_override = mat
	# Paredes e telhado são planos de uma face: a parede de costas para o sol não
	# entrava no mapa de sombra, só telhado e cornija sombreavam, e a sombra saía
	# descolada da base (casa "voando" no deserto). Sombra dos dois lados fecha a caixa.
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
	root.add_child(mesh)


## Folha 3D no vão: frente e verso pintados, dobradiça na ombreira esquerda.
## Só a ENTRADA DE VERDADE (walk_in: prédio com interior) abre com o jogador perto;
## as outras folhas (módulo repetido, segunda porta do duplex, fundos) ficam
## fechadas e não reagem, como porta de vizinho trancada. Antes toda porta abria
## para um corredor falso e o jogador batia na parede: o prédio parecia quebrado.
## Vão sem folha (garagem, portão largo) fica só com o fundo escuro.
static func _door(root: Node3D, style: String, side: String, rect: Array, xform: Transform3D, w: float, h: float, collision_parent: Node3D, walk_in := false, leaf := true) -> void:
	if rect.size() != 4: return
	var leaf_w := (float(rect[2]) - float(rect[0])) * w
	var leaf_h := (float(rect[3]) - float(rect[1])) * h
	var bottom := (1.0 - float(rect[3])) * h
	var anchor := Node3D.new()
	anchor.name = "Doorway_" + side
	anchor.transform = xform.translated_local(Vector3(float(rect[0]) * w, bottom, 0))
	root.add_child(anchor)
	if walk_in: anchor.set_meta("walk_in", true)
	elif not leaf:
		var corridor := MeshInstance3D.new()
		corridor.name = "Corridor"
		var corridor_mesh := BoxMesh.new()
		corridor_mesh.size = Vector3(leaf_w, leaf_h, minf(1.6, leaf_w * 1.5 + 0.6))
		corridor.mesh = corridor_mesh
		corridor.position = Vector3(leaf_w * 0.5, leaf_h * 0.5, -corridor_mesh.size.z * 0.5)
		corridor.material_override = _corridor_material()
		anchor.add_child(corridor)
	if not leaf: return
	var door := PaintedDoor.new()
	door.name = "Door"
	anchor.add_child(door)
	door.position = Vector3(0, 0, -0.04)
	var part := "door_front" if side == "front" else "door_back"
	var outside := MeshInstance3D.new()
	outside.mesh = QuadMesh.new()
	outside.mesh.size = Vector2(leaf_w, leaf_h)
	outside.position = Vector3(leaf_w * 0.5, leaf_h * 0.5, 0.005)
	outside.material_override = material(style, part)
	door.hinge.add_child(outside)
	var inside := MeshInstance3D.new()
	inside.mesh = QuadMesh.new()
	inside.mesh.size = Vector2(leaf_w, leaf_h)
	inside.position = Vector3(leaf_w * 0.5, leaf_h * 0.5, -0.005)
	inside.rotation.y = PI
	inside.material_override = material(style, part + "_inside")
	door.hinge.add_child(inside)
	if walk_in and collision_parent != null: door.watch_player(Vector3(leaf_w + 0.4, leaf_h, DOOR_REACH))


## Dobradiça com abertura animada. Usa uma Area3D (física avisa a entrada) em vez
## de olhar a distância do jogador todo quadro.
class PaintedDoor extends Node3D:
	var hinge := Node3D.new()
	var open_amount := 0.0
	var _tween: Tween
	var _area: Area3D

	func _init() -> void:
		hinge.name = "Hinge"
		add_child(hinge)

	func set_open_amount(amount: float) -> void:
		open_amount = clampf(amount, 0.0, 1.0)
		# Rotação positiva em Y leva a ponta da folha (+X) para -Z: para dentro.
		hinge.rotation.y = open_amount * PaintedFacadeKit.DOOR_MAX_ANGLE

	func swing(open: bool) -> void:
		if _tween != null: _tween.kill()
		_tween = create_tween()
		if open:
			# Empurrão firme no começo, a folha perde força até parar.
			_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			_tween.tween_method(set_open_amount, open_amount, 1.0, PaintedFacadeKit.DOOR_OPEN_SECONDS * (1.0 - open_amount))
		else:
			# Espera, começa a fechar devagar e encosta devagar no batente.
			_tween.tween_interval(PaintedFacadeKit.DOOR_CLOSE_DELAY)
			_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_tween.tween_method(set_open_amount, open_amount, 0.0, PaintedFacadeKit.DOOR_CLOSE_SECONDS * open_amount)

	func watch_player(zone: Vector3) -> void:
		var area := Area3D.new()
		area.name = "DoorZone"
		area.collision_layer = 0
		area.collision_mask = PaintedFacadeKit.PLAYER_LAYER
		area.monitorable = false
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = zone
		shape.shape = box
		# Na frente da folha (+Z local é a rua), com 0,2 m de folga de cada lado.
		shape.position = Vector3(zone.x * 0.5 - 0.2, zone.y * 0.5, zone.z * 0.5 + 0.04)
		area.add_child(shape)
		add_child(area)
		_area = area
		area.body_entered.connect(_on_enter)
		area.body_exited.connect(_on_exit)

	func _on_enter(_body: Node3D) -> void:
		swing(true)

	func _on_exit(_body: Node3D) -> void:
		if _area.get_overlapping_bodies().is_empty(): swing(false)
