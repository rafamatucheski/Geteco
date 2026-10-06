extends SceneTree
## Real rooms, colliders and articulated residents; no full-session startup.
const HOMES := preload("res://world/desert/village/DesertVillageHomes.gd")
const PLACE := preload("res://world/places/NativePlace.gd")
const LIFE := preload("res://runtime/desert/DesertVillageLife.gd")
const ACTOR := preload("res://scripts/Actor.gd")
var failures: Array[String]=[]
var checks := 0

class FakeState extends RefCounted:
	var region_id := "desert"
	var place_id := ""
class FakeWeather extends Node:
	var time_of_day := .9
class FakeSession extends Node:
	var state := FakeState.new()
	var ready_for_play := true
	var weather: Node
	var room: Node3D
	var transitioning := false
	func is_transition_blocked() -> bool: return transitioning

func _initialize() -> void:
	create_timer(80).timeout.connect(func(): push_error("DESERT_VILLAGE_LIFE timeout"); quit(3))
	run.call_deferred()

func check(ok: bool,message: String) -> void:
	checks+=1
	if ok: return
	failures.append(message)
	push_error(message)

func run() -> void:
	if "--no-save" not in OS.get_cmdline_user_args():
		push_error("Desert home life test requires --no-save"); quit(2); return
	var stage := Node3D.new()
	root.add_child(stage)
	var player: CharacterBody3D=ACTOR.new()
	player.is_player=true
	player.controlled_automatically=true
	player.position=Vector3(-40,.04,0)
	stage.add_child(player)
	player.set_physics_process(false)
	var session := FakeSession.new()
	stage.add_child(session)
	var weather := FakeWeather.new()
	stage.add_child(weather)
	session.weather=weather
	var life: Node=LIFE.new()
	stage.add_child(life)
	life.configure(session)
	for hour in [.25,.5,.749999]: check(not LIFE.night_at(hour),"Daytime is empty at hour %s"%hour)
	for hour in [.0,.249999,.75,.9]: check(LIFE.night_at(hour),"Night occupancy includes hour %s"%hour)
	for index in 4:
		var definition: Dictionary=HOMES.home_data(HOMES.IDS[index])
		var room: Node3D=PLACE.new()
		room.definition=definition
		room.position=Vector3(float(index)*40,0,0)
		stage.add_child(room)
		session.room=room
		session.state.place_id=str(definition.id)
		weather.time_of_day=.9
		for frame in 3: await physics_frame
		life.reconcile()
		for frame in 8: await physics_frame
		var state: Dictionary=life.diagnostics()
		check(int(state.count)==1,"Night admits resident in %s: %s"%[definition.id,state.admission_failure])
		check(state.home==definition.id,"Resident keeps the active home identity")
		check(state.activity==definition.resident_data.activity,"Home keeps its authored domestic routine")
		if is_instance_valid(life.resident):
			var resident: CharacterBody3D=life.resident
			check(resident.get_parent()==room,"Resident belongs to the real room for shared depth and cleanup")
			check(resident.home_model is Node3D and resident.home_model.scale.is_equal_approx(Vector3.ONE),"Native resident retains authored human scale")
			check(resident.find_children("*","SubViewport",true,false).is_empty(),"Resident adds no private render viewport")
			for child in resident.get_children():
				if not child is CollisionShape3D: continue
				var query := PhysicsShapeQueryParameters3D.new()
				query.shape=child.shape
				query.transform=child.global_transform
				query.collision_mask=1
				var overlaps: Array[Dictionary]=stage.get_world_3d().direct_space_state.intersect_shape(query,32)
				var furniture_hits: Array[String]=[]
				for hit in overlaps:
					var collider: Node3D=hit.collider
					var solid_id: String=str(collider.get_meta("interior_solid_id",collider.name))
					# A settled capsule legitimately touches the floor; separate that
					# support from furniture without accepting penetration below it.
					if solid_id=="Floor" and state.activity!="sleep" and child.shape is CapsuleShape3D:
						var floor_bounds: AABB=collider.get_meta("bounds",AABB())
						var capsule_bottom: float=room.to_local(child.global_position).y-float(child.shape.height)*.5
						var below_floor: float=floor_bounds.end.y-capsule_bottom
						print("RESIDENT_SUPPORT_CONTACT ",definition.id," collider=",collider.name," bottom=",capsule_bottom," floor_top=",floor_bounds.end.y," penetration=",below_floor)
						check(resident.is_on_floor() and below_floor<=resident.safe_margin+.0001,"Floor contact is supported and within the engine body margin in "+str(definition.id))
					else:
						furniture_hits.append("%s(id=%s, at=%s)"%[collider.name,solid_id,collider.global_position])
				check(furniture_hits.is_empty(),"Resident body clears furniture in %s: %s"%[definition.id,", ".join(furniture_hits)])
			if state.activity=="sleep":
				check(resident.get_meta("explicit_sleep_pose",false) and not resident.is_physics_processing(),"Sleeping pose uses supported horizontal body rather than walking on bed")
				check(absf(float(resident.get_meta("sleep_support_height",0))-.63)<.04,"Sleeping resident uses actual mattress support")
			else:
				check(resident.is_physics_processing() and resident.is_on_floor(),"Awake resident stands on physical floor")
				check(resident.held_prop is Node3D,"Cooking/reading has a held functional prop")
			# An ordinary pause freezes both occupancy polling and presentation.
			var clock_before: float=float(resident.home_model.clock)
			paused=true
			weather.time_of_day=.5
			await create_timer(.35,true,false,true).timeout
			check(is_instance_valid(life.resident) and int(life.diagnostics().count)==1,"Paused clock edit does not run occupancy processing")
			check(is_equal_approx(float(resident.home_model.clock),clock_before),"Resident animation honors pause")
			paused=false
		weather.time_of_day=.25
		life.reconcile()
		await process_frame
		check(int(life.diagnostics().count)==0,"Sunrise empties the occupied home")
		check(get_nodes_in_group("desert_village_resident").is_empty(),"Sunrise releases all resident rigs and bodies")
		weather.time_of_day=.75
		life.reconcile()
		for frame in 2: await physics_frame
		check(int(life.diagnostics().count)==1,"Evening recreates a single resident")
		session.transitioning=true
		life.reconcile()
		await process_frame
		check(int(life.diagnostics().count)==0,"Transition releases the resident before the room changes")
		session.transitioning=false
		life.reconcile()
		for frame in 2: await physics_frame
		check(int(life.diagnostics().count)==1,"Reentry does not retain a duplicate resident")
		if is_instance_valid(life.resident):
			var victim: CharacterBody3D=life.resident
			var supported_pose: Transform3D=victim.visual.transform
			victim.receive_damage(1000.0)
			check(victim.dead and victim.collision_layer==0,"Resident remains damageable and death releases its collision")
			check(bool(life.diagnostics().death_suppressed),"Death blocks readmission for the current visit")
			if victim.home_activity=="sleep":
				check(victim.visual.transform.is_equal_approx(supported_pose),"Death preserves the validated horizontal mattress pose")
				check(not victim.home_model.is_processing(),"Sleeping death stops breathing and domestic activity")
			# Exercise the productive fade itself without spending the ten-second
			# display delay four times. Its normal two-second cleanup remains intact.
			preload("res://gameplay/DestroyedFade3D.gd").fade(victim)
			await create_timer(2.25).timeout
			check(not is_instance_valid(victim),"Production corpse fade actually removes the actor")
			for attempt in 3: life.reconcile()
			check(int(life.diagnostics().count)==0 and get_nodes_in_group("desert_village_resident").is_empty(),"A cleaned-up corpse never respawns during the same visit")
			session.state.place_id=""
			session.room=null
			life.reconcile()
			check(not bool(life.diagnostics().death_suppressed),"Leaving ends the visit-scoped death suppression")
			session.state.place_id=str(definition.id)
			session.room=room
			life.reconcile()
			for frame in 2: await physics_frame
			check(int(life.diagnostics().count)==1,"A later visit can create one ordinary resident")
		session.state.place_id=""
		session.room=null
		life.reconcile()
		room.queue_free()
		for frame in 2: await process_frame
		check(get_nodes_in_group("desert_village_resident").is_empty(),"Leaving frees resident presentation and physical body")
	stage.queue_free()
	for frame in 3: await process_frame
	print("DESERT_VILLAGE_LIFE ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
