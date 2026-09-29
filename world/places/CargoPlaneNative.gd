extends Node3D
const PICKUP := preload("res://systems/inventory/PickupPresentation.gd")
## Original aircraft and original aisle/treasure geometry in the shared native world.
var model: Node3D
var reward_points: Array[Dictionary] = []
var _roof_parts: Array[Node3D] = []
var treasure_model: Node3D
var treasure_lid: Node3D
var gold: Node3D
var _treasure_paint: StandardMaterial3D
var _treasure_brass: StandardMaterial3D
var _treasure_box_mesh_resource: BoxMesh
var _presentation_jobs: Array[Callable] = []
func _ready() -> void:
	model = preload("res://assets/regions/source/world/mountain_pass/art/review_0908/CrashedCargoPlane3D.gd").new()
	add_child(model)
	model.set_cutaway(true)
	_open_cargo_aisle()
	for part in _roof_parts: part.hide()
	_build_solids()
	_floor_box(Vector3(0,.105,-1.25),Vector3(2.7,.21,15.5))
	var ramp := _floor_box(Vector3(0,.06,8),Vector3(2.4,.12,3.2))
	ramp.rotation.x = deg_to_rad(3.5)
	_floor_box(Vector3(0,.55,-11.2),Vector3(2.5,.2,4.4))
	# Original cockpit step becomes a physical short slope for native locomotion.
	var step := _floor_box(Vector3(0,.40,-8.4),Vector3(.95,.06,1.3))
	step.rotation.x = deg_to_rad(20)
	_prepare_treasure_staging()
	_queue_presentation_stages()
	for job in _presentation_jobs:
		job.call()
	# Arma e baú ganham a apresentação de coleta da V1. O baú é grande demais para
	# girar: só halo maior e absorção; a arma gira e flutua como qualquer pickup.
	var weapon_holder := PICKUP.new()
	weapon_holder.name = "SmgPickup"
	weapon_holder.position = Vector3(-.55,.39,-7.35)
	model.add_child(weapon_holder)
	var weapon_art := Node3D.new()
	var weapon := Node3D.new()
	weapon.rotation.z = PI*.5
	weapon_art.add_child(weapon)
	weapon_holder.configure(weapon_art,"smg")
	preload("res://assets/regions/source/scripts/player/ArsenalWeapon3D.gd").build(weapon,"smg")
	var treasure_holder := PICKUP.new()
	treasure_holder.name = "TreasurePickup"
	treasure_holder.position = treasure_model.position
	model.add_child(treasure_holder)
	treasure_model.position = Vector3.ZERO
	model.remove_child(treasure_model)
	treasure_holder.configure(treasure_model,"cash")
	treasure_holder.spin_speed = 0.0
	treasure_holder.bob_height = 0.0
	treasure_holder.lift = 0.0
	treasure_holder.halo_scale = 2.3
	for entry in [[{"id":"mountain_cargo_plane_treasure_01","kind":"cash","amount":1800},Vector3(.55,.215,-6.7),treasure_holder],[{"id":"mountain_cargo_plane_smg_01","kind":"weapon","item":"smg","amount":1,"ammo":20},Vector3(-.55,.215,-7.35),weapon_holder]]:
		var point: Dictionary = entry[0].duplicate(true)
		point["reward"] = entry[0].duplicate(true)
		point["position"] = to_global(entry[1])
		point["visual"] = entry[2]
		reward_points.append(point)
	add_to_group("native_world_rewards")
func set_reward_available(available: bool,id: String = "",animate := false) -> void:
	for point in reward_points:
		if id.is_empty() or point.id == id: point.visual.set_available(available,animate)
func _floor_box(center: Vector3,size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	return body
func add_solid(rect: Rect2,id: String) -> void:
	var body := _floor_box(Vector3(rect.get_center().x,1.3,rect.get_center().y),Vector3(rect.size.x,2.6,rect.size.y))
	body.name = id
func _open_cargo_aisle() -> void:
	var materials: Dictionary = model._materials
	for part in model.find_children("*", "MeshInstance3D", true, false):
		if not part is MeshInstance3D or not part.mesh is BoxMesh: continue
		if part.material_override in [materials.get("crate_wood"),materials.get("crate_metal")]:
			# The supplied art stacked cargo across the complete fuselage width.
			# Lash it against the port wall and keep the middle/right aisle open.
			part.position.x = -0.95
			part.mesh = part.mesh.duplicate()
			part.mesh.size.x = minf(part.mesh.size.x,0.55)
		if part.position.y > 2.0 and absf(part.position.x)<0.1:
			# Wing centre and raised tail would still cover the walking corridor
			# even with CutawayRoof removed. Treat these as overhead sections.
			_roof_parts.append(part)
	# The optimized aircraft batches static boxes in MultiMeshes. Keep the same
	# walkable aisle contract by moving only authored cargo-crate instances.
	for batch in model.find_children("*", "MultiMeshInstance3D", true, false):
		if batch.material_override not in [materials.get("crate_wood"), materials.get("crate_metal")]: continue
		var multimesh: MultiMesh = batch.multimesh
		for index in multimesh.instance_count:
			var transform := multimesh.get_instance_transform(index)
			transform.origin.x = -0.95
			if transform.basis.x.length() > 0.55:
				transform.basis.x = transform.basis.x.normalized() * 0.55
			multimesh.set_instance_transform(index, transform)
func _build_solids() -> void:
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*1.55-0.12,-13.3,0.24,19.9),"FuselageWall")
	add_solid(Rect2(-1.55,-13.6,3.1,0.3),"CockpitNose")
	add_solid(Rect2(-14.1,-4.9,12.6,2.8),"LeftWing")
	add_solid(Rect2(1.65,-4.9,12.3,2.8),"RightWing")
	add_solid(Rect2(-1.27,-4.0,0.65,1.6),"SecuredForwardCargo")
	add_solid(Rect2(-1.27,1.9,0.65,1.5),"SecuredRampCargo")
	add_solid(Rect2(0.18,-7.65,0.75,0.60),"TreasureCrate")
	for side in [-1.0,1.0]:
		add_solid(Rect2(side*0.62-0.26,-11.85,0.52,0.8),"PilotSeat")
	add_solid(Rect2(-1.1,-12.9,2.2,0.6),"CockpitInstruments")
