extends RefCounted
## Uma câmera temporária, da tentativa de pesca e restaurada em toda saída.
var camera: Camera3D
var _previous: Camera3D
var _normal: Camera3D
var _normal_locked := false
var _focus := Vector3.ZERO
var _offset := Vector3.ZERO
var _initialized := false
var _phase := ""
var _phase_time := 0.0

func begin(world: Node3D) -> void:
	release()
	_previous = world.get_viewport().get_camera_3d()
	_normal = world.get("camera") as Camera3D
	_normal_locked = bool(_normal.get("locked"))
	_normal.set("locked", true)
	camera = Camera3D.new()
	camera.name = "FishingCloseCamera"
	# O peixe segurado precisa tapar o Dante por profundidade real. O contrato de câmera compartilhado
	# suprime a silhueta de raio-x externa e a restaura com a câmera antiga.
	camera.set_meta("uses_interior_depth", true)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.4
	camera.near = .1
	camera.far = _previous.far if is_instance_valid(_previous) else 180.0
	if is_instance_valid(_previous): camera.cull_mask = _previous.cull_mask
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	world.add_child(camera)
	_initialized = false

func present(actor: Node3D, water: Vector3, fish: Node3D, phase: String, landing: float, delta: float) -> void:
	if not is_instance_valid(camera): return
	if phase != _phase:
		_phase = phase
		_phase_time = 0.0
	else: _phase_time += delta
	var direction := water - actor.global_position
	direction.y = 0
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP)
	var finish := smoothstep(.1, 1.0, landing) if phase == "landing" else (1.0 if phase in ["caught", "storing"] else 0.0)
	if phase == "releasing": finish = 1.0 - smoothstep(.55, 2.1, _phase_time)
	var focus := actor.global_position.lerp(water, .42) + Vector3.UP * .65
	if phase in ["reeling", "hooking", "releasing"] and is_instance_valid(fish) and fish.visible:
		focus = actor.global_position.lerp(fish.global_position, .42) + Vector3.UP * .7
	focus = focus.lerp(actor.global_position + direction * .40 + Vector3.UP * 1.0, finish)
	var blend := 1.0 if not _initialized else 1.0 - exp(-delta * 4.0)
	_focus = _focus.lerp(focus, blend)
	var fishing_offset := -direction * 6.8 + right * 4.8 + Vector3.UP * 7.4
	# Gira pelo lado da água aberta enquanto o peixe passa pelo parapeito. Uma vista de trás
	# escondia as espécies pequenas atrás da cabeça do Dante quando chegavam às mãos dele.
	var showcase_offset := direction * 6.4 + right * 3.4 + Vector3.UP * 4.8
	var showcase := smoothstep(.36, 1.0, landing) if phase == "landing" else (1.0 if phase in ["caught", "storing"] else 0.0)
	if phase == "releasing": showcase = 1.0 - smoothstep(.55, 2.1, _phase_time)
	_offset = _offset.lerp(fishing_offset.lerp(showcase_offset, showcase), blend)
	camera.global_position = _focus + _offset
	camera.look_at(_focus, Vector3.UP)
	camera.size = lerpf(camera.size, lerpf(10.4, 4.7, finish), blend)
	if not _initialized: camera.make_current()
	_initialized = true

func release() -> void:
	# Uma transição pode já ter instalado a própria câmera. Nunca a toma de volta.
	if is_instance_valid(camera):
		if camera.is_current():
			if is_instance_valid(_previous) and not _previous.is_queued_for_deletion(): _previous.make_current()
			elif is_instance_valid(_normal) and not _normal.is_queued_for_deletion(): _normal.make_current()
		camera.queue_free()
	if is_instance_valid(_normal):
		_normal.set("locked", _normal_locked)
		_normal.set("initialized", false)
	camera = null
	_previous = null
	_normal = null
	_initialized = false
	_phase = ""
	_phase_time = 0.0
