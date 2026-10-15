extends Node3D
## Porta dupla da Umbra (casa assombrada do parque). Antes era uma placa escura
## colada na fachada e a entrada era só pela ação "Entrar": o jogador empurrava a
## porta, nada abria ("no parque tem porta que nem abre"). Agora é a mesma entrada
## de empurrar das lojas (WeaponShopEntrance): as folhas giram para dentro de um
## vão recuado e quem atravessa entra na casa.
const GEOMETRY := preload("res://world/places/amusement_park/ParkGeometry.gd")
const PLACE_ID := "harbor_haunted_house"
## Cada folha cobre metade do vão de 2,3 m; o recuo (1,3 m) cabe a folha aberta.
const LEAF := Vector3(1.15, 2.55, .08)
var open_amount := 0.0
## Dobradiça esquerda: WeaponShopEntrance mede o contato por `hinge`.
var hinge: Node3D
var hinge_right: Node3D

func _init() -> void:
	name = "UmbraDoor"
	set_meta("place_id", PLACE_ID)
	hinge = _leaf("UmbraLeafLeft", -1.0)
	hinge_right = _leaf("UmbraLeafRight", 1.0)

func _ready() -> void:
	add_to_group("v2_walkin_facade")
	set_open_amount(open_amount)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount, 0.0, 1.0)
	# +Y leva a ponta da folha esquerda (+X) para -Z; a direita gira ao contrário.
	hinge.rotation.y = open_amount * PI * .5
	hinge_right.rotation.y = -open_amount * PI * .5

## Folha com dobradiça na ombreira `side` (-1 esquerda, +1 direita), plano da
## fachada em z=0 deste nó; a folha fica 5 cm para dentro do vão.
func _leaf(label: String, side: float) -> Node3D:
	var pivot := GEOMETRY.new()
	pivot.name = label
	pivot.position = Vector3(side * LEAF.x, 0, -.05)
	add_child(pivot)
	var middle := Vector3(-side * LEAF.x * .5, LEAF.y * .5 + .02, 0)
	pivot.box("Leaf", middle, LEAF, "181b24", false, "wood")
	pivot.box("Panel", middle + Vector3(0, .25, .045), Vector3(LEAF.x * .7, 1.5, .02), "2b2735", false, "wood")
	pivot.box("Handle", Vector3(-side * (LEAF.x - .14), 1.1, .07), Vector3(.05, .22, .05), "8e7a5a", false, "metal")
	pivot.flush()
	var body := StaticBody3D.new()
	body.name = "LeafSolid"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = LEAF
	shape.shape = box
	shape.position = middle
	body.add_child(shape)
	pivot.add_child(body)
	return pivot
