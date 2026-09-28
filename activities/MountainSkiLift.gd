extends Node
## Owns one passenger and the session transition lock; never persists mid-air.
const DEFINITIONS := preload("res://activities/ActivityDefinitions.gd")
const POINTS := [Vector2(7100,-4890),Vector2(7900,-4220),Vector2(8050,-3600),Vector2(6880,-3015)]
const DURATION := 6.0
var progression
var riding := false
var elapsed := 0.0
var path := Curve3D.new()
var chair: Node3D
var expected := Vector3.ZERO
var origin := Vector3.ZERO
var saved := {}
var landing_wait := 0.0
func configure(owner_progression) -> void:
	progression = owner_progression
	for point in POINTS: path.add_point(DEFINITIONS.at(point,"mountain")+Vector3(.875,4.45,0))
func can_board() -> bool:
	var session = progression.session
	if riding or not progression._outside() or session.modal or session.is_transition_blocked() or session.world.player.input_locked: return false
	return session.world.player.position.distance_to(DEFINITIONS.at(POINTS[0],"mountain")) < 7.2
func board() -> bool:
	if not can_board(): return false
	var session = progression.session
	if not progression._open(): session.show_message("Teleférico: 08:00 às 18:00."); return true
	progression._stop()
	var actor = session.world.player
	origin = actor.position
	expected = origin
	saved = {"physics":actor.is_physics_processing(),"locked":actor.input_locked}
	session.transition_kind = "ski_lift"
	actor.input_locked = true
	actor.velocity = Vector3.ZERO
	actor.set_physics_process(false)
	actor.visual.rotation.y = 0
	session.state.equip_weapon("fists")
	riding = true
	elapsed = 0
	landing_wait = 0
	chair = Node3D.new()
	session.world.add_child(chair)
	_chair_part(Vector3(0,.75,.15),Vector3(1.35,.1,.65),Color("2d4b68"))
	_chair_part(Vector3(0,1.2,.44),Vector3(1.35,.75,.08),Color("2d4b68"))
	_chair_part(Vector3(0,1.1,-.25),Vector3(1.4,.06,.06),Color("d99834"))
	_chair_part(Vector3(0,2.4,.44),Vector3(.05,2.2,.05),Color("4a5660"))
	_chair_part(Vector3(0,3.5,.22),Vector3(.22,.16,.5),Color("4a5660"))
	session.show_message("Subindo ao cume · %s adiantar viagem" % get_node("/root/GameInput").hint("interact"))
	return true
func _chair_part(point: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = point
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	chair.add_child(mesh)
func skip() -> void:
	if riding: elapsed = DURATION
func _physics_process(delta: float) -> void:
	if not riding: return
	var session = progression.session
	var actor = session.world.player
	# Recovery/mission travel owns its new position and lock. Never teleport it back.
	if not progression._outside() or session.rescue_pending or session.arrest_pending or actor.position.distance_to(expected) > 2:
		_release(false)
		return
	if session.modal: return
	elapsed = minf(DURATION, elapsed+delta)
	expected = path.sample_baked(path.get_baked_length()*elapsed/DURATION)
	actor.position = expected
	actor.velocity = Vector3.ZERO
	actor.pose_vehicle(1.0)
	chair.position = expected
	if elapsed < DURATION: return
	var region = session.controller.region
	var summit := DEFINITIONS.at(POINTS[-1],"mountain")
	region.prepare_collision_at(summit)
	landing_wait += delta
	for offset in [Vector3(0,0,5),Vector3(0,0,-5),Vector3(5,0,0),Vector3(-5,0,0)]:
		var point: Vector3 = summit+offset
		var query := PhysicsRayQueryParameters3D.create(point+Vector3.UP*3,point-Vector3.UP*5,1)
		var hit: Dictionary = session.world.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty(): continue
		point = hit.position+Vector3.UP*.06
		if not session.position_clear(point): continue
		actor.teleport(point)
		_release(true)
		session.show_message("Chegada ao cume")
		return
	if landing_wait > 3:
		cancel()
		session.show_message("Desembarque bloqueado. Viagem devolvida à base.")
func cancel() -> void:
	if not riding: return
	var session = progression.session
	if not is_instance_valid(session) or not is_instance_valid(session.world) or not is_instance_valid(session.world.player):
		riding = false
		if is_instance_valid(chair): chair.queue_free()
		return
	var actor = session.world.player
	if progression._outside() and not session.rescue_pending and not session.arrest_pending and actor.position.distance_to(expected) < 2:
		session.controller.region.prepare_collision_at(origin)
		actor.teleport(origin)
	_release(true)
func _release(normal: bool) -> void:
	if not riding: return
	riding = false
	var session = progression.session
	var actor = session.world.player
	if session.transition_kind == "ski_lift": session.transition_kind = ""
	if is_instance_valid(actor) and session.world.gameplay.health > 0 and not session.rescue_pending and not session.arrest_pending:
		actor.set_physics_process(bool(saved.get("physics",true)))
		if normal or not session.is_transition_blocked(): actor.input_locked = bool(saved.get("locked",false))
	if is_instance_valid(chair): chair.queue_free()
	chair = null
func _exit_tree() -> void:
	cancel()
