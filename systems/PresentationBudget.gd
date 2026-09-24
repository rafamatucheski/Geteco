extends Node
## O orçamento limita trabalho entre entidades; um rig individual é indivisível.
## budget_usec só é conferido antes de escolher e depois de construir: uma
## construção longa NÃO é interrompida. get_stats() expõe esse custo real,
## as violações e a espera por relevância para que a fila seja verificável.
# Untyped on purpose: a pooled Node2D can be queued_free between scans. A typed
# array attempts to validate the dead object during `has()`/iteration and emits
# engine errors before this manager gets a chance to purge it.
var pending: Array = []
var max_builds_per_frame := 1
var budget_usec := 2000

const LATENCY_SAMPLES := 256
# A janela de fallback deve ser curta o bastante para não ser percebida em
# tráfego entrando na câmera, sem transformar a fila em um loop caro por frame.
# A construção continua limitada a um rig por frame.
const PENDING_SCAN_INTERVAL := 1.0 / 30.0
var _pending_scan_elapsed := 0.0
var _requested_msec: Dictionary = {}
# Espera relevante: começa quando o ator entra na margem de construção (visível ou
# prestes a entrar). A idade desde o pedido inclui o tempo em que ele estava longe
# da câmera e sozinha não mede atraso de apresentação.
var _relevant_msec: Dictionary = {}
var _stats := {"requests": 0, "builds": 0, "cancelled": 0, "over_budget_builds": 0, "max_build_usec": 0}
var _by_kind: Dictionary = {}
var _latency: Dictionary = {"visible": [], "near": []}
var _oldest_msec: Dictionary = {"visible": 0, "near": 0, "far": 0}

# Animated pedestrians keep separate cameras and textures, but share one
# World3D. Each rig is placed in an isolated cell so cameras never see another
# actor while the renderer avoids one environment/light/world per pedestrian.
const CHARACTER_SLOT_SPACING := 8.0
const CHARACTER_SLOT_COLUMNS := 32
var _character_world_host: SubViewport
var _character_slots: Dictionary = {}
var _free_character_slots: Array[int] = []
var _next_character_slot := 0
var _character_material_cache: Dictionary = {}

# Ambient residents use a single camera pass per batch. Each batch has capacity
# for eight actors, but only residents inside the camera margin occupy render
# tiles. Hidden/sleeping residents keep their 3D rig and membership without
# reserving a 96x96 tile until they are relevant again.
const AMBIENT_ATLAS_TILE_SIZE := 104
## Keep transparent pixels around every portrait. Without a gutter, an arm or
## accessory crossing the exact camera-cell boundary is sampled from the next
## resident's tile and the Sprite2D appears sliced while the atlas is moving.
const AMBIENT_ATLAS_TILE_GUTTER := 13
const AMBIENT_ATLAS_CELL_SIZE := AMBIENT_ATLAS_TILE_SIZE + AMBIENT_ATLAS_TILE_GUTTER * 2
const AMBIENT_ATLAS_SLOTS := 8
const AMBIENT_ATLAS_WORLD_SPACING := 1.92 * float(AMBIENT_ATLAS_CELL_SIZE) / float(AMBIENT_ATLAS_TILE_SIZE)
var _ambient_atlases: Array[Dictionary] = []
var _ambient_atlas_slots: Dictionary = {}
var _ambient_authored_prewarm_running := false
var _ambient_authored_prewarm_complete := false

