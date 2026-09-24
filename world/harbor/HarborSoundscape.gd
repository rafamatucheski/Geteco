extends Node
## Camadas gravadas com transição suave e fontes ligadas ao primeiro quarteirão.
const BANK := preload("res://world/harbor/HarborAudioBank.gd")
const RECORDED := preload("res://audio/living_city/LivingCityAudio.gd")
var beds: Dictionary = {}
var weights := {"city": 0.0, "water": 0.0, "terminal": 0.0, "workshop": 0.0, "port": 0.0, "crickets": 0.0}
var targets := weights.duplicate()
var _nature_gain := 0.0
var _nature_candidate := 0.0
var _nature_elapsed := 0.0
var detail: AudioStreamPlayer2D
var _clock := 0.0
var dialogue_focused := false
var focus_gain := 1.0
var _detail_clock := 9.0
var _rng := RandomNumberGenerator.new()
var _visits := 0
var _departures := 0
var quarter: Node2D
var _listener_position := Vector2.ZERO
var _room: Node2D
var _dark := false
var _district_gain := 1.0
var _detail_variant := 0
var _detail_room: Node2D
var water_details: Node
var regional: Node
var listener: AudioListener2D

func _ready() -> void:
	_rng.randomize()
	# Interior cameras frame the whole room. Hearing stays with Dante (or his
	# vehicle), rather than with that fixed overview's center.
	listener = AudioListener2D.new()
	listener.name = "PlayerAudioListener"
	listener.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(listener)
	listener.global_position = _actor_position()
	listener.make_current()
	for kind in weights:
		var audio: Node = AudioStreamPlayer2D.new() if kind == "workshop" else AudioStreamPlayer.new()
		if audio is AudioStreamPlayer2D:
			audio.max_distance = 320.0
			audio.attenuation = 1.35
		audio.name = kind.capitalize() + "Bed"
		var recordings := {"city": "street", "water": "water", "terminal": "street", "workshop": "workshop", "crickets": "crickets"}
		audio.stream = BANK.sound("port") if kind == "port" else RECORDED.bed(recordings[kind], 1 if kind == "terminal" else 0)
		audio.bus = "Ambient"
		audio.volume_db = -80.0
		add_child(audio)
		beds[kind] = audio
	for kind in ["air", "gull", "metal"]:
		BANK.sound(kind)
	detail = AudioStreamPlayer2D.new()
	detail.name = "NearbyDetail"
	detail.bus = "Ambient"
	detail.max_distance = 700.0
	detail.volume_db = -16.0
	add_child(detail)
	quarter = preload("res://world/harbor/HarborLivingQuarter.gd").new()
	quarter.name = "LivingQuarter"
	add_child(quarter)
	water_details = preload("res://audio/WaterSoundscape.gd").new()
	water_details.name = "WaterDetails"
	add_child(water_details)
	regional = preload("res://audio/regional/RegionalSoundscape.gd").new()
	regional.name = "RegionalSoundscape"
	add_child(regional)
	var interiors := get_parent().get_node("Interiors")
	interiors.actor_entered_interior.connect(_on_room_transition)
	interiors.actor_returned_to_exterior.connect(_on_room_transition)
	_update_zones()

