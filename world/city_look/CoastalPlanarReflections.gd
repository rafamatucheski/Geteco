extends Node
## Two shared reflection targets, allocated once. Same World3D, dedicated
## capture layers: receivers never sample a viewport while being drawn into it.
## Registration follows scene lifetime; no scene traversal in the frame loop.
const BATCHES := preload("res://world/city_look/CoastalFacadeBatches.gd")
const ROADS := preload("res://world/urban_detail/HarborRoadGeometry3D.gd")
const FACADE_GROUP := &"coastal_reflective_facade"
const EXCLUDED := [&"CityLightPools", &"CitySidewalkLampPools", &"RainPuddles", &"RainPuddle", &"Water", &"AlpineWater"]
var controller
var ground_view: SubViewport
var facade_view: SubViewport
var ground_camera: Camera3D
var facade_camera: Camera3D
var _environment: Environment
var _bits := Vector2i.ZERO
var _registered: Dictionary = {}
var _dynamic: Dictionary = {}
# Malhas dinâmicas agrupadas pelo corpo (veículo/ator) dono. Antes a captura
# da fachada reclassificava cada malha de carro e pedestre em todo quadro com
# a câmera andando: reflection.dynamic custou 0,28–0,36 ms de média e até 2 ms
# por quadro no circuito oeste (evidence/profile-west-cpu-20261013). Um teste
# por corpo resolve quem está inteiro de um lado do plano; só quem cruza o
# plano volta ao teste por malha, e o layer só é reescrito quando o lado muda.
const DYNAMIC_BODY_MARGIN := 1.5
var _bodies: Dictionary = {}
var _dynamic_body: Dictionary = {}
var _batches: Dictionary = {}
var _view_cameras: Dictionary = {}
var _pending: Array[Node] = []
var _facade: MeshInstance3D
var _plane_normal := Vector3.BACK
var _plane_point := Vector3.ZERO
var _selection_clock := 0.0
var _capture_clock := 0.0
var _last_camera := Transform3D()
var _active := false
var _ground_active := false
var _facade_visible := false
var last_process_usec := 0
var last_batch_usec := 0
var last_dynamic_usec := 0
var last_registration_usec := 0
var last_batch_rebuilds := 0
var last_batches_checked := 0
var last_dynamic_checked := 0
var last_hidden_dynamic_count := 0
var last_rebuilt_batch_names: Array[String] = []
var _benchmark := false

func _ready() -> void:
	_benchmark = "--benchmark" in OS.get_cmdline_user_args()
	name = "CoastalPlanarReflections"
	process_priority = 110
	# Reserve two currently unused public visual layers; do not commandeer
	# masks owned by silhouettes, interiors, cutaways or another session system.
	# Bits 18/19 are reserved even before their scenes stream in (secret
	# passages, residence mirror and canopy cutaway). Coastal owns 16/17.
	var used := (1 << 18) | (1 << 19)
	var queue: Array[Node] = [controller.world]
	while not queue.is_empty():
		var node: Node = queue.pop_back()
		if node is VisualInstance3D: used |= node.layers
		if node is MeshInstance3D or node is MultiMeshInstance3D: _pending.append(node)
		queue.append_array(node.get_children())
	for index in [17, 16]:
		if used & (1 << index): continue
		if _bits.x == 0: _bits.x = 1 << index
		else:
			_bits.y = 1 << index
			break
	if _bits.y == 0:
		set_process(false)
		return
	ground_view = _make_view("GroundReflection", 640)
	facade_view = _make_view("FacadeReflection", 512)
	ground_camera = ground_view.get_child(0)
	facade_camera = facade_view.get_child(0)
	ground_camera.cull_mask = _bits.x
	facade_camera.cull_mask = _bits.y
	get_tree().node_added.connect(_queue_node)
	get_tree().node_removed.connect(_remove_node)

func _make_view(label: String, width: int) -> SubViewport:
	var view := SubViewport.new()
	view.name = label
	view.size = Vector2i(width, width * 9 / 16)
	view.world_3d = controller.world.get_world_3d()
	view.transparent_bg = true
	# Keep sampled radiance linear and HDR; the main viewport tones it once.
	view.use_hdr_2d = true
	view.gui_disable_input = true
	view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	view.positional_shadow_atlas_size = 0
	view.mesh_lod_threshold = 2.0
	add_child(view)
	var camera := Camera3D.new()
	# Copy the displayed source camera in _process; do not interpolate it twice.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	view.add_child(camera)
	camera.current = true
	return view

