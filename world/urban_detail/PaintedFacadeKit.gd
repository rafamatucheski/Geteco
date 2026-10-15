extends RefCounted
class_name PaintedFacadeKit

## Prédio inteiro pintado, no jeito do GTA III/Vice City: as quatro paredes e o
## telhado são imagens (assets/facades/<estilo>/, geradas por
## tools/build_painted_facades.py) em vez de dezenas de caixas. Só fica em 3D o que
## muda a silhueta ou se mexe: a cornija do topo e a porta, que gira na dobradiça
## para dentro de um corredor escuro atrás do vão.
##
## A fachada é um módulo de 6 m x 7 m (lateral 8 m): prédio mais largo repete o
## módulo, como sobrados geminados. A frente é montada em volta do vão da porta
## (sem transparência), então tudo continua na passada opaca e funde por trecho.
##
## Interruptor: GETECO_PAINTED_FACADES=1 liga nos sobrados (padrão desligado
## enquanto o visual é avaliado).

const ROOT := "res://assets/facades/"
const MODULE_W := 6.0
const SIDE_W := 8.0
const STYLES := ["tijolo-vermelho", "reboco-creme", "concreto-cinza", "rosa-praia", "tijolo-londrino",
	"pastilha-60", "madeira-azul", "fabrica-tijolo", "comercio-terreo"]
## Estilos de moradia: galpão e loja não viram sobrado residencial.
const RESIDENTIAL := ["tijolo-vermelho", "reboco-creme", "concreto-cinza", "rosa-praia", "tijolo-londrino",
	"pastilha-60", "madeira-azul"]
const PLAYER_LAYER := 2
const DOOR_OPEN_SECONDS := 0.45

static var _materials := {}
static var _styles := {}


static func enabled() -> bool:
	return OS.get_environment("GETECO_PAINTED_FACADES") == "1"


static func residential_style(key: String) -> String:
	return RESIDENTIAL[posmod(hash(key), RESIDENTIAL.size())]


static func style_data(style: String) -> Dictionary:
	if not _styles.has(style):
		var text := FileAccess.get_file_as_string(ROOT + style + "/style.json")
		_styles[style] = JSON.parse_string(text) if not text.is_empty() else {}
	return _styles[style]


## Material de uma peça (front/back/side/roof/door_*); paredes têm luz noturna.
static func material(style: String, part: String) -> StandardMaterial3D:
	var key := style + "/" + part
	if _materials.has(key): return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(ROOT + style + "/" + part + ".jpg")
	mat.roughness = 0.88
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
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
## largura (X), altura (Y) e profundidade (Z). Devolve o nó visual; a colisão vai
## para `collision_parent` (se houver) como uma caixa só.
static func build(parent: Node3D, style: String, size: Vector3, collision_parent: Node3D = null) -> Node3D:
	var root := Node3D.new()
	root.name = "PaintedFacade_" + style
	parent.add_child(root)
	var data := style_data(style)
	var doors: Dictionary = data.get("doors", {})
	var half := size * 0.5
	var modules := maxi(1, roundi(size.x / MODULE_W))
	var module_w := size.x / float(modules)
	var side_modules := maxi(1, roundi(size.z / SIDE_W))
	# Frente e fundos: um quad por faixa em volta de cada vão de porta.
	var front := SurfaceTool.new()
	front.begin(Mesh.PRIMITIVE_TRIANGLES)
	var back := SurfaceTool.new()
	back.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in modules:
		var x0 := -half.x + module_w * float(index)
		_face_with_opening(front, Transform3D(Basis.IDENTITY, Vector3(x0, 0, half.z)), module_w, size.y, doors.get("front", []))
		# Fundos olham para -Z: gira 180° e começa do outro canto.
		_face_with_opening(back, Transform3D(Basis(Vector3.UP, PI), Vector3(-x0, 0, -half.z)), module_w, size.y, doors.get("back", []))
		_door(root, style, "front", doors.get("front", []), Transform3D(Basis.IDENTITY, Vector3(x0, 0, half.z)), module_w, size.y, collision_parent)
		_door(root, style, "back", doors.get("back", []), Transform3D(Basis(Vector3.UP, PI), Vector3(-x0, 0, -half.z)), module_w, size.y, collision_parent)
	_add_mesh(root, "Front", front, material(style, "front"))
	_add_mesh(root, "Back", back, material(style, "back"))
	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	var side_w := size.z / float(side_modules)
	for index in side_modules:
		var z0 := -half.z + side_w * float(index)
		# Lateral direita olha +X, começando do fundo; a esquerda é o espelho.
		_quad(sides, Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(half.x, 0, z0 + side_w)), side_w, size.y, Rect2(0, 0, 1, 1))
		_quad(sides, Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-half.x, 0, z0)), side_w, size.y, Rect2(0, 0, 1, 1))
	_add_mesh(root, "Sides", sides, material(style, "side"))
	var roof := SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(roof, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(-half.x, size.y, half.z)), size.x, size.z, Rect2(0, 0, 1, 1))
	_add_mesh(root, "Roof", roof, material(style, "roof"))
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
	root.add_child(cornice)
	if collision_parent != null:
		var body := StaticBody3D.new()
		body.name = "PaintedFacadeSolid"
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.position = Vector3(0, half.y, 0)
		body.add_child(shape)
		collision_parent.add_child(body)
	return root