func _process(delta: float) -> void:
	_listener_position = _actor_position()
	listener.global_position = _listener_position
	_clock += delta
	_detail_clock -= delta
	if _clock >= 0.2:
		_clock = 0.0
		_update_zones()
	focus_gain = move_toward(focus_gain, 0.35 if dialogue_focused else 1.0, delta / (0.2 if dialogue_focused else 0.8))
	detail.volume_db = float(detail.get_meta("base_db", -7.0)) + linear_to_db(focus_gain)
	quarter.update_context(_listener_position, _room, _dark, focus_gain, _district_gain, delta)
	var actor := get_parent().get_node("Player")
	var indoors := is_instance_valid(_room) or bool(actor.get_meta("mountain_interior", false)) or bool(actor.get_meta("harbor_interior", false))
	regional.update_context(_listener_position, indoors, _dark, focus_gain, delta)
	water_details.update_context(_listener_position, indoors, focus_gain, delta)
	var garage_interior: Node2D = get_parent().get_node("Interiors").get("garage_interior") if get_parent().has_node("Interiors") else null
	var in_garage := is_instance_valid(_room) and is_instance_valid(garage_interior) and _room == garage_interior
	if in_garage:
		for kind in weights:
			if kind != "workshop":
				weights[kind] = 0.0
				targets[kind] = 0.0
				if beds[kind].playing:
					beds[kind].stop()
	for kind in weights:
		# Same fade duration for quiet and loud beds; no stream swaps or queued tweens.
		weights[kind] = lerpf(float(weights[kind]), float(targets[kind]), 1.0 - exp(-delta / 0.7))
		var audio: Node = beds[kind]
		var gain := float(weights[kind]) * focus_gain
		audio.volume_db = linear_to_db(maxf(gain, 0.0001)) - (32.0 if kind == "workshop" else 10.0 if kind == "city" else 4.0)
		if gain > 0.005 and not audio.playing:
			audio.play()
		elif gain <= 0.001 and audio.playing:
			audio.stop()

func _actor_position() -> Vector2:
	var actor: Node2D = get_parent().get_node("Player")
	if not actor.visible:
		for car in get_tree().get_nodes_in_group("vehicle"):
			if car.get("is_driven_by_player") == true: return car.global_position
	return actor.global_position

func _on_room_transition(_actor: Node2D, _room_id: StringName) -> void:
	# Door signals run before HarborGame's periodic presentation restore.
	# Resolve the actual space now, so old exterior details cannot leak in.
	_update_zones()
	listener.global_position = _listener_position

func _current_room(world: Node, position: Vector2) -> Node2D:
	var current: Node2D = world.get("_last_room")
	if is_instance_valid(current) and current.contains_point(position): return current
	for candidate in world.get_node("Interiors/InteriorSpaces").get_children():
		if candidate.has_method("contains_point") and candidate.contains_point(position): return candidate
	return null