func prewarm_ambient_authored() -> void:
	if _ambient_authored_prewarm_complete:
		return
	if _ambient_authored_prewarm_running:
		while _ambient_authored_prewarm_running:
			await get_tree().process_frame
		return
	_ambient_authored_prewarm_running = true
	if _ambient_atlases.is_empty():
		_ambient_atlases.append(_create_ambient_atlas())
	var atlas: Dictionary = _ambient_atlases[0]
	var viewport: SubViewport = atlas["viewport"]
	var geometry = preload("res://characters/pedestrians/CitizenGeometry.gd").new()
	geometry.loft([
		Vector4(-.18, .14, .11, 0.0),
		Vector4(.18, .16, .13, 0.0),
	], Color("b7896f"), 16)
	# Exercise every procedural primitive used by the authored citizen sculpt so
	# the renderer cannot discover an oval/lock/box vertex layout mid-game.
	geometry.oval(Vector3(.08, .06, .04), Vector3(.12, 0.0, 0.0), Color("4a352f"))
	geometry.box(Vector3(.05, .12, .03), Vector3(-.12, 0.0, 0.0), Color("596878"))
	geometry.lock(Vector3(0.0, .16, .04), Vector3(.05, .08, .08), Vector3(.02, -.08, .06), .025, Color("3a302d"))
	geometry.scalp(Color("3a302d"))
	var warm_mesh: MeshInstance3D = geometry.finish_detached("AmbientAuthoredPrewarm", 1.0)
	warm_mesh.position = Vector3(0.0, .75, 0.0)
	viewport.add_child(warm_mesh)
	var warm_body := MeshInstance3D.new()
	var warm_capsule := CapsuleMesh.new()
	warm_capsule.radius = .17
	warm_capsule.height = .48
	var warm_body_material := StandardMaterial3D.new()
	warm_body_material.albedo_color = Color("596878")
	warm_body_material.roughness = .6
	warm_body.mesh = warm_capsule
	warm_body.material_override = warm_body_material
	warm_body.position = Vector3(0.0, .75, 0.0)
	viewport.add_child(warm_body)
	viewport.size = Vector2i(AMBIENT_ATLAS_TILE_SIZE, AMBIENT_ATLAS_TILE_SIZE)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# Two process frames cover both dummy/headless validation and the real Vulkan
	# render submission without depending on a frame_post_draw signal that some
	# headless drivers never emit.
	await get_tree().process_frame
	await get_tree().process_frame
	# Retain the warmed instances hidden in the atlas. Releasing the last shaded
	# primitive lets the renderer tear down the pipeline and merely postpones the
	# same synchronization until the first live resident.
	warm_mesh.visible = false
	warm_body.visible = false
	atlas["authored_warmup_nodes"] = [warm_mesh, warm_body]
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.size = Vector2i.ONE
	_ambient_authored_prewarm_complete = true
	_ambient_authored_prewarm_running = false

func acquire_ambient_atlas(actor: Node) -> Dictionary:
	var actor_id := actor.get_instance_id()
	if _ambient_atlas_slots.has(actor_id):
		return _ambient_atlas_slots[actor_id]
	var atlas: Dictionary = {}
	for candidate in _ambient_atlases:
		var free_slots: Array = candidate.get("free_slots", [])
		if not free_slots.is_empty():
			atlas = candidate
			break
	if atlas.is_empty():
		atlas = _create_ambient_atlas()
		_ambient_atlases.append(atlas)
	var slots: Array = atlas["free_slots"]
	var slot: int = int(slots.pop_back())
	atlas["free_slots"] = slots
	var origin := Vector3(float(slot) * AMBIENT_ATLAS_WORLD_SPACING, 0.0, 0.0)
	var allocation := {
		"viewport": atlas["viewport"],
		"world": atlas["viewport"].find_world_3d(),
		"origin": origin,
		"member_slot": slot,
		"render_slot": -1,
		"region": Rect2(slot * AMBIENT_ATLAS_CELL_SIZE + AMBIENT_ATLAS_TILE_GUTTER, 0, AMBIENT_ATLAS_TILE_SIZE, AMBIENT_ATLAS_TILE_SIZE),
		"atlas": atlas,
		"actor": actor,
		"population_active": true,
		"render_visible": false,
		"render_interval": 1.0 / 12.0,
	}
	_ambient_atlas_slots[actor_id] = allocation
	atlas["actors"][actor_id] = actor
	actor.tree_exiting.connect(_release_ambient_atlas_slot.bind(actor_id), CONNECT_ONE_SHOT)
	_repack_ambient_atlas(atlas)
	return allocation

func _create_ambient_atlas() -> Dictionary:
	var viewport := SubViewport.new()
	viewport.name = "AmbientCharacterAtlas_%d" % _ambient_atlases.size()
	# The target expands to exactly the number of camera-relevant residents.
	viewport.size = Vector2i.ONE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.92
	camera.position = Vector3(0.0, 3.15, 4.8)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.70, 0.0), Vector3.UP)
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.35
	light.shadow_enabled = false
	viewport.add_child(light)
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0, 0, 0, 0)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color(0.70, 0.72, 0.82)
	environment.environment = resource
	viewport.add_child(environment)
	var free_slots: Array[int] = []
	for slot in range(AMBIENT_ATLAS_SLOTS - 1, -1, -1): free_slots.append(slot)
	return {
		"viewport": viewport,
		"camera": camera,
		"free_slots": free_slots,
		"actors": {},
		"render_actor_count": 0,
		"render_interval": 1.0 / 12.0,
		"elapsed": 0.0,
		"render_requests": 0,
	}

