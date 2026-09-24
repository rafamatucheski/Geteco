extends "res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd"

func _ready() -> void:
	var timber := _mat("timber",Color("493c32"))
	var stone := _mat("stone",Color("535b60"))
	var iron := _mat("iron",Color("26333c"),.7,.2)
	var snow := _mat("snow",Color("d8e1e3"))
	var glass := _mat("glass",Color("657e83"),.25,.25)
	_box("Foundation",Vector3(0,.12,0),Vector3(6.7,.24,4.0),stone)
	_box("BackWall",Vector3(0,1.6,-1.8),Vector3(6.5,3.0,.24),timber).set_meta("interior_solid_id",&"ShopBack")
	for side in [-1,1]:
		_box("SideWall",Vector3(side*3.15,1.6,0),Vector3(.24,3.0,3.6),timber).set_meta("interior_solid_id",StringName("ShopSide%d"%side))
		_box("WindowPlinth",Vector3(side*1.88,.45,1.8),Vector3(2.5,.65,.25),stone).set_meta("interior_solid_id",StringName("ShopWindow%d"%side))
		_box("WindowLintel",Vector3(side*1.88,2.75,1.8),Vector3(2.5,.3,.25),timber)
		_box("WindowBackdrop%d"%side,Vector3(side*1.88,1.65,1.18),Vector3(2.45,1.9,.06),glass)
		for x in [side*.65,side*3.1]:
			_box("WindowFrame",Vector3(x,1.6,1.83),Vector3(.08,2.2,.12),iron)
		var dummy := preload("res://assets/regions/source/world/mountain_pass/WinterResidentModel.gd").new()
		dummy.role = "visitor"
		dummy.coat_color = Color("a74739") if side<0 else Color("396676")
		dummy.appearance_variant = 2 if side<0 else 3
		add_child(dummy)
		dummy.position = Vector3(side*1.88,.72,1.48)
		dummy.scale = Vector3.ONE * .9
		dummy.set_process(false)
		_box("WindowSill",Vector3(side*1.88,.74,1.85),Vector3(2.55,.09,.40),timber)
		for y in [1.0,1.35,1.7,2.05,2.4]:
			_box("Cladding",Vector3(side*3.29,y,0),Vector3(.035,.022,3.7),iron)
		var roof := _box("Roof",Vector3(side*1.7,3.55,0),Vector3(3.8,.20,4.7),iron,Vector3(0,0,-side*23))
		_box("SnowRoof",roof.position+Vector3(0,.13,0),Vector3(3.8,.10,4.7),snow,Vector3(0,0,-side*23))
	_box("Door",Vector3(0,1.18,1.82),Vector3(1.1,2.2,.14),iron).set_meta("interior_solid_id",&"ShopDoor")
	_box("DoorGlass",Vector3(0,1.4,1.9),Vector3(.84,1.3,.035),glass)
	_box("Handle",Vector3(.38,1.1,1.94),Vector3(.03,.25,.035),stone)
	_box("Threshold",Vector3(0,.035,2.25),Vector3(1.8,.07,.7),stone)
	var label := Label3D.new()
	label.text = "BOUTIQUE ALPINA"
	label.font_size = 48
	label.pixel_size = .007
	label.position = Vector3(0,3.04,2.07)
	label.modulate = Color("ddd5be")
	add_child(label)
