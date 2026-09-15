extends "res://world/mountain_pass/SummitSkiLodge3D.gd"

func _ready() -> void:
	var concrete := _mat("concrete",Color("59656b"))
	var asphalt := _mat("asphalt",Color("303e46"))
	var white := _mat("white",Color("dce0d8"))
	var amber := _mat("amber",Color("cea94e"))
	var steel := _mat("steel",Color("34434a"),.6,.4)
	var deck := _cylinder("Platform",Vector3(0,-.03,0),3.1,.12,concrete)
	deck.mesh.radial_segments = 8
	var surface := _cylinder("Tarmac",Vector3(0,.035,0),2.91,.012,asphalt)
	surface.mesh.radial_segments = 8
	# Flush walkable deck: only the visible mast and perimeter rails are solids.
	for side in [-1,1]:
		_box("HStem",Vector3(side*.55,.046,0),Vector3(.27,.015,1.65),white)
	_box("HBar",Vector3(0,.047,0),Vector3(.95,.015,.25),white)
	for i in 32:
		var angle := TAU*i/32.0
		_box("TouchdownRing",Vector3(sin(angle)*2.12,.05,cos(angle)*2.12),Vector3(.43,.02,.09),amber,Vector3(0,rad_to_deg(angle),0))
	for i in 8:
		var angle := TAU*i/8.0
		var point := Vector3(sin(angle)*2.90,0,cos(angle)*2.90)
		_cylinder("InsetLight",point+Vector3(0,.085,0),.07,.045,_mat("beacon",Color("61b790"),.35,0,.55))
		if i in [0,1,7]: continue
		var id := StringName("Perimeter%d"%i)
		_box("Rail",point+Vector3(0,.78,0),Vector3(1.5,.065,.065),steel,Vector3(0,rad_to_deg(angle),0)).set_meta("interior_solid_id",id)
		_cylinder("RailPost",point+Vector3(0,.4,0),.035,.8,steel).set_meta("interior_solid_id",id)
	_cylinder("WindsockMast",Vector3(3.45,1.3,-.5),.045,2.6,steel).set_meta("interior_solid_id",&"Windsock")
	_cylinder("MastFoot",Vector3(3.45,.12,-.5),.17,.24,concrete).set_meta("interior_solid_id",&"Windsock")
	for i in 5:
		var cloth := CylinderMesh.new()
		cloth.top_radius = .17-i*.025
		cloth.bottom_radius = .19-i*.025
		cloth.height = .22
		cloth.radial_segments = 10
		var segment := MeshInstance3D.new()
		segment.mesh = cloth
		segment.material_override = amber if i%2==0 else white
		segment.position = Vector3(3.55+i*.20,2.54-i*.035,-.5)
		segment.rotation.z = -PI*.55
		add_child(segment)
