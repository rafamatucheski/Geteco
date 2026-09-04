extends Node2D

## Autoridade unica para os semaforos da cidade.
##
## Intersecoes registram apenas sua geometria. Este autoload mantem uma unica
## maquina de estados, desenha um conjunto compacto de quatro postes por
## cruzamento e oferece a mesma consulta para todos os agentes de trafego.

signal phase_changed(state_ew: int, state_ns: int)

enum LightState { GREEN, YELLOW, RED }
enum CyclePhase { EW_GREEN, EW_YELLOW, ALL_RED_TO_NS, NS_GREEN, NS_YELLOW, ALL_RED_TO_EW }

const TIME_GREEN := 7.5
const TIME_YELLOW := 2.2
const TIME_ALL_RED := 2.0
const SIGNAL_SET_Z_INDEX := 32

var state_ew: LightState = LightState.GREEN
var state_ns: LightState = LightState.RED
var _timer := 0.0
var _cycle_phase: int = CyclePhase.EW_GREEN
var _intersections: Dictionary = {}
var _visual_sets: Dictionary = {}

func _ready() -> void:
	name = "TrafficLightManager"
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_timer += delta
	var phase_duration := TIME_GREEN
	if _cycle_phase == CyclePhase.EW_YELLOW or _cycle_phase == CyclePhase.NS_YELLOW:
		phase_duration = TIME_YELLOW
	elif _cycle_phase == CyclePhase.ALL_RED_TO_NS or _cycle_phase == CyclePhase.ALL_RED_TO_EW:
		phase_duration = TIME_ALL_RED
	if _timer >= phase_duration:
		_advance_phase()

func _advance_phase() -> void:
	_cycle_phase = (_cycle_phase + 1) % CyclePhase.size()
	_timer = 0.0
	match _cycle_phase:
		CyclePhase.EW_GREEN:
			state_ew = LightState.GREEN
			state_ns = LightState.RED
		CyclePhase.EW_YELLOW:
			state_ew = LightState.YELLOW
			state_ns = LightState.RED
		CyclePhase.ALL_RED_TO_NS, CyclePhase.ALL_RED_TO_EW:
			state_ew = LightState.RED
			state_ns = LightState.RED
		CyclePhase.NS_GREEN:
			state_ew = LightState.RED
			state_ns = LightState.GREEN
		CyclePhase.NS_YELLOW:
			state_ew = LightState.RED
			state_ns = LightState.YELLOW
	_update_visuals()
	phase_changed.emit(state_ew, state_ns)

func is_green_for(direction_axis: String) -> bool:
	return get_state_for(direction_axis) == LightState.GREEN

func get_state_for(direction_axis: String) -> LightState:
	return state_ew if direction_axis.to_upper() == "EW" else state_ns

func is_safe_for_pedestrian_crossing(crossing_axis: String) -> bool:
	if crossing_axis.to_upper() == "CROSS_EW":
		return state_ew == LightState.RED
	return state_ns == LightState.RED

## Registra um unico conjunto visual. Repetir a chamada atualiza o conjunto,
## em vez de empilhar novos managers/postes no mesmo cruzamento.
func register_intersection(intersection_id: StringName, world_center: Vector2, road_width: float, create_visual_posts: bool = true) -> void:
	var safe_width := maxf(road_width, 32.0)
	_intersections[intersection_id] = {
		"center": world_center,
		"road_width": safe_width,
		"create_visual_posts": create_visual_posts,
	}
	if create_visual_posts:
		_rebuild_visual_set(intersection_id)

func unregister_intersection(intersection_id: StringName) -> void:
	_intersections.erase(intersection_id)
	var visual := _visual_sets.get(intersection_id) as Node2D
	if is_instance_valid(visual):
		visual.queue_free()
	_visual_sets.erase(intersection_id)

