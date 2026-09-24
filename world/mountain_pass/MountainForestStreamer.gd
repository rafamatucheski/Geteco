class_name MountainForestStreamer
extends Node2D

## Mantém apenas a faixa de floresta relevante ao deslocamento real do jogador.
## O plano inteiro é barato (dicionários); árvores, rochas e colisões só existem
## quando suas células entram no envelope de carga.

const PINE_SCRIPT := preload("res://world/mountain_pass/MountainPine3D.gd")
const ROCK_SCRIPT := preload("res://geodata/nature/ProceduralUrbanRock.gd")
const RUNTIME_WORK := preload("res://systems/RuntimeWorkScheduler.gd")

const CELL_SIZE := 320.0
const LOAD_RADIUS := 900.0
const AHEAD_LOAD_RADIUS := 720.0
const EVICT_RADIUS := 1480.0
const AHEAD_EVICT_RADIUS := 1120.0
const LOOKAHEAD_SECONDS := 1.15
const MAX_LOOKAHEAD_DISTANCE := 820.0
const REFRESH_DISTANCE := 48.0
const REFRESH_INTERVAL_SECONDS := 0.12
const FOCUS_RESOLVE_INTERVAL_SECONDS := 0.35
const BUILD_BUDGET_USEC := 1800
const EVICT_BUDGET_USEC := 900
const MAX_INSTANCES_PER_FRAME := 2
const MAX_EVICT_CELLS_PER_FRAME := 1

var _plan: Array[Dictionary] = []
var _cell_plans: Dictionary = {}
var _cell_nodes: Dictionary = {}
var _resident_by_index: Dictionary = {}
var _wanted_cells: Dictionary = {}
var _build_queue: Array[int] = []
var _evict_queue: Array[Vector2i] = []
var _ever_materialized: Dictionary = {}
var _focus: Node2D
var _last_focus_position := Vector2.INF
var _last_sample_position := Vector2.INF
var _observed_velocity := Vector2.ZERO
var _refresh_clock := 0.0
var _focus_resolve_clock := 0.0
var _configured := false
var _build_gate_pending := false

func _ready() -> void:
	set_meta("stream_resident_count", 0)
	set_meta("stream_resident_cells", 0)
	set_meta("stream_corridor_ready", false)
	set_process(false)

func configure(plan: Array[Dictionary]) -> void:
	_plan.clear()
	_cell_plans.clear()
	for source_item in plan:
		var item := source_item.duplicate(true)
		var plan_index := _plan.size()
		item["plan_id"] = int(item.get("plan_id", plan_index))
		_plan.append(item)
		var cell := _cell_for_position(item["position"])
		if not _cell_plans.has(cell):
			_cell_plans[cell] = []
		var indexes: Array = _cell_plans[cell]
		indexes.append(plan_index)
	_configured = true
	set_meta("stream_plan_count", _plan.size())
	set_meta("stream_cell_count", _cell_plans.size())
	set_meta("stream_resident_count", 0)
	set_meta("stream_resident_cells", 0)
	set_meta("stream_peak_resident", 0)
	set_meta("stream_materialized_total", 0)
	set_meta("stream_evicted_total", 0)
	set_meta("stream_reentered_total", 0)
	set_meta("stream_build_frames", 0)
	set_meta("stream_build_peak_usec", 0)
	set_meta("stream_evict_peak_usec", 0)
	set_meta("stream_peak_instances_per_frame", 0)
	set_meta("stream_peak_trees_per_frame", 0)
	set_meta("stream_corridor_ready", false)
	set_meta("streamed_build_complete", true)
	set_process(true)
	call_deferred("_refresh_from_live_focus")

func get_plan_snapshot() -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for item in _plan:
		snapshot.append(item.duplicate(true))
	return snapshot

func get_resident_count() -> int:
	return _resident_by_index.size()

func get_resident_plan_ids() -> Array[int]:
	var ids: Array[int] = []
	for index in _resident_by_index:
		ids.append(int(_plan[int(index)]["plan_id"]))
	ids.sort()
	return ids

func _process(delta: float) -> void:
	if not _configured or _plan.is_empty():
		return
	_focus_resolve_clock += delta
	if _focus_needs_refresh() or _focus_resolve_clock >= FOCUS_RESOLVE_INTERVAL_SECONDS:
		_focus = _resolve_live_focus()
		_focus_resolve_clock = 0.0
	if _focus == null:
		return
	var focus_position := to_local(_focus.global_position)
	if _last_sample_position != Vector2.INF and delta > 0.0001:
		var sampled := (focus_position - _last_sample_position) / delta
		if sampled.length() <= 2400.0:
			_observed_velocity = _observed_velocity.lerp(sampled, 0.28)
	_last_sample_position = focus_position
	_refresh_clock += delta
	if _last_focus_position == Vector2.INF or focus_position.distance_to(_last_focus_position) >= REFRESH_DISTANCE or _refresh_clock >= REFRESH_INTERVAL_SECONDS:
		_refresh_targets(focus_position)
		_last_focus_position = focus_position
		_refresh_clock = 0.0
	_run_evict_slice()
	_run_build_slice()
	_update_corridor_ready()

