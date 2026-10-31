extends Node3D
## Quatro operários de obra parados, com um relógio de apresentação de 30 Hz.
## O NorthGateway é dono da proximidade, da conclusão da ponte e de carga/descarga.
## +Z local é a direção de trabalho. Reserva X[-.7,.7], Z[-.4,.9] por posto.
## set_active(false) congela a apresentação. O dono esconde/libera o canteiro
## concluído; os corpos físicos ficam enquanto este grupo está visível.
const MODEL := preload("res://world/north_gateway/NorthGatewayWorkerModel.gd")
const GEAR := preload("res://world/north_gateway/NorthGatewayWorkerGeometry.gd")
const COUNT := 4
const POSE_INTERVAL := 1.0/30.0
var _positions: Array[Vector3] = []
var _yaws: Array[float] = []
var _models: Array[Node3D] = []
var _workers: Array[CharacterBody3D] = []
var _active := false
var _clock := 0.0
var _elapsed := 0.0
var _configured := false
static var _capsule: CapsuleShape3D

func configure(work_positions: Array[Vector3], yaws: Array[float] = []) -> bool:
	if work_positions.size() != COUNT or (not yaws.is_empty() and yaws.size() != COUNT): return false
	for point in work_positions:
		if not point.is_finite(): return false
	for yaw in yaws:
		if not is_finite(yaw): return false
	_clear()
	_positions.assign(work_positions)
	_yaws.assign(yaws)
	if _yaws.is_empty(): _yaws.assign([0.0,0.0,0.0,0.0])
	_configured = true
	if is_node_ready(): _build()
	return true

func _ready() -> void:
	name = "NorthGatewayWorkers"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(false)
	if _configured: _build()

func _build() -> void:
	if not _workers.is_empty(): return
	if _capsule == null:
		_capsule = CapsuleShape3D.new()
		_capsule.radius = .30
		_capsule.height = 1.7
	for index in COUNT:
		var worker := CharacterBody3D.new()
		worker.name = ["BreakerOperator","SteelFitter","SiteSurveyor","BoltFitter"][index]
		worker.position = _positions[index]
		worker.rotation.y = _yaws[index]
		worker.collision_layer = 2
		worker.collision_mask = 0
		worker.set_meta("gameplay_role","ambient_worker")
		worker.set_meta("north_gateway_worker",index)
		var body_shape := CollisionShape3D.new()
		body_shape.shape = _capsule
		body_shape.position.y = .86
		worker.add_child(body_shape)
		add_child(worker)
		worker.set_process(false)
		worker.set_physics_process(false)
		var model := MODEL.new()
		model.job = index
		worker.add_child(model)
		_models.append(model)
		_workers.append(worker)
		if index in [1,3]:
			GEAR.add(worker,"brace" if index==3 else "bench")
			# The full tabletop footprint blocks feet, including between thin legs.
			_fixture(worker,Vector3(0,.55 if index==3 else .42,.6),Vector3(.66,1.10 if index==3 else .84,.42))
		elif index == 0:
			_fixture(worker,Vector3(0,.55,.40),Vector3(.37,1.1,.23))
	set_process(_active)

func _fixture(parent: Node3D, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "WorkEquipmentSolid"
	body.position = center
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func set_active(value: bool) -> void:
	if _active == value: return
	_active = value
	_elapsed = 0.0
	set_process(value and is_node_ready() and not _models.is_empty())
	for model in _models:
		if not is_instance_valid(model): continue
		model.set_process(false)
		model.set_physics_process(false)

func _process(delta: float) -> void:
	if not _active or not is_visible_in_tree() or not is_finite(delta) or delta <= 0.0: return
	_clock += delta
	_elapsed += delta
	if _elapsed < POSE_INTERVAL: return
	var step := minf(_elapsed,.1)
	_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	for model in _models:
		if not is_instance_valid(model): continue
		if camera != null and not camera.is_position_in_frustum(model.global_position+Vector3.UP): continue
		model.sample_work(_clock,step)

func debug_snapshot() -> Dictionary:
	return {"workers":_workers.size(),"active":_active,"independent_model_processes":_models.filter(func(model): return is_instance_valid(model) and (model.is_processing() or model.is_physics_processing())).size(),
		"positions":_positions.duplicate(),"yaws":_yaws.duplicate(),"clock":_clock}

func _clear() -> void:
	for worker in _workers:
		if not is_instance_valid(worker): continue
		remove_child(worker)
		worker.queue_free()
	_workers.clear()
	_models.clear()
	_elapsed = 0.0
	_clock = 0.0
