extends "res://world/places/supermarket/MarketGeometry.gd"
var open_amount := 0.0
var leaves: Array[Node3D] = []
func _ready() -> void:
	name = "BoaPraca"
	set_meta("place_id","harbor_supermarket")
	add_to_group("v2_walkin_facade")
	box("Back",Vector3(0,2.1,-5.5),Vector3(14.2,4.2,.3),"cfccad",true)
	for side in [-1,1]:
		box("Side%d"%side,Vector3(side*7,2.1,0),Vector3(.3,4.2,11),"c6c6ac",true)
		box("Front%d"%side,Vector3(side*4.25,1.5,5.5),Vector3(5.5,3,.2),"3c6553",true)
		box("Window%d"%side,Vector3(side*4.25,1.55,5.62),Vector3(4.9,2.05,.045),"698d87")
		for post in [-1,0,1]: box("WindowFrame",Vector3(side*4.25+post*1.65,1.55,5.66),Vector3(.045,2.15,.05),"d7d5bf")
		# Display crates make the use legible without category/slogan text.
		for i in 3:
			var x: float = side*4.25-1.4+i*1.4
			box("WindowCrate",Vector3(x,.57,5.73),Vector3(1.15,.5,.16),"b89158")
			for a in 5: product(4,Vector3(x-.43+a*.21,.84,5.78),["c47c3d","8eaa51","c7b754"][i])
	box("Roof",Vector3(0,4.23,0),Vector3(14.5,.22,11.4),"566358")
	for side in [-1,1]:
		box("RoofParapet",Vector3(side*7.1,4.43,0),Vector3(.22,.35,11.2),"acb5a3")
		box("RoofParapet",Vector3(0,4.43,side*5.5),Vector3(14.2,.35,.22),"acb5a3")
		box("RoofVent",Vector3(side*3.8,4.64,-2.2),Vector3(1.7,.6,1.15),"82938b",false,true)
		for i in 10: piece("box",Vector3(side*3.8-.68+i*.15,4.96,-2.2),Vector3(.055,.025,.92),"354b47")
		box("WallBase",Vector3(side*7.17,.23,0),Vector3(.08,.46,10.9),"718177")
		for z in [-3.7,0,3.7]: box("WallPier",Vector3(side*7.17,1.75,z),Vector3(.10,3.1,.22),"b6bba6")
		box("DrainPipe",Vector3(side*7.2,1.95,-4.7),Vector3(.09,3.9,.09),"687c71",false,true)
	box("Fascia",Vector3(0,3.5,5.55),Vector3(14.5,1.0,.32),"295d47")
	box("Canopy",Vector3(0,2.98,6.05),Vector3(14.5,.12,1.35),"dbcfab")
	var name_label := Label3D.new()
	name_label.text = "BOA PRAÇA"
	name_label.font_size = 100
	name_label.pixel_size = .010
	name_label.position = Vector3(0,3.52,5.73)
	name_label.modulate = Color("f3e4b4")
	name_label.outline_size = 0
	add_child(name_label)
	for side in [-1,1]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side*.66,0,5.52)
		add_child(leaf)
		var glass := box("Door",Vector3(0,1.35,0),Vector3(1.3,2.7,.09),"7a9f96")
		remove_child(glass); leaf.add_child(glass)
		for edge in [-1,1]:
			var frame := box("DoorRail",Vector3(edge*.62,1.35,.055),Vector3(.045,2.7,.06),"d9d7c8")
			remove_child(frame); leaf.add_child(frame)
		leaves.append(leaf)
		_solid(leaf,Vector3(0,1.35,0),Vector3(1.3,2.7,.13))
	for mesh in get_children():
		if mesh is MeshInstance3D and mesh.has_meta("interior_solid_id"):
			_solid(self,mesh.position,mesh.mesh.get_aabb().size)
	flush_batches()

func _solid(parent: Node3D, point: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1; body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = point
	body.add_child(collision)
	parent.add_child(body)

func set_open_amount(amount: float) -> void:
	open_amount = clampf(amount,0,1)
	for i in leaves.size(): leaves[i].position.x = (-1 if i == 0 else 1)*(.66+open_amount*1.37)
