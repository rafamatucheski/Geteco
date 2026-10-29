extends RefCounted
## Exterior pintado (PaintedFacadeKit) do Lastro e do Sede, pacotes do Codex de 28/10.
##
## Como no banco pintado: a porta é aberta pela WeaponShopEntrance (`set_open_amount`), não pela
## proximidade, então o casco de caixa cheia e as zonas de abertura do kit saem e a colisão é
## refeita em paredes com o vão da porta. A pintura manda no tamanho do prédio (o kit tira a altura
## da proporção da frente): 13,4 m no Lastro e 12 m no Sede, dentro do lote de 16 x 12 m; o
## interior continua com 16 x 12 m, porque é outra sala.
const KIT := preload("res://world/urban_detail/PaintedFacadeKit.gd")
const DEPTH := 12.0
const WALL := .24
## Corredor escuro atrás da folha de entrada: sem ele, a porta aberta mostrava o casco vazio.
const VESTIBULE := 1.6


static func available(style: String) -> bool:
	return KIT.enabled() and FileAccess.file_exists(KIT.ROOT + style + "/style.json")


static func size_for(style: String, depth := DEPTH) -> Vector3:
	var natural := KIT.natural_size(style)
	return Vector3(natural.x, natural.y, depth)


## Monta a fachada em `owner` (frente em +Z, centro na origem do lugar) e devolve as folhas da
## entrada de verdade, que `owner.set_open_amount` gira. `depth`: o escritório da mina
## (MiningOfficeFacade) tem 5 m de fundo, não os 12 m dos bares.
static func build(owner: Node3D, style: String, depth := DEPTH) -> Array[Node3D]:
	var size := size_for(style, depth)
	var scratch := Node3D.new()
	scratch.name = "PaintedSolidScratch"
	owner.add_child(scratch)
	var root := KIT.build(owner, style, size, scratch, 0.0)
	for hull in scratch.find_children("PaintedFacadeSolid", "StaticBody3D", true, false): hull.free()
	var leaves: Array[Node3D] = []
	var anchor := root.get_node_or_null("Doorway_front")
	var opening := Vector2(1.8, 2.4)
	if anchor != null:
		opening = anchor.get_meta("opening_size", opening)
		for leaf_name in ["Door", "Door2"]:
			var leaf := anchor.get_node_or_null(leaf_name) as KIT.PaintedDoor
			if leaf == null: continue
			for zone in leaf.find_children("DoorZone", "Area3D", false, false): zone.free()
			leaves.append(leaf)
	var wall_h := size.y - float(root.get_meta("ground_sink", 0.0))
	var half := size*.5
	var gap := opening.x*.5
	var front_w := half.x-gap
	_solid(owner, Vector3(-(gap+front_w*.5), wall_h*.5, half.z-WALL*.5), Vector3(front_w, wall_h, WALL))
	_solid(owner, Vector3(gap+front_w*.5, wall_h*.5, half.z-WALL*.5), Vector3(front_w, wall_h, WALL))
	# Verga sobre o vão: a folha pintada é mais baixa que a parede.
	_solid(owner, Vector3(0, (opening.y+wall_h)*.5, half.z-WALL*.5), Vector3(opening.x, maxf(.05, wall_h-opening.y), WALL))
	_solid(owner, Vector3(0, wall_h*.5, -half.z+WALL*.5), Vector3(size.x, wall_h, WALL))
	for side in [-1, 1]:
		_solid(owner, Vector3(side*(half.x-WALL*.5), wall_h*.5, 0), Vector3(WALL, wall_h, size.z))
	_solid(owner, Vector3(0, wall_h+.09, 0), Vector3(size.x, .18, size.z))
	var corridor := MeshInstance3D.new()
	corridor.name = "EntranceVestibule"
	var box := BoxMesh.new()
	box.size = Vector3(opening.x, opening.y, VESTIBULE)
	corridor.mesh = box
	corridor.position = Vector3(0, opening.y*.5, half.z-VESTIBULE*.5-.05)
	corridor.material_override = KIT._corridor_material()
	owner.add_child(corridor)
	scratch.queue_free()
	return leaves


static func _solid(owner: Node3D, at: Vector3, box_size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "PaintedBarSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = box_size
	shape.shape = box
	shape.position = at
	body.add_child(shape)
	owner.add_child(body)
