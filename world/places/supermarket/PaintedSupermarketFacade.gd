extends RefCounted
## Exterior pintado (PaintedFacadeKit) do Boa Praça. Playtest de 30/10: "ainda tá com as
## texturas antigas" — a fachada era a última da North Frontage feita de caixas de cor lisa.
##
## Pacote "mercearia-esquina" (o único mercado pintado sem nome escrito na pintura; o
## "mercado-ilha" traz NORTHBANK GROCERY). O nome próprio vai num Label3D na faixa amarela
## entre as janelas e o toldo, como era antes. Mesma receita do PaintedBarFacade: a porta é
## aberta pela WeaponShopEntrance (`set_open_amount`), não pela proximidade, então o casco
## de caixa cheia e as zonas de abertura do kit saem e a colisão é refeita em paredes com o
## vão. A diferença é que o vão desta pintura não fica no meio da frente: as paredes saem
## em volta de `door_x()`, e a WeaponShopEntrance usa o mesmo número para a porta.
##
## Largura natural da pintura (10 m, um módulo) dentro do lote de 14,2 m, como o banco: esticar
## para 14,2 m alargava janelas e toldo em 42%. Fundo de 11 m: a frente fica em z = 5,5, o plano
## da porta antiga. Materiais: os do kit, já desenhados sob a cortina pelo PaintedFacadePrewarm
## (todos os estilos de assets/facades), então nada compila na primeira aparição.
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const STYLE := "mercearia-esquina"
const DEPTH := 11.0
const WALL := .24
## Corredor escuro atrás da folha de entrada: sem ele, a porta aberta mostrava o casco vazio.
const VESTIBULE := 1.6
## GETECO_PAINTED_SUPERMARKET=0 volta às caixas antigas (A/B).
static var _enabled := OS.get_environment("GETECO_PAINTED_SUPERMARKET") != "0"
## -1 = ainda não conferido. A WeaponShopEntrance pergunta a cada quadro (posição da porta).
static var _available := -1


static func available() -> bool:
	if _available < 0:
		_available = 1 if _enabled and KIT.enabled() and FileAccess.file_exists(KIT.ROOT + STYLE + "/style.json") else 0
	return _available == 1


static func size() -> Vector3:
	var natural := KIT.natural_size(STYLE)
	return Vector3(natural.x, natural.y, DEPTH)


## Meio do vão da entrada (x local, frente em +Z).
static func door_x() -> float:
	return KIT.nearest_door_x(STYLE, size().x, 0.0)


## Plano da folha fechada (z local): a frente menos o recuo da folha no kit.
static func door_z() -> float:
	return DEPTH * .5 - KIT.LEAF_INSET


## Largura e altura do vão pintado da frente, em metros.
static func opening() -> Vector2:
	var built := size()
	for entry in KIT.openings(STYLE, "front"):
		if not bool(entry.leaf): continue
		var rect: Array = entry.rect
		return Vector2((float(rect[2]) - float(rect[0])) * built.x, (float(rect[3]) - float(rect[1])) * built.y)
	return Vector2(.93, 2.3)


## Quanto o kit afunda o prédio para a soleira encostar na calçada (mesma conta do kit).
static func ground_sink() -> float:
	var wall_h := size().y
	var lowest := INF
	for entry in KIT.openings(STYLE, "front"):
		if bool(entry.leaf): lowest = minf(lowest, (1.0 - float(entry.rect[3])) * wall_h)
	return maxf(0.0, lowest - 0.03) if lowest < INF else 0.0


## Topo da laje acima do chão (HarborServiceRoofCatalog), com a cornija do kit.
static func roof_height() -> float:
	return size().y - ground_sink() + .14


## Monta a fachada em `owner` (centro do lugar na origem) e devolve as folhas da entrada.
static func build(owner: Node3D) -> Array[Node3D]:
	var built := size()
	var gap_center := door_x()
	var scratch := Node3D.new()
	scratch.name = "PaintedSolidScratch"
	owner.add_child(scratch)
	var root := KIT.build(owner, STYLE, built, scratch, gap_center)
	for hull in scratch.find_children("PaintedFacadeSolid", "StaticBody3D", true, false): hull.free()
	var leaves: Array[Node3D] = []
	var anchor := root.get_node_or_null("Doorway_front")
	var gap := opening()
	if anchor != null:
		gap = anchor.get_meta("opening_size", gap)
		for leaf_name in ["Door", "Door2"]:
			var leaf := anchor.get_node_or_null(leaf_name) as KIT.PaintedDoor
			if leaf == null: continue
			# A porta abre pelo empurrão (WeaponShopEntrance), não pela proximidade.
			for zone in leaf.find_children("DoorZone", "Area3D", false, false): zone.free()
			leaves.append(leaf)
	var wall_h := built.y - float(root.get_meta("ground_sink", 0.0))
	var half := built * .5
	var left_edge := gap_center - gap.x * .5
	var right_edge := gap_center + gap.x * .5
	var front_z := half.z - WALL * .5
	_solid(owner, Vector3((-half.x + left_edge) * .5, wall_h * .5, front_z), Vector3(left_edge + half.x, wall_h, WALL))
	_solid(owner, Vector3((half.x + right_edge) * .5, wall_h * .5, front_z), Vector3(half.x - right_edge, wall_h, WALL))
	# Verga sobre o vão: a folha pintada é mais baixa que a parede.
	_solid(owner, Vector3(gap_center, (gap.y + wall_h) * .5, front_z), Vector3(gap.x, maxf(.05, wall_h - gap.y), WALL))
	_solid(owner, Vector3(0, wall_h * .5, -half.z + WALL * .5), Vector3(built.x, wall_h, WALL))
	for side in [-1, 1]:
		_solid(owner, Vector3(side * (half.x - WALL * .5), wall_h * .5, 0), Vector3(WALL, wall_h, built.z))
	_solid(owner, Vector3(0, wall_h + .09, 0), Vector3(built.x, .18, built.z))
	var corridor := MeshInstance3D.new()
	corridor.name = "EntranceVestibule"
	var box := BoxMesh.new()
	box.size = Vector3(gap.x, gap.y, VESTIBULE)
	corridor.mesh = box
	corridor.position = Vector3(gap_center, gap.y * .5, half.z - VESTIBULE * .5 - .05)
	corridor.material_override = KIT._corridor_material()
	owner.add_child(corridor)
	# Nome próprio na faixa de reboco entre as janelas e o toldo (36% da altura da pintura,
	# medido de cima em front.jpg), menos o que o kit afundou.
	var name_label := Label3D.new()
	name_label.name = "ProperName"
	name_label.text = "BOA PRAÇA"
	name_label.font_size = 64
	name_label.pixel_size = .010
	name_label.position = Vector3(0, built.y * (1.0 - .36) - ground_sink(), half.z + .03)
	name_label.modulate = Color("2e5a46")
	name_label.outline_size = 0
	owner.add_child(name_label)
	scratch.queue_free()
	return leaves


static func _solid(owner: Node3D, at: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "PaintedSupermarketSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	owner.add_child(body)
