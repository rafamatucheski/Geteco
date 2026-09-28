extends Node3D
## Bounded aerial reinforcement and handler-owned K9 response.
const HELICOPTER = preload("res://gameplay/police_response/air_k9/PoliceHelicopter.gd")
const DOG = preload("res://gameplay/police_response/air_k9/PoliceK9.gd")
const RULES = preload("res://gameplay/dispatch/DispatchRules.gd")
const MAX_K9 := 2
const MAX_OFFICERS := 16
const SQUAD_SIZE := 4
const HOVER_HEIGHT := 13.0
const DROP_OFFSETS := [Vector3(-1.7, 0, -0.8), Vector3(1.7, 0, -0.8), Vector3(-1.7, 0, 1.05), Vector3(1.7, 0, 1.05)]
@export var helicopter_cooldown_seconds := 60.0
@export var initial_response_seconds := 6.0
var gameplay: Node3D
var helicopter: CharacterBody3D
var dogs: Array[CharacterBody3D] = []
var retiring_officers: Array[CharacterBody3D] = []
var helicopter_timer := 6.0
var dog_timer := 8.0
var _tick := 0.0
var _region := ""
var _active := false
var _search_phase := 0
var _retire_tick := 0.0

func configure(p_gameplay: Node3D) -> void:
	gameplay = p_gameplay
	# Custos únicos de malha saem da carga, não do quadro em que a polícia chega.
	HELICOPTER.AIRFRAME.warm()
	var scratch := Node3D.new()
	for weapon in ["pistol", "smg", "m4a1"]: preload("res://gameplay/ArsenalWeapon3D.gd").build_cached(scratch, weapon)
	scratch.free()
	helicopter_timer = initial_response_seconds
	_region = _state_region()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(gameplay) or gameplay.state == null: return
	if response_paused(): return
	var region := _state_region()
	if region != _region:
		clear_response()
		_region = region
	_retire_tick -= delta
	if _retire_tick <= 0.0:
		_retire_tick = 0.25
		_cleanup_retired_officers()
	var wanted := int(gameplay.stars) >= 3 and float(gameplay.health) > 0.0
	if float(gameplay.health) <= 0.0 or not gameplay.state.weapons_allowed():
		if _active or is_instance_valid(helicopter) or not dogs.is_empty(): clear_response()
		_active = false
		return
	if not wanted:
		# Normal evasion does not erase a visible aircraft or a person on a rope.
		# The transport lowers those already attached, then climbs and flies out.
		if is_instance_valid(helicopter): helicopter.begin_departure()
		for dog in dogs:
			if is_instance_valid(dog): dog.begin_withdrawal()
		_active = false
		return
	_active = true
	_tick -= delta
	if _tick > 0.0: return
	_tick = 0.25
	dogs = dogs.filter(func(dog): return is_instance_valid(dog) and not dog.is_queued_for_deletion())
	# Interior coordinates belong to a different physical room; never use them outdoors.
	if not exterior_active():
		if is_instance_valid(helicopter): helicopter.begin_departure()
		return
	helicopter_timer = maxf(0.0, helicopter_timer - 0.25)
	dog_timer = maxf(0.0, dog_timer - 0.25)
	if not is_instance_valid(helicopter) and helicopter_timer <= 0.0 and gameplay.last_known_valid:
		if officer_count() + SQUAD_SIZE <= officer_limit():
			var zone := find_landing_zone(gameplay.last_known)
			if not zone.is_empty(): launch_helicopter(zone)
			else: helicopter_timer = 4.0
	if dog_timer <= 0.0 and dogs.size() < (2 if gameplay.stars >= 5 else 1):
		dog_timer = 6.0
		_try_deploy_dog()

func exterior_active() -> bool:
	if not is_instance_valid(gameplay) or gameplay.state == null: return false
	if response_paused(): return false
	var place := str(gameplay.state.place_id) if "place_id" in gameplay.state else ""
	return place.is_empty() and gameplay.state.weapons_allowed() and gameplay.stars > 0 and gameplay.health > 0.0

func response_paused() -> bool:
	if not is_instance_valid(gameplay) or get_tree().paused: return true
	if "enabled" in gameplay and not gameplay.enabled: return true
	var world: Variant = gameplay.get("world")
	if is_instance_valid(world) and "session" in world:
		var session: Variant = world.get("session")
		if session != null and "ready_for_play" in session and not session.ready_for_play: return true
	return false

func _state_region() -> String:
	if not is_instance_valid(gameplay) or gameplay.state == null: return ""
	return str(gameplay.state.region_id) if "region_id" in gameplay.state else ""

