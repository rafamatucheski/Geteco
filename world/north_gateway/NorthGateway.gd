extends Node3D
## The existing regional connection owns this site's lifetime. The campaign
## can be read during startup, before FullSession or its HUD has been mounted.
const POLICY := preload("res://world/north_gateway/NorthGatewayPolicy.gd")
const LAYOUT := preload("res://world/north_gateway/NorthGatewayLayout.gd")
const SCENERY := preload("res://world/north_gateway/NorthGatewayScenery.gd")
const WORKERS := preload("res://world/north_gateway/NorthGatewayWorkers.gd")
const LOAD_DISTANCE := 150.0
const RELEASE_DISTANCE := 210.0
const ANIMATION_DISTANCE := 70.0
var world: Node3D
var scenery: Node3D
var workers: Node3D
var completed := false
var _clock := 0.0

func configure(owner_world: Node3D) -> void:
	world = owner_world
	name = "NorthGateway"

func _ready() -> void:
	add_to_group("north_gateway")
	process_mode = Node.PROCESS_MODE_PAUSABLE
	reconcile()

func _process(delta: float) -> void:
	_clock += delta
	if _clock < .25: return
	_clock = 0.0
	reconcile()

func reconcile() -> void:
	if not is_instance_valid(world): return
	var production = world.get("production")
	if not is_instance_valid(production): return
	var state = production.get("state")
	if state == null: return
	# Completion is monotonic within one world. Loading an earlier save creates
	# another world; transient invalid state must not pull a deck from under a car.
	var should_open: bool = not production.save_invalid and POLICY.campaign_completed(state.campaign.snapshot())
	if should_open and not completed:
		completed = true
		if is_instance_valid(scenery): scenery.set_completed(true)
		_release_workers()
	var player = world.get("player")
	if not is_instance_valid(player): return
	var point: Vector3 = player.global_position
	var driving = world.get("driving")
	if is_instance_valid(driving) and driving.occupied and is_instance_valid(driving.car):
		point = driving.car.global_position
	var distance := _distance_to_site(point)
	var vehicle_support := _parked_vehicle_needs_support(production)
	if not is_mounted() and (distance <= LOAD_DISTANCE or vehicle_support):
		_mount()
	elif is_mounted() and distance > RELEASE_DISTANCE and not vehicle_support:
		_unmount()
	if is_instance_valid(workers):
		var nearby := false
		for position: Vector3 in LAYOUT.work_positions():
			if point.distance_to(position) <= ANIMATION_DISTANCE:
				nearby = true
				break
		workers.set_active(nearby and state.place_id.is_empty())

func _distance_to_site(point: Vector3) -> float:
	var bounds: Rect2 = LAYOUT.bounds()
	var flat := Vector2(point.x,point.z)
	var closest := Vector2(clampf(flat.x,bounds.position.x,bounds.end.x),clampf(flat.y,bounds.position.y,bounds.end.y))
	return flat.distance_to(closest)

func _parked_vehicle_needs_support(production) -> bool:
	var footprint: Rect2 = LAYOUT.bounds().grow(5.0)
	for car in production.vehicles:
		if not is_instance_valid(car) or car.is_queued_for_deletion(): continue
		if not car.visible or car.collision_layer == 0: continue
		# Streaming-suspended cars retain their request: they need this deck to
		# pass ProductionWorld's ground check and resume after loading a save.
		if not car.is_physics_processing() and not car.has_meta("awaiting_ground"): continue
		if footprint.has_point(Vector2(car.global_position.x,car.global_position.z)): return true
	return false

func is_mounted() -> bool:
	return is_instance_valid(scenery) and not scenery.is_queued_for_deletion()

func _mount() -> void:
	scenery = SCENERY.new()
	add_child(scenery)
	scenery.build(completed)
	if completed: return
	workers = WORKERS.new()
	add_child(workers)
	workers.configure(LAYOUT.work_positions(),LAYOUT.work_yaws())
	workers.set_active(false)

func _release_workers() -> void:
	if not is_instance_valid(workers): return
	workers.set_active(false)
	workers.queue_free()
	workers = null

func _unmount() -> void:
	_release_workers()
	if is_instance_valid(scenery): scenery.queue_free()
	scenery = null

static func campaign_completed(snapshot: Variant) -> bool:
	return POLICY.campaign_completed(snapshot)