func _queue_node(node: Node) -> void:
	if node is MeshInstance3D or node is MultiMeshInstance3D: _pending.append(node)

func _remove_node(node: Node) -> void:
	var id := node.get_instance_id()
	if _batches.has(id):
		# Retirement can remove the capture mesh before its source node.
		# Validate the dictionary value before assigning it to a typed Node.
		if is_instance_valid(_batches[id].visual): _batches[id].visual.queue_free()
		_batches.erase(id)
	if _registered.has(id):
		# Nodes can be pooled and reattached: relinquish only our own bits.
		if node is VisualInstance3D: node.layers &= ~(_bits.x | _bits.y)
		_registered.erase(id)
		_dynamic.erase(id)
		if _dynamic_body.has(id):
			var body_id: int = _dynamic_body[id]
			_dynamic_body.erase(id)
			if _bodies.has(body_id):
				_bodies[body_id].meshes.erase(id)
				if _bodies[body_id].meshes.is_empty(): _bodies.erase(body_id)

func _register(node: Node) -> void:
	if node.has_meta("coastal_capture_only"): return
	if not (node is MeshInstance3D or node is MultiMeshInstance3D): return
	if not node.is_inside_tree() or not controller.world.is_ancestor_of(node): return
	if _registered.has(node.get_instance_id()): return
	var parent := node
	var dynamic := false
	var body: Node3D
	while parent != controller.world and parent != null:
		if parent.name in EXCLUDED or parent is GPUParticles3D or parent is CPUParticles3D: return
		if parent is CharacterBody3D or parent is RigidBody3D:
			dynamic = true
			if body == null: body = parent
		parent = parent.get_parent()
	if node.is_in_group(FACADE_GROUP): return
	var ground_receiver := false
	if node is MeshInstance3D:
		if node.mesh == null: return
		for index in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(index)
			if material is ShaderMaterial and material.shader != null:
				var path: String = material.shader.resource_path
				if "coastal_wet_asphalt" in path or "rural_road_end" in path: ground_receiver = true
				elif "coastal_" in path or "RainPuddle" in path or "water" in path.to_lower() or "lamp_pool" in path: return
	var bounds: AABB = node.global_transform * node.get_aabb()
	# Exclude horizontal terrain/floors, including sidewalks. They would hide
	# above-ground geometry from the camera mirrored below the wet street.
	_registered[node.get_instance_id()] = weakref(node)
	if dynamic:
		_dynamic[node.get_instance_id()] = weakref(node)
		_add_dynamic_to_body(node, body)
	if not ground_receiver and bounds.size.y >= .18 and bounds.end.y >= .25: node.layers |= _bits.x
	_update_facade_layer(node, bounds)

func _add_dynamic_to_body(node: GeometryInstance3D, body: Node3D) -> void:
	var body_id := body.get_instance_id()
	if not _bodies.has(body_id):
		_bodies[body_id] = {"body": weakref(body), "meshes": {}, "local": AABB(), "dirty": true, "side": 0}
	var entry: Dictionary = _bodies[body_id]
	entry.meshes[node.get_instance_id()] = weakref(node)
	# Peça nova (arma, roupa, dano) amplia a caixa e precisa receber o lado atual.
	entry.dirty = true
	entry.side = 0
	_dynamic_body[node.get_instance_id()] = body_id

## Caixa de todas as malhas no espaço do corpo, com folga para portas, rodas e
## peças presas a ossos que se movem em relação ao corpo.
static func _body_local_bounds(body: Node3D, meshes: Dictionary) -> AABB:
	var inverse := body.global_transform.affine_inverse()
	var bounds := AABB()
	var has_bounds := false
	for ref in meshes.values():
		var mesh = ref.get_ref()
		if not is_instance_valid(mesh): continue
		var part: AABB = (inverse * mesh.global_transform) * mesh.get_aabb()
		bounds = bounds.merge(part) if has_bounds else part
		has_bounds = true
	return bounds.grow(DYNAMIC_BODY_MARGIN) if has_bounds else AABB()

func _set_facade_bit(node: GeometryInstance3D, in_front: bool) -> void:
	# Mesma regra de _update_facade_layer para malha inteira de um lado do plano:
	# fonte com lote de captura próprio nunca entra com o layer de fachada.
	var mask := node.layers & ~_bits.y
	if in_front and not _batches.has(node.get_instance_id()): mask |= _bits.y
	if node.layers != mask: node.layers = mask

