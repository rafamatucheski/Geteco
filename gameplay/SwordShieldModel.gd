extends RefCounted
## Espada de uma mão e escudo redondo do cavaleiro da cabana escondida da serra. Modelos do Meshy
## (30/10, texto → 3D, remesh 3 mil triângulos, textura PBR) em assets/weapons/sword_shield/; sem eles, o
## modelo por primitivas com o material da katana. Os materiais do Meshy são pré-aquecidos na
## ForgePrewarm, sob a cortina.
## Espada: cabo na origem, lâmina em −Z, fio em ±X (como a katana). Escudo: centro na origem, face
## para −Z, alça no +Z (é o lado do antebraço).
const KATANA := preload("res://gameplay/KatanaModel.gd")
const SWORD_SCENE := "res://assets/weapons/sword_shield/ice_sword.glb"
const SHIELD_SCENE := "res://assets/weapons/sword_shield/ice_shield.glb"
## Espada inteira com 1,0 m; o cabo (origem) fica a 12% do comprimento a partir do pomo.
const SWORD_LENGTH := 1.0
const SWORD_GRIP_SHARE := 0.12
const TIP := Vector3(0.0, 0.0, -0.88)
const SHIELD_RADIUS := 0.34

## Espada do Meshy: gerada em pé com a ponta para +Y e a face plana para a câmera (fio em ±X). Gira
## +Y → −Z, encaixa o comprimento e põe o cabo na origem. Sem o arquivo, cai nas primitivas.
static func build_sword(root: Node3D) -> Vector3:
	var model := _instance(SWORD_SCENE)
	if model == null: return _build_primitive_sword(root)
	var box := _bounds(model)
	var holder := Node3D.new()
	holder.name = "IceSword"
	holder.rotation.x = -PI * .5
	var scale := SWORD_LENGTH / maxf(box.size.y, .001)
	holder.scale = Vector3.ONE * scale
	model.position = -Vector3(box.get_center().x, box.position.y + box.size.y * SWORD_GRIP_SHARE, box.get_center().z)
	holder.add_child(model)
	root.add_child(holder)
	return TIP

## Escudo do Meshy: gerado de frente para a câmera (+Z). Gira 180° para a face ir a −Z e encaixa o
## diâmetro em 2 × SHIELD_RADIUS.
static func build_shield(root: Node3D) -> void:
	var model := _instance(SHIELD_SCENE)
	if model == null:
		_build_primitive_shield(root)
		return
	var box := _bounds(model)
	var holder := Node3D.new()
	holder.name = "IceShield"
	holder.rotation.y = PI
	holder.scale = Vector3.ONE * (SHIELD_RADIUS * 2.0 / maxf(maxf(box.size.x, box.size.y), .001))
	model.position = -box.get_center()
	holder.add_child(model)
	root.add_child(holder)

static func _instance(path: String) -> Node3D:
	if not ResourceLoader.exists(path): return null
	var scene := load(path) as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

## Caixa das malhas no espaço do modelo (sem ler vértices: só o AABB de cada malha).
static func _bounds(model: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var local := _relative(model, mesh) * mesh.get_aabb()
		result = local if first else result.merge(local)
		first = false
	return result

static func _relative(model: Node3D, node: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != model:
		if current is Node3D: result = (current as Node3D).transform * result
		current = current.get_parent()
	return result

static func _build_primitive_sword(root: Node3D) -> Vector3:
	var steel := KATANA._material(Color("c4ced6"), 0.92, 0.22)
	var dark := KATANA._material(Color("2a2420"), 0.05, 0.82)
	var silver := KATANA._material(Color("9fb3c4"), 0.88, 0.30)
	KATANA._oval(root, "Grip", 0.017, 0.16, 0.85, Vector3(0, 0, 0.05), dark)
	KATANA._oval(root, "Pommel", 0.026, 0.035, 1.0, Vector3(0, 0, 0.145), silver)
	KATANA._box(root, "Guard", Vector3(0.20, 0.03, 0.035), Vector3(0, 0, -0.04), silver)
	KATANA._box(root, "Blade", Vector3(0.052, 0.009, 0.78), Vector3(0, 0, -0.44), steel)
	KATANA._box(root, "Fuller", Vector3(0.012, 0.012, 0.6), Vector3(0, 0, -0.38), silver)
	var point := KATANA._box(root, "Point", Vector3(0.037, 0.009, 0.037), Vector3(0, 0, -0.84), steel)
	point.rotation.y = PI * .25
	return Vector3(0.0, 0.0, -0.92)

static func _build_primitive_shield(root: Node3D) -> void:
	var wood := KATANA._material(Color("5a3b22"), 0.0, 0.78)
	var iron := KATANA._material(Color("8c96a0"), 0.85, 0.35)
	var frost := KATANA._material(Color("bfe4f2"), 0.65, 0.25)
	var face := CylinderMesh.new()
	face.top_radius = SHIELD_RADIUS
	face.bottom_radius = SHIELD_RADIUS
	face.height = 0.035
	face.radial_segments = 24
	face.rings = 1
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = face
	board.material_override = wood
	board.rotation.x = PI * .5
	root.add_child(board)
	var rim := TorusMesh.new()
	rim.inner_radius = SHIELD_RADIUS - 0.02
	rim.outer_radius = SHIELD_RADIUS + 0.012
	rim.rings = 24
	rim.ring_segments = 6
	var rim_mesh := MeshInstance3D.new()
	rim_mesh.name = "Rim"
	rim_mesh.mesh = rim
	rim_mesh.material_override = iron
	rim_mesh.rotation.x = PI * .5
	root.add_child(rim_mesh)
	KATANA._oval(root, "Boss", 0.075, 0.05, 1.0, Vector3(0, 0, -0.035), frost)
	# Cruz de ferro na face: o desenho que separa o escudo "do gelo" de uma tampa de barril.
	KATANA._box(root, "BandV", Vector3(0.05, SHIELD_RADIUS * 1.9, 0.012), Vector3(0, 0, -0.022), iron)
	KATANA._box(root, "BandH", Vector3(SHIELD_RADIUS * 1.9, 0.05, 0.012), Vector3(0, 0, -0.022), iron)
	KATANA._box(root, "Strap", Vector3(0.05, 0.16, 0.03), Vector3(0, 0, 0.035), wood)
