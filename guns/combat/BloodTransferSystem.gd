extends Node2D
## Ground contact transfers residue; distance, rather than waiting time, wears it off.
const MAX_MARKS := 900
const MARK_LIFETIME := 14.0
const MARK_FADE_DURATION := 4.0
const TIRE_DISTANCE := 210.0
const FOOT_DISTANCE := 85.0
const SAMPLE_INTERVAL := 1.0 / 30.0
var tracks: Dictionary = {}
var _active_track_ids: Array[int] = []
var marks: Array[Dictionary] = []
var surfaces: Array[Node] = []
var _surface_cells: Dictionary = {}
var _refresh := 0.0
var _clock := 0.0
var _sample_elapsed := 0.0
var _marks_dirty := false

static func ensure(source) -> Node:
	if not is_instance_valid(source) or not source is Node or not source.is_inside_tree(): return null
	var existing: Node = source.get_tree().get_first_node_in_group("blood_transfer_system")
	if existing != null: return existing
	var scene: Node = source.get_tree().current_scene
	if scene == null:
		scene = source
		while scene.get_parent() != source.get_tree().root: scene = scene.get_parent()
	var system := new()
	scene.add_child(system)
	return system

static func wash(actor: Node) -> void:
	var system := actor.get_tree().get_first_node_in_group("blood_transfer_system")
	if system != null:
		system.tracks.erase(actor.get_instance_id())
		system._active_track_ids.erase(actor.get_instance_id())

static func actor_activity_changed(actor: Node2D, active: bool) -> void:
	if not is_instance_valid(actor) or not actor.is_inside_tree(): return
	var system := actor.get_tree().get_first_node_in_group("blood_transfer_system")
	if system != null: system._set_actor_active(actor, active)

static func splash(actor: Node2D) -> void:
	var system = ensure(actor)
	if not system.tracks.has(actor.get_instance_id()): system._refresh_contacts()
	if system.tracks.has(actor.get_instance_id()):
		system.tracks[actor.get_instance_id()].residue = [TIRE_DISTANCE, TIRE_DISTANCE]

func _ready() -> void:
	name = "BloodTransferSystem"
	add_to_group("blood_transfer_system")
	z_as_relative = false
	z_index = 5
	process_physics_priority = 100

func _refresh_contacts() -> void:
	surfaces.clear()
	_surface_cells.clear()
	for group in ["ground_blood", "bank_guard_blood", "wildlife_blood"]:
		for surface in get_tree().get_nodes_in_group(group):
			if not surface is Node2D: continue
			surfaces.append(surface)
			var cell := Vector2i((surface.global_position / 128.0).floor())
			if not _surface_cells.has(cell): _surface_cells[cell] = []
			_surface_cells[cell].append(surface)
	for group in ["vehicle", "pedestrian", "player", "paramedic", "firefighter", "police_officer", "mortician"]:
		for actor in get_tree().get_nodes_in_group(group):
			if actor is Node2D and not tracks.has(actor.get_instance_id()):
				tracks[actor.get_instance_id()] = {"actor": weakref(actor), "previous": actor.global_position, "travel": 0.0, "residue": [0.0, 0.0], "foot": 0, "active": false}
	for id in tracks.keys():
		if not is_instance_valid(tracks[id].actor.get_ref()): tracks.erase(id)
	_refresh_active_tracks()

func _refresh_active_tracks() -> void:
	_active_track_ids.clear()
	for id in tracks:
		var track: Dictionary = tracks[id]
		var actor = track.actor.get_ref()
		if not is_instance_valid(actor): continue
		var active: bool = not actor.get_meta("proximity_sleeping", false) and actor.can_process()
		track.active = active
		if active:
			_active_track_ids.append(id)
		else:
			# A later wake starts from the live position instead of joining a trail.
			track.previous = actor.global_position
			_reset_foot_phase(actor, track)

func _set_actor_active(actor: Node2D, active: bool) -> void:
	var id := actor.get_instance_id()
	if not tracks.has(id): return
	var track: Dictionary = tracks[id]
	track.previous = actor.global_position
	track.active = active
	_reset_foot_phase(actor, track)
	if active:
		if not _active_track_ids.has(id): _active_track_ids.append(id)
	else:
		_active_track_ids.erase(id)

