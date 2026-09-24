extends Node3D
## Cutaway alpine lodge. Mesh groups are the source of physical footprints.
var materials: Dictionary = {}
var _solid_id: StringName = &""

func _ready() -> void:
	_build_room()

func _mat(id: String, color: Color, roughness := 0.82, metallic := 0.0, emission := 0.0) -> StandardMaterial3D:
	if materials.has(id): return materials[id]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission
	materials[id] = material
	return material

func _mesh(label: String, mesh: Mesh, point: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = mesh
	node.material_override = material
	node.position = point
	node.rotation_degrees = rotation
	node.set_meta("interior_solid_id", _solid_id)
	add_child(node)
	return node

func _box(label: String, point: Vector3, size: Vector3, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(label, mesh, point, material, rotation)

func _cylinder(label: String, point: Vector3, radius: float, height: float, material: Material, rotation := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	return _mesh(label, mesh, point, material, rotation)

func _build_room() -> void:
	var wood := _mat("oak", Color("795036"))
	var endgrain := _mat("endgrain", Color("b58a58"))
	var dark := _mat("iron", Color("242a2c"), .38, .65)
	var stone := _mat("mortar", Color("454848"), .98)
	var fabric := _mat("petrol_wool", Color("315761"), .98)
	var red := _mat("oxblood", Color("803e32"), .96)
	var brass := _mat("brass", Color("c39b58"), .32, .72)
	var cream := _mat("linen", Color("d3c2a2"), .95)
	var glow := _mat("lamps", Color("ffd59a"), .5, .0, 1.1)
	_box("FloorFoundation", Vector3(0,-.14,0), Vector3(16,.28,11), wood)
	# Separate planks, staggered joints and restrained timber variation.
	for row in 22:
		for col in 4:
			var tone := .88 + float((row * 7 + col * 3) % 5) * .045
			var plank := _mat("plank%d" % ((row * 7 + col * 3) % 5), Color("876346") * tone)
			_box("OakFloorboard", Vector3(-6+col*4,.012,-5.25+row*.5), Vector3(3.975,.025,.485), plank)
	for side in [-1,1]:
		_solid_id = StringName("NorthWall%d" % side)
		_box("NorthWall",Vector3(side*4.45,1.65,-5.45),Vector3(7.1,3.3,.30),wood)
		for row in 10:
			_cylinder("WallLog",Vector3(side*4.45,.18+row*.32,-5.28),.17,7.1,wood,Vector3(0,0,90))
	for side in [-1,1]:
		_solid_id = StringName("SideWall%d" % side)
		# Low cutaway walls keep both circulation lanes visible.
		_box("SideWall",Vector3(side*7.85,.42,0),Vector3(.3,.84,11),wood)
		_box("WallCap",Vector3(side*7.85,.88,0),Vector3(.38,.12,11),endgrain)
		_solid_id = StringName("SouthRail%d" % side)
		_box("SouthRail",Vector3(side*4.8,.22,5.45),Vector3(6,.44,.25),wood)
		_box("RailCap",Vector3(side*4.8,.46,5.45),Vector3(6.1,.09,.32),endgrain)
	for x in [-7.65,-2.3,2.3,7.65]:
		_solid_id = StringName("TimberPost%s" % x)
		_box("TimberPost",Vector3(x,1.8,-5.10),Vector3(.24,3.6,.28),endgrain)
		_box("IronPostShoe",Vector3(x,.22,-5.10),Vector3(.27,.4,.31),dark)
	_solid_id = &""
	_box("RearHeader",Vector3(0,3.55,-5.1),Vector3(15.6,.28,.32),endgrain)
	# The entrance openings are actually open; no glass plane across the actor.
	for z in [-5.4,5.4]:
		_solid_id = StringName("ExitThreshold%s" % z)
		_box("Threshold",Vector3(0,.04,z),Vector3(3.6,.08,.12),dark)
	_solid_id = &""
	_box("EntryRunner",Vector3(0,.032,3.65),Vector3(2.0,.028,2.4),red)
	for x in [-.88,.88]:
		_box("RunnerBorder",Vector3(x,.05,3.65),Vector3(.065,.012,2.4),cream)
	# Solid paneled rental counter with slate surface, brass trim and till.
	_solid_id = &"RentalCounter"
	_box("CounterCarcass",Vector3(-4.7,.55,-2.5),Vector3(4.4,1.1,1.05),wood)
	_box("SlateCountertop",Vector3(-4.7,1.14,-2.5),Vector3(4.6,.13,1.2),dark)
	for x in [-6.25,-5.48,-4.7,-3.92,-3.15]:
		_box("CounterPanel",Vector3(x,.59,-1.963),Vector3(.68,.77,.035),endgrain)
		_box("PanelInset",Vector3(x,.59,-1.94),Vector3(.55,.62,.025),wood)
	_box("CounterBrassRail",Vector3(-4.7,1.02,-1.91),Vector3(4.4,.035,.035),brass)
	_box("Till",Vector3(-6,1.30,-2.5),Vector3(.42,.2,.35),dark)
	_box("TillScreen",Vector3(-6,1.52,-2.63),Vector3(.36,.27,.05),dark,Vector3(-12,0,0))
	_cylinder("CounterBell",Vector3(-3.1,1.25,-2.3),.10,.09,brass)
	# Folded rental textiles on a wall shelf, not giant rectangular jackets.
	_solid_id = &"RentalShelf"
	_box("RentalShelf",Vector3(-4.7,1.7,-4.9),Vector3(4.6,.12,.58),wood)
	for i in 6:
		for layer in 3:
			_box("FoldedWool",Vector3(-6.4+i*.68,1.81+layer*.095,-4.9),Vector3(.55,.08,.4),[red,fabric,cream][i%3])
	# Dressing cabin retains its established solid envelope.
	_solid_id = &"ChangingRooms"
	for x in [-1.0,1.0]:
		_box("ChangingPartition",Vector3(x,1.1,.2),Vector3(.12,2.2,3),wood)
		_box("PartitionCap",Vector3(x,2.22,.2),Vector3(.16,.09,3),endgrain)
	_box("ChangingBack",Vector3(0,1.1,-1.25),Vector3(2.1,2.2,.12),wood)
	_cylinder("CurtainRod",Vector3(0,2.23,1.65),.035,2.1,brass,Vector3(0,0,90))
	for side in [-1,1]:
		for fold in 7:
			_cylinder("CurtainFold",Vector3(side*(.15+fold*.12),1.12,1.65),.075,2.02,red)
		_box("CurtainHem",Vector3(side*.51,.16,1.68),Vector3(.87,.075,.08),brass)
	# Individually bound skis with bent tips, bindings and metal edges.
	_solid_id = &"SkiRack"
	for y in [.45,1.95]:
		_box("SkiRackRail",Vector3(5.25,y,-4.95),Vector3(4.2,.12,.22),wood)
	for i in 8:
		var x := 3.58+i*.46
		var ski: Material = [red,fabric,cream][i%3]
		_box("RentalSki",Vector3(x,1.35,-4.78),Vector3(.14,2.12,.07),ski)
		_box("SkiTip",Vector3(x,2.45,-4.73),Vector3(.14,.18,.07),ski,Vector3(25,0,0))
		_box("SteelEdge",Vector3(x+.07,1.35,-4.775),Vector3(.014,2.12,.08),brass)
		for y in [1.02,1.4]:
			_box("SkiBinding",Vector3(x,y,-4.68),Vector3(.20,.15,.15),dark)
	_solid_id = &"BootBench"
	_box("BenchSeat",Vector3(4.8,.51,-1.9),Vector3(4.6,.16,.9),endgrain)
	for x in [2.8,6.8]:
		_box("BenchLeg",Vector3(x,.24,-1.9),Vector3(.16,.48,.76),dark)
	for x in [3.3,4.3,5.3,6.3]:
		_box("BootToe",Vector3(x,.69,-1.83),Vector3(.32,.20,.51),dark)
		_box("BootCuff",Vector3(x,.9,-2.00),Vector3(.29,.43,.27),dark,Vector3(-8,0,0))
		for y in [.79,.94]:
			_box("BootBuckle",Vector3(x,y,-1.84),Vector3(.31,.035,.05),brass)
	# Stone fireplace: real recess, jambs, lintel, hearth and charred logs.
	_solid_id = &"Fireplace"
	_box("HearthSlab",Vector3(-5.9,.12,3.15),Vector3(2.5,.24,1.0),stone)
	_box("Fireback",Vector3(-5.9,1.25,2.72),Vector3(2.4,2.5,.14),dark)
	for row in 7:
		for col in 5:
			if row < 3 and col in [1,2,3]: continue
			var rock := _mat("stone%d"%((row+col)%4),Color("7a7c76")*(.8+((row+col)%4)*.08),.97)
			_box("MasonryBlock",Vector3(-6.88+col*.49,.40+row*.34,3.13),Vector3(.465,.315,.83),rock)
	_box("Mantel",Vector3(-5.9,2.72,3.15),Vector3(2.5,.16,1),endgrain)
	for i in 3:
		_cylinder("HearthLog",Vector3(-6.22+i*.30,.34,3.24),.09,.62,wood,Vector3(0,0,78+i*8))
	_solid_id = &""
	var fire := preload("res://assets/regions/source/world/mountain_pass/MountainHearthEffects3D.gd").new()
	fire.name = "LivingHearth"
	fire.position = Vector3(-5.9,.36,3.36)
	fire.scale = Vector3(1.8,1.35,1.2)
	fire.smoke_height = .35
	add_child(fire)
	# Upholstered lounge with cushions, piping, wooden feet and blanket.
	_solid_id = &"LoungeBench"
	for x in [2.9,6.5]:
		for z in [2.88,3.62]:
			_cylinder("SofaFoot",Vector3(x,.15,z),.085,.3,wood)
	_box("SofaFrame",Vector3(4.7,.39,3.25),Vector3(4.1,.3,1.1),wood)
	for i in 3:
		_box("SeatCushion",Vector3(3.38+i*1.32,.64,3.19),Vector3(1.26,.28,.94),fabric)
		_box("BackCushion",Vector3(3.38+i*1.32,1.0,3.68),Vector3(1.26,.69,.22),fabric,Vector3(-8,0,0))
		_box("CushionPiping",Vector3(3.38+i*1.32,.7,2.713),Vector3(1.25,.022,.022),cream)
	for x in [2.73,6.67]:
		_box("SofaArm",Vector3(x,.83,3.25),Vector3(.16,.48,1.1),endgrain)
	_box("FoldedBlanket",Vector3(5.8,.8,3.16),Vector3(.63,.055,.84),red)
	for x in [5.56,5.75,5.94]:
		_box("BlanketWeave",Vector3(x,.831,3.16),Vector3(.035,.008,.83),cream)
	# Suspended iron wheel lights share the room depth, never block the floor.
	_solid_id = &""
	for x in [-4.4,4.4]:
		var ring := TorusMesh.new()
		ring.inner_radius = .63
		ring.outer_radius = .70
		ring.rings = 24
		ring.ring_segments = 6
		_mesh("IronChandelier",ring,Vector3(x,3.3,-.45),dark)
		for i in 6:
			var angle := i*TAU/6
			var point := Vector3(x+cos(angle)*.66,3.4,-.45+sin(angle)*.66)
			_cylinder("LampSocket",point,.085,.13,brass)
			_cylinder("WarmBulb",point+Vector3.UP*.14,.055,.2,glow)
		_cylinder("ChandelierChain",Vector3(x,3.9,-.45),.025,1.0,dark)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x,3,-.45)
		lamp.light_color = Color("ffd4a0")
		lamp.light_energy = 1.15
		lamp.omni_range = 7.5
		add_child(lamp)
