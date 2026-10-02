extends Node3D
## Dono único da população ambiente. Missões continuam donas de seus encontros.
const GUARD := preload("res://gameplay/urban_v1/CobraLocalGuard.gd")
const CENTER := Vector3(7700,0,1700)/16.0
const POSTS := [Vector3(7180,0,1580)/16.0,Vector3(7330,0,1350)/16.0,Vector3(8200,0,1760)/16.0]
const NAMES := ["Ren","Haruka","Daichi"]
const ROUTES := [
	[Vector3(7400,0,1290)/16.0,Vector3(7730,0,1290)/16.0,Vector3(7400,0,1290)/16.0],
	[Vector3(7430,0,2080)/16.0,Vector3(7750,0,2080)/16.0,Vector3(7430,0,2080)/16.0]]
var session
var guards: Dictionary = {}
var residents: Dictionary = {}
var scan := 0.0
var active := false

func configure(owner_session) -> void:
	session = owner_session
	name = "CobraNeighborhoodLife"

func _process(delta: float) -> void:
	if session == null or not session.ready_for_play: return
	scan -= delta
	if scan>0: return
	scan = .35
	active = session.state.region_id == "harbor" and session.state.place_id.is_empty() and session.world.player.global_position.distance_to(CENTER)<105
	var defeated: bool = session.state.campaign.cobra_status().defeated
	for actor in guards.values()+residents.values():
		if not is_instance_valid(actor): continue
		var enabled: bool = active and not (actor is GUARD and defeated)
		actor.visible = enabled
		actor.collision_layer = 2 if enabled and not actor.dead else 0
		actor.set_physics_process(enabled and not actor.dead)
		actor.visual.process_mode = Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		if actor is GUARD and (not enabled or _mission_access() or actor.global_position.distance_to(CENTER)>85): actor.set_engaged(false)
	if not active: return
	if not defeated:
		for index in POSTS.size():
			if guards.has(index) or session.state.world_state.get("cobra_local_dead_%d"%index,false): continue
			var point: Vector3 = POSTS[index]+Vector3.UP*.06
			if not session.position_clear(point): continue
			var actor := GUARD.new()
			actor.configure(session.world.gameplay,1 if index==1 else 0)
			actor.territory = self
			actor.position = point
			add_child(actor)
			actor.set_meta("character_name",NAMES[index])
			actor.died.connect(_record_death.bind("cobra_local_dead_%d"%index))
			guards[index] = actor
	for index in ROUTES.size():
		if residents.has(index) or session.state.world_state.get("cobra_neighbor_dead_%d"%index,false): continue
		var point: Vector3 = ROUTES[index][0]+Vector3.UP*.06
		if not session.position_clear(point): continue
		var actor := preload("res://scripts/Actor.gd").new()
		actor.identity = 200+index
		actor.position = point
		actor.route = PackedVector3Array(ROUTES[index])
		add_child(actor)
		actor.add_to_group("cobra_local")
		actor.set_meta("character_name",["Aiko","Ryo"][index])
		residents[index] = actor
	# Actor has no death signal; retain the outcome across streaming and saves.
	for index in residents:
		if residents[index].dead: _record_death("cobra_neighbor_dead_%d"%index)

func _record_death(key: String) -> void:
	session.state.world_state[key] = true

func _mission_access() -> bool:
	return session.state.campaign.active_id.begins_with("cobra_") or session.state.campaign.cobra_status().cobra_access>0 or session.state.campaign.cobra_status().defeated

func provoke(source: Node) -> void:
	if not active or _mission_access(): return
	var player: Node = session.world.player
	var driving = session.world.driving
	if source!=player and not (driving.occupied and source==driving.car): return
	for actor in guards.values():
		if is_instance_valid(actor) and not actor.dead:
			actor.last_known = player.global_position
			actor.alerted = true
			actor.set_engaged(true)
