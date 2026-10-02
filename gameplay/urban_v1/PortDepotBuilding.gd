extends Node3D
## Vértice: a working inland distribution warehouse, in local lot coordinates.
## Pure presentation/physics. Scheduling, workers and freight belong to the depot.

class SlidingDoor extends Node3D:
	var closed_position := Vector3.ZERO
	var travel := Vector3.UP * 5.6
	var open_amount := 0.0
	func set_open_amount(amount: float) -> void:
		open_amount = clampf(amount, 0.0, 1.0)
		position = closed_position + travel * open_amount

var roof_parts: Array[Node3D] = []
var facade_parts: Array[Node3D] = []
var solids: Array[StaticBody3D] = []
var office_door: Node3D
var dock_doors: Array[Node3D] = []
var interior_lights: Array[OmniLight3D] = []
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _roof: Node3D
var _facade: Node3D
var _fixed: Node3D

func _ready() -> void:
	name = "VerticeWarehouse"
	_fixed = _group("PermanentArchitecture")
	_roof = _group("RoofCutaway")
	_facade = _group("FacadeCutaway")
	roof_parts.append(_roof)
	facade_parts.append(_facade)
	_build_shell()
	_build_roof()
	_build_docks()
	_build_office()
	_build_storage()
	_build_lights()
	_commit_batches()

func _group(id: String) -> Node3D:
	var group := Node3D.new()
	group.name = id
	add_child(group)
	return group

func set_cutaway(active: bool) -> void:
	for part in roof_parts: part.visible = not active
	for part in facade_parts: part.visible = not active

func set_dock_open(index: int, amount: float) -> void:
	if index >= 0 and index < dock_doors.size():
		dock_doors[index].set_open_amount(amount)

func set_office_open(amount: float) -> void:
	if is_instance_valid(office_door): office_door.set_open_amount(amount)

func set_lights_active(active: bool) -> void:
	for light in interior_lights: light.visible = active

func _build_shell() -> void:
	# Native terrain is the support body: the floor finish never creates a step.
	_box("PolishedConcrete", Vector3(0, .02, -1), Vector3(56, .03, 38), "floor")
	_box("OfficeFloor", Vector3(35, .02, 15), Vector3(14, .03, 30), "floor")
	_wall("WestWall", Vector3(-28, 0, -1), Vector3(.4, 9, 38))
	_wall("BackWall", Vector3(0, 0, -20), Vector3(56, 9, .4))
	_wall("EastBackWall", Vector3(28, 0, -7), Vector3(.4, 9, 26))
	_wall("EastFrontWall", Vector3(28, 0, 14), Vector3(.4, 9, 8))
	_box("OfficePassageLintel", Vector3(28, 6, 8), Vector3(.4, 6, 4), "plaster", true, _facade)
	for span in [Vector2(-28, -22), Vector2(-14, -4), Vector2(4, 14), Vector2(22, 28)]:
		_wall("FrontPier", Vector3((span.x + span.y) * .5, 0, 18), Vector3(span.y - span.x, 9, .4))
	for x in [-18.0, 0.0, 18.0]:
		_box("DockLintel", Vector3(x, 7.2, 18), Vector3(8, 3.6, .4), "cladding", true, _facade)
	for x in [-27.65, -14.0, 14.0, 27.65]:
		for z in [-19.65, 17.65]:
			_box("SteelColumn", Vector3(x, 4.5, z), Vector3(.32, 9, .4), "steel", true, _facade)
	for x in range(-27, 29, 2):
		_box("RearCladdingRib", Vector3(x, 6.5, -20.25), Vector3(.06, 5, .08), "seam", false, _facade)
	for z in range(-19, 18, 2):
		_box("SideCladdingRib", Vector3(-28.24, 6.5, z), Vector3(.08, 5, .06), "seam", false, _facade)
	for x in [-28.3, 28.3]:
		for z in [-19.6, 17.4]:
			_box("Downpipe", Vector3(x, 4.4, z), Vector3(.16, 8.8, .16), "steel", false, _facade)
	# The teal band and masonry plinth distinguish a company from a port gantry.
	_box("FrontBrandBand", Vector3(0, 7.0, 18.29), Vector3(56.4, 1.5, .15), "teal", false, _facade)
	var sign_node := Label3D.new()
	sign_node.name = "CompanyName"
	sign_node.text = "VÉRTICE"
	sign_node.font_size = 112
	sign_node.pixel_size = .021
	sign_node.outline_size = 0
	sign_node.modulate = Color("f2ede0")
	sign_node.position = Vector3(0, 7.02, 18.41)
	_facade.add_child(sign_node)

