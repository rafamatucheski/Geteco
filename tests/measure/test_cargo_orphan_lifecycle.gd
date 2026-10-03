extends SceneTree
## Ownership diagnostic only: no Main, save operations or FPS claim.
## Use Godot .NET debug, --no-save and an isolated APPDATA/LOCALAPPDATA.
const ID := "cargo_flatbed_truck"
const SCENE := "res://assets/fleet/cargo_flatbed_truck.scn"
const FLEET := preload("res://runtime/FleetCatalog.gd")
const HEAVY := preload("res://runtime/HeavyVehicleDetail.gd")
const FINISH := preload("res://runtime/VehicleFinish.gd")
const TWO_TONE := preload("res://runtime/VehicleTwoTone.gd")
const SPEED := preload("res://runtime/FleetSpeedPass.gd")
const VEHICLE := preload("res://scripts/Vehicle.gd")
const INTERIOR := preload("res://gameplay/VehicleInterior.gd")
const DISPATCH_RULES := preload("res://gameplay/dispatch/DispatchRules.gd")
const SOURCES := [
	SCENE, "res://runtime/FleetCatalog.gd",
	"res://runtime/HeavyVehicleDetail.gd",
	"res://runtime/VehicleFinish.gd",
	"res://runtime/VehicleTwoTone.gd",
	"res://runtime/FleetSpeedPass.gd",
	"res://runtime/VehicleSurfaceRoles.gd",
	"res://runtime/VehiclePaint.gd",
	"res://scripts/Vehicle.gd", "res://gameplay/VehicleInterior.gd",
	"res://gameplay/VehicleEquipment.gd", "res://gameplay/VehicleDoorPresentation.gd",
	"res://gameplay/VehicleDoorBuilder.gd", "res://data/catalogs/VehicleDoorSpecs.gd",
	"res://gameplay/vehicle_effects/VehicleDamage.gd",
	"res://gameplay/vehicle_effects/VehicleWreckBody.gd",
	"res://gameplay/dispatch/DispatchRules.gd", "res://runtime/ProductionWorld.gd",
	"res://tests/measure/test_cargo_orphan_lifecycle.gd",
]
var baseline_ids: Dictionary = {}
var observations: Dictionary = {}
var stages: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
	print(("PASS " if condition else "FAIL ") + message)

func _hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCES:
		result[path] = FileAccess.get_sha256(path)
	return result

func _describe(node: Node) -> Dictionary:
	var parent := node.get_parent()
	var row := {
		"id": str(node.get_instance_id()), "class": node.get_class(),
		"name": str(node.name), "inside_tree": node.is_inside_tree(),
		"queued": node.is_queued_for_deletion(),
		"parent_id": str(parent.get_instance_id()) if parent != null else "",
	}
	if node is MeshInstance3D:
		var mesh: Mesh = node.mesh
		row["mesh_id"] = str(mesh.get_instance_id()) if mesh != null else ""
		row["mesh_class"] = mesh.get_class() if mesh != null else ""
		row["mesh_path"] = mesh.resource_path if mesh != null else ""
		row["transform"] = str(node.transform)
		var materials: Array[Dictionary] = []
		if mesh != null:
			for surface in mesh.get_surface_count():
				var material: Material = node.get_active_material(surface)
				materials.append({
					"surface": surface,
					"id": str(material.get_instance_id()) if material != null else "",
					"path": material.resource_path if material != null else "",
					"name": material.resource_name if material != null else "",
				})
		row["materials"] = materials
	return row

func _remember(node: Node, stage: String) -> void:
	var id := node.get_instance_id()
	if observations.has(id): return
	observations[id] = {
		"weak": weakref(node), "first_stage": stage,
		"initial": _describe(node),
	}

func _remember_tree(owner: Node, stage: String) -> void:
	var pending: Array[Node] = [owner]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		_remember(node, stage)
		for child: Node in node.get_children(true):
			pending.append(child)