func _update_zones() -> void:
	var world := get_parent()
	var actor: Node2D = world.get_node("Player")
	var pos := _actor_position()
	var room: Node2D = _current_room(world, pos)
	dialogue_focused = bool(actor.get("is_in_dialogue"))
	if is_instance_valid(world.weather.weather_audio):
		world.weather.weather_audio.set_dialogue_focus(dialogue_focused)
	var interiors := world.get_node("Interiors")
	var inside := is_instance_valid(room) or bool(actor.get_meta("harbor_interior", false)) or bool(actor.get_meta("mountain_interior", false))
	var dark := bool(world.weather.is_dark)
	_dark = dark
	_listener_position = pos
	_room = room
	# O porto deixa de tocar ao seguir para a montanha, inclusive no mundo contínuo.
	_district_gain = clampf((pos.y + 1800.0) / 1300.0, 0.0, 1.0) if not inside else 1.0
	# Mountain rooms live off-map at positive Y; those coordinates are not city zones.
	if actor.get_meta("mountain_interior", false):
		_district_gain = 0.0
	var crowd := nearby_conversation_weight(pos) if not inside else 0.0
	targets.city = (0.22 if dark else 0.42) * crowd
	var outdoors: bool = not inside and not actor.get_meta("harbor_interior", false) and not actor.get_meta("mountain_interior", false)
	var cemetery_gain := cemetery_weight(pos)
	var nature := natural_weight(pos) if outdoors else 0.0
	# Require a stable vegetation boundary before changing its bed.
	if absf(nature - _nature_candidate) > 0.05:
		_nature_candidate = nature
		_nature_elapsed = 0.0
	else:
		_nature_elapsed += 0.2
		if _nature_elapsed >= 0.6: _nature_gain = nature
	targets.crickets = _nature_gain * 0.22 if outdoors and dark else 0.0
	# Street recordings contain chatter; fade them out before the cemetery wall.
	targets.city *= 1.0 - cemetery_gain
	var port_gain := port_weight(pos) if not inside and not actor.get_meta("harbor_interior", false) and not actor.get_meta("mountain_interior", false) else 0.0
	targets.port = port_gain * (0.55 if dark else 0.85)
	targets.city *= 1.0-port_gain
	var plaza_gain := plaza_weight(pos) if outdoors else 0.0
	targets.city *= 1.0 - plaza_gain
	targets.water = 0.0 if inside or actor.get_meta("mountain_interior", false) or actor.get_meta("harbor_interior", false) else preload("res://audio/WaterSoundscape.gd").coast_weight(pos)
	targets.terminal = 0.0 if inside else clampf(1.0 - pos.distance_to(Vector2(1700, 1130)) / 220.0, 0.0, 1.0) * crowd
	targets.terminal *= 1.0 - cemetery_gain
	if dark:
		targets.terminal *= 0.5
	targets.workshop = 1.0 if inside and room == interiors.get("garage_interior") else 0.0
	# Tools belong to the actual workbench, not the radio or a nonspatial bed.
	var garage: Node2D = interiors.garage_interior
	if is_instance_valid(world.weather.weather_audio):
		world.weather.weather_audio.set_interior_silence(room == garage)
	if room == garage:
		for kind in weights:
			if kind != "workshop":
				weights[kind] = 0.0
				targets[kind] = 0.0
				beds[kind].stop()
	beds.workshop.global_position = garage.diagnostic_area.global_position
	for kind in targets:
		if kind not in ["water", "crickets"]: targets[kind] *= _district_gain
	if _detail_room != room or _district_gain < 0.1:
		detail.stop()
	var terminal := world.get_node("ArrivalStop")
	if terminal.visits != _visits or terminal.departures != _departures:
		_visits = terminal.visits
		_departures = terminal.departures
		if not inside and _district_gain > 0.1 and is_instance_valid(terminal.bus) and pos.distance_to(terminal.bus.global_position) < 650.0:
			_play_detail("air", terminal.bus.global_position)
	if _detail_clock <= 0.0:
		_detail_clock = _rng.randf_range(13.0, 27.0)
		# O navio tem gaivotas próprias, para não sobrepor os dois agendamentos.
		var crew := world.get_node_or_null("Waterfront/DockCrew")
		if targets.water > 0.25 and not dark and not (crew != null and crew.active):
			if _rng.randf() < 0.35:
				_play_detail("ship_horn", Vector2(clampf(pos.x, 3000, 4500), pos.y + _rng.randf_range(-400, 400)))
			else:
				_play_detail("gull", Vector2(clampf(pos.x, 3250, 3900), pos.y + _rng.randf_range(-180, 180)))
		elif targets.port > 0.2 and _rng.randf() < 0.4:
			_play_detail("ship_horn", pos + Vector2(400, -200))
		elif dark and not inside and targets.city > 0.1 and _rng.randf() < 0.45:
			_play_detail("dog", pos + Vector2(_rng.randf_range(-500, 500), _rng.randf_range(-500, 500)))
		elif targets.workshop > 0.5:
			_play_detail("metal", beds.workshop.global_position)
		elif targets.port > 0.2:
			_play_detail("metal", pos + Vector2(100, -80))

func nearby_conversation_weight(point: Vector2) -> float:
	if not point.is_finite(): return 0.0
	var presence := 0.0
	var query := PhysicsRayQueryParameters2D.new()
	query.collision_mask = 1
	query.from = point
	var rays := 0
	for person in get_tree().get_nodes_in_group("pedestrian"):
		if not person is Node2D or not person.is_visible_in_tree(): continue
		if person.get("is_dead") == true or person.get("is_incapacitated") == true or person.get("is_scared") == true: continue
		var person_position: Vector2 = person.global_position
		if not person_position.is_finite(): continue
		var distance: float = point.distance_to(person_position)
		if distance >= 160.0: continue
		if rays >= 12: break
		rays += 1
		query.to = person_position
		if not person.get_world_2d().direct_space_state.intersect_ray(query).is_empty(): continue
		presence += 1.0 - smoothstep(55.0, 160.0, distance)
		if presence >= 4.0: break
	# A lone passerby does not sound like a crowd. Walls silence the next street.
	return smoothstep(1.0, 4.0, presence)