func _wall(id: String, base: Vector3, size: Vector3) -> void:
	var low := size
	low.y = 1.15
	_box(id + "Masonry", base + Vector3.UP * .575, low, "masonry", true)
	var high := size
	high.y = size.y - 1.15
	_box(id + "Upper", base + Vector3.UP * (1.15 + high.y * .5), high, "cladding", true, _facade)
	# Mortar courses are shallow trim within the supporting wall collision.
	for y in [.3, .6, .9]:
		var course := low + Vector3(.015, 0, .015)
		course.y = .022
		_box(id + "Mortar", base + Vector3.UP * y, course, "mortar")

func _build_roof() -> void:
	var pitch := atan2(2.2, 28.8)
	for side in [-1.0, 1.0]:
		var angle: float = side * pitch
		_box("StandingSeamRoof", Vector3(side * 14.4, 10.1, -1), Vector3(28.9, .2, 40), "roof", true, _roof, Vector3(0, 0, -angle))
		for z in range(-21, 20, 2):
			_box("RoofStandingSeam", Vector3(side * 14.4, 10.23, z), Vector3(28.9, .065, .045), "seam", false, _roof, Vector3(0, 0, -angle))
		_box("RainGutter", Vector3(side * 29, 8.96, -1), Vector3(.26, .24, 40), "steel", false, _roof)
		for z in [-12.0, 4.0]:
			_box("SkylightCurb", Vector3(side * 10, 10.55, z), Vector3(5.5, .16, 5), "steel", false, _roof, Vector3(0, 0, -angle))
			_box("SkylightGlazing", Vector3(side * 10, 10.68, z), Vector3(5.2, .12, 4.7), "glass", false, _roof, Vector3(0, 0, -angle))
			for divider in [-1.4, 0.0, 1.4]:
				_box("SkylightMullion", Vector3(side * 10, 10.76, z + divider), Vector3(5.3, .045, .055), "steel", false, _roof, Vector3(0, 0, -angle))
	_box("RidgeCap", Vector3(0, 11.28, -1), Vector3(.55, .18, 40), "seam", false, _roof)
	for z in [-20.0, 18.0]: _gable(z)
	for z in [-12.0, 10.0]:
		_box("VentilatorBase", Vector3(0, 11.4, z), Vector3(2, .3, 2), "steel", false, _roof)
		_box("VentilatorHousing", Vector3(0, 11.85, z), Vector3(1.4, .65, 1.4), "roof", false, _roof)
		_box("VentilatorCap", Vector3(0, 12.23, z), Vector3(1.85, .14, 1.85), "seam", false, _roof)
		for y in [11.6, 11.8, 12.0]:
			_box("VentLouver", Vector3(0, y, z + .72), Vector3(1.4, .05, .09), "dark", false, _roof)
	# Interior beams and braces stay with the roof cutaway.
	for z in [-18.0, -6.0, 6.0, 16.0]:
		_box("RoofTieBeam", Vector3(0, 8.6, z), Vector3(55.5, .24, .22), "steel", false, _roof)
		for x in [-20.0, 0.0, 20.0]:
			_box("SuspendedLight", Vector3(x, 8.05, z), Vector3(2.2, .14, .4), "light", false, _roof)

