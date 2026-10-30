extends "res://world/places/arcade/ArcadeGeometry.gd"
## Fachada do Ferro Velho: galpãozinho de tijolo de 11 × 8 m (pedido de 30/10: a casca de 16 × 12 do
## Lastro ficava gigante na rua), telhado baixo de chapa, porta dupla de correr no meio da frente
## (+Z) e uma janela de cada lado. Entra pelo grupo `v2_walkin_facade`.
const SIZE := Vector2(11, 8)
const HEIGHT := 3.2
var leaves: Array[Node3D] = []
var open_amount := 0.0

func _ready() -> void:
	set_meta("place_id","harbor_gym")
	add_to_group("v2_walkin_facade")
	var half := SIZE * .5
	var front := half.y - .12
	box("Rear",Vector3(0,HEIGHT*.5,-front),Vector3(SIZE.x,HEIGHT,.24),"6e4a3c","Rear","stone")
	for side in [-1,1]:
		box("Side",Vector3(side*(half.x-.12),HEIGHT*.5,0),Vector3(.24,HEIGHT,SIZE.y),"6e4a3c","Side%d"%side,"stone")
		# Frente: do batente da porta (1,2 m do meio) até a quina.
		box("Front",Vector3(side*(1.2+(half.x-1.2)*.5),HEIGHT*.5,front),Vector3(half.x-1.2,HEIGHT,.24),"7d5242","Front%d"%side,"stone")
		box("Window",Vector3(side*3.35,1.55,front+.14),Vector3(2.6,1.3,.035),"3d4446")
		for x in [-1.3,0.0,1.3]: box("WindowFrame",Vector3(side*3.35+x,1.55,front+.175),Vector3(.07,1.42,.07),"3a3632","","metal")
		box("WindowSill",Vector3(side*3.35,.86,front+.2),Vector3(2.8,.1,.26),"3a3632","","metal")
		var leaf := Node3D.new()
		leaf.position = Vector3(side*.54,0,front)
		add_child(leaf)
		var panel := box("Door",Vector3(0,1.15,0),Vector3(1.06,2.3,.11),"2b2e30")
		remove_child(panel)
		leaf.add_child(panel)
		_collision(leaf,Vector3(0,1.15,0),Vector3(1.06,2.3,.14))
		leaves.append(leaf)
	box("Lintel",Vector3(0,2.75,front),Vector3(2.4,.9,.24),"7d5242","Lintel","stone")
	box("Fascia",Vector3(0,2.72,front+.18),Vector3(6.4,.55,.16),"1f2224")
	var label := Label3D.new()
	label.text = "FERRO VELHO · ACADEMIA"
	label.font_size = 56
	label.pixel_size = .008
	label.position = Vector3(0,2.72,front+.27)
	label.outline_size = 0
	label.modulate = Color("d9b46a")
	add_child(label)
	box("Roof",Vector3(0,HEIGHT+.08,0),Vector3(SIZE.x+.3,.16,SIZE.y+.3),"505450","Roof","metal")
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			_collision(self,child.position,child.mesh.get_aabb().size)
	flush()
	set_process(false)
	set_physics_process(false)

func _collision(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = at
	body.add_child(collision)
	parent.add_child(body)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	for index in leaves.size(): leaves[index].position.x = (-1 if index == 0 else 1)*(.54+open_amount*1.12)
