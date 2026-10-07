extends Node3D
const L:=preload("res://world/desert/north_pass/DesertNorthPassLayout.gd")
const ART:=preload("res://world/desert/north_pass/DesertNorthPassScenery.gd")
const MODEL:=preload("res://world/north_gateway/NorthGatewayWorkerModel.gd")
var session
var _workers: Node3D
var _clock:=0.0
var _check:=0.0
var _pose:=0.0

func configure(owner_session) -> void:
	session=owner_session
	name="DesertNorthPass"
	refresh()

func _process(delta: float) -> void:
	_clock+=delta
	_check+=delta
	_pose+=delta
	if _check>=.25:
		_check=0.0
		refresh()
	if is_instance_valid(_workers) and _pose>=1.0/20.0:
		for worker in _workers.get_children():
			var model=worker.get_node("Model")
			model.sample_work(_clock,_pose)
		_pose=0.0

func refresh() -> void:
	if not is_inside_tree() or not is_instance_valid(session): return
	var done:=L.completed(session.state.world_state)
	var region: Node3D=session.controller.regions.get("desert")
	if is_instance_valid(region) and region.has_method("set_north_pass_completed"): region.set_north_pass_completed(done)
	for gate in get_tree().get_nodes_in_group(L.GROUP): ART.set_completed(gate,done)
	var active: bool=session.ready_for_play and L.enabled() and not done and session.state.region_id=="desert" and session.state.place_id.is_empty()
	if active: active=session.world.player.global_position.distance_to(L.GATE)<(110.0 if is_instance_valid(_workers) else 85.0)
	if not active:
		_clear_workers()
		return
	if is_instance_valid(_workers): return
	_pose=0.0
	_workers=Node3D.new()
	_workers.name="NorthPassWorkers"
	add_child(_workers)
	for specification in L.workers():
		var worker:=StaticBody3D.new()
		worker.name="RoadWorker"
		worker.position=specification.position
		worker.rotation.y=specification.yaw
		worker.collision_layer=1
		worker.collision_mask=0
		_workers.add_child(worker)
		var collider:=CollisionShape3D.new()
		var capsule:=CapsuleShape3D.new()
		capsule.radius=.3
		capsule.height=1.75
		collider.shape=capsule
		collider.position.y=.875
		worker.add_child(collider)
		var model:=MODEL.new()
		model.name="Model"
		model.job=specification.job
		worker.add_child(model)

func _clear_workers() -> void:
	if not is_instance_valid(_workers): return
	remove_child(_workers)
	_workers.queue_free()
	_workers=null

func cancel_attempt() -> void:
	_clear_workers()
	_check=.25