func _build_docks() -> void:
	for index in 3:
		var x := float(index - 1) * 18.0
		var door := SlidingDoor.new()
		door.name = "DockShutter%d" % index
		door.closed_position = Vector3(x, 0, 18.06)
		door.position = door.closed_position
		add_child(door)
		dock_doors.append(door)
		_box("ShutterPanel", Vector3(0, 2.7, 0), Vector3(7.85, 5.4, .16), "shutter", true, door)
		for row in range(1, 18):
			_box("ShutterSeam", Vector3(0, row * .3, .1), Vector3(7.8, .045, .04), "seam", false, door)
		_box("ShutterHandle", Vector3(0, .85, .16), Vector3(.65, .065, .1), "dark", false, door)
		for side in [-1.0, 1.0]:
			_box("DoorSeal", Vector3(x + side * 4.1, 2.7, 18.32), Vector3(.26, 5.4, .42), "dark", true)
			_box("DockBumper", Vector3(x + side * 3.2, .6, 20.1), Vector3(.45, 1.2, .32), "rubber", true)
			_box("Bollard", Vector3(x + side * 4.65, .6, 20.5), Vector3(.22, 1.2, .22), "yellow", true)
		# Small dock bridge; broad approach and pedestrian office remain level.
		_box("DockBridge", Vector3(x, .55, 19.05), Vector3(6.6, 1.1, 1.8), "masonry", true)
		_box("DockSteelPlate", Vector3(x, 1.12, 19.05), Vector3(6.6, .045, 1.8), "steel")
		_box("DoorHood", Vector3(x, 5.65, 18.55), Vector3(8.7, .24, 1.1), "teal", false, _facade)
		_box("DockLamp", Vector3(x + 4.65, 4.2, 18.48), Vector3(.35, .22, .25), "light", false, _facade)
		for side in [-1.0, 1.0]:
			_box("DockApproachStripe", Vector3(x + side * 4.5, .018, 25.5), Vector3(.12, .022, 9), "yellow")

