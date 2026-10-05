extends SceneTree
## Immutable cache preparation; no Main or gameplay entity admission.
## Baseline fixture preserves the original wardrobe and rig independently.
const MODEL := preload("res://assets/CivilianModel.gd")
const ORIGINAL := preload("res://tests/fixtures/TerminalCivilianModelOriginal.gd")
const KIT := preload("res://assets/civilians/CivilianMeshKit.gd")
const OPS := preload("res://runtime/terminal/TerminalOperations.gd")
const ROUTES := preload("res://runtime/terminal/TerminalRoutes.gd")
const WORK := preload("res://runtime/StallWorkTrace.gd")

class FakeWorld extends Node3D:
	var player := Node3D.new()
	func _init() -> void: add_child(player)

class FakeController extends RefCounted:
	var world: Node3D
	var state := {"region_id":"harbor","place_id":""}
	var session := {"ready_for_play":false}
	var urban_transit := {"instances":{"harbor_coach_terminal":true}}

var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TERMINAL_MESH_PREP: "+label)

func appearance(model, identity: int) -> void:
	model.appearance_locked = true
	model.appearance_variant = identity
	model.coat_color = [Color("426c70"),Color("a35d42"),Color("d3c3a1"),Color("42556f"),Color("8e5362"),Color("70835d")][identity % 6]
	model.pants_color = [Color("293849"),Color("484644"),Color("615342")][identity % 3]
	model._choose_wardrobe(identity)

func same_rig(a, b) -> bool:
	if a.scale != b.scale or a._joints.size() != b._joints.size(): return false
	for index in a._joints.size():
		var first: MeshInstance3D = a._joints[index]
		var second: MeshInstance3D = b._joints[index]
		if first.mesh != second.mesh or first.name != second.name or first.transform != second.transform: return false
	return true

func ineligible(controller, label: String) -> void:
	var operations := OPS.new()
	operations.configure(controller)
	root.add_child(operations)
	await operations.prepare_startup_passenger_meshes(1)
	check(not operations._passenger_meshes_prepared and operations.get_child_count()==0 and WORK.take().is_empty(),label)
	operations.free()

func run() -> void:
	# StallLog's headless autoload queues its own deletion in _ready. Settle
	# that bootstrap before measuring the fixture's immutable node inventory.
	var queued_autoloads: Array[String] = []
	for node in root.get_children():
		if node.is_queued_for_deletion(): queued_autoloads.append(str(node.name))
	print("TERMINAL_MESH_FIXTURE bootstrap_queued=",queued_autoloads)
	for frame in 2: await process_frame
	var controller := FakeController.new()
	controller.world = FakeWorld.new()
	root.add_child(controller.world)
	controller.world.player.global_position = ROUTES.point(0,0)
	var operations := OPS.new()
	operations.configure(controller)
	root.add_child(operations)
	# This standalone process owns the cache; production has no cache reset.
	KIT._meshes.clear()
	var references: Array = []
	for identity in range(80,96):
		var original = ORIGINAL.new()
		appearance(original,identity)
		references.append(original)
	var tree_nodes := root.find_children("*","",true,false).size()
	seed(384757)
	var expected_random := randf()
	seed(384757)
	WORK.enabled = true
	WORK.take()
	var admitted_nodes: Array[int] = []
	var on_admitted := func(node: Node) -> void: admitted_nodes.append(node.get_instance_id())
	node_added.connect(on_admitted)
	# A one-us test budget forces the yield branch without a timing assertion.
	await operations.prepare_startup_passenger_meshes(1)
	node_added.disconnect(on_admitted)
	check(randf()==expected_random,"Preparation leaves the gameplay global RNG unchanged")
	var ids: Array[int] = []
	var slices := 0
	var total_active := -1
	for event in WORK.take():
		if event.get("label","")=="terminal.passenger.mesh_prewarm":
			ids.append(int(event.details.identity))
			check(event.details.startup,"Every preparation identity is recorded before ready_for_play")
		elif event.get("label","")=="terminal.passenger.mesh_prewarm_slice":
			if event.details.yielding: slices += 1
			else: total_active = int(event.details.total_active_usec)
	check(ids==range(80,96),"Exactly the sixteen conserved terminal identities are prepared")
	check(slices>0 and total_active>=0,"Preparation yields between identities and records active work separately")
	var tree_nodes_after := root.find_children("*","",true,false).size()
	print("TERMINAL_MESH_FIXTURE nodes_before=",tree_nodes," nodes_after=",tree_nodes_after," admitted=",admitted_nodes.size())
	check(admitted_nodes.is_empty() and tree_nodes_after==tree_nodes and operations.get_child_count()==0,
		"Immutable preparation creates no scene nodes or gameplay entities")
	check(operations._passenger_meshes_prepared and not operations.resident and not operations.running and operations.fleet.is_empty() and operations.gates.is_empty(),
		"Coaches, passengers, gates and atomic admission remain untouched")
	check(operations._clock==0.0 and not controller.session.ready_for_play and operations.road==null and not operations._road_prepared,
		"Preparation changes no simulation timer, ready flag or route")
	var filled := KIT.cache_size()
	check(filled>0,"Cold immutable cache receives the required meshes")
	var wardrobes_equal := true
	var rigs_equal := true
	for index in references.size():
		var baseline = references[index]
		var candidate = MODEL.new()
		appearance(candidate,80+index)
		wardrobes_equal = wardrobes_equal and baseline.wardrobe==candidate.wardrobe
		baseline._build_rig()
		candidate._build_rig()
		rigs_equal = rigs_equal and same_rig(baseline,candidate)
		candidate.free()
		baseline.free()
	check(wardrobes_equal,"All deterministic wardrobes match the frozen original implementation")
	check(rigs_equal,"All original/candidate rig joints use identical meshes, names and transforms")
	check(KIT.cache_size()==filled,"The original sixteen rigs require no new cache keys after preparation")
	WORK.take()
	await operations.prepare_startup_passenger_meshes(1)
	check(WORK.take().is_empty() and KIT.cache_size()==filled,"Repeated preparation is idempotent")
	controller.state.region_id = "mountain"
	await ineligible(controller,"Mountain startup keeps lazy geometry available")
	controller.state.region_id = "harbor"
	controller.state.place_id = "garage"
	await ineligible(controller,"Interior startup keeps lazy geometry available")
	controller.state.place_id = ""
	controller.world.player.global_position = Vector3(1000,0,1000)
	await ineligible(controller,"Distant startup does not prepare terminal geometry")
	controller.world.player.global_position = ROUTES.point(0,0)
	controller.urban_transit.instances.clear()
	await ineligible(controller,"Absent terminal geometry does not prepare passenger cuts")
	controller.urban_transit.instances.harbor_coach_terminal = true
	controller.session.ready_for_play = true
	await ineligible(controller,"This startup preparation cannot run during interactive gameplay")
	operations.free()
	controller.world.free()
	WORK.enabled = false
	WORK.take()
	print("TERMINAL_MESH_PREP ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
