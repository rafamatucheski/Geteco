extends "res://world/harbor/cemetery/CemeteryPropBuilder.gd"

## The walk-in floor of Harbor Patrol fits its 190 x 250 px street building.
var door_leaves: Array[MeshInstance3D] = []

func _ready() -> void:
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-58,-30,0)
	lamp.light_energy = 1.1
	lamp.shadow_enabled = true
	add_child(lamp)
	box("TerrazzoFloor",Vector3(8.6,.12,12.0),Vector3(0,-.08,0),"43505d")
	for x in range(-4,5): box("FloorJoint",Vector3(.012,.008,11.8),Vector3(x,.005,0),"54616d")
	for z in range(-5,6): box("FloorJoint",Vector3(8.4,.008,.012),Vector3(0,.005,z),"54616d")
	_solid("RearWall",Vector3(8.6,3.1,.25),Vector3(0,1.55,-6),"334155")
	_solid("WestWall",Vector3(.25,3.1,12),Vector3(-4.3,1.55,0),"334155")
	_solid("EastWall",Vector3(.25,3.1,12),Vector3(4.3,1.55,0),"334155")
	_solid("FrontLeft",Vector3(2.95,3.1,.25),Vector3(-2.825,1.55,6),"334155")
	_solid("FrontRight",Vector3(2.95,3.1,.25),Vector3(2.825,1.55,6),"334155")
	box("DoorLintel",Vector3(2.7,.45,.25),Vector3(0,2.875,6),"667d8d")
	for side in [-1.0,1.0]:
		box("DoorJamb",Vector3(.09,2.55,.22),Vector3(side*1.35,1.27,6),"9fb0b7")
		var leaf := box("GlassDoor",Vector3(1.27,2.45,.07),Vector3(side*.675,1.22,6.02),"638996")
		door_leaves.append(leaf)
	box("NameStrip",Vector3(4.4,.48,.08),Vector3(0,2.55,-5.82),"233440")
	# Reception is central, but the clear path from the entry branches to both sides.
	_solid("ReceptionDesk",Vector3(3.4,1.02,.75),Vector3(.2,.51,.55),"24394a")
	box("ReceptionTop",Vector3(3.55,.07,.85),Vector3(.2,1.055,.55),"8299a3")
	for x in [-.75,.55]:
		box("DeskScreen",Vector3(.44,.35,.08),Vector3(x,1.36,.28),"101f2b")
		box("ScreenGlass",Vector3(.37,.27,.012),Vector3(x,1.36,.33),"5b9aab")
		box("Keyboard",Vector3(.46,.025,.2),Vector3(x,1.1,.75),"a8b6b5")
	# The public terminal and waiting bench remain reachable from the front aisle.
	_solid("IncidentTerminal",Vector3(1.15,.88,.68),Vector3(-3.25,.44,2.35),"293948")
	box("TerminalScreen",Vector3(.73,.52,.08),Vector3(-3.25,1.13,2.3),"142831")
	box("TerminalGlass",Vector3(.62,.42,.014),Vector3(-3.25,1.13,2.35),"65a7ad")
	_solid("WaitingBench",Vector3(1.72,.55,.58),Vector3(-3.08,.28,4.45),"4b6270")
	box("BenchBack",Vector3(1.72,.66,.14),Vector3(-3.08,.8,4.73),"5e7886")
	# Detective's worktable sits to the rear left; the right side remains a service aisle.
	_solid("DetectiveDesk",Vector3(2.25,.76,1.15),Vector3(-2.6,.38,-3.85),"344858")
	box("DetectiveTop",Vector3(2.36,.06,1.26),Vector3(-2.6,.79,-3.85),"8b9793")
	box("CaseBoard",Vector3(2.25,1.18,.08),Vector3(-2.25,1.68,-5.83),"88745c")
	for x in [-2.8,-2.1,-1.4]: box("CasePhoto",Vector3(.35,.4,.025),Vector3(x,1.8,-5.76),"d0d2c7")
	# A barred holding area reads clearly while keeping its detainee behind a real wall.
	_solid("CellWest",Vector3(.16,3.0,3.15),Vector3(1.2,1.5,-4.45),"657481")
	_solid("CellFrontRail",Vector3(3.1,.11,.12),Vector3(2.75,.22,-2.86),"8a9aa2")
	for x in [1.35,1.7,2.05,2.4,2.75,3.1,3.45,3.8,4.15]:
		var bar := box("CellBar",Vector3(.055,2.55,.07),Vector3(x,1.35,-2.86),"9aa9ab")
		bar.set_meta("interior_solid_id",&"CellBars")
	box("CellUpperRail",Vector3(3.1,.09,.12),Vector3(2.75,2.6,-2.86),"8a9aa2")
	_solid("CellBed",Vector3(1.35,.52,2.2),Vector3(3.35,.26,-4.65),"46545d")
	box("CellBlanket",Vector3(1.2,.07,1.05),Vector3(3.35,.57,-4.25),"74828a")
	for z in [-4.8,-1.3,3.4]:
		var light := OmniLight3D.new()
		light.position = Vector3(0,2.75,z)
		light.light_color = Color("d6e9ee")
		light.light_energy = .35
		light.omni_range = 5.5
		add_child(light)
		box("CeilingLight",Vector3(1.7,.08,.35),Vector3(0,2.84,z),"d6e9ee")

func _solid(id: String,size: Vector3,point: Vector3,color: String) -> MeshInstance3D:
	var part := box(id,size,point,color)
	part.set_meta("interior_solid_id",StringName(id))
	return part

func set_open_amount(amount: float) -> void:
	for i in door_leaves.size():
		var side := -1.0 if i==0 else 1.0
		door_leaves[i].position.x = side*(.675+amount*1.28)