func _physics_process(delta: float) -> void:
	_clock += delta
	_sample_elapsed += delta
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh_contacts()
		_refresh = 0.25
	# Contact sampling is distance-swept in sample_actor(), so retaining the
	# previous position for one physics tick preserves every crossed puddle and
	# the exact distance-based mark cadence while halving population-wide work.
	if _sample_elapsed >= SAMPLE_INTERVAL:
		_sample_elapsed = fposmod(_sample_elapsed, SAMPLE_INTERVAL)
		var became_inactive: Array[int] = []
		for id in _active_track_ids:
			if not tracks.has(id): continue
			var track: Dictionary = tracks[id]
			var actor = track.actor.get_ref()
			if not is_instance_valid(actor): continue
			if actor.get_meta("proximity_sleeping", false) or not actor.can_process():
				# Preserve residue but do not draw a trail across an offscreen relocation.
				track.previous = actor.global_position
				_reset_foot_phase(actor, track)
				track.active = false
				became_inactive.append(id)
				continue
			sample_actor(actor, track)
		for id in became_inactive:
			_active_track_ids.erase(id)
	while not marks.is_empty() and _clock - float(marks[0].time) > MARK_LIFETIME:
		marks.pop_front()
		_marks_dirty = true
	# CanvasItem retains draw commands. Existing marks only change color during
	# their final seconds; keep rebuilding then, or when marks change.
	var fading := not marks.is_empty() and _clock - float(marks[0].time) > MARK_LIFETIME - MARK_FADE_DURATION
	if _marks_dirty or fading:
		queue_redraw()
		_marks_dirty = false

func _grounded(actor: Node2D) -> bool:
	if not actor.is_visible_in_tree(): return false
	if actor.get("is_flying") == true or actor.get("is_dead") == true or actor.get("is_incapacitated") == true: return false
	var transit = actor.get("transit_state")
	return transit != "onboard"

func _direction(actor: Node2D, motion: Vector2) -> Vector2:
	if actor.is_in_group("vehicle"):
		if actor.is_in_group("harbor_terminal_coach"): return actor.get_parent().heading
		return actor.global_transform.x.normalized()
	return motion.normalized()

func _wheel_offsets(actor: Node2D, direction: Vector2) -> Array[Vector2]:
	var collision := actor.get_node_or_null("Collision") as CollisionShape2D
	if collision == null: collision = actor.get_node_or_null("CollisionShape2D") as CollisionShape2D
	var half_length := 23.0
	var half_width := 10.0
	if collision != null and collision.shape != null:
		half_length = 0.0
		half_width = 0.0
		var bounds := collision.shape.get_rect()
		var points := PackedVector2Array([bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)])
		if collision.shape is ConvexPolygonShape2D: points = collision.shape.points
		for point in points:
			var offset := collision.to_global(point) - actor.global_position
			half_length = maxf(half_length, absf(offset.dot(direction)))
			half_width = maxf(half_width, absf(offset.dot(direction.orthogonal())))
	var rear := -direction * half_length * 0.60
	if actor.is_in_group("motorcycle"): return [rear]
	return [rear + direction.orthogonal() * half_width * 0.78, rear - direction.orthogonal() * half_width * 0.78]

func _in_blood(point: Vector2) -> bool:
	if surfaces.size() <= 8:
		for surface in surfaces:
			if _touches_surface(point, surface): return true
		return false
	var cell := Vector2i((point / 128.0).floor())
	for x in range(-1, 2):
		for y in range(-1, 2):
			var nearby := cell + Vector2i(x, y)
			if not _surface_cells.has(nearby): continue
			for surface in _surface_cells[nearby]:
				if _touches_surface(point, surface): return true
	return false

func _touches_surface(point: Vector2, surface) -> bool:
	if not is_instance_valid(surface): return false
	if point.distance_squared_to(surface.global_position) > 6400.0: return false
	if not surface.is_visible_in_tree() or surface.modulate.a < 0.08 or surface.get("settling_actor") != null: return false
	var outline: PackedVector2Array
	if surface is Polygon2D:
		outline = surface.polygon
	elif surface.get("outline") is PackedVector2Array:
		outline = surface.outline
	else:
		for child in surface.get_children():
			if child is Polygon2D and Geometry2D.is_point_in_polygon(child.to_local(point), child.polygon): return true
		return false
	return outline.size() >= 3 and Geometry2D.is_point_in_polygon(surface.to_local(point), outline)

