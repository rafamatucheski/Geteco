extends "res://assets/regions/source/world/harbor/cemetery/CemeteryPropBuilder.gd"

func _ready() -> void:
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

func _solid(id: String, size: Vector3, point: Vector3, color: String) -> MeshInstance3D:
	var mesh := box(id,size,point,color)
	mesh.set_meta("interior_solid_id",StringName(id))
	return mesh
