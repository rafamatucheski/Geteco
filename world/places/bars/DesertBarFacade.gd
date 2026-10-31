extends "res://world/places/arcade/ArcadeGeometry.gd"
## A varanda da frente e as portas vaivém de saloon do Sede pertencem ao chunk em streaming.
var leaves: Array[Node3D] = []
var open_amount := 0.0
## Folhas do kit pintado; a varanda, os bancos e a placa continuam 3D por cima da pintura.
var painted := false
const PAINTED := preload("res://world/places/bars/PaintedBarFacade.gd")
const PAINTED_STYLE := "bar-sede"

func _ready() -> void:
	name = "SedeFacade"
	set_meta("place_id","desert_bar")
	add_to_group("v2_walkin_facade")
	if PAINTED.available(PAINTED_STYLE):
		_painted_porch()
		return
	for side in [-1,1]:
		box("SideWall",Vector3(side*7.88,1.8,0),Vector3(.24,3.6,12),"ad906b","SideWall%d"%side,"stone")
		box("FrontWall",Vector3(side*4.5,1.8,5.88),Vector3(6.76,3.6,.24),"8d6744","FrontWall%d"%side,"wood")
		box("WindowFrame",Vector3(side*4.4,1.65,6.03),Vector3(3.8,1.9,.10),"4b3829","","wood")
		box("WindowGlass",Vector3(side*4.4,1.65,6.092),Vector3(3.53,1.63,.024),"35433d")
		for cross in [-1,1]:
			detail(Vector3(side*4.4+cross*.59,1.65,6.113),Vector3(.06,1.65,.03),"b18e58","wood")
			detail(Vector3(side*4.4,1.65+cross*.28,6.113),Vector3(3.55,.06,.03),"b18e58","wood")
		box("PorchPost",Vector3(side*6.8,1.56,7.65),Vector3(.22,3.12,.22),"685037","PorchPost%d"%side,"wood")
		box("PorchBench",Vector3(side*4.8,.43,6.95),Vector3(2.6,.86,.64),"72583c","PorchBench%d"%side,"wood")
		box("PorchBenchBack",Vector3(side*4.8,.86,6.65),Vector3(2.6,.70,.12),"72583c","PorchBench%d"%side,"wood")
	box("RearWall",Vector3(0,1.8,-5.88),Vector3(16,3.6,.24),"b19a78","RearWall","stone")
	box("Roof",Vector3(0,3.72,0),Vector3(16.5,.24,12.5),"71644d","Roof","metal")
	box("PorchRoof",Vector3(0,3.20,6.8),Vector3(16.5,.14,2.8),"82704f","","wood")
	box("Fascia",Vector3(0,3.88,6.34),Vector3(15.9,.98,.22),"59432c","","wood")
	for y in [3.46,4.30]: detail(Vector3(0,y,6.465),Vector3(15.7,.06,.03),"be9d63","wood")
	var label := Label3D.new()
	label.name="SedeName"
	label.text="SEDE"
	label.font_size=96
	label.pixel_size=.009
	label.outline_size=0
	label.modulate=Color("e1c48a")
	label.position=Vector3(0,3.89,6.48)
	add_child(label)
	# O telhado da varanda esconde a fachada da câmera alta, então o nome se repete numa
	# placa em pé na borda da frente da varanda.
	box("PorchSign",Vector3(0,3.62,8.16),Vector3(3.4,.72,.10),"59432c","","wood")
	detail(Vector3(0,3.99,8.16),Vector3(3.5,.05,.12),"be9d63","wood")
	var porch_label := label.duplicate()
	porch_label.name="SedePorchName"
	porch_label.pixel_size=.007
	porch_label.position=Vector3(0,3.62,8.23)
	add_child(porch_label)
	for side in [-1,1]:
		var hinge := Node3D.new()
		hinge.name="SaloonHinge%d"%side
		hinge.position=Vector3(side*1.10,0,5.88)
		add_child(hinge)
		var leaf := box("SaloonDoor",Vector3(-side*.54,1.27,0),Vector3(1.06,2.54,.12),"765432","","wood")
		remove_child(leaf)
		hinge.add_child(leaf)
		for slat in 9:
			var trim := box("DoorSlat",Vector3(-side*.54,1.00+slat*.13,.071),Vector3(.91,.07,.045),"9b7749","","wood")
			remove_child(trim)
			hinge.add_child(trim)
		_collision(hinge,Vector3(-side*.54,1.27,0),Vector3(1.06,2.54,.14),"SedeDoor")
		leaves.append(hinge)
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			_collision(self,child.position,child.mesh.get_aabb().size,str(child.get_meta("interior_solid_id")))
	flush()
	set_process(false)
	set_physics_process(false)

func _collision(parent: Node3D, at: Vector3, size: Vector3, label: String) -> void:
	var body := StaticBody3D.new()
	body.name=label+"Collision"
	body.collision_layer=1
	body.collision_mask=0
	body.set_meta("interior_solid_id",label)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size=size
	collision.shape=shape
	collision.position=at
	body.add_child(collision)
	parent.add_child(body)

func _painted_porch() -> void:
	painted = true
	leaves = PAINTED.build(self,PAINTED_STYLE)
	var half_w: float = PAINTED.size_for(PAINTED_STYLE).x*.5
	# Bancos sob as janelas pintadas e postes na beira do telhado da varanda, mais estreita.
	for side in [-1,1]:
		box("PorchPost",Vector3(side*(half_w-.4),1.56,7.65),Vector3(.22,3.12,.22),"685037","PorchPost%d"%side,"wood")
		box("PorchBench",Vector3(side*3.4,.43,6.95),Vector3(2.6,.86,.64),"72583c","PorchBench%d"%side,"wood")
		box("PorchBenchBack",Vector3(side*3.4,.86,6.65),Vector3(2.6,.70,.12),"72583c","PorchBench%d"%side,"wood")
	box("PorchRoof",Vector3(0,3.20,6.8),Vector3(half_w*2+.5,.14,2.8),"82704f","","wood")
	# A platibanda pintada fica atrás do telhado da varanda para a câmera alta: o nome se repete
	# numa placa na beira dela.
	box("PorchSign",Vector3(0,3.62,8.16),Vector3(3.4,.72,.10),"59432c","","wood")
	detail(Vector3(0,3.99,8.16),Vector3(3.5,.05,.12),"be9d63","wood")
	var label := Label3D.new()
	label.name="SedePorchName"
	label.text="SEDE"
	label.font_size=96
	label.pixel_size=.007
	label.outline_size=0
	label.modulate=Color("e1c48a")
	label.position=Vector3(0,3.62,8.23)
	add_child(label)
	for child in get_children():
		if child is MeshInstance3D and child.has_meta("interior_solid_id"):
			_collision(self,child.position,child.mesh.get_aabb().size,str(child.get_meta("interior_solid_id")))
	flush()
	set_process(false)
	set_physics_process(false)

func set_open_amount(amount: float) -> void:
	open_amount=clampf(amount,0,1)
	if painted:
		for leaf in leaves: leaf.set_open_amount(open_amount)
		return
	for index in leaves.size(): leaves[index].rotation.y=(-1 if index==0 else 1)*open_amount*PI*.55