func _release_ambient_atlas_slot(actor_id: int) -> void:
	if not _ambient_atlas_slots.has(actor_id): return
	var allocation: Dictionary = _ambient_atlas_slots[actor_id]
	var atlas: Dictionary = allocation["atlas"]
	var actor: Node = allocation.get("actor", null)
	if is_instance_valid(actor):
		var model: Node = actor.get("model_root")
		if is_instance_valid(model) and model.get_parent() == atlas["viewport"]:
			model.queue_free()
	atlas["actors"].erase(actor_id)
	var slots: Array = atlas["free_slots"]
	slots.append(int(allocation["member_slot"]))
	atlas["free_slots"] = slots
	_ambient_atlas_slots.erase(actor_id)
	_repack_ambient_atlas(atlas)

func detach_ambient_atlas_actor(actor: Node) -> bool:
	# A fallen rig needs its own camera framing. Remove only atlas membership;
	# the caller immediately reparents the live model into a personal viewport.
	var actor_id := actor.get_instance_id()
	if not _ambient_atlas_slots.has(actor_id): return false
	var allocation: Dictionary = _ambient_atlas_slots[actor_id]
	var atlas: Dictionary = allocation["atlas"]
	atlas["actors"].erase(actor_id)
	var slots: Array = atlas["free_slots"]
	slots.append(int(allocation["member_slot"]))
	atlas["free_slots"] = slots
	_ambient_atlas_slots.erase(actor_id)
	_repack_ambient_atlas(atlas)
	return true

func set_ambient_atlas_actor_active(actor: Node, active: bool) -> void:
	var allocation: Dictionary = _ambient_atlas_slots.get(actor.get_instance_id(), {})
	if allocation.is_empty(): return
	if bool(allocation.get("population_active", true)) == active:
		return
	allocation["population_active"] = active
	_ambient_atlas_slots[actor.get_instance_id()] = allocation
	_repack_ambient_atlas(allocation["atlas"])

func set_ambient_atlas_actor_visibility(actor: Node, visible: bool, render_hz: float) -> void:
	var actor_id := actor.get_instance_id()
	var allocation: Dictionary = _ambient_atlas_slots.get(actor_id, {})
	if allocation.is_empty(): return
	var interval := 1.0 / clampf(render_hz, 1.0, 60.0)
	if bool(allocation.get("render_visible", false)) == visible and is_equal_approx(float(allocation.get("render_interval", interval)), interval):
		return
	allocation["render_visible"] = visible
	allocation["render_interval"] = interval
	_ambient_atlas_slots[actor_id] = allocation
	_repack_ambient_atlas(allocation["atlas"])

func _repack_ambient_atlas(atlas: Dictionary) -> void:
	var render_allocations: Array[Dictionary] = []
	for actor_id in atlas["actors"].keys():
		var actor: Node = atlas["actors"].get(actor_id, null)
		var allocation: Dictionary = _ambient_atlas_slots.get(actor_id, {})
		if not is_instance_valid(actor) or allocation.is_empty():
			continue
		var render_actor := bool(allocation.get("population_active", true)) and bool(allocation.get("render_visible", false))
		var model: Node = actor.get("model_root")
		if is_instance_valid(model): model.visible = render_actor
		if render_actor: render_allocations.append(allocation)
	render_allocations.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("member_slot", 0)) < int(b.get("member_slot", 0))
	)
	var viewport: SubViewport = atlas["viewport"]
	var camera: Camera3D = atlas["camera"]
	var render_count := render_allocations.size()
	var render_interval := 1.0 / 12.0
	for render_slot in render_count:
		var allocation: Dictionary = render_allocations[render_slot]
		var origin := Vector3(float(render_slot) * AMBIENT_ATLAS_WORLD_SPACING, 0.0, 0.0)
		var region := Rect2(render_slot * AMBIENT_ATLAS_CELL_SIZE + AMBIENT_ATLAS_TILE_GUTTER, 0, AMBIENT_ATLAS_TILE_SIZE, AMBIENT_ATLAS_TILE_SIZE)
		allocation["render_slot"] = render_slot
		allocation["origin"] = origin
		allocation["region"] = region
		var actor: Node = allocation["actor"]
		_ambient_atlas_slots[actor.get_instance_id()] = allocation
		render_interval = minf(render_interval, float(allocation.get("render_interval", render_interval)))
		if actor.has_method("_apply_ambient_atlas_slot"):
			actor.call("_apply_ambient_atlas_slot", render_slot, origin, region)
	atlas["render_actor_count"] = render_count
	atlas["render_interval"] = render_interval
	atlas["elapsed"] = 0.0
	if render_count == 0:
		viewport.size = Vector2i.ONE
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	viewport.size = Vector2i(AMBIENT_ATLAS_CELL_SIZE * render_count, AMBIENT_ATLAS_TILE_SIZE)
	var center_x := float(render_count - 1) * AMBIENT_ATLAS_WORLD_SPACING * 0.5
	camera.look_at_from_position(Vector3(center_x, 3.15, 4.8), Vector3(center_x, 0.70, 0.0), Vector3.UP)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	atlas["render_requests"] = int(atlas.get("render_requests", 0)) + 1