func _refresh_from_live_focus() -> void:
	if not is_inside_tree():
		return
	var live_focus := _resolve_live_focus()
	if live_focus == null:
		return
	_focus = live_focus
	var focus_position := to_local(_focus.global_position)
	_last_sample_position = focus_position
	_refresh_targets(focus_position)

func _resolve_live_focus() -> Node2D:
	if get_tree() == null:
		return null
	var region_travel := get_node_or_null("/root/RegionTravel")
	if region_travel != null and region_travel.has_method("controlled_car"):
		var controlled_car = region_travel.controlled_car()
		if controlled_car is Node2D and is_instance_valid(controlled_car):
			set_meta("stream_focus_is_vehicle", true)
			set_meta("stream_focus_name", String(controlled_car.name))
			return controlled_car as Node2D
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return null
	set_meta("stream_focus_is_vehicle", false)
	set_meta("stream_focus_name", String(player.name))
	return player

func _focus_needs_refresh() -> bool:
	if not is_instance_valid(_focus):
		return true
	if _focus.is_in_group("player"):
		return not _focus.visible
	if _focus.is_in_group("vehicle"):
		return _focus.get("is_driven_by_player") != true
	return false

func _refresh_targets(focus_position: Vector2) -> void:
	var velocity := _focus_velocity_local()
	if velocity.length_squared() < 16.0:
		velocity = _observed_velocity
	var lookahead := velocity * LOOKAHEAD_SECONDS
	if lookahead.length() > MAX_LOOKAHEAD_DISTANCE:
		lookahead = lookahead.normalized() * MAX_LOOKAHEAD_DISTANCE
	var ahead_position := focus_position + lookahead
	_wanted_cells.clear()
	for key_variant in _cell_plans:
		var key: Vector2i = key_variant
		if _distance_to_cell(focus_position, key) <= LOAD_RADIUS or _distance_to_cell(ahead_position, key) <= AHEAD_LOAD_RADIUS:
			_wanted_cells[key] = true

	_build_queue.clear()
	for key_variant in _wanted_cells:
		var key: Vector2i = key_variant
		var indexes: Array = _cell_plans[key]
		for index_variant in indexes:
			var index := int(index_variant)
			if not _resident_by_index.has(index):
				_build_queue.append(index)
	_build_queue.sort_custom(func(a: int, b: int) -> bool:
		return _item_priority(a, focus_position, ahead_position) < _item_priority(b, focus_position, ahead_position)
	)

	_evict_queue.clear()
	for key_variant in _cell_nodes:
		var key: Vector2i = key_variant
		if _distance_to_cell(focus_position, key) > EVICT_RADIUS and _distance_to_cell(ahead_position, key) > AHEAD_EVICT_RADIUS:
			_evict_queue.append(key)
	_evict_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _distance_to_cell(focus_position, a) > _distance_to_cell(focus_position, b)
	)
	set_meta("stream_wanted_cells", _wanted_cells.size())
	set_meta("stream_pending_instances", _build_queue.size())
	set_meta("stream_corridor_ready", _build_queue.is_empty())

func _run_build_slice() -> void:
	if _build_queue.is_empty() or _build_gate_pending:
		return
	_build_gate_pending = true
	var ticket: Dictionary = await RUNTIME_WORK.reserve(
		self,
		&"mountain_forest",
		RUNTIME_WORK.PRIORITY_NEAR_COLLISION,
		BUILD_BUDGET_USEC)
	_build_gate_pending = false
	if ticket.is_empty():
		return
	if _build_queue.is_empty():
		RUNTIME_WORK.complete(ticket, 0)
		return
	var started := Time.get_ticks_usec()
	var instances := 0
	var trees := 0
	while not _build_queue.is_empty() and instances < MAX_INSTANCES_PER_FRAME:
		if instances > 0 and Time.get_ticks_usec() - started >= BUILD_BUDGET_USEC:
			break
		var index: int = int(_build_queue.pop_front())
		if _resident_by_index.has(index):
			continue
		var item := _plan[index]
		var cell := _cell_for_position(item["position"])
		if not _wanted_cells.has(cell):
			continue
		_materialize(index, cell)
		instances += 1
		if not bool(item["rock"]):
			trees += 1
	var elapsed := Time.get_ticks_usec() - started
	RUNTIME_WORK.complete(ticket, elapsed)
	set_meta("stream_build_frames", int(get_meta("stream_build_frames", 0)) + 1)
	set_meta("stream_build_peak_usec", maxi(int(get_meta("stream_build_peak_usec", 0)), elapsed))
	set_meta("stream_peak_instances_per_frame", maxi(int(get_meta("stream_peak_instances_per_frame", 0)), instances))
	set_meta("stream_peak_trees_per_frame", maxi(int(get_meta("stream_peak_trees_per_frame", 0)), trees))
	set_meta("stream_pending_instances", _build_queue.size())