func sample_actor(actor: Node2D, track: Dictionary) -> void:
	var start: Vector2 = track.previous
	var motion := actor.global_position - start
	track.previous = actor.global_position
	# Hidden boarding, respawn, recovery and airborne motion must never join a trail.
	if not _grounded(actor) or motion.length() > 80.0:
		track.residue = [0.0, 0.0]
		track.travel = 0.0
		_reset_foot_phase(actor, track)
		return
	var distance := motion.length()
	if distance < 0.01:
		if not is_equal_approx(float(track.get("phase", -1.0)), _foot_phase(actor)):
			_reset_foot_phase(actor, track)
		return
	var vehicle := actor.is_in_group("vehicle")
	var direction := _direction(actor, motion)
	if not vehicle:
		_sample_feet(actor, track, start, motion)
		return
	var offsets: Array[Vector2] = []
	if vehicle:
		offsets = _wheel_offsets(actor, direction)
	else:
		offsets.assign([direction.orthogonal() * 3.0 + Vector2(0, 3), -direction.orthogonal() * 3.0 + Vector2(0, 3)])
	var capacity := TIRE_DISTANCE if vehicle else FOOT_DISTANCE
	var stride := 3.5 if vehicle else 12.0
	var count := maxi(1, ceili(distance / 2.0))
	var step := distance / float(count)
	# Reuse a conservative set across every contact substep. The original
	# exact surface/visibility/polygon checks remain below; positions are live
	# for this call, with no cache across actors or frames.
	var region := Rect2(start, Vector2.ZERO).expand(actor.global_position)
	for offset in offsets:
		region = region.expand(start + offset).expand(actor.global_position + offset)
	region = region.grow(80.001) # _touches_surface rejects centres farther than 80.
	var candidates: Array[Node] = []
	for surface in surfaces:
		if is_instance_valid(surface) and region.has_point(surface.global_position):
			candidates.append(surface)
	for index in count:
		var position_at_step := start + motion * (float(index + 1) / count)
		for side in offsets.size():
			track.residue[side] = maxf(0.0, float(track.residue[side]) - step)
			for surface in candidates:
				if _touches_surface(position_at_step + offsets[side], surface):
					track.residue[side] = capacity
					break
		track.travel += step
		if track.travel < stride: continue
		track.travel = fmod(track.travel, stride)
		for side in offsets.size():
			if not vehicle and side != int(track.foot): continue
			var strength := float(track.residue[side]) / capacity
			if strength <= 0.015: continue
			marks.append({"position": to_local(position_at_step + offsets[side]), "angle": direction.angle(), "strength": strength, "tire": vehicle, "time": _clock})
			_marks_dirty = true
		if not vehicle: track.foot = 1 - int(track.foot)
	while marks.size() > MAX_MARKS: marks.pop_front()

func _foot_phase(actor: Node2D) -> float:
	var gait = actor.get("gait")
	if gait != null: return float(gait.phase)
	var phase = actor.get("walk_clock")
	return float(phase) if phase != null else -1.0

func _reset_foot_phase(actor: Node2D, track: Dictionary) -> void:
	track.phase = _foot_phase(actor)
	track.erase("phase_travel")

func _sample_feet(actor: Node2D, track: Dictionary, start: Vector2, motion: Vector2) -> void:
	var distance := motion.length()
	var direction := motion / distance
	var phase := _foot_phase(actor)
	var previous := float(track.get("phase", phase))
	track.phase = phase
	var advance := fposmod(phase - previous, TAU) if phase >= 0.0 and previous >= 0.0 else distance * PI / 20.0
	if not track.has("phase_travel"):
		track.phase_travel = fposmod(previous, PI) if phase >= 0.0 else 0.0
		if phase >= 0.0: track.foot = posmod(int(floorf(previous / PI)) + 1, 2)
	var initial := float(track.phase_travel)
	var boundary := PI
	var consumed := 0.0
	while advance > 0.000001 and boundary <= initial + advance + 0.000001:
		var travelled := clampf((boundary - initial) / advance, 0.0, 1.0) * distance
		for side in 2: track.residue[side] = maxf(0.0, float(track.residue[side]) - (travelled - consumed))
		consumed = travelled
		var foot := int(track.foot)
		var point := start + direction * travelled + direction.orthogonal() * (2.5 if foot == 0 else -2.5) + Vector2(0, 3)
		if _in_blood(point): track.residue[foot] = FOOT_DISTANCE
		var strength := float(track.residue[foot]) / FOOT_DISTANCE
		if strength > 0.015:
			# Sample variation once, retaining it throughout the mark's lifetime.
			marks.append({"position": to_local(point), "angle": direction.angle() + randf_range(-0.07, 0.07), "strength": strength * randf_range(0.88, 1.0), "size": randf_range(0.86, 1.06), "tire": false, "time": _clock})
			_marks_dirty = true
		track.foot = 1 - foot
		boundary += PI
	track.phase_travel = maxf(0.0, initial + advance - (boundary - PI))
	for side in 2: track.residue[side] = maxf(0.0, float(track.residue[side]) - (distance - consumed))
	track.travel = fposmod(float(track.travel) + distance, 20.0)
	while marks.size() > MAX_MARKS: marks.pop_front()

func _draw() -> void:
	for mark in marks:
		var fade := clampf((MARK_LIFETIME - (_clock - float(mark.time))) / MARK_FADE_DURATION, 0.0, 1.0)
		var color := Color(0.34, 0.045, 0.065, float(mark.strength) * fade * 0.82)
		draw_set_transform(mark.position, mark.angle, Vector2.ONE * float(mark.get("size", 1.0)))
		if mark.tire:
			draw_rect(Rect2(-1.4, -1.35, 2.8, 2.7), color)
			draw_line(Vector2(-0.5, -1.3), Vector2(0.6, 1.3), Color(0.48, 0.10, 0.12, color.a * 0.45), 0.55)
		else:
			draw_circle(Vector2(0.65, 0), 0.95, color)
			draw_rect(Rect2(-0.45, -0.85, 1.0, 1.7), color)
			draw_rect(Rect2(-1.8, -0.7, 0.8, 1.4), color)
	draw_set_transform(Vector2.ZERO)
