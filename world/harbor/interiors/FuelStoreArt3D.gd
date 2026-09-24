extends "res://world/harbor/cemetery/CemeteryPropBuilder.gd"

var compact_mode := false
var roof: Node3D
var door_left: MeshInstance3D
var door_right: MeshInstance3D

func _ready() -> void:
	if compact_mode:
		_build_compact()
		return
	box("Foundation", Vector3(14,.18,10), Vector3(0,-.12,0), "303a36")
	for x in 14:
		for z in 10:
			box("FloorTile",Vector3(.985,.035,.985),Vector3(-6.5+x,0,-4.5+z),"9b9d89" if (x+z)%2 else "8a9283")
	_solid("BackWall",Vector3(14,3,.2),Vector3(0,1.5,-5),"b6b69b")
	for side in [-1.0,1.0]:
		_solid("SideWall%d"%int(side),Vector3(.2,3,10),Vector3(side*7,1.5,0),"788e83")
		_solid("FrontWall%d"%int(side),Vector3(5.8,.55,.2),Vector3(side*4.1,.275,5),"394f45")
		box("WallTrim",Vector3(.08,.18,10),Vector3(side*6.86,1.2,0),"dbb06c")
	for x in [-5.8,-4.1,-2.4]:
		_solid("Cooler%.1f"%x,Vector3(1.5,2.45,1.05),Vector3(x,1.225,-4.35),"334b47")
		box("CoolerInset",Vector3(1.31,2.08,.06),Vector3(x,1.27,-3.79),"657d70")
		for y in [.46,1.05,1.64]:
			box("CoolerShelf",Vector3(1.2,.035,.45),Vector3(x,y,-3.63),"b5b9a3")
			for j in 5:
				cylinder("Bottle",.065,.31,Vector3(x-.44+j*.22,y+.18,-3.62),["9a5e36","74974e","bc9d4c"][j%3])
		box("CoolerHandle",Vector3(.035,.6,.05),Vector3(x+.56,1.3,-3.51),"c4c2a8")
	for index in 2:
		var x := -4.2 + index*3.0
		var id := "GroceryIsland%d"%index
		_solid(id,Vector3(1.15,.23,3.3),Vector3(x,.14,.3),"55665b")
		for level in 3:
			_solid(id,Vector3(1.2,.07,3.4),Vector3(x,.5+level*.5,.3),"c4b383")
			for row in 6:
				for side in [-1,1]:
					_solid(id,Vector3(.34,.31,.37),Vector3(x+side*.27,.69+level*.5,-1.02+row*.52),["c6a465","8e4e3a","576c48","d0bd92"][(row+level)%4])
	_solid("Counter",Vector3(3.4,1.05,1.0),Vector3(4.6,.525,-2.8),"735740")
	_solid("Counter",Vector3(3.55,.085,1.12),Vector3(4.6,1.09,-2.8),"c8b991")
	_solid("Counter",Vector3(.55,.3,.4),Vector3(4.7,1.27,-2.8),"293b35")
	box("RegisterScreen",Vector3(.38,.19,.02),Vector3(4.7,1.4,-2.57),"83a783")
	_solid("CoffeeStation",Vector3(1.4,.9,1),Vector3(5.5,.45,1.7),"7d684c")
	_solid("CoffeeStation",Vector3(.7,.7,.6),Vector3(5.5,1.25,1.7),"3f4e45")
	for x in [5.25,5.75]:
		cylinder("CoffeePot",.15,.3,Vector3(x,1.16,2.05),"3e2d20")
	box("EntryMat",Vector3(2,.015,1.4),Vector3(0,.04,3.8),"465c48")
	for x in [-4.5,4.5]:
		box("PracticalHousing",Vector3(1.7,.1,.32),Vector3(x,2.8,-.4),"e1d9b7")
		var light := OmniLight3D.new()
		light.position = Vector3(x,2.7,-.4)
		light.light_color = Color("ffe6b7")
		light.light_energy = .9
		light.omni_range = 6
		add_child(light)