func ground_officers() -> Array[CharacterBody3D]:
	var result: Array[CharacterBody3D] = []
	# Dispatch squads live in DispatchUnit.officers rather than Gameplay.police.
	# The shared group includes those squads and officers transferred indoors.
	for officer in get_tree().get_nodes_in_group("v2_police_officers"):
		if officer is CharacterBody3D and not officer.get_meta("police_rappelling", false): result.append(officer)
	for officer in gameplay.police:
		if is_instance_valid(officer) and not result.has(officer) and not officer.get_meta("police_rappelling", false): result.append(officer)
	return result

func officer_count() -> int:
	var count := 0
	for officer in ground_officers():
		if is_instance_valid(officer) and not officer.is_queued_for_deletion() and officer.get("dead") != true: count += 1
	return count

func officer_limit() -> int:
	return mini(MAX_OFFICERS, int(RULES.FOOT_LIMIT[clampi(int(gameplay.stars), 0, RULES.FOOT_LIMIT.size() - 1)]))

func launch_helicopter(zone: Dictionary) -> bool:
	if is_instance_valid(helicopter) or not exterior_active() or officer_count() + SQUAD_SIZE > officer_limit(): return false
	var center: Vector3 = zone.center
	var spawn := center + Vector3(0, HOVER_HEIGHT + 7.0, 90.0)
	# New aircraft never appear in the camera. The flight itself remains physical.
	for index in 8:
		var candidate := center + Vector3(sin(index * TAU / 8.0) * 90.0, HOVER_HEIGHT + 7.0, cos(index * TAU / 8.0) * 90.0)
		if not point_on_screen(candidate, 10.0) and aerial_clear(candidate):
			spawn = candidate
			break
		if index == 7: return false
	gameplay.set_meta("police_air_reserved_slots", SQUAD_SIZE)
	helicopter = HELICOPTER.new()
	helicopter.director = self
	helicopter.landing_zone = zone
	helicopter.position = to_local(spawn)
	add_child(helicopter)
	helicopter_timer = helicopter_cooldown_seconds
	return true

func helicopter_finished(body: CharacterBody3D) -> void:
	if body != helicopter: return
	gameplay.set_meta("police_air_reserved_slots", 0)
	helicopter = null
	helicopter_timer = helicopter_cooldown_seconds

func release_air_slot() -> void:
	if is_instance_valid(gameplay): gameplay.set_meta("police_air_reserved_slots", maxi(0, int(gameplay.get_meta("police_air_reserved_slots", 0)) - 1))

func clear_response() -> void:
	if is_instance_valid(helicopter):
		helicopter.cleanup_rappellers()
		helicopter.queue_free()
	helicopter = null
	for dog in dogs:
		if is_instance_valid(dog): dog.queue_free()
	dogs.clear()
	for officer in retiring_officers:
		if is_instance_valid(officer): officer.queue_free()
	retiring_officers.clear()
	if is_instance_valid(gameplay): gameplay.set_meta("police_air_reserved_slots", 0)
	helicopter_timer = initial_response_seconds
	dog_timer = 8.0

func retire_ground_officer(officer: CharacterBody3D) -> void:
	if not is_instance_valid(officer): return
	officer.set_meta("police_retiring", true)
	officer.set_physics_process(false)
	if not retiring_officers.has(officer): retiring_officers.append(officer)

func _cleanup_retired_officers() -> void:
	for index in range(retiring_officers.size() - 1, -1, -1):
		var officer := retiring_officers[index]
		if not is_instance_valid(officer): retiring_officers.remove_at(index); continue
		if not point_on_screen(officer.global_position, 2.0):
			gameplay.police.erase(officer)
			officer.queue_free()
			retiring_officers.remove_at(index)

func _exit_tree() -> void:
	clear_response()

func point_on_screen(point: Vector3, margin: float = 1.0) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return false
	var rect := get_viewport().get_visible_rect().grow(48.0)
	for offset in [Vector3.ZERO, Vector3.RIGHT * margin, Vector3.LEFT * margin, Vector3.UP * margin]:
		if not camera.is_position_behind(point + offset) and rect.has_point(camera.unproject_position(point + offset)): return true
	return false

func aerial_clear(point: Vector3) -> bool:
	var shape := CylinderShape3D.new()
	shape.radius = 7.7
	shape.height = 5.2
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point + Vector3(0, 0.9, 0)
	query.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func ground_hit(point: Vector3, above: float = 2.0) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * above, point - Vector3.UP * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < 0.92: return {}
	return hit

