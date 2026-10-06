extends Node3D
## Six authored work stations, one shared clock, zero work when the site is far.
## Bodies stay at real floor stations; the production human rig supplies hand IK.
const LAYOUT := preload("res://world/mining/MiningLayout.gd")
const MODEL := preload("res://world/north_gateway/NorthGatewayWorkerModel.gd")
const GEAR := preload("res://world/north_gateway/NorthGatewayWorkerGeometry.gd")
const BATCH := preload("res://world/mining/MiningBatch.gd")
const ACTIVE_RADIUS := 158.0
const SLEEP_RADIUS := 184.0
const POSE_INTERVAL := .05
var _workers: Array[CharacterBody3D]=[]
var _models: Array[Node3D]=[]
var _focus := Vector3.INF
var _active := false
var _clock := 0.0
var _elapsed := 0.0
var _configured := false
var _work_root: Node3D

func configure(_owner: Node3D = null) -> void:
	_configured=true
	if is_node_ready(): _update_presence()

func _ready() -> void:
	name="MiningWorkers"
	process_mode=Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	if _configured: _update_presence()

func set_focus(point: Vector3) -> void:
	_focus=point
	if _configured and is_node_ready(): _update_presence()

func _update_presence() -> void:
	if not LAYOUT.enabled() or not _focus.is_finite():
		suspend()
		return
	var distance := Vector2(_focus.x-LAYOUT.CENTER.x,_focus.z-(LAYOUT.CENTER.z+35)).length()
	if _active and distance>SLEEP_RADIUS:
		suspend()
	elif not _active and distance<ACTIVE_RADIUS:
		if _workers.is_empty(): _build()
		_active=true
		visible=true
		set_process(true)
		for worker in _workers: worker.collision_layer=2

func suspend() -> void:
	_active=false
	visible=false
	_elapsed=0.0
	set_process(false)
	for worker in _workers:
		if is_instance_valid(worker): worker.collision_layer=0
	# No work fixtures remain on unloaded terrain. On the next visit the same
	# six stations are rebuilt; there are no orphan colliders or autonomous rigs.
	if is_instance_valid(_work_root):
		remove_child(_work_root)
		_work_root.queue_free()
	_work_root=null
	_workers.clear()
	_models.clear()

func _build() -> void:
	_work_root=Node3D.new()
	_work_root.name="ResidentMineCrew"
	_work_root.position=LAYOUT.CENTER
	add_child(_work_root)
	var capsule := CapsuleShape3D.new()
	capsule.radius=.30
	capsule.height=1.7
	for station in LAYOUT.worker_stations():
		var worker := CharacterBody3D.new()
		worker.name="Miner_"+str(station.id)
		worker.position=station.point
		worker.rotation.y=float(station.yaw)
		worker.collision_layer=2
		worker.collision_mask=0
		worker.set_meta("gameplay_role","ambient_worker")
		worker.set_meta("mining_worker",station.id)
		var collider := CollisionShape3D.new()
		collider.shape=capsule
		collider.position.y=.86
		worker.add_child(collider)
		_work_root.add_child(worker)
		var model := MODEL.new()
		model.job=int(station.job)
		worker.add_child(model)
		_workers.append(worker)
		_models.append(model)
		if int(station.job) in [1,3]:
			GEAR.add(worker,"brace" if int(station.job)==3 else "bench")
			var equipment := StaticBody3D.new()
			equipment.name="MinerWorkBench"
			equipment.collision_layer=1
			equipment.collision_mask=0
			var shape := BoxShape3D.new()
			shape.size=Vector3(.68,1.1 if int(station.job)==3 else .86,.46)
			var fixture := CollisionShape3D.new()
			fixture.shape=shape
			fixture.position=Vector3(0,shape.size.y*.5,.6)
			equipment.add_child(fixture)
			worker.add_child(equipment)
		elif int(station.job)==0:
			var rock_batch := BATCH.new(worker,"OreBeingSampled")
			rock_batch.rock("OreSample",Vector3(0,.12,.4),Vector3(.6,.27,.55),"ore_light",true)
			rock_batch.finish()

func _process(delta: float) -> void:
	if not _active or not is_finite(delta) or delta<=0.0: return
	_clock+=delta
	_elapsed+=delta
	if _elapsed<POSE_INTERVAL: return
	var step := minf(_elapsed,.1)
	_elapsed=0.0
	var camera := get_viewport().get_camera_3d()
	for i in _models.size():
		var model := _models[i]
		if not is_instance_valid(model): continue
		if model.global_position.distance_squared_to(_focus)>10000: continue
		if camera!=null and not camera.is_position_in_frustum(model.global_position+Vector3.UP): continue
		model.sample_work(_clock+float(i)*.43,step)

func debug_snapshot() -> Dictionary:
	return {"workers":_workers.size(),"active":_active,"clock":_clock,
		"independent_model_processes":_models.filter(func(model): return is_instance_valid(model) and (model.is_processing() or model.is_physics_processing())).size(),
		"positions":_workers.map(func(worker): return worker.global_position)}
