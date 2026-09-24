extends Node3D
## Shared floor-space measurements drive the model and projected 2D collision.
var footprints: Array[Dictionary] = []
var materials: Dictionary = {}
var radio_light: OmniLight3D
var _ambient_clock := 0.0

func _ready() -> void:
	_build_shell()
	_build_command()
	_build_barracks()
	_build_radio()
	_build_supplies()
	_build_lived_in_details()
	_build_lighting()
	var fire := preload("res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd").new()
	fire.name = "HeaterFlame"
	fire.position = Vector3(7.7, 0.48, 3.23)
	fire.scale = Vector3.ONE * 0.55
	fire.smoke_height = 0.25
	fire.warmth = 0.5
	add_child(fire)
	var steam := preload("res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd").new()
	steam.name = "VentSteam"
	steam.position = Vector3(8.7, 2.5, -5.8)
	steam.show_flames = false
	steam.warmth = 0.0
	steam.smoke_height = 0.45
	add_child(steam)

func material(id: String, color: String, metal: float = 0.0, emission: float = 0.0) -> StandardMaterial3D:
	if materials.has(id):
		return materials[id]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color)
	mat.roughness = 0.78 if metal == 0.0 else 0.42
	mat.metallic = metal
	if emission > 0.0:
		mat.emission_enabled = true
		mat.emission = Color(color)
		mat.emission_energy_multiplier = emission
	materials[id] = mat
	return mat