func _classify_dynamic() -> void:
	for body_id in _bodies.keys():
		var entry: Dictionary = _bodies[body_id]
		var body = entry.body.get_ref()
		if not is_instance_valid(body):
			_bodies.erase(body_id)
			continue
		# Corpo escondido não contribui para a captura (como a malha escondida antes).
		if not body.is_visible_in_tree():
			if _benchmark: last_hidden_dynamic_count += entry.meshes.size()
			continue
		if entry.dirty:
			entry.local = _body_local_bounds(body, entry.meshes)
			entry.dirty = false
		var bounds: AABB = body.global_transform * entry.local
		var distance := _plane_normal.dot(bounds.get_center() - _plane_point)
		var radius := _plane_normal.abs().dot(bounds.size * .5)
		var side := 1 if distance - radius >= -.08 else (-1 if distance + radius <= .08 else 0)
		if side != 0:
			if side == entry.side: continue
			entry.side = side
			for ref in entry.meshes.values():
				var visual = ref.get_ref()
				if not is_instance_valid(visual): continue
				if _benchmark: last_dynamic_checked += 1
				_set_facade_bit(visual, side > 0)
			continue
		# Cruza o plano: teste exato por malha, como antes.
		entry.side = 0
		for ref in entry.meshes.values():
			var visual = ref.get_ref()
			if not is_instance_valid(visual): continue
			if _benchmark: last_dynamic_checked += 1
			# Hidden accessories/LOD meshes cannot contribute to this capture.
			# A newly visible mesh is classified before UPDATE_ONCE below.
			if not visual.is_visible_in_tree():
				if _benchmark: last_hidden_dynamic_count += 1
				continue
			_update_facade_layer(visual, visual.global_transform * visual.get_aabb())

func _update_facade_layer(node: GeometryInstance3D, bounds: AABB) -> void:
	var mask := node.layers & ~_bits.y
	if is_instance_valid(_facade):
		var distance := _plane_normal.dot(bounds.get_center() - _plane_point)
		var radius := _plane_normal.abs().dot(bounds.size * .5)
		# Existing proxies own this source's facade eligibility, including
		# changes caused by breakable instances inside a formerly static batch.
		if not _batches.has(node.get_instance_id()):
			if distance - radius >= -.08: mask |= _bits.y
			elif distance + radius > .08 and node is MultiMeshInstance3D:
				var batch := BATCHES.build(node, _plane_normal, _plane_point, _bits.y)
				if batch != null:
					batch.set_meta("coastal_capture_only", true)
					node.add_child(batch)
					_batches[node.get_instance_id()] = {"visual":batch,"source":weakref(node)}
	if node.layers != mask: node.layers = mask

static func bounds_in_frustum(camera: Camera3D, bounds: AABB, margin: float = 1.0) -> bool:
	var center := bounds.get_center()
	var half_size := bounds.size * .5 + Vector3.ONE * margin
	for plane in camera.get_frustum():
		if plane.distance_to(center) > plane.normal.abs().dot(half_size): return false
	return true

func _clear_batches() -> void:
	for entry in _batches.values():
		if is_instance_valid(entry.visual):
			# Hide immediately; queue_free alone survives until end of frame.
			entry.visual.visible = false
			entry.visual.layers = 0
			entry.visual.queue_free()
	_batches.clear()

func _process(delta: float) -> void:
	if not _benchmark:
		_process_reflections(delta)
		return
	last_batch_usec = 0
	last_dynamic_usec = 0
	last_registration_usec = 0
	last_batch_rebuilds = 0
	last_batches_checked = 0
	last_dynamic_checked = 0
	last_hidden_dynamic_count = 0
	last_rebuilt_batch_names.clear()
	var started := Time.get_ticks_usec()
	_process_reflections(delta)
	last_process_usec = Time.get_ticks_usec() - started