func _stage(label: String, owner: Node = null) -> void:
	if is_instance_valid(owner): _remember_tree(owner, label)
	var unexpected: Array[Dictionary] = []
	var expected_off_tree := 0
	for id: int in Node.get_orphan_node_ids():
		if baseline_ids.has(id): continue
		var node := instance_from_id(id) as Node
		if node == null: continue
		if is_instance_valid(owner) and (node == owner or owner.is_ancestor_of(node)):
			expected_off_tree += 1
			continue
		_remember(node, label)
		var row := _describe(node)
		row["first_stage"] = observations[id].first_stage
		row["initial"] = observations[id].initial
		unexpected.append(row)
	var row := {
		"stage": label, "expected_off_tree_nodes": expected_off_tree,
		"unexpected_orphans": unexpected,
		"owner_children": owner.get_child_count() if is_instance_valid(owner) else 0,
	}
	stages.append(row)
	print("CARGO_ORPHAN_STAGE ", JSON.stringify(row))
	_check(unexpected.is_empty(), label + ": no unexpected orphan nodes")

func _release(model: Node3D, label: String) -> void:
	model.free()
	model = null
	await process_frame
	await process_frame
	_stage(label)

func _decorated_pass(packed: PackedScene, label: String) -> void:
	var model := packed.instantiate() as Node3D
	_stage(label + "/instantiate", model)
	HEAVY.decorate(ID, model)
	_stage(label + "/heavy", model)
	FINISH.decorate(ID, model)
	_stage(label + "/finish", model)
	TWO_TONE.decorate(ID, model)
	_stage(label + "/two_tone", model)
	SPEED.decorate(ID, model)
	_stage(label + "/speed", model)
	# Production decorates off-tree, then adds the model during fleet prewarm.
	root.add_child(model)
	await process_frame
	_stage(label + "/attached", model)
	await _release(model, label + "/freed")

func _vehicle_pass() -> void:
	# The real consumer owns its children; no Main or fabricated world callbacks.
	var host := Node3D.new()
	root.add_child(host)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_body.position.y = -.5
	floor_body.add_child(floor_shape)
	host.add_child(floor_body)
	var car := VEHICLE.new()
	car.archetype = ID
	car.vehicle_id = "cargo_orphan_consumer"
	car.position.y = .1
	host.add_child(car)
	await physics_frame
	await process_frame
	_check(is_instance_valid(car.visual) and is_instance_valid(car.damage_look),
		"real Vehicle ready creates visual and damage consumer")
	_stage("vehicle/ready", host)
	# Null world is an explicit supported path in Equipment's night/player guards.
	car.ensure_equipment(null)
	_stage("vehicle/equipment", host)
	car.finish_doors()
	_check(is_instance_valid(car.door_presentation), "real cargo doors constructed")
	_stage("vehicle/doors", host)
	await INTERIOR.prewarm(car)
	await process_frame
	_stage("vehicle/prewarm", host)
	INTERIOR.attach(car)
	_check(car.visual.has_node("Interior"), "real cargo interior attached")
	_stage("vehicle/interior_open", host)
	INTERIOR.close_view(car)
	_stage("vehicle/interior_closed", host)
	car.receive_damage(car.max_health * .45 / maxf(car.damage_resistance, .05))
	_check(car.health > 0 and car.health < car.max_health, "partial damage applied")
	_stage("vehicle/damaged", host)
	car.repair()
	_stage("vehicle/repaired", host)
	car.receive_damage(car.max_health * 2.0 / maxf(car.damage_resistance, .05))
	await physics_frame
	await physics_frame
	await process_frame
	_check(car.health == 0 and car.damage_look.wrecked, "real wreck consumer activated")
	_stage("vehicle/wreck", host)
	car.repair()
	await process_frame
	_check(car.health == car.max_health and not car.damage_look.wrecked,
		"real wreck repaired")
	_stage("vehicle/wreck_repaired", host)
	# queue_free is the normal scene-removal path; do not clean detached objects.
	host.queue_free()
	await process_frame
	await process_frame
	_stage("vehicle/freed")