func _prepare_treasure_staging() -> void:
	treasure_model = Node3D.new()
	treasure_model.name = "SmugglerTreasure"
	treasure_model.position = Vector3(0.55,0.20,-7.35)
	model.add_child(treasure_model)
	_treasure_paint = StandardMaterial3D.new()
	_treasure_paint.albedo_color = Color("98532c")
	_treasure_paint.roughness = 0.75
	treasure_lid = Node3D.new()
	treasure_lid.name = "Lid"
	treasure_lid.position = Vector3(0,0.45,-0.30)
	treasure_model.add_child(treasure_lid)
	_treasure_brass = StandardMaterial3D.new()
	_treasure_brass.albedo_color = Color("ffd16b")
	_treasure_brass.metallic = 0.45
	_treasure_brass.emission_enabled = true
	_treasure_brass.emission = Color("b67a24")
	_treasure_brass.emission_energy_multiplier = 0.35
	gold = Node3D.new()
	gold.name = "Gold"
	treasure_model.add_child(gold)

func _queue_presentation_stages() -> void:
	_presentation_jobs.append(Callable(self, "_box").bind(treasure_model,Vector3(0,0.04,0),Vector3(0.75,0.08,0.6),_treasure_paint))
	for x in [-0.34,0.34]:
		_presentation_jobs.append(Callable(self, "_box").bind(treasure_model,Vector3(x,0.25,0),Vector3(0.07,0.42,0.6),_treasure_paint))
	for z in [-0.265,0.265]:
		_presentation_jobs.append(Callable(self, "_box").bind(treasure_model,Vector3(0,0.25,z),Vector3(0.68,0.42,0.07),_treasure_paint))
	# Broad bands and a front lock read as a treasure chest from the overhead camera.
	for x in [-0.26,0.26]:
		_presentation_jobs.append(Callable(self, "_box").bind(treasure_model,Vector3(x,0.21,0),Vector3(0.075,0.44,0.62),_treasure_brass))
	# Each lid segment is a single bounded stage so it never appears half assembled.
	for segment in 8:
		_presentation_jobs.append(Callable(self, "_stage_treasure_lid_segment").bind(segment))
	_presentation_jobs.append(Callable(self, "_box").bind(treasure_model,Vector3(0,0.035,0),Vector3(0.79,0.07,0.64),_treasure_brass))
	_presentation_jobs.append(Callable(self, "_box").bind(treasure_lid,Vector3(0,-0.035,0.62),Vector3(0.16,0.20,0.045),_treasure_brass))
	for x in [-0.2,0.0,0.2]:
		_presentation_jobs.append(Callable(self, "_box").bind(gold,Vector3(x,0.39,0),Vector3(0.13,0.06,0.25),_treasure_brass))
	for z in [-7.0, 1.5]:
		_presentation_jobs.append(Callable(self, "_stage_cargo_lamp").bind(z))

func _stage_cargo_lamp(z: float) -> void:
	var lens := StandardMaterial3D.new()
	lens.albedo_color = Color("ffd1a0")
	lens.emission_enabled = true
	lens.emission = Color("ffc080")
	lens.emission_energy_multiplier = 1.3
	_box(model, Vector3(1.35,.95,z), Vector3(.08,.16,.28), lens)
	var light := OmniLight3D.new()
	light.name = "CargoEmergencyLight"
	light.position = Vector3(.8,1.25,z)
	light.light_color = Color("ffcd95")
	light.light_energy = 1.35
	light.omni_range = 4.5
	light.shadow_enabled = false
	model.add_child(light)

func _stage_treasure_lid_segment(segment: int) -> void:
	var angle := (float(segment)+0.5)*PI/8.0
	var centre := Vector3(0,sin(angle)*0.24,0.30+cos(angle)*0.30)
	var panel := _box(treasure_lid,centre,Vector3(0.78,0.055,0.125),_treasure_paint)
	panel.rotation.x = angle-PI*0.5
	for x in [-0.26,0.26]:
		var strap := _box(treasure_lid,centre+Vector3(x,sin(angle)*0.025,cos(angle)*0.025),Vector3(0.08,0.035,0.13),_treasure_brass)
		strap.rotation.x = angle-PI*0.5

func _treasure_box_mesh() -> BoxMesh:
	if _treasure_box_mesh_resource == null:
		_treasure_box_mesh_resource = BoxMesh.new()
		_treasure_box_mesh_resource.size = Vector3.ONE
		_treasure_box_mesh_resource.resource_name = "MountainCargoTreasureSharedBox"
	return _treasure_box_mesh_resource

func _box(parent: Node3D,pos: Vector3,size: Vector3,material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = _treasure_box_mesh()
	part.material_override = material
	part.position = pos
	part.scale = size
	parent.add_child(part)
	return part