func box(id: String, pos: Vector3, size: Vector3, mat: Material, solid: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	add_child(node)
	if solid:
		footprints.append({"id": id, "rect": Rect2(pos.x - size.x * 0.5, pos.z - size.z * 0.5, size.x, size.z)})
	return node

func cylinder(id: String, pos: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = id
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	node.mesh = mesh
	node.material_override = mat
	node.position = pos
	add_child(node)
	return node

func label(text: String, pos: Vector3, size: int, color: Color, floor_text: bool = false) -> void:
	var node := Label3D.new()
	node.text = text
	node.font_size = size
	node.pixel_size = 0.008
	node.modulate = color
	node.outline_size = 0
	node.position = pos
	if floor_text:
		node.rotation.x = -PI / 2
	add_child(node)

func _build_shell() -> void:
	var concrete := material("concrete", "657079")
	var floor_mat := material("floor", "363f46")
	var dark := material("steel", "253139", 0.6)
	var edge := material("edge", "a5b1b2", 0.35)
	var yellow := material("yellow", "d1a955")
	box("Foundation", Vector3(0, -0.23, 0), Vector3(18.5, 0.3, 12.5), dark)
	box("Floor", Vector3(0, -0.035, 0), Vector3(18, 0.07, 12), floor_mat)
	for x in range(-8, 9, 2):
		box("FloorJoint", Vector3(x, 0.005, 0), Vector3(0.015, 0.01, 12), dark)
	for z in range(-5, 6, 2):
		box("FloorJoint", Vector3(0, 0.005, z), Vector3(18, 0.01, 0.015), dark)
	box("NorthWall", Vector3(0, 1.6, -6.15), Vector3(18.6, 3.2, 0.3), concrete, true)
	# Cutaway walls keep the floor and player visible from the south.
	box("WestWall", Vector3(-9.15, 0.65, 0), Vector3(0.3, 1.3, 12), concrete, true)
	box("EastWall", Vector3(9.15, 0.65, 0), Vector3(0.3, 1.3, 12), concrete, true)
	box("SouthWestWall", Vector3(-5.1, 0.28, 6.15), Vector3(8.4, 0.56, 0.3), concrete, true)
	box("SouthEastWall", Vector3(5.1, 0.28, 6.15), Vector3(8.4, 0.56, 0.3), concrete, true)
	# Physics threshold is solid; the pedestrian door transfers before it.
	footprints.append({"id": "ExitThreshold", "rect": Rect2(-0.9, 6, 1.8, 0.3)})
	for x in [-8.7, -4.3, 4.3, 8.7]:
		box("ConcreteRib", Vector3(x, 1.6, -5.87), Vector3(0.3, 3.2, 0.3), edge)
	for x in [-4.4, 4.4]:
		box("PartitionNorth", Vector3(x, 0.75, -3.1), Vector3(0.22, 1.5, 5.8), dark, true)
		box("PartitionSouth", Vector3(x, 0.55, 4.3), Vector3(0.22, 1.1, 3.4), dark, true)
		box("DoorThreshold", Vector3(x, 0.015, 1.2), Vector3(0.6, 0.02, 2.5), yellow)
	# Clearly marked, continuous approach to the command hall.
	for side in [-1.0, 1.0]:
		box("AisleEdge", Vector3(side * 1.15, 0.012, 3.9), Vector3(0.035, 0.02, 3.8), yellow)
	label("ESTAÇÃO ZERO", Vector3(0, 2.25, -5.94), 55, Color("d8e5e7"))

func _build_command() -> void:
	var steel: Material = materials["steel"]
	var red := material("flag", "923b38")
	var brass := material("brass", "c1a366", 0.4)
	var paper := material("paper", "ddd3b1")
	var cyan := material("cyan", "74c4d4", 0.1, 0.5)
	for side in [-1.0, 1.0]:
		box("WolfBanner", Vector3(side * 2.7, 1.95, -5.92), Vector3(1.15, 1.9, 0.04), red)
		# Angular white insignia, authored geometry rather than floating text.
		var stripe := box("Insignia", Vector3(side * 2.7 - 0.15, 2, -5.87), Vector3(0.14, 0.75, 0.02), paper)
		stripe.rotation.z = 0.4
		stripe = box("Insignia", Vector3(side * 2.7 + 0.15, 2, -5.87), Vector3(0.14, 0.75, 0.02), paper)
		stripe.rotation.z = -0.4
	box("CommandDesk", Vector3(0, 0.55, -4.2), Vector3(3.4, 1.1, 1.1), steel, true)
	box("DeskTop", Vector3(0, 1.13, -4.2), Vector3(3.55, 0.1, 1.2), brass)
	box("RouteMap", Vector3(-0.3, 1.19, -4.1), Vector3(1.7, 0.015, 0.65), paper)
	for i in 5:
		box("MapRoute", Vector3(-0.9 + i * 0.28, 1.205, -4.2 + sin(i) * 0.17), Vector3(0.22, 0.01, 0.025), red)
	box("DeskRadio", Vector3(1.15, 1.32, -4.3), Vector3(0.55, 0.3, 0.4), steel)
	box("RadioDisplay", Vector3(1.15, 1.35, -4.08), Vector3(0.25, 0.09, 0.025), cyan)
	box("BossChair", Vector3(0, 0.5, -5.15), Vector3(0.85, 1.0, 0.55), red, true)
	box("BossChairBack", Vector3(0, 1.05, -5.4), Vector3(0.85, 1.3, 0.12), steel)
	# Cover stays outside the central movement corridor.
	for side in [-1.0, 1.0]:
		box("HallCover", Vector3(side * 2.9, 0.45, -0.25), Vector3(1.25, 0.9, 0.95), steel, true)
		box("CoverStripe", Vector3(side * 2.9, 0.91, -0.25), Vector3(1.26, 0.035, 0.15), brass)

func _build_barracks() -> void:
	var steel: Material = materials["steel"]
	var fabric := material("blanket", "5a6e63")
	var pillow := material("pillow", "b8bbaa")
	for z in [-4.6, -1.9]:
		box("BunkFootprint", Vector3(-7.35, 0.23, z), Vector3(2.15, 0.25, 1.45), steel, true)
		for height in [0.48, 1.65]:
			box("BunkMattress", Vector3(-7.35, height, z), Vector3(2, 0.18, 1.25), fabric)
			box("BunkPillow", Vector3(-8.05, height + 0.14, z), Vector3(0.45, 0.14, 0.85), pillow)
		for dx in [-1.02, 1.02]:
			for dz in [-0.62, 0.62]:
				box("BunkPost", Vector3(-7.35 + dx, 1, z + dz), Vector3(0.055, 2, 0.055), steel)
		for rung in 5:
			box("Ladder", Vector3(-6.27, 0.25 + rung * 0.29, z), Vector3(0.06, 0.035, 0.48), pillow)
	for i in 4:
		var x := -8.25 + i * 0.75
		box("Locker", Vector3(x, 0.9, 4.8), Vector3(0.67, 1.8, 0.7), steel, true)
		box("LockerHandle", Vector3(x + 0.19, 0.9, 4.42), Vector3(0.035, 0.18, 0.04), pillow)
		for vent in 3:
			box("LockerVent", Vector3(x, 1.5 + vent * 0.08, 4.43), Vector3(0.4, 0.025, 0.02), fabric)

func _build_radio() -> void:
	var steel: Material = materials["steel"]
	var cyan: Material = materials["cyan"]
	var screen := material("screen", "14383d", 0.1, 0.15)
	box("RadioConsole", Vector3(6.65, 0.5, -4.5), Vector3(3.5, 1.0, 1.2), steel, true)
	for x in [5.5, 6.65, 7.8]:
		box("MonitorCase", Vector3(x, 1.4, -4.7), Vector3(0.9, 0.65, 0.2), steel)
		box("MonitorGlass", Vector3(x, 1.4, -4.58), Vector3(0.76, 0.51, 0.02), screen)
		for row in 4:
			box("MonitorReadout", Vector3(x - 0.12, 1.25 + row * 0.09, -4.56), Vector3(0.43 - row * 0.06, 0.018, 0.01), cyan)
		box("Keyboard", Vector3(x, 1.03, -4.15), Vector3(0.65, 0.04, 0.26), materials["edge"])
	for z in [-2.65, -1.5]:
		box("ServerRack", Vector3(8.25, 0.95, z), Vector3(0.9, 1.9, 0.85), steel, true)
		for i in 7:
			box("ServerSlot", Vector3(8.25, 0.28 + i * 0.21, z + 0.44), Vector3(0.73, 0.13, 0.04), materials["edge"])
			box("ServerLED", Vector3(7.98, 0.28 + i * 0.21, z + 0.47), Vector3(0.035, 0.025, 0.02), cyan)

func _build_supplies() -> void:
	var wood := material("crate", "77654b")
	var steel: Material = materials["steel"]
	for i in 3:
		var x := 5.3 + i * 1.05
		box("SupplyCrate", Vector3(x, 0.4, 4.8), Vector3(0.9, 0.8, 0.85), wood, true)
		for dx in [-0.31, 0.31]:
			box("CrateBand", Vector3(x + dx, 0.41, 4.8), Vector3(0.08, 0.84, 0.88), steel)
	var heater := cylinder("Heater", Vector3(7.7, 0.6, 2.8), 0.38, 1.2, steel)
	footprints.append({"id": "Heater", "rect": Rect2(7.25, 2.35, 0.9, 0.9)})
	var orange := material("heater_glow", "efa65d", 0, 0.8)
	box("HeaterGrille", Vector3(7.7, 0.65, 3.18), Vector3(0.4, 0.42, 0.035), orange)
	for i in 5:
		box("HeaterBars", Vector3(7.54 + i * 0.08, 0.65, 3.21), Vector3(0.025, 0.44, 0.03), steel)

func _build_lived_in_details() -> void:
	var steel: Material = materials["steel"]
	var edge: Material = materials["edge"]
	var cloth: Material = materials["blanket"]
	# Wall conduits, worn blankets and desk objects give each functional zone
	# its own scale cues without adding obstacles to the circulation lanes.
	for y in [2.65,2.83]:
		box("WallConduit",Vector3(0,y,-5.92),Vector3(17.5,.045,.055),steel)
	for x in [-8.6,-4.1,4.1,8.6]:
		box("ConduitClip",Vector3(x,2.75,-5.84),Vector3(.12,.3,.08),edge)
	for z in [-4.6,-1.9]:
		for height in [.48,1.65]:
			for fold in 7:
				box("BlanketFold",Vector3(-7.5+fold*.15,height+.097,z),Vector3(.035,.025,1.18),cloth)
	for i in 3:
		box("CommandDocuments",Vector3(-1.18,1.2+i*.018,-4.35),Vector3(.35,.016,.46),materials["paper"])
	cylinder("EnamelMug",Vector3(.68,1.28,-3.95),.085,.17,edge)
	for x in [-8.25,-7.5,-6.75,-6.0]:
		box("LockerBase",Vector3(x,.07,4.8),Vector3(.71,.14,.76),edge)

func _build_lighting() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("10171c")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("97b1c3")
	env.environment.ambient_light_energy = 0.38
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -25, 0)
	sun.light_color = Color("b6cbd6")
	sun.light_energy = 0.55
	sun.shadow_enabled = true
	add_child(sun)
	for x in [-6.5, 0, 6.5]:
		var light := OmniLight3D.new()
		light.position = Vector3(x, 2.6, -2.8)
		light.light_color = Color("8cc8d8") if x > 4 else Color("ffd9a0")
		light.light_energy = 1.65
		if x > 4:
			radio_light = light
		light.omni_range = 7
		add_child(light)
		box("WallLamp", Vector3(x, 2.9, -5.87), Vector3(1.2, 0.09, 0.15), material("lamp", "efdfb4", 0, 1))

func _process(delta: float) -> void:
	_ambient_clock += minf(delta, 0.1)
	if radio_light:
		radio_light.light_energy = 1.60 + 0.035 * sin(_ambient_clock * 1.8) + 0.015 * sin(_ambient_clock * 4.2)