func _fleet_sequence() -> void:
	# Optional fresh-process ordering from ProductionWorld's shader warm-up.
	# No cache reset: prove cargo has not already warmed its merge plan.
	_check(not SPEED._plans.has(ID), "cargo merge plan cold before fleet sequence")
	var order: Array[String] = []
	for value: String in DISPATCH_RULES.ARCHETYPES.values():
		order.append("dispatch/" + value)
		var model: Node3D = FLEET.create(value)
		_check(model != null, "dispatch factory creates " + value)
		if model == null: continue
		_stage("dispatch/" + value + "/created", model)
		await _release(model, "dispatch/" + value + "/freed")
	for value: String in FLEET.all():
		order.append("fleet/" + value)
		var model: Node3D = FLEET.create(value)
		_check(model != null, "fleet factory creates " + value)
		if model == null: continue
		_stage("fleet/" + value + "/created", model)
		# Keep production's disabled callbacks and actual attach/free ownership.
		# Headless process frames do not certify the two rendered draws.
		model.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(model)
		await process_frame
		await process_frame
		_stage("fleet/" + value + "/attached", model)
		await _release(model, "fleet/" + value + "/freed")
	print("CARGO_FLEET_ORDER ", JSON.stringify(order))

func run() -> void:
	_check("--no-save" in OS.get_cmdline_user_args(), "--no-save required")
	_check(OS.is_debug_build(), "debug build exposes orphan IDs")
	_check(ClassDB.class_exists(&"CSharpScript"), "Godot .NET required")
	if not failures.is_empty():
		quit(2)
		return
	var before := _hashes()
	# Let deferred autoload removal finish before defining the baseline.
	await process_frame
	await process_frame
	for id: int in Node.get_orphan_node_ids(): baseline_ids[id] = true
	var sentinel := Node3D.new()
	_check(Node.get_orphan_node_ids().has(sentinel.get_instance_id()),
		"orphan census observes an intentionally unparented node")
	sentinel.free()
	if not failures.is_empty():
		quit(2)
		return
	var fleet_sequence := "--fleet-sequence" in OS.get_cmdline_user_args()
	if fleet_sequence: await _fleet_sequence()
	var packed := load(SCENE) as PackedScene
	_check(packed != null, "real cargo scene available")
	if packed == null:
		quit(2)
		return
	var raw := packed.instantiate() as Node3D
	_stage("raw/instantiate", raw)
	await _release(raw, "raw/freed")
	await _decorated_pass(packed, "after_fleet" if fleet_sequence else "cold")
	await _decorated_pass(packed, "cache_hit")
	# Confirm the same lifecycle through the actual public factory.
	var factory := FLEET.create(ID)
	_stage("factory/create", factory)
	root.add_child(factory)
	await process_frame
	_stage("factory/attached", factory)
	await _release(factory, "factory/freed")
	await _vehicle_pass()
	var survivors: Array[Dictionary] = []
	for entry: Dictionary in observations.values():
		var node := entry.weak.get_ref() as Node
		if is_instance_valid(node):
			var row := _describe(node)
			row["first_stage"] = entry.first_stage
			survivors.append(row)
	_check(survivors.is_empty(), "all observed owned nodes released")
	_check(before == _hashes(), "tracked sources unchanged")
	var report := {
		"checks": checks, "failures": failures, "stages": stages,
		"survivors": survivors, "sources_before": before,
		"fleet_sequence": fleet_sequence,
		"sources_after": _hashes(), "user_data_dir": OS.get_user_data_dir(),
		"scope": "Raw scene, decorators cold/cache, factory, real Vehicle/equipment/doors/interior/damage/wreck/repair/removal. Equipment has no world binding. No Main or FPS approval; detached leaks are never manually cleaned.",
	}
	var output := FileAccess.open("user://cargo-orphan-lifecycle.json", FileAccess.WRITE)
	if output == null:
		push_error("Cannot write cargo orphan report")
		quit(2)
		return
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("CARGO_ORPHAN_RESULT ", JSON.stringify({
		"checks": checks, "failures": failures, "survivors": survivors,
	}))
	quit(0 if failures.is_empty() else 1)