## Quad de largura w e altura h com canto inferior esquerdo na origem de `xform`,
## olhando para +Z local; `uv` é o recorte da imagem (origem no topo).
static func _quad(st: SurfaceTool, xform: Transform3D, w: float, h: float, uv: Rect2) -> void:
	var corners := [Vector3(0, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(0, h, 0)]
	var uvs := [Vector2(uv.position.x, uv.end.y), Vector2(uv.end.x, uv.end.y), Vector2(uv.end.x, uv.position.y), uv.position]
	var normal := xform.basis * Vector3.BACK
	# Godot usa sentido horário como face da frente.
	for index in [0, 2, 1, 0, 3, 2]:
		st.set_normal(normal)
		st.set_uv(uvs[index])
		st.add_vertex(xform * corners[index])


## Parede de um módulo com o vão da porta aberto: até quatro quads em volta do
## retângulo (frações da imagem, origem no topo).
static func _face_with_opening(st: SurfaceTool, xform: Transform3D, w: float, h: float, rect: Array) -> void:
	if rect.size() != 4:
		_quad(st, xform, w, h, Rect2(0, 0, 1, 1))
		return
	var u0: float = rect[0]
	var v0: float = rect[1]
	var u1: float = rect[2]
	var v1: float = rect[3]
	# Coordenadas de mundo com origem embaixo: v da imagem cresce para baixo.
	var y_top := (1.0 - v0) * h
	var y_bottom := (1.0 - v1) * h
	_quad(st, xform, u0 * w, h, Rect2(0, 0, u0, 1))
	_quad(st, xform.translated_local(Vector3(u1 * w, 0, 0)), (1.0 - u1) * w, h, Rect2(u1, 0, 1.0 - u1, 1))
	_quad(st, xform.translated_local(Vector3(u0 * w, y_top, 0)), (u1 - u0) * w, h - y_top, Rect2(u0, 0, u1 - u0, v0))
	if y_bottom > 0.001:
		_quad(st, xform.translated_local(Vector3(u0 * w, 0, 0)), (u1 - u0) * w, y_bottom, Rect2(u0, v1, u1 - u0, 1.0 - v1))


static func _add_mesh(root: Node3D, mesh_name: String, st: SurfaceTool, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = mesh_name
	mesh.mesh = st.commit()
	mesh.material_override = mat
	root.add_child(mesh)


## Folha 3D no vão: frente e verso pintados, dobradiça na ombreira esquerda,
## abre para dentro de um corredor escuro. Abre sozinha com o jogador perto.
static func _door(root: Node3D, style: String, side: String, rect: Array, xform: Transform3D, w: float, h: float, collision_parent: Node3D) -> void:
	if rect.size() != 4: return
	var leaf_w := (float(rect[2]) - float(rect[0])) * w
	var leaf_h := (float(rect[3]) - float(rect[1])) * h
	var bottom := (1.0 - float(rect[3])) * h
	var anchor := Node3D.new()
	anchor.name = "Doorway_" + side
	anchor.transform = xform.translated_local(Vector3(float(rect[0]) * w, bottom, 0))
	root.add_child(anchor)
	var corridor := MeshInstance3D.new()
	corridor.name = "Corridor"
	var corridor_mesh := BoxMesh.new()
	corridor_mesh.size = Vector3(leaf_w, leaf_h, 1.6)
	corridor.mesh = corridor_mesh
	corridor.position = Vector3(leaf_w * 0.5, leaf_h * 0.5, -0.8)
	corridor.material_override = _corridor_material()
	anchor.add_child(corridor)
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
	if collision_parent != null: door.watch_player(Vector3(leaf_w, leaf_h, 3.0))


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
		hinge.rotation.y = open_amount * PI * 0.5

	func swing(open: bool) -> void:
		if _tween != null: _tween.kill()
		_tween = create_tween()
		_tween.tween_method(set_open_amount, open_amount, 1.0 if open else 0.0, PaintedFacadeKit.DOOR_OPEN_SECONDS * absf((1.0 if open else 0.0) - open_amount))

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
		shape.position = Vector3(zone.x * 0.5, zone.y * 0.5, zone.z * 0.5)
		area.add_child(shape)
		add_child(area)
		_area = area
		area.body_entered.connect(_on_enter)
		area.body_exited.connect(_on_exit)

	func _on_enter(_body: Node3D) -> void:
		swing(true)

	func _on_exit(_body: Node3D) -> void:
		if _area.get_overlapping_bodies().is_empty(): swing(false)
