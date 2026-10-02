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
		_cylinder("StoneBase",Vector3(0,.12,0),.72,.24,stone).set_meta("interior_solid_id",&"Brazier")
		var bowl := _cylinder("IronBowl",Vector3(0,.42,0),.58,.35,iron)
		bowl.mesh.bottom_radius = .30
		bowl.set_meta("interior_solid_id",&"Brazier")
		_cylinder("Embers",Vector3(0,.60,0),.48,.025,_mat("embers",Color("bd6134"),.8,0,.5))
		for i in 5:
			var flame := _cylinder("Flame",Vector3(sin(i*2.4)*.24,.74,cos(i*2.4)*.24),.10,.29,amber)
			flame.mesh.top_radius = .0
		for side in [-1,1]:
			var id := StringName("Bench%d"%side)
			_box("Seat",Vector3(side*1.9,.46,0),Vector3(.55,.12,1.6),wood).set_meta("interior_solid_id",id)
			_box("Back",Vector3(side*2.15,.83,0),Vector3(.10,.62,1.6),wood).set_meta("interior_solid_id",id)
			for end in [-1,1]: _box("Leg",Vector3(side*1.9,.23,end*.6),Vector3(.42,.46,.1),iron).set_meta("interior_solid_id",id)