func _build_office() -> void:
	_wall("OfficeRear", Vector3(35, 0, 0), Vector3(14, 3.5, .3))
	_wall("OfficeEast", Vector3(42, 0, 15), Vector3(.3, 3.5, 30))
	_wall("OfficeWestFront", Vector3(28, 0, 24), Vector3(.3, 3.5, 12))
	# Front windows with actual frames; solid glass collision covers their opening.
	for x in [30.8, 39.2]:
		_box("OfficeWindowSill", Vector3(x, .55, 30), Vector3(5.6, 1.1, .3), "masonry", true)
		_box("OfficeWindow", Vector3(x, 2.1, 30), Vector3(5.4, 1.8, .09), "glass", true, _facade)
		for frame_x in [x - 2.7, x, x + 2.7]:
			_box("OfficeMullion", Vector3(frame_x, 2.1, 30.1), Vector3(.07, 1.85, .12), "steel", false, _facade)
		_box("OfficeWindowHeader", Vector3(x, 3.25, 30), Vector3(5.6, .5, .3), "teal", true, _facade)
	_box("OfficeDoorHeader", Vector3(35, 3.25, 30), Vector3(2.8, .5, .3), "teal", true, _facade)
	var door := SlidingDoor.new()
	door.name = "OfficeSlidingDoor"
	door.closed_position = Vector3(35, 0, 30)
	door.travel = Vector3(2.8, 0, 0)
	door.position = door.closed_position
	add_child(door)
	office_door = door
	_box("DoorGlazing", Vector3(0, 1.5, 0), Vector3(2.4, 3, .1), "glass", true, door)
	for x in [-1.2, 1.2]:
		_box("DoorFrame", Vector3(x, 1.5, .04), Vector3(.07, 3, .14), "steel", false, door)
	_box("DoorPushRail", Vector3(0, 1.1, .1), Vector3(2.4, .08, .06), "steel", false, door)
	_box("OfficeRoof", Vector3(35, 3.68, 15), Vector3(15, .28, 31), "roof", true, _roof)
	_box("EntranceCanopy", Vector3(35, 3.4, 31.4), Vector3(5.7, .2, 3.4), "teal", false, _roof)
	for x in [28.6, 41.4]:
		_box("OfficeRoofFascia", Vector3(x, 3.6, 15), Vector3(.18, .65, 31), "teal", false, _roof)
	# Desks stay away from the continuous warehouse/office passage at z8.
	for z in [14.0, 21.0]:
		_box("OfficeDesk", Vector3(39.3, .72, z), Vector3(3, .18, 1.5), "wood", true)
		for x in [38.0, 40.6]:
			_box("DeskPedestal", Vector3(x, .34, z), Vector3(.45, .68, 1.25), "steel", true)
		_box("ComputerMonitor", Vector3(39.3, 1.16, z - .35), Vector3(.85, .62, .09), "dark", true)
		_box("MonitorScreen", Vector3(39.3, 1.18, z - .295), Vector3(.74, .48, .01), "screen")
		_box("Keyboard", Vector3(39.3, .84, z + .22), Vector3(.65, .045, .24), "dark")
		# Real seat, backrest and column: a clerk sits here (VerticeCompany.desk_staff).
		_box("OfficeChairSeat", Vector3(39.3, .5, z + 1.1), Vector3(.54, .08, .5), "teal")
		_box("OfficeChairBack", Vector3(39.3, .92, z + 1.42), Vector3(.5, .66, .07), "teal")
		_box("OfficeChairColumn", Vector3(39.3, .26, z + 1.1), Vector3(.06, .44, .06), "steel")
		_box("OfficeChairBase", Vector3(39.3, .04, z + 1.1), Vector3(.6, .05, .6), "dark")
		_solid("OfficeChair", Vector3(39.3, .5, z + 1.2), Vector3(.64, 1.0, .64), self)
	_box("FileCabinets", Vector3(40.9, 1.05, 3), Vector3(1.2, 2.1, 3), "shutter", true)
	for y in [.45, 1.05, 1.65]:
		_box("CabinetHandles", Vector3(40.25, y, 3), Vector3(.08, .07, 2.4), "steel")
	_box("BenchSeat", Vector3(29.15, .43, 25), Vector3(.75, .86, 3), "wood", true)
	_box("BenchBack", Vector3(28.85, 1.1, 25), Vector3(.12, .7, 3), "wood", true)
	_box("Doormat", Vector3(35, .02, 28.9), Vector3(2.5, .035, 1.4), "rubber")

func _build_storage() -> void:
	# Shelves occupy authored islands; dock lanes z4..18 and perimeter stay free.
	for x in [-19.0, -7.0, 7.0, 19.0]:
		for z in [-13.0, -4.0]:
			_rack(Vector3(x, 0, z))
	for x in [-23.0, -15.0]:
		_box("PackingBench", Vector3(x, .87, -17.6), Vector3(4, 1.74, 1.3), "wood", true)
		_box("PackingRoll", Vector3(x, 1.91, -17.7), Vector3(1.2, .32, .35), "paper", true)
	_box("DispatchCabinet", Vector3(26.2, 1.0, -16.8), Vector3(1.2, 2, 2.8), "teal", true)
	for x in [-9.0, 9.0]:
		_box("WalkingLane", Vector3(x, .047, 9.7), Vector3(.1, .018, 15), "yellow")

func _rack(at: Vector3) -> void:
	# One enclosing collider prevents climbing through open shelf levels.
	_solid("StorageRack", at + Vector3(0, 2.15, 0), Vector3(6.2, 4.3, 2.6), self)
	for x in [-3.0, 3.0]:
		for z in [-1.2, 1.2]:
			_box("RackUpright", at + Vector3(x, 2.15, z), Vector3(.13, 4.3, .13), "teal")
	for y in [.18, 2.05, 3.92]:
		_box("RackShelf", at + Vector3(0, y, 0), Vector3(6.2, .13, 2.6), "steel")
		for z in [-1.27, 1.27]:
			_box("RackBeam", at + Vector3(0, y + .05, z), Vector3(6.1, .19, .09), "yellow")
	for x in [-2.0, 0.0, 2.0]:
		for y in [.4, 2.27]:
			_box("Pallet", at + Vector3(x, y, 0), Vector3(1.7, .2, 2), "wood")
			_box("WrappedCartons", at + Vector3(x, y + .64, 0), Vector3(1.5, 1.08, 1.8), "paper")
			_box("CartonBand", at + Vector3(x, y + .65, .911), Vector3(.08, 1.07, .014), "dark")