func acquire_character_material(world: World3D, color: Color, roughness: float) -> StandardMaterial3D:
	var world_id := world.get_instance_id()
	if not _character_material_cache.has(world_id):
		_character_material_cache[world_id] = {}
	var cache: Dictionary = _character_material_cache[world_id]
	var key := "%s|%.3f" % [color.to_html(true), roughness]
	if cache.has(key):
		return cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	# Ambient low-LOD characters are rendered in isolated cameras that share one
	# World3D. Keep their small cached materials unshaded so a missing/late light
	# in that shared world cannot turn a valid rig into a black silhouette.
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.0
	cache[key] = material
	return material

func acquire_character_shadow(world: World3D) -> StandardMaterial3D:
	var world_id := world.get_instance_id()
	var key := "__shadow__"
	if not _character_material_cache.has(world_id):
		_character_material_cache[world_id] = {}
	var cache: Dictionary = _character_material_cache[world_id]
	if cache.has(key):
		return cache[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.02, 0.02, 0.04, 0.50)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cache[key] = material
	return material

func acquire_character_world(actor: Node) -> Dictionary:
	_ensure_character_world()
	var id := actor.get_instance_id()
	if not _character_slots.has(id):
		var slot: int = int(_free_character_slots.pop_back()) if not _free_character_slots.is_empty() else _next_character_slot
		if slot == _next_character_slot: _next_character_slot += 1
		_character_slots[id] = slot
		actor.tree_exiting.connect(_release_character_slot.bind(id), CONNECT_ONE_SHOT)
	var index: int = int(_character_slots[id])
	return {
		"world": _character_world_host.world_3d,
		"origin": Vector3(float(index % CHARACTER_SLOT_COLUMNS) * CHARACTER_SLOT_SPACING, 0.0, float(index / CHARACTER_SLOT_COLUMNS) * CHARACTER_SLOT_SPACING),
	}

func _release_character_slot(id: int) -> void:
	if not _character_slots.has(id): return
	_free_character_slots.append(int(_character_slots[id]))
	_character_slots.erase(id)

func _ensure_character_world() -> void:
	if is_instance_valid(_character_world_host): return
	_character_world_host = SubViewport.new()
	_character_world_host.name = "SharedCharacterWorld"
	_character_world_host.size = Vector2i.ONE
	_character_world_host.transparent_bg = true
	_character_world_host.own_world_3d = true
	# Keep the tiny host viewport updating so its World3D resources (light and
	# environment) stay initialized for the portrait viewports that reference it.
	# The host is 1x1, so this has negligible raster cost.
	_character_world_host.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_character_world_host)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-60.0, 35.0, 0.0)
	light.light_energy = 1.35
	# Each portrait already owns a cheap unshaded ground shadow. A shared shadow
	# map would cover every isolated character slot and can leave some rigs in a
	# stale/self-shadowed black state while also multiplying submission cost.
	light.shadow_enabled = false
	_character_world_host.add_child(light)
	var environment := WorldEnvironment.new()
	var resource := Environment.new()
	resource.background_mode = Environment.BG_COLOR
	resource.background_color = Color(0, 0, 0, 0)
	resource.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	resource.ambient_light_color = Color(0.70, 0.72, 0.82)
	environment.environment = resource
	_character_world_host.add_child(environment)
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func request(actor: Node2D) -> void:
	if not pending.has(actor):
		pending.append(actor)
		_requested_msec[actor.get_instance_id()] = Time.get_ticks_msec()
		_stats.requests += 1