func _process_reflections(delta: float) -> void:
	var registration_started := Time.get_ticks_usec() if _benchmark else 0
	# Streaming construction is incremental too; bound registration work.
	for index in mini(_pending.size(), 128):
		var node = _pending.pop_back()
		if is_instance_valid(node): _register(node)
	if _benchmark: last_registration_usec = Time.get_ticks_usec() - registration_started
	if controller == null or controller.session == null: return
	var weather = controller.session.weather
	var camera := get_viewport().get_camera_3d()
	var available: bool = camera != null and weather != null and controller.state.region_id == "harbor" and (String(controller.state.place_id).is_empty() or weather._embedded_building())
	if available:
		var weights: Dictionary = weather.atmosphere.weights_at(weather.atmosphere.focus_position(controller))
		available = float(weights.mountain) < .5 and float(weights.get("desert", 0.0)) < .5
	if not available:
		if _active: _disable()
		return
	_active = true
	# Dedicated facade batches exist only in the capture layer; the player's
	# camera (including binocular view) must not draw them a second time.
	if not _view_cameras.has(camera.get_instance_id()):
		_view_cameras[camera.get_instance_id()] = {"camera":weakref(camera),"bits":camera.cull_mask & (_bits.x | _bits.y)}
		camera.cull_mask &= ~(_bits.x | _bits.y)
	_selection_clock += delta
	if _selection_clock >= .25 or _environment == null:
		_selection_clock = 0.0
		_sync_environment()
		_select_facade(camera)
	var was_visible := _facade_visible
	_facade_visible = is_instance_valid(_facade) and _facade.is_visible_in_tree() and bounds_in_frustum(camera, _facade.global_transform * _facade.get_aabb())
	var facade_entered := _facade_visible and not was_visible
	if was_visible and not _facade_visible:
		facade_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if is_instance_valid(_facade): _facade.material_override.set_shader_parameter("reflection_enabled", false)
	var wet: bool = weather.get_coastal_wetness() > .015
	if not wet and _ground_active:
		_bind_ground(false)
		ground_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_ground_active = wet
	_capture_clock += delta
	# During camera motion capture every displayed frame. A stationary view
	# refreshes at 20Hz for moving traffic; textures remain world projected.
	var moving := not camera.global_transform.is_equal_approx(_last_camera)
	if not moving and not facade_entered and _capture_clock < .05: return
	_capture_clock = 0.0
	_last_camera = camera.global_transform
	# As capturas são viewports sem MSAA (o principal usa o MSAA do jogador): cada
	# material precisa de pipeline próprio nesse formato, compilado no primeiro
	# desenho. Sem isto a conta caía na primeira chuva ou na primeira vez que a
	# fachada da delegacia entra na tela. Sob a cortina (ready_for_play falso)
	# a captura do chão roda seca, sem ligar a textura a ninguém, só para compilar.
	var priming: bool = not wet and controller.session.get("ready_for_play") == false
	if wet or priming:
		mirror_camera(camera, ground_camera, Vector3.UP, Vector3(0, .035, 0))
		ground_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		if wet: _bind_ground(true)
	if _facade_visible:
		var batch_started := Time.get_ticks_usec() if _benchmark else 0
		for entry in _batches.values():
			var source = entry.source.get_ref()
			if is_instance_valid(source) and is_instance_valid(entry.visual):
				var rebuilt: bool = BATCHES.sync(source, entry.visual, _plane_normal, _plane_point)
				if _benchmark:
					last_batches_checked += 1
					if rebuilt:
						last_batch_rebuilds += 1
						last_rebuilt_batch_names.append(String(source.get_path()))
		if _benchmark: last_batch_usec = Time.get_ticks_usec() - batch_started
		var dynamic_started := Time.get_ticks_usec() if _benchmark else 0
		# Vehicles/actors can cross the reflecting half-space without a camera
		# change. Only this small dynamic set needs refreshed eligibility.
		_classify_dynamic()
		if _benchmark: last_dynamic_usec = Time.get_ticks_usec() - dynamic_started
		mirror_camera(camera, facade_camera, _plane_normal, _plane_point)
		facade_view.render_target_update_mode = SubViewport.UPDATE_ONCE
		var material := _facade.material_override as ShaderMaterial
		material.set_shader_parameter("reflection_texture", facade_view.get_texture())
		material.set_shader_parameter("reflection_projection", projection_for(facade_camera))
		material.set_shader_parameter("reflection_texel_size", Vector2.ONE / Vector2(facade_view.size))
		material.set_shader_parameter("reflection_enabled", true)

static func projection_for(camera: Camera3D) -> Projection:
	return camera.get_camera_projection() * Projection(camera.global_transform.affine_inverse())

