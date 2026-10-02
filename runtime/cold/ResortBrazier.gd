extends "res://assets/regions/source/world/mountain_pass/SummitSkiLodge3D.gd"
func _ready() -> void: pass

func build(kind: String) -> void:
	var wood := _mat("wood",Color("66503e"))
	var iron := _mat("iron",Color("303a40"),.8,.25)
	var stone := _mat("stone",Color("5b666c"))
	var amber := _mat("amber",Color("ecb76c"),.6,0,.4)
	if kind == "lamp":
		_box("Base",Vector3(0,.15,0),Vector3(.35,.3,.35),stone).set_meta("interior_solid_id",&"Lamp")
		_box("Mast",Vector3(0,1.25,0),Vector3(.14,2.5,.14),wood).set_meta("interior_solid_id",&"Lamp")
		_box("Arm",Vector3(.22,2.45,0),Vector3(.55,.07,.07),iron)
		_box("Lantern",Vector3(.43,2.17,0),Vector3(.26,.36,.26),amber)
		_box("Cap",Vector3(.43,2.39,0),Vector3(.36,.08,.36),iron)
		for side in [-1,1]: _box("Frame",Vector3(.43+side*.14,2.17,.12),Vector3(.025,.36,.025),iron)
	elif kind == "rack":
		for side in [-1,1]:
			_box("Upright",Vector3(side*.85,.6,0),Vector3(.09,1.2,.09),wood).set_meta("interior_solid_id",&"Rack")
			_box("Foot",Vector3(side*.85,.045,0),Vector3(.14,.09,.65),wood).set_meta("interior_solid_id",&"Rack")
		_box("Beam",Vector3(0,1.05,0),Vector3(1.9,.13,.12),wood).set_meta("interior_solid_id",&"Rack")
		for i in 6:
			# Whole-number grouping/index; preserve integer truncation and precision.
			@warning_ignore("integer_division")
			_box("Ski",Vector3(-.63+i*.25,.85,.14),Vector3(.10,1.7,.045),_mat("ski%d"%i,[Color("a74738"),Color("4d7181"),Color("b29a5a")][i/2]),Vector3(-9,0,2))
	else:
		_cylinder("StoneBase",Vector3(0,.12,0),.72,.24,preload("res://world/places/ShopInteriorMaterials.gd").material("stone",Color("5b666c"))).set_meta("interior_solid_id",&"Brazier")
		var bowl := preload("res://runtime/cold/FireArt.gd").bowl()
		bowl.position.y = .21
		add_child(bowl)
		bowl.set_meta("interior_solid_id",&"Brazier")
		var fuel := preload("res://runtime/cold/FireArt.gd").fuel()
		fuel.position.y = .53
		add_child(fuel)
		var flame := preload("res://runtime/cold/HearthEffects.gd").new()
		flame.position.y = .58
		flame.scale = Vector3.ONE * 1.5
		flame.smoke_height = .8
		add_child(flame)
		for side in [-1,1]:
			var id := StringName("Bench%d"%side)
			var bench := preload("res://world/urban_detail/BenchFinish.gd").create(1.6,.65,.52,1.14)
			bench.position = Vector3(side*2,0,0)
			bench.rotation.y = -side*PI/2
			bench.set_meta("interior_solid_id",id)
			add_child(bench)