func cemetery_weight(point: Vector2) -> float:
	var cemetery := get_parent().get_node_or_null("Cemetery") as Node2D
	if cemetery == null: return 0.0
	var half: Vector2 = cemetery.LOT_SIZE * 0.5
	var local := cemetery.to_local(point)
	return 1.0 - smoothstep(0.0, 180.0, local.distance_to(local.clamp(-half, half)))

func natural_weight(point: Vector2) -> float:
	var result := cemetery_weight(point)
	var world := get_parent()
	# Reuse authored garden areas; tiny decorative planters do not fill city streets.
	var gardens := preload("res://audio/footsteps/FootstepSurfaceResolver.gd").GARDENS
	for provider_name in gardens:
		var provider := world.get_node_or_null(NodePath(provider_name)) as Node2D
		if provider == null: continue
		var local := provider.to_local(point)
		for area: Rect2 in gardens[provider_name]:
			var depth := minf(minf(local.x - area.position.x, area.end.x - local.x), minf(local.y - area.position.y, area.end.y - local.y))
			result = maxf(result, smoothstep(0.0, 65.0, depth))
	# The planted western buffer is authored by HarborDistrict.
	var buffer := Rect2(10, 500, 225, 1670)
	var district := world.get_node_or_null("District") as Node2D
	if district != null:
		var local := district.to_local(point)
		if buffer.has_point(local):
			result = maxf(result, smoothstep(0.0, 65.0, minf(minf(local.x-buffer.position.x, buffer.end.x-local.x), minf(local.y-buffer.position.y, buffer.end.y-local.y))))
	for ground in get_tree().get_nodes_in_group("audio_ground"):
		if ground is Polygon2D and ground.is_visible_in_tree() and world.is_ancestor_of(ground) and ground.get_meta("mountain_surface", "") == "forest":
			if Geometry2D.is_point_in_polygon(ground.to_local(point), ground.polygon): return 1.0
	return result

static func port_weight(point: Vector2) -> float:
	var land := preload("res://world/harbor/HarborSouthPortLayout.gd").LAND
	var nearest := point.clamp(land.position, land.end)
	return 1.0-smoothstep(0,350,point.distance_to(nearest))

static func plaza_weight(point: Vector2) -> float:
	var plazas: Array[Rect2] = [
		Rect2(1440, 780, 620, 380),   # Praça Market Street / Terminal
		Rect2(1440, 1660, 620, 480),  # Praça Union Plaza / Fonte
		Rect2(7200, 1200, 1000, 1000) # Praça de Ashbend (Ashbend Court)
	]
	var weight := 0.0
	for rect in plazas:
		var nearest := point.clamp(rect.position, rect.end)
		var dist := point.distance_to(nearest)
		var w := 1.0 - smoothstep(0.0, 120.0, dist)
		if w > weight:
			weight = w
	return weight

func _play_detail(kind: String, position: Vector2) -> void:
	if dialogue_focused:
		return
	_detail_room = _room
	var indoor_tools := kind == "metal" and is_instance_valid(_room)
	detail.set_meta("base_db", -36.0 if indoor_tools else (-4.0 if kind == "ship_horn" else -9.0 if kind == "dog" else -7.0))
	detail.volume_db = float(detail.get_meta("base_db")) + linear_to_db(focus_gain)
	detail.max_distance = 320.0 if indoor_tools else (1400.0 if kind == "ship_horn" else 950.0 if kind == "dog" else 700.0)
	# Never allocate a player per event; a more recent physical bus event wins.
	if kind == "air":
		detail.stream = BANK.sound(kind)
	else:
		detail.stream = RECORDED.detail("workshop" if kind == "metal" else kind, _detail_variant)
		_detail_variant = (_detail_variant + 1) % 3
	detail.global_position = position
	detail.pitch_scale = _rng.randf_range(0.94, 1.04)
	detail.play()