static func mirror_camera(source: Camera3D, target: Camera3D, normal: Vector3, point: Vector3) -> void:
	var view := target.get_viewport() as SubViewport
	var visible_size := source.get_viewport().get_visible_rect().size
	var height := maxi(1, roundi(float(view.size.x) * visible_size.y / maxf(1, visible_size.x)))
	if height != view.size.y: view.size.y = height
	target.projection = source.projection
	target.keep_aspect = source.keep_aspect
	target.size = source.size
	target.fov = source.fov
	target.near = source.near
	target.far = minf(source.far, 220.0)
	target.frustum_offset = source.frustum_offset
	var position := source.global_position
	position -= 2.0 * normal * normal.dot(position - point)
	var forward := -source.global_basis.z
	forward -= 2.0 * normal * normal.dot(forward)
	var up := source.global_basis.y
	up -= 2.0 * normal * normal.dot(up)
	target.global_transform = Transform3D(Basis.looking_at(forward, up), position)

func _sync_environment() -> void:
	var source: Environment = controller.environment.environment
	if _environment == null:
		_environment = source.duplicate()
		_environment.background_mode = Environment.BG_COLOR
		_environment.background_color = Color.TRANSPARENT
		_environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		_environment.tonemap_exposure = 1.0
		_environment.glow_enabled = false
		_environment.fog_enabled = false
		_environment.volumetric_fog_enabled = false
		_environment.adjustment_enabled = false
		ground_camera.environment = _environment
		facade_camera.environment = _environment
	_environment.sky = source.sky
	_environment.ambient_light_source = source.ambient_light_source
	_environment.ambient_light_color = source.ambient_light_color
	_environment.ambient_light_energy = source.ambient_light_energy
	_environment.ambient_light_sky_contribution = source.ambient_light_sky_contribution
	_environment.reflected_light_source = source.reflected_light_source

func _select_facade(camera: Camera3D) -> void:
	var selected: MeshInstance3D
	var nearest := 110.0 * 110.0
	for candidate in get_tree().get_nodes_in_group(FACADE_GROUP):
		if not candidate is MeshInstance3D or not candidate.is_visible_in_tree(): continue
		var normal: Vector3 = (candidate.global_basis * candidate.get_meta("coastal_reflection_plane_normal", Vector3.BACK)).normalized()
		var point: Vector3 = candidate.global_transform * candidate.get_meta("coastal_reflection_plane_point", Vector3.ZERO)
		if normal.dot(camera.global_position - point) < .2: continue
		var distance := camera.global_position.distance_squared_to(point)
		if distance < nearest:
			nearest = distance
			selected = candidate
	if selected == _facade: return
	_clear_batches()
	_facade_visible = false
	if is_instance_valid(_facade): _facade.material_override.set_shader_parameter("reflection_enabled", false)
	_facade = selected
	if is_instance_valid(_facade):
		_plane_normal = (_facade.global_basis * _facade.get_meta("coastal_reflection_plane_normal")).normalized()
		_plane_point = _facade.global_transform * _facade.get_meta("coastal_reflection_plane_point")
	else: facade_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	for ref in _registered.values():
		var node = ref.get_ref()
		if is_instance_valid(node): _update_facade_layer(node, node.global_transform * node.get_aabb())
	# Lado por corpo era relativo ao plano anterior.
	for entry in _bodies.values(): entry.side = 0

func _bind_ground(enabled: bool) -> void:
	var projection := projection_for(ground_camera) if enabled else Projection.IDENTITY
	var texture: Texture2D = ground_view.get_texture() if enabled else null
	var harbor = controller.regions.get("harbor")
	if is_instance_valid(harbor) and harbor.harbor_road_geometry != null:
		harbor.harbor_road_geometry.set_coastal_reflection(texture, projection, enabled)
	if not is_instance_valid(controller.world): return
	var puddles: Node = controller.world.get_node_or_null("RainPuddles")
	if puddles != null: puddles.set_coastal_reflection(texture, projection, enabled)

func _disable() -> void:
	_facade_visible = false
	_active = false
	_ground_active = false
	_bind_ground(false)
	ground_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	facade_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_facade): _facade.material_override.set_shader_parameter("reflection_enabled", false)

func _exit_tree() -> void:
	_clear_batches()
	if ground_camera != null: _disable()
	if is_instance_valid(_facade): _facade.material_override.set_shader_parameter("reflection_texture", null)
	for ref in _registered.values():
		var node = ref.get_ref()
		if is_instance_valid(node): node.layers &= ~(_bits.x | _bits.y)
	_registered.clear()
	_dynamic.clear()
	_bodies.clear()
	_dynamic_body.clear()
	for entry in _view_cameras.values():
		var camera = entry.camera.get_ref()
		if is_instance_valid(camera): camera.cull_mask |= int(entry.bits)
	_view_cameras.clear()
