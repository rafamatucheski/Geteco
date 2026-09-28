extends SceneTree
const LIGHTING := preload("res://world/city_look/CityLocalLighting.gd")
const FRAGILE := preload("res://gameplay/street_physics/FragileProps3D.gd")
class Clock extends RefCounted:
	var time_of_day := .93
class Session extends RefCounted:
	var weather := Clock.new()
class World extends Node3D:
	var player: Node3D
	var driving = null
class Controller extends RefCounted:
	var session := Session.new()
	var state := {"place_id":"","region_id":"harbor"}
	var world: World
var failures: Array[String] = []
var checks := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var lighting := LIGHTING.new()
	stage.add_child(lighting)
	lighting.set_process(false)
	var sources: Array[Dictionary] = []
	for i in 20: sources.append({"id":str(i),"point":Vector3((i%5)*10,5,(i/5)*10)})
	lighting.apply_sources(sources,Vector3(15,0,15),1.0)
	check(lighting.assignments.size()==LIGHTING.CAPACITY,"fixed pool budget")
	for lamp in lighting.lights:
		check(not lamp.shadow_enabled and lamp.is_visible_in_tree(),"real active light without extra shadow pass")
	var slots := lighting.assignments.duplicate()
	lighting.apply_sources(sources,Vector3(15.1,0,15),1.0)
	for id in slots: check(lighting.assignments.get(id,-1)==slots[id],"stable light assignment "+id)
	lighting.apply_sources(sources,Vector3.ZERO,0.0)
	check(lighting.assignments.is_empty() and lighting.lights.all(func(lamp): return not lamp.visible),"day disables all local sources")
	lighting.apply_sources(sources,Vector3(1000,0,1000),1.0)
	check(lighting.assignments.is_empty(),"distant region leaves pool inactive")
	var twins: Array[Dictionary] = [{"id":"a","point":Vector3(0,5,0)},{"id":"b","point":Vector3(1,5,0)}]
	lighting.apply_sources(twins,Vector3.ZERO,1.0)
	check(lighting.assignments.size()==1,"twin globes do not duplicate illumination")
	var chunk := Node3D.new()
	stage.add_child(chunk)
	var pole := Node3D.new()
	chunk.add_child(pole)
	FRAGILE.register_node("lamp",pole,chunk)
	check(lighting.nearby_sources(Vector3.ZERO).size()==1,"standing streamed post supplies illumination")
	var records := FRAGILE.query(Vector3.ZERO,20)
	records[0].state = "down"
	check(lighting.nearby_sources(Vector3.ZERO).is_empty(),"broken post loses real light")
	records[0].state = "standing"
	chunk.hide()
	check(lighting.nearby_sources(Vector3.ZERO).is_empty(),"hidden chunk cannot light another region")
	chunk.free()
	check(lighting.nearby_sources(Vector3.ZERO).is_empty(),"unloaded source is discarded")
	var fitting := Node3D.new()
	stage.add_child(fitting)
	fitting.position = Vector3(5,0,6)
	fitting.add_to_group(LIGHTING.SOURCE_GROUP)
	fitting.set_meta("local_light",{"offset":Vector3(0,8,0),"range":23.0,"energy":2.2})
	var fixtures := lighting.nearby_sources(Vector3.ZERO)
	check(fixtures.size()==1 and fixtures[0].point.is_equal_approx(Vector3(5,8,6)),"floodlight follows its actual fitting transform")
	lighting.refresh()
	check(lighting.assignments.is_empty(),"missing world/session disables lighting")
	var world := World.new()
	stage.add_child(world)
	world.player = Node3D.new()
	world.add_child(world.player)
	var controller := Controller.new()
	controller.world = world
	lighting.controller = controller
	lighting.refresh()
	check(lighting.assignments.size()==1,"night enables an actual nearby fitting")
	controller.state.place_id = "maciota"
	lighting.refresh()
	check(lighting.assignments.is_empty(),"interior transition disables outdoor pool")
	controller.state.place_id = ""
	controller.state.region_id = "mountain"
	lighting.refresh()
	check(lighting.assignments.is_empty(),"mountain keeps its own lighting system")
	controller.state.region_id = "harbor"
	controller.session.weather.time_of_day = .45
	lighting.refresh()
	check(lighting.assignments.is_empty(),"real daylight factor disables fittings")
	stage.free()
	print("CITY_LOCAL_LIGHTING checks=",checks," failures=",failures)
	quit(0 if failures.is_empty() else 1)
