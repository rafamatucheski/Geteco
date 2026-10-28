extends "res://world/places/arcade/ArcadeGeometry.gd"
var leaves: Array[Node3D] = []
var open_amount := 0.0
## Folhas do kit pintado: giram em vez de correr.
var painted := false
const PAINTED := preload("res://world/places/bars/PaintedBarFacade.gd")
const PAINTED_STYLE := "bar-lastro"
func _ready() -> void:
	set_meta("place_id","harbor_bar")
	add_to_group("v2_walkin_facade")
	if PAINTED.available(PAINTED_STYLE):
		painted = true
		leaves = PAINTED.build(self,PAINTED_STYLE)
		set_process(false)
		set_physics_process(false)
		return
	box("Rear",Vector3(0,1.8,-5.88),Vector3(16,3.6,.24),"675347","Rear","stone")
	for side in [-1,1]:
		box("Side",Vector3(side*7.88,1.8,0),Vector3(.24,3.6,12),"675347","Side%d"%side,"stone")
		box("Front",Vector3(side*4.55,1.8,5.88),Vector3(6.9,3.6,.24),"805947","Front%d"%side,"stone")
		box("Window",Vector3(side*4.4,1.65,6.02),Vector3(4.9,1.8,.035),"314444")
		for x in [-2.5,0.0,2.5]: box("WindowFrame",Vector3(side*4.4+x,1.65,6.055),Vector3(.07,1.95,.07),"a28658","","metal")
		box("WindowSill",Vector3(side*4.4,.71,6.08),Vector3(5.2,.12,.3),"a28658","","metal")
		var leaf := Node3D.new()
		leaf.position = Vector3(side*.54,0,5.88)
		add_child(leaf)
		var panel := box("Door",Vector3(0,1.25,0),Vector3(1.06,2.5,.11),"3c4847")
		remove_child(panel)
		leaf.add_child(panel)
		_collision(leaf,Vector3(0,1.25,0),Vector3(1.06,2.5,.14))
		leaves.append(leaf)
	box("Fascia",Vector3(0,3.05,6.06),Vector3(15.7,.8,.2),"33413e")
	var label := Label3D.new()
	label.text = "LASTRO"
	label.font_size = 96
	label.pixel_size = .008
	label.position = Vector3(0,3.05,6.18)
	label.outline_size = 0
	label.modulate = Color("dec69a")
	add_child(label)
	box("Canopy",Vector3(0,2.61,6.4),Vector3(15.7,.11,1.1),"695145","","metal")
	box("Roof",Vector3(0,3.65,0),Vector3(16,.18,12),"505450","Roof","metal")
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
	if painted:
		for leaf in leaves: leaf.set_open_amount(open_amount)
		return
	for index in leaves.size(): leaves[index].position.x = (-1 if index == 0 else 1)*(.54+clampf(amount,0,1)*1.12)