func _run_evict_slice() -> void:
	if _evict_queue.is_empty():
		return
	var started := Time.get_ticks_usec()
	var evicted_cells := 0
	while not _evict_queue.is_empty() and evicted_cells < MAX_EVICT_CELLS_PER_FRAME:
		if evicted_cells > 0 and Time.get_ticks_usec() - started >= EVICT_BUDGET_USEC:
			break
		var cell: Vector2i = _evict_queue.pop_front() as Vector2i
		_evict_cell(cell)
		evicted_cells += 1
	set_meta("stream_evict_peak_usec", maxi(int(get_meta("stream_evict_peak_usec", 0)), Time.get_ticks_usec() - started))

func _materialize(index: int, cell: Vector2i) -> void:
	var cell_node := _cell_nodes.get(cell) as Node2D
	if cell_node == null:
		cell_node = Node2D.new()
		cell_node.name = "Cell_%d_%d" % [cell.x, cell.y]
		cell_node.set_meta("forest_cell", cell)
		add_child(cell_node)
		_cell_nodes[cell] = cell_node
	var item := _plan[index]
	var pos: Vector2 = item["position"]
	var instance: Node2D
	if bool(item["rock"]):
		var rock = ROCK_SCRIPT.new()
		rock.variant_seed = int(pos.x * 43 + pos.y * 71)
		var placed_index := int(item["placed_index"])
		rock.rock_size = Vector2(38 + placed_index % 3 * 12, 28 + placed_index % 4 * 6)
		rock.base_color = Color("89979f") if bool(item["snow_region"]) else Color("61665a")
		rock.set_meta("mountain_grove", true)
		instance = rock
	else:
		var pine = PINE_SCRIPT.new()
		pine.tree_scale = float(item["scale"])
		pine.variant_seed = int(pos.x * 43 + pos.y * 71)
		pine.is_snowy = (bool(item["snow_region"]) and posmod(pine.variant_seed, 7) != 0) or (not bool(item["snow_region"]) and pos.y < -650.0 and posmod(pine.variant_seed, 5) == 0)
		if bool(item["grove"]):
			pine.set_meta("mountain_grove", true)
		instance = pine
	instance.name = "ForestItem_%d" % int(item["plan_id"])
	instance.position = pos
	instance.set_meta("forest_plan_index", index)
	cell_node.add_child(instance)
	_resident_by_index[index] = instance
	var was_seen := _ever_materialized.has(index)
	_ever_materialized[index] = true
	set_meta("stream_materialized_total", int(get_meta("stream_materialized_total", 0)) + 1)
	if was_seen:
		set_meta("stream_reentered_total", int(get_meta("stream_reentered_total", 0)) + 1)
	_update_resident_telemetry()

func _evict_cell(cell: Vector2i) -> void:
	var cell_node := _cell_nodes.get(cell) as Node2D
	if cell_node == null:
		return
	var evicted := 0
	var indexes: Array = _cell_plans.get(cell, [])
	for index_variant in indexes:
		var index := int(index_variant)
		if _resident_by_index.erase(index):
			evicted += 1
	_cell_nodes.erase(cell)
	cell_node.queue_free()
	set_meta("stream_evicted_total", int(get_meta("stream_evicted_total", 0)) + evicted)
	_update_resident_telemetry()

func _update_resident_telemetry() -> void:
	var resident := _resident_by_index.size()
	set_meta("stream_resident_count", resident)
	set_meta("stream_resident_cells", _cell_nodes.size())
	set_meta("stream_peak_resident", maxi(int(get_meta("stream_peak_resident", 0)), resident))

func _update_corridor_ready() -> void:
	if _build_queue.is_empty():
		set_meta("stream_corridor_ready", true)

func _focus_velocity_local() -> Vector2:
	if _focus == null:
		return Vector2.ZERO
	var velocity_variant = (_focus as CharacterBody2D).velocity if _focus is CharacterBody2D else _property_value(_focus, &"velocity")
	if velocity_variant is Vector2:
		var world_velocity: Vector2 = velocity_variant
		return to_local(_focus.global_position + world_velocity) - to_local(_focus.global_position)
	return Vector2.ZERO

func _property_value(object: Object, property_name: StringName):
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return object.get(property_name)
	return null

func _cell_for_position(position: Vector2) -> Vector2i:
	return Vector2i(floori(position.x / CELL_SIZE), floori(position.y / CELL_SIZE))

func _cell_bounds(cell: Vector2i) -> Rect2:
	return Rect2(Vector2(cell) * CELL_SIZE, Vector2.ONE * CELL_SIZE)

func _distance_to_cell(point: Vector2, cell: Vector2i) -> float:
	var bounds := _cell_bounds(cell)
	var closest := Vector2(
		clampf(point.x, bounds.position.x, bounds.end.x),
		clampf(point.y, bounds.position.y, bounds.end.y)
	)
	return point.distance_to(closest)

func _item_priority(index: int, focus_position: Vector2, ahead_position: Vector2) -> float:
	var position: Vector2 = _plan[index]["position"]
	return minf(position.distance_squared_to(ahead_position) * 0.72, position.distance_squared_to(focus_position))