## Consulta usada por TrafficLaneAgent. A sonda deve representar a dianteira
## do carro; assim o veiculo para antes da linha sem invadir a faixa de pedestre.
func should_stop_vehicle(
	intersection_id: StringName,
	probe_position: Vector2,
	direction_axis: String,
	forward_direction: Vector2,
	lookahead: float = 42.0
) -> bool:
	if is_green_for(direction_axis):
		return false
	var data: Dictionary = _intersections.get(intersection_id, {})
	if data.is_empty():
		return false
	var center: Vector2 = data.center
	var half_width: float = float(data.road_width) * 0.5
	var stop_offset := half_width + 8.0
	var forward := forward_direction.normalized()
	if direction_axis.to_upper() == "EW":
		if absf(probe_position.y - center.y) > half_width * 0.62:
			return false
		var stop_x := center.x - stop_offset if forward.x > 0.0 else center.x + stop_offset
		var distance := (stop_x - probe_position.x) * signf(forward.x)
		return distance >= 0.0 and distance <= lookahead
	if absf(probe_position.x - center.x) > half_width * 0.62:
		return false
	var stop_y := center.y - stop_offset if forward.y > 0.0 else center.y + stop_offset
	var distance := (stop_y - probe_position.y) * signf(forward.y)
	return distance >= 0.0 and distance <= lookahead

func _rebuild_visual_set(intersection_id: StringName) -> void:
	var previous := _visual_sets.get(intersection_id) as Node2D
	if is_instance_valid(previous):
		previous.free()
	var data: Dictionary = _intersections[intersection_id]
	var center: Vector2 = data.center
	var half_width: float = float(data.road_width) * 0.5
	var setback := half_width + 14.0
	var visual_root := Node2D.new()
	visual_root.name = "Signals_%s" % String(intersection_id)
	visual_root.z_index = SIGNAL_SET_Z_INDEX
	add_child(visual_root)
	# Um poste por esquina, cada qual orientado para a aproximacao visivel.
	_add_signal_post(visual_root, center + Vector2(-setback, -setback), "NS", false)
	_add_signal_post(visual_root, center + Vector2(setback, -setback), "EW", true)
	_add_signal_post(visual_root, center + Vector2(-setback, setback), "EW", false)
	_add_signal_post(visual_root, center + Vector2(setback, setback), "NS", true)
	_visual_sets[intersection_id] = visual_root
	_update_visuals()

func _add_signal_post(parent: Node2D, world_position: Vector2, axis: String, mirrored: bool) -> void:
	var post := Node2D.new()
	post.name = "Signal_%02d" % (parent.get_child_count() + 1)
	post.position = world_position
	post.set_meta("axis", axis)
	parent.add_child(post)

	var base := ColorRect.new()
	base.position = Vector2(-4, 7)
	base.size = Vector2(8, 4)
	base.color = Color("30343a")
	post.add_child(base)
	var pole := ColorRect.new()
	pole.position = Vector2(-1.5, -11)
	pole.size = Vector2(3, 19)
	pole.color = Color("59616a")
	post.add_child(pole)
	var box := ColorRect.new()
	box.name = "SignalBox"
	box.position = Vector2(-11 if mirrored else 2, -18)
	box.size = Vector2(9, 18)
	box.color = Color("11161c")
	post.add_child(box)
	for index in 3:
		var bulb := ColorRect.new()
		bulb.name = ["Red", "Yellow", "Green"][index]
		bulb.position = Vector2(2, 2 + index * 5)
		bulb.size = Vector2(5, 4)
		box.add_child(bulb)

func _update_visuals() -> void:
	for visual_value in _visual_sets.values():
		var visual := visual_value as Node2D
		if not is_instance_valid(visual):
			continue
		for post_value in visual.get_children():
			var post := post_value as Node2D
			var box := post.get_node_or_null("SignalBox") as ColorRect
			if box == null:
				continue
			var state := get_state_for(String(post.get_meta("axis", "NS")))
			_set_bulb(box.get_node("Red") as ColorRect, state == LightState.RED, Color("ff3b30"))
			_set_bulb(box.get_node("Yellow") as ColorRect, state == LightState.YELLOW, Color("ffd43b"))
			_set_bulb(box.get_node("Green") as ColorRect, state == LightState.GREEN, Color("34d058"))

func _set_bulb(bulb: ColorRect, enabled: bool, active_color: Color) -> void:
	bulb.color = active_color if enabled else active_color.darkened(0.72)
