extends SceneTree
const DEST := preload("res://runtime/NavigationDestination.gd")
const FIXTURE := preload("res://tests/fixtures/NorthGatewayFixtures.gd")
class Production extends RefCounted:
	var urban_transit = null
class Driving extends RefCounted:
	var occupied := false
	var car: CharacterBody3D
class Place extends Node3D:
	var entry_position := Vector3(166,0,110)
class World extends Node3D:
	var production := Production.new()
	var driving := Driving.new()
	var maciota_place := Place.new()
class Session extends RefCounted:
	var state = preload("res://runtime/GameState.gd").new()
	var world: World
	var mission_world
	var arrival = {"active":false}
	var urban_operations = null
	var desert = null
	var mountain_activities = null
	var fishing = null
	var freight_active := false
	var freight_target := Vector3.INF
	var hud_objective := ""
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var session := Session.new()
	session.world=World.new(); root.add_child(session.world)
	session.world.add_child(session.world.maciota_place)
	var mission = preload("res://runtime/MissionWorld.gd").new()
	mission.session=session; session.mission_world=mission
	session.world.add_child(mission); mission.set_process(false)
	mission.truck=CharacterBody3D.new(); session.world.add_child(mission.truck); mission.truck.position=Vector3(-37,0,61)
	mission.cargo=CharacterBody3D.new(); session.world.add_child(mission.cargo); mission.cargo.position=Vector3(218,0,260)
	var intro: Dictionary=session.state.intro.snapshot(); intro.phase="complete"; intro.completed_missions=[preload("res://data/GarageSequence.gd").ID]
	check(session.state.intro.restore_snapshot(intro),"valid completed intro")
	for row in [[0,"Ferrugem"],[1,"Guincho do Neco"],[2,"Baia do Neco"],[3,"Neco"],[4,"Ferrugem"]]:
		var saved := FIXTURE.prefix(1); saved.active_id="cobra_contact"; saved.step=row[0]
		check(session.state.campaign.restore_snapshot(saved),"valid tow step "+str(row[0]))
		var target := DEST.resolve(session)
		check(target.title==row[1] and target.region=="harbor" and target.point==mission.target_position(),"mission title and position agree at step "+str(row[0]))
	var saved := FIXTURE.prefix(1); saved.active_id="cobra_contact"; saved.step=1; session.state.campaign.restore_snapshot(saved)
	session.world.driving.occupied=true; session.world.driving.car=mission.truck
	var target := DEST.resolve(session)
	check(target.title=="Caminhonete da cliente" and target.point==mission.cargo.position,"boarding actual truck changes named destination")
	session.world.driving.car=mission.cargo
	check(DEST.resolve(session).title=="Guincho do Neco","another vehicle cannot count as tow truck")
	session.world.driving.occupied=false
	session.world.set_meta("map_waypoint",Vector2.ZERO)
	check(DEST.resolve(session).source=="mission","manual waypoint never silently replaces mission")
	session.state.campaign.restore_snapshot(FIXTURE.prefix(1))
	session.world.set_meta("map_waypoint_title","Neco")
	check(DEST.resolve(session).title=="Neco" and DEST.resolve(session).point==Vector3.ZERO,"world-origin waypoint is a valid destination")
	session.world.remove_meta("map_waypoint")
	check(DEST.resolve(session).is_empty(),"free exploration has no stale mission")
	var places := preload("res://ui/hud/NavigationPlaces.gd").harbor(session)
	for id in ["maciota","neco","ferrugem"]: check(places.any(func(place): return place.id==id and place.kind=="workshop" and place.title!=""),"important named landmark "+id)
	session.world.free()
	print("NAVIGATION_DESTINATION ",checks," checks failures=",failures)
	quit(0 if failures.is_empty() else 1)