func _process(delta: float) -> void:
	# Resident presentation is not useful while GameLoading owns the frame
	# budget. The loading path explicitly prepares only relevant actors; doing
	# both here and there duplicates expensive 3D rig construction and can
	# prolong the loading gate without improving the first playable frame.
	var loading := get_node_or_null("/root/GameLoading")
	if loading != null and loading.get("active") == true:
		return
	for atlas in _ambient_atlases:
		if int(atlas.get("render_actor_count", 0)) <= 0:
			continue
		var interval := float(atlas.get("render_interval", 1.0 / 12.0))
		atlas["elapsed"] = float(atlas.get("elapsed", 0.0)) + delta
		if float(atlas["elapsed"]) >= interval:
			atlas["elapsed"] = fmod(float(atlas["elapsed"]), interval)
			(atlas["viewport"] as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
			atlas["render_requests"] = int(atlas.get("render_requests", 0)) + 1
	# Cancelamentos não podem esperar pela janela de construção. Population
	# Activity e pooling podem liberar um ator entre dois scans; removê-lo aqui
	# mantém a fila curta e impede TypedArray de reter referências inválidas.
	for index in range(pending.size() - 1, -1, -1):
		var queued: Variant = pending[index]
		if not is_instance_valid(queued) or not queued.is_inside_tree() or queued.is_queued_for_deletion():
			pending.remove_at(index)
			_requested_msec.erase(queued.get_instance_id() if is_instance_valid(queued) else 0)
			_relevant_msec.erase(queued.get_instance_id() if is_instance_valid(queued) else 0)
			_stats.cancelled += 1
	_pending_scan_elapsed += delta
	if _pending_scan_elapsed < PENDING_SCAN_INTERVAL:
		return
	_pending_scan_elapsed = fmod(_pending_scan_elapsed, PENDING_SCAN_INTERVAL)
	var started := Time.get_ticks_usec()
	var now_msec := Time.get_ticks_msec()
	for iteration in max_builds_per_frame:
		if Time.get_ticks_usec() - started >= budget_usec:
			return
		var best: Node2D
		var best_distance := INF
		var best_class := "near"
		var oldest := {"visible": 0, "near": 0, "far": 0}
		for index in range(pending.size() - 1, -1, -1):
			var actor: Node2D = pending[index]
			if not is_instance_valid(actor) or not actor.is_inside_tree() or actor.is_queued_for_deletion():
				pending.remove_at(index)
				_stats.cancelled += 1
				continue
			# Sleeping actors cannot become relevant until PopulationActivity
			# wakes them. Do not retain an unserviceable request or scan it every
			# cadence tick; set_active(true) re-enqueues it when needed.
			if actor.get_meta("proximity_sleeping", false):
				pending.remove_at(index)
				_requested_msec.erase(actor.get_instance_id())
				_relevant_msec.erase(actor.get_instance_id())
				_stats.cancelled += 1
				continue
			var age: int = now_msec - int(_requested_msec.get(actor.get_instance_id(), now_msec))
			if not actor.is_visible_in_tree():
				oldest.far = maxi(oldest.far, age)
				continue
			var screen: Vector2 = actor.get_global_transform_with_canvas().origin
			var rect: Rect2 = actor.get_viewport_rect()
			if not rect.grow(220).has_point(screen):
				oldest.far = maxi(oldest.far, age)
				continue
			var kind := "visible" if rect.has_point(screen) else "near"
			var actor_id: int = actor.get_instance_id()
			if not _relevant_msec.has(actor_id): _relevant_msec[actor_id] = now_msec
			oldest[kind] = maxi(oldest[kind], now_msec - int(_relevant_msec[actor_id]))
			var distance: float = screen.distance_squared_to(rect.get_center())
			if distance < best_distance:
				best = actor
				best_distance = distance
				best_class = kind
		_oldest_msec = oldest
		_forget_released()
		if best == null:
			return
		pending.erase(best)
		var id := best.get_instance_id()
		var since_request: int = now_msec - int(_requested_msec.get(id, now_msec))
		var waited: int = now_msec - int(_relevant_msec.get(id, now_msec))
		_requested_msec.erase(id)
		_relevant_msec.erase(id)
		var kind_name := best.name + " (" + best.get_class() + ")"
		if best.get_script() != null and not String(best.get_script().resource_path).is_empty():
			kind_name = String(best.get_script().resource_path).get_file()
		# Veículos com modelo adiado: separar por classe de modelo, pois primeiro
		# exemplar e exemplares repetidos têm custos muito diferentes.
		var pending_spec = best.get("_pending_spec")
		if pending_spec is Dictionary and pending_spec.has("model_class"):
			kind_name += ":" + String(pending_spec.model_class).get_file()
		var build_started := Time.get_ticks_usec()
		best.ensure_presentation()
		var build_usec := Time.get_ticks_usec() - build_started
		if build_usec > 5000:
			print("PB_BUILD: %s took %.2f ms" % [kind_name, build_usec / 1000.0])
		_record_build(kind_name, build_usec, best_class, waited, since_request)
		if Time.get_ticks_usec() - started >= budget_usec:
			return

func _record_build(kind_name: String, usec: int, relevance: String, waited_msec: int, since_request_msec: int) -> void:
	_stats.max_age_since_request_msec = maxi(int(_stats.get("max_age_since_request_msec", 0)), since_request_msec)
	_stats.builds += 1
	_stats.max_build_usec = maxi(_stats.max_build_usec, usec)
	if usec > budget_usec: _stats.over_budget_builds += 1
	if not _by_kind.has(kind_name): _by_kind[kind_name] = {"builds": 0, "total_usec": 0, "max_usec": 0, "over_budget": 0}
	var entry: Dictionary = _by_kind[kind_name]
	entry.builds += 1
	entry.total_usec += usec
	entry.max_usec = maxi(entry.max_usec, usec)
	if usec > budget_usec: entry.over_budget += 1
	var samples: Array = _latency[relevance]
	samples.append(waited_msec)
	if samples.size() > LATENCY_SAMPLES: samples.pop_front()

func _forget_released() -> void:
	# Pedidos liberados por troca de cena deixam carimbos órfãos; limpar em lote.
	if _requested_msec.size() + _relevant_msec.size() <= 2 * pending.size() + 64: return
	var alive := {}
	for actor in pending:
		if is_instance_valid(actor): alive[actor.get_instance_id()] = true
	for id in _requested_msec.keys():
		if not alive.has(id): _requested_msec.erase(id)
	for id in _relevant_msec.keys():
		if not alive.has(id): _relevant_msec.erase(id)

func get_stats() -> Dictionary:
	var latency := {}
	for relevance in _latency:
		var ordered: Array = (_latency[relevance] as Array).duplicate()
		ordered.sort()
		latency[relevance] = {"samples": ordered.size(),
			"p50_msec": ordered[ordered.size() / 2] if not ordered.is_empty() else null,
			"p95_msec": ordered[mini(ordered.size() - 1, int(ordered.size() * 0.95))] if not ordered.is_empty() else null,
			"max_msec": ordered[-1] if not ordered.is_empty() else null}
	return {"budget_usec": budget_usec, "pending": pending.size(), "totals": _stats.duplicate(), "by_kind": _by_kind.duplicate(true),
		"wait_since_relevant_msec": latency, "oldest_pending_msec": _oldest_msec.duplicate(), "ambient_atlas": get_ambient_atlas_stats(),
		"oldest_note": "visible/near: desde que ficou relevante; far: desde o pedido"}

func get_ambient_atlas_stats() -> Dictionary:
	var active_viewports := 0
	var visible_actors := 0
	var allocated_pixels := 0
	var scheduled_pixels_per_second := 0.0
	var render_requests := 0
	for atlas in _ambient_atlases:
		var viewport: SubViewport = atlas["viewport"]
		var pixels := viewport.size.x * viewport.size.y
		var actor_count := int(atlas.get("render_actor_count", 0))
		allocated_pixels += pixels
		visible_actors += actor_count
		render_requests += int(atlas.get("render_requests", 0))
		if actor_count > 0:
			active_viewports += 1
			scheduled_pixels_per_second += float(pixels) / maxf(0.001, float(atlas.get("render_interval", 1.0 / 12.0)))
	var atlas_capacity_pixels := _ambient_atlases.size() * AMBIENT_ATLAS_SLOTS * AMBIENT_ATLAS_CELL_SIZE * AMBIENT_ATLAS_TILE_SIZE
	return {
		"actors": _ambient_atlas_slots.size(),
		"atlas_viewports": _ambient_atlases.size(),
		"active_viewports": active_viewports,
		"visible_actors": visible_actors,
		"allocated_pixels": allocated_pixels,
		"full_capacity_pixels": atlas_capacity_pixels,
		"saved_capacity_pixels": atlas_capacity_pixels - allocated_pixels,
		"individual_equivalent_viewports": _ambient_atlas_slots.size(),
		"individual_equivalent_pixels": _ambient_atlas_slots.size() * AMBIENT_ATLAS_TILE_SIZE * AMBIENT_ATLAS_TILE_SIZE,
		"scheduled_pixels_per_second": scheduled_pixels_per_second,
		"render_requests": render_requests,
	}
