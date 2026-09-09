extends Node2D

## Finite campaign opponents. No respawner, ambient population deletion or
## reward delivery: the campaign owns completion and persistence.
signal completed
signal phase_changed(phase: String)
const RESIDENT := preload("res://district/harbor_preview/cobras/CobraResident.gd")
const BOSS := preload("res://district/harbor_preview/cobras/CobraBoss.gd")
var actors: Array = []
var kind := "ambush"
var phase := "confrontation"
var _points := PackedVector2Array()
var _finished := false
var _retreated := false
var _phase_time := 0.0
var _cover_point := Vector2.ZERO
var _subject: Node2D

func configure(encounter_kind: String, points: PackedVector2Array) -> void:
	kind = encounter_kind
	_points = points.duplicate()

func _ready() -> void:
	add_to_group("cobra_campaign_encounter")
	for i in mini(3,_points.size()):
		var actor = BOSS.new() if kind == "boss" and i == 0 else RESIDENT.new()
		actor.name = "CobraOpponent%d" % i
		actor.territory = self
		actor.guard = true
		actor.profile = i
		actor.combat_role = "leader" if kind == "boss" and i == 0 else ("enforcer" if i == 1 else "lookout")
		actor.position = _points[i]
		actor.patrol = PackedVector2Array([to_global(_points[i])])
		add_child(actor)
		actors.append(actor)
	_subject = _find_subject()
	if not actors.is_empty():
		actors[0].say("End of the road, Dante." if TranslationServer.get_locale().begins_with("en") else "Acabou o caminho, Dante.")

func _find_subject() -> Node2D:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if is_instance_valid(player) and not player.visible:
		for car in get_tree().get_nodes_in_group("vehicle"):
			if car is Node2D and car.get("is_driven_by_player") == true:
				return car
	return player

func interaction_suspended() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	return get_tree().paused or (is_instance_valid(player) and (player.get("is_in_dialogue") == true or player.get("is_control_disabled") == true or player.get("is_dead") == true))

func can_see(observer: Node2D, target: Node2D) -> bool:
	if not is_instance_valid(target) or observer.global_position.distance_to(target.global_position)>420.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(observer.global_position,target.global_position,1)
	if observer is CollisionObject2D:
		query.exclude = [observer.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target

func combat_target_for(actor: Node2D) -> Node2D:
	if _finished or interaction_suspended() or phase == "confrontation":
		return null
	return _subject if can_see(actor,_subject) else null

func report_aggression() -> void:
	if phase == "confrontation":
		_change_phase("engage")

func get_living_count() -> int:
	var living := 0
	for actor in actors:
		if is_instance_valid(actor) and not actor.is_dead:
			living += 1
	return living

func _physics_process(delta: float) -> void:
	if _finished or interaction_suspended():
		return
	_subject = _find_subject()
	_phase_time += delta
	if not actors.is_empty() and get_living_count() == 0:
		_finished = true
		_change_phase("defeated")
		completed.emit()
		return
	if phase == "confrontation" and _phase_time >= 2.0:
		_change_phase("engage")
	if kind != "boss" or actors.is_empty() or not is_instance_valid(actors[0]) or actors[0].is_dead:
		return
	var leader = actors[0]
	if not _retreated and leader.health <= int(leader.max_health*0.55):
		_retreated = true
		_cover_point = _find_retreat_point(leader)
		leader.walk_target = _cover_point
		_change_phase("reposition")
		leader.say("Cover me!" if TranslationServer.get_locale().begins_with("en") else "Me dá cobertura!")
	elif phase == "reposition" and (leader.global_position.distance_to(_cover_point)<20 or _phase_time>5.0):
		_change_phase("last_stand")

func get_tactical_destination(actor: Node2D, ordinary: Vector2) -> Vector2:
	if phase == "reposition" and not actors.is_empty() and actor == actors[0]:
		return _cover_point
	return ordinary

func _find_retreat_point(leader: CollisionObject2D) -> Vector2:
	var origin := to_global(_points[_points.size()-1])
	var shape := CircleShape2D.new()
	shape.radius = 14.0
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.collision_mask = 7
	query.exclude = [leader.get_rid()]
	query.collide_with_areas = false
	for offset in [Vector2(35,0),Vector2(-35,0),Vector2(0,35),Vector2(0,-35)]:
		var candidate: Vector2 = origin+offset
		query.transform = Transform2D(0,candidate)
		if get_world_2d().direct_space_state.intersect_shape(query,1).is_empty():
			return candidate
	# Never force the leader into a wall/standing ally when all pockets are busy.
	return leader.global_position

func _change_phase(next: String) -> void:
	if phase == next:
		return
	phase = next
	_phase_time = 0.0
	phase_changed.emit(phase)