func is_landing_ground(hit: Dictionary) -> bool:
	if hit.is_empty(): return false
	var node: Node = hit.collider as Node
	for index in 7:
		if not is_instance_valid(node): break
		if node.has_meta("interior_solid_id") or not str(node.get_meta("place_id", "")).is_empty(): return false
		if bool(node.get_meta("mountain_terrain", false)) or bool(node.get_meta("police_landing_ground", false)): return true
		if str(node.name) in ["Land", "OriginalPortSurface", "MountainTerrain"]: return true
		node = node.get_parent()
	# Harbor road/sidewalk colliders use several procedural factories. Only a
	# genuinely low exterior slab is admitted by this fallback, never furniture/roof.
	return _state_region() == "harbor" and absf((hit.position as Vector3).y) <= 0.18

func capsule_clear(point: Vector3, radius: float = 0.36, height: float = 1.9, exclude: Array[RID] = []) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform.origin = point + Vector3.UP * (height * 0.5 + 0.04)
	query.collision_mask = 7
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func landing_column_clear(point: Vector3, height: float = HOVER_HEIGHT) -> bool:
	if not capsule_clear(point): return false
	var shape := CapsuleShape3D.new()
	shape.radius = 0.4
	shape.height = 1.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point + Vector3.UP * (height - 1.7)
	query.motion = Vector3.DOWN * (height - 2.7)
	query.collision_mask = 1
	var safe := get_world_3d().direct_space_state.cast_motion(query)
	return safe.size() == 2 and safe[0] >= 0.999

func dog_clear(point: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = DOG.BODY_SIZE + Vector3(0.04, 0.0, 0.04)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = point + DOG.BODY_CENTER
	query.collision_mask = 7
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func find_landing_zone(known: Vector3) -> Dictionary:
	# Bounded search: one ring per retry, twelve candidates, only last reported position.
	var radius := 12.0 + float(_search_phase % 3) * 7.0
	_search_phase += 1
	for index in 12:
		var angle := index * TAU / 12.0 + float(_search_phase % 2) * 0.23
		var center := known + Vector3(sin(angle) * radius, 0, cos(angle) * radius)
		var hit := ground_hit(center, 4.0)
		if not is_landing_ground(hit): continue
		center.y = (hit.position as Vector3).y + 0.04
		if not aerial_clear(center + Vector3.UP * HOVER_HEIGHT): continue
		var points: Array[Vector3] = []
		for offset in DROP_OFFSETS:
			var support := ground_hit(center + offset)
			if not is_landing_ground(support): break
			var point: Vector3 = support.position + Vector3.UP * 0.04
			if absf(point.y - center.y) > 0.4 or not landing_column_clear(point): break
			points.append(point)
		if points.size() == SQUAD_SIZE: return {"center": center, "points": points}
	return {}

func _try_deploy_dog() -> void:
	if not exterior_active() or dogs.size() >= MAX_K9: return
	for handler in ground_officers():
		if not is_instance_valid(handler) or handler.get("dead") == true or handler.is_queued_for_deletion(): continue
		if not handler.is_physics_processing() or not handler.is_on_floor(): continue
		if not str(handler.get_meta("police_place_id", "")).is_empty(): continue
		if handler.get_meta("police_k9_deployed", false): continue
		if handler.get("mode") != null and handler.get("mode") != "combat": continue
		if gameplay.last_known_valid and handler.global_position.distance_to(gameplay.last_known) > 55.0: continue
		for offset in [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.3)]:
			var hit := ground_hit(handler.global_position + offset, 0.8)
			if hit.is_empty(): continue
			var point: Vector3 = hit.position + Vector3.UP * 0.05
			if point_on_screen(point) or not dog_clear(point): continue
			if not has_line_of_sight(handler, point + Vector3.UP * 0.55, null, 3.0): continue
			var dog := DOG.new()
			dog.director = self
			dog.handler = handler
			dog.position = to_local(point)
			add_child(dog)
			dogs.append(dog)
			handler.set_meta("police_k9_deployed", true)
			return

func has_line_of_sight(observer: CollisionObject3D, point: Vector3, target: Node3D, limit: float) -> bool:
	var origin := observer.global_position + Vector3.UP * (0.72 if observer.get_meta("police_k9", false) else 0.5)
	if origin.distance_to(point) > limit: return false
	var ray := PhysicsRayQueryParameters3D.create(origin, point, 7, [observer.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	return hit.is_empty() or (target != null and hit.collider == target)