func _gable(z: float) -> void:
	var builder := SurfaceTool.new()
	builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points := PackedVector3Array([Vector3(-28, 9, z), Vector3(0, 11.2, z), Vector3(28, 9, z)])
	for i in [0, 1, 2, 2, 1, 0]: builder.add_vertex(points[i])
	builder.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.name = "GableCladding"
	mesh.mesh = builder.commit()
	mesh.material_override = _material("cladding")
	_facade.add_child(mesh)

func _build_lights() -> void:
	# One source per zone; static emissive fittings carry the smaller details.
	for at in [Vector3(-14, 6.8, -1), Vector3(14, 6.8, -1), Vector3(35, 2.7, 17)]:
		var light := OmniLight3D.new()
		light.name = "WarehouseInteriorLight"
		light.position = at
		light.light_color = Color("ffdfb2")
		light.light_energy = .65 if at.x < 30 else .5
		light.omni_range = 23.0 if at.x < 30 else 13.0
		light.shadow_enabled = false
		add_child(light)
		interior_lights.append(light)

func _material(key: String) -> StandardMaterial3D:
	if _materials.has(key): return _materials[key]
	var colors := {"floor":"9a9c92", "masonry":"9e9785", "mortar":"797766", "cladding":"c9c7b8", "plaster":"d6d0ba", "teal":"28565a", "steel":"626f71", "seam":"849493", "roof":"465c60", "glass":"61838b", "dark":"252d2e", "rubber":"303536", "yellow":"d7af56", "shutter":"82908b", "wood":"957454", "paper":"b6a181", "light":"f4dfb6", "screen":"406c72"}
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(colors.get(key, "ffffff"))
	material.roughness = .85
	if key in ["steel", "roof", "seam", "shutter"]:
		material.metallic = .45
		material.roughness = .52
	if key == "glass":
		material.metallic = .28
		material.roughness = .18
	if key in ["light", "screen"]:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = .45
	_materials[key] = material
	return material

func _box(id: String, at: Vector3, size: Vector3, material_key: String, solid := false, group: Node3D = null, angles := Vector3.ZERO) -> void:
	if group == null: group = _fixed
	var mesh := BoxMesh.new()
	mesh.size = size
	var local_transform := Transform3D(Basis.from_euler(angles), at)
	var key := "%s:%s" % [group.get_instance_id(), material_key]
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = {"surface": surface, "group": group, "material": _material(material_key)}
	var builder: SurfaceTool = _batches[key].surface
	builder.append_from(mesh, 0, local_transform)
	if solid:
		# Cutaway hides meshes, never architecture physics.
		var body_parent: Node3D = self if group in [_fixed, _roof, _facade] else group
		_solid(id, at, size, body_parent, angles)

func _solid(id: String, at: Vector3, size: Vector3, parent: Node3D, angles := Vector3.ZERO) -> void:
	var body := StaticBody3D.new()
	body.name = id + "Solid"
	body.position = at
	body.rotation = angles
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("interior_solid_id", "vertice/" + id + "/" + str(solids.size()))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)
	solids.append(body)

func _commit_batches() -> void:
	for key in _batches:
		var batch: Dictionary = _batches[key]
		var instance := MeshInstance3D.new()
		instance.name = "ArchitectureBatch"
		instance.mesh = batch.surface.commit()
		instance.material_override = batch.material
		batch.group.add_child(instance)
	_batches.clear()