func _build_compact() -> void:
	# The city lot is 230 x 180 pixels; leave one central pedestrian aisle.
	box("Foundation", Vector3(8.4,.18,4.4), Vector3(0,-.12,0), "303a36")
	var floor_batches := {"9b9d89": [], "8a9283": []}
	for x in 8:
		for z in 4:
			var color := "9b9d89" if (x+z)%2 else "8a9283"
			floor_batches[color].append(Vector3(-3.5+x,0,-1.5+z))
	for color in floor_batches:
		_batch_boxes("FloorTile",Vector3(1.02,.035,1.06),floor_batches[color],color)
	_solid("RearWall", Vector3(8.4,3,.2), Vector3(0,1.5,-2.2), "b6b69b")
	for side in [-1.0,1.0]:
		_solid("SideWall%d"%int(side), Vector3(.2,3,4.4), Vector3(side*4.2,1.5,0), "788e83")
		_solid("FrontWall%d"%int(side), Vector3(3.25,.55,.2), Vector3(side*2.58,.275,2.2), "394f45")
		box("FrontGlass%d"%int(side), Vector3(3.12,1.75,.07), Vector3(side*2.58,1.48,2.23), "5f8783")
		box("FrontFrame%d"%int(side), Vector3(3.25,.12,.2), Vector3(side*2.58,2.4,2.2), "c9b58a")
	# Stock belongs against the walls; the aisle stays clear from door to counter.
	var goods_batches := {"c6a465": [], "8e4e3a": [], "576c48": [], "d0bd92": []}
	for side in [-1.0,1.0]:
		var sx: float = side*3.67
		_solid("WallStock%d"%int(side), Vector3(.66,1.95,2.05), Vector3(sx,.98,-.45), "53645b")
		for shelf in 3:
			box("StockShelf", Vector3(.69,.065,2.08), Vector3(sx,.42+shelf*.52,-.45), "c4b383")
			for row in 4:
				var color: String = ["c6a465","8e4e3a","576c48","d0bd92"][(row+shelf)%4]
				goods_batches[color].append(Vector3(sx,.62+shelf*.52,-1.17+row*.47))
	for color in goods_batches:
		_batch_boxes("StockGoods",Vector3(.28,.3,.36),goods_batches[color],color)
	_solid("Cooler", Vector3(1.45,2.1,.62), Vector3(-2.65,1.05,-1.78), "334b47")
	box("CoolerGlass", Vector3(1.24,1.7,.05), Vector3(-2.65,1.06,-1.44), "72918a")
	_solid("Counter", Vector3(2.8,1.05,.8), Vector3(1.5,.525,-1.1), "735740")
	box("CounterTop", Vector3(2.96,.085,.92), Vector3(1.5,1.09,-1.1), "c8b991")
	box("Register", Vector3(.42,.3,.34), Vector3(2.25,1.27,-1.1), "293b35")
	box("RegisterScreen", Vector3(.3,.17,.02), Vector3(2.25,1.4,-.91), "83a783")
	box("StaffMat", Vector3(2.95,.015,.58), Vector3(1.5,.025,-1.78), "8a9283")
	_solid("CoffeeStation", Vector3(.75,.85,.67), Vector3(3.23,.425,1.3), "7d684c")
	box("CoffeePot", Vector3(.32,.34,.32), Vector3(3.23,1.02,1.3), "3e2d20")
	box("EntryMat", Vector3(1.8,.015,.75), Vector3(0,.04,1.74), "465c48")
	for side in [-1.0,1.0]:
		box("PracticalHousing", Vector3(1.2,.1,.28), Vector3(side*2.25,2.75,-.3), "e1d9b7")
		var light := OmniLight3D.new()
		light.position = Vector3(side*2.25,2.6,-.3)
		light.light_color = Color("ffe6b7")
		light.light_energy = .9
		light.omni_range = 5
		add_child(light)
	# Exterior shell and roof share this viewport with the playable interior.
	roof = Node3D.new()
	roof.name = "CutawayRoof"
	add_child(roof)
	var roof_panel := box("RoofPanel", Vector3(8.65,.18,4.65), Vector3(0,3.08,0), "485653")
	roof_panel.reparent(roof, true)
	for side in [-1.0,1.0]:
		var fascia := box("RoofFascia", Vector3(4.32,.38,.24), Vector3(side*2.16,2.8,2.27), "35615a")
		fascia.reparent(roof, true)
		var top_front := box("FrontUpper", Vector3(3.25,.58,.18), Vector3(side*2.58,2.68,2.2), "a7a18a")
		top_front.reparent(roof, true)
	door_left = box("DoorLeft", Vector3(.95,2.28,.09), Vector3(-.47,1.14,2.22), "507b77")
	door_right = box("DoorRight", Vector3(.95,2.28,.09), Vector3(.47,1.14,2.22), "507b77")

func set_open_amount(amount: float) -> void:
	if is_instance_valid(door_left): door_left.position.x = -.47 - .96*amount
	if is_instance_valid(door_right): door_right.position.x = .47 + .96*amount

func set_roof_visible(value: bool) -> void:
	if is_instance_valid(roof): roof.visible = value

func _batch_boxes(label: String, size: Vector3, points: Array, color: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var batch := MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_3D
	batch.mesh = mesh
	batch.instance_count = points.size()
	for index in points.size():
		batch.set_instance_transform(index,Transform3D(Basis.IDENTITY,points[index]))
	var instance := MultiMeshInstance3D.new()
	instance.name = label + color
	instance.multimesh = batch
	instance.material_override = material(color)
	add_child(instance)

func _solid(id: String, size: Vector3, point: Vector3, color: String) -> MeshInstance3D:
	var mesh := box(id,size,point,color)
	mesh.set_meta("interior_solid_id",StringName(id))
	return mesh
