extends Node3D
## One optional rival at the edge of the meet, released with the visit.
const MODEL := preload("res://assets/CivilianModel.gd")
const CARS := preload("res://gameplay/desert_cars/DesertCarCatalog.gd")
const HONOR := preload("res://runtime/TakeshiHonor.gd")
const POINT := Vector3(-1014,0,-1275)
const CAR_POINT := Vector3(-1019,0,-1275)
var session
var race: Node3D
var actor: StaticBody3D
var parked: CharacterBody3D
var clock := 0.0
var retired := false

func configure(owner_session, owner_race: Node3D) -> void:
	session = owner_session
	race = owner_race
	name = "TakeshiAtDragMeet"
	session.world.gameplay.player_died.connect(_reset_visit)

func _reset_visit() -> void:
	_clear()
	retired = false

func _process(delta: float) -> void:
	clock += delta
	if clock<.3: return
	clock = 0.0
	reconcile()

func reconcile() -> void:
	var outdoors: bool = session.ready_for_play and session.state.region_id=="desert" and session.state.place_id.is_empty() and session.world.gameplay.health>0
	var nearby: bool = outdoors and session.world.player.global_position.distance_to(POINT)<(110.0 if is_instance_valid(actor) else 85.0)
	if not nearby or race.active:
		_clear()
		if not nearby: retired = false
		return
	if is_instance_valid(actor) and actor.dead: retired = true
	if retired: return
	if not is_instance_valid(actor):
		if not session.controller.region.is_streaming_idle(): return
		session.controller.region.prepare_collision_at(POINT)
		if not session.position_clear(POINT+Vector3.UP*.1): return
		var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(POINT+Vector3.UP*.35,POINT-Vector3.UP*.4,1))
		if hit.is_empty() or float(hit.normal.y)<.95: return
		actor = preload("res://runtime/desert/drag_meet/TrackParticipant.gd").new()
		actor.name = "Takeshi"
		actor.position = hit.position+Vector3.UP*.025
		actor.collision_layer = 2
		actor.collision_mask = 0
		actor.set_meta("character_identity","takeshi")
		actor.set_meta("character_name","Takeshi")
		actor.set_meta("reaction_exempt",true)
		var shape := CollisionShape3D.new()
		var capsule := CapsuleShape3D.new()
		capsule.radius = .3
		capsule.height = 1.75
		shape.shape = capsule
		shape.position.y = .875
		actor.add_child(shape)
		var person := MODEL.new()
		person.appearance_locked = true
		person.appearance_variant = 732
		person.coat_color = Color("23302a")
		person.pants_color = Color("202522")
		person.wardrobe_overrides = {"female":false,"build":2,"height":1.04,"top":0,"bottom":0,"shoe":1,"hair":0,"beard":2,"hat":0,"glasses":false,"bag":0,"backpack":false,"skin":Color("80553e"),"hair_color":Color("171917"),"top_color":Color("23302a"),"bottom_color":Color("202522"),"inner":Color("222923"),"accent":Color("82916c")}
		person.rotation.y = -PI*.5
		actor.visual = person
		actor.add_child(person)
		add_child(actor)
		preload("res://gameplay/urban_v1/CobraAppearance.gd").dress(person)
		person.set_process(false)
	if str(HONOR.data(session.state.world_state).reward)=="car":
		if is_instance_valid(parked): parked.queue_free(); parked=null
	elif not is_instance_valid(parked):
		_spawn_display()

func _spawn_display() -> void:
	if not CARS.IDS.has("supra_a80"): return
	session.controller.region.prepare_collision_at(CAR_POINT)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.84,1.3,4.52)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 7
	query.transform = Transform3D(Basis(Vector3.UP,PI*.5),CAR_POINT+Vector3.UP*.8)
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return
	var floor_hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(CAR_POINT+Vector3.UP*.35,CAR_POINT-Vector3.UP*.4,1))
	if floor_hit.is_empty() or float(floor_hit.normal.y)<.95: return
	parked = preload("res://runtime/desert/drag_meet/StealableMeetCar.gd").new()
	parked.archetype = "supra_a80"
	parked.half_width = .92
	parked.half_length = 2.26
	parked.name = "TakeshiSupraDisplay"
	parked.collision_layer = 1
	parked.collision_mask = 0
	parked.position = floor_hit.position+Vector3.UP*.035
	parked.rotation.y = PI*.5
	var bounds := CollisionShape3D.new()
	bounds.shape = shape
	bounds.position.y = .75
	parked.add_child(bounds)
	parked.add_child(preload("res://runtime/FleetCatalog.gd").create("supra_a80"))
	add_child(parked)

func nearest_action() -> Dictionary:
	if not is_instance_valid(actor) or actor.dead or race.active or session.world.driving.occupied or session.modal: return {}
	if session.world.player.global_position.distance_to(actor.global_position)>2.5: return {}
	return {"id":"desert_drag","target":"takeshi","label":"Falar com Takeshi"}

func _clear() -> void:
	for body in [actor,parked]:
		if not is_instance_valid(body): continue
		body.hide()
		body.collision_layer = 0
		body.queue_free()
	actor = null
	parked = null
